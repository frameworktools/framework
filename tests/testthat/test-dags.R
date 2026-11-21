# DAGs: dagitty graphs and ggdag tidy_dagitty objects publish as a dag
# artifact. Cloud's ArtifactDag (framework-cloud app/Support/Dags/) is the
# source of truth for the document these tests check.

# The document as Cloud receives it: dag.json, read back.
dag_json <- function(object) {
  dir <- withr::local_tempdir()
  path <- framework:::.fw_artifact_file(object, dir, cloud = TRUE)
  expect_identical(basename(path), "dag.json")
  jsonlite::read_json(path, simplifyVector = FALSE)
}

smoking_dag <- function() {
  dagitty::dagitty('dag {
    age [pos="1,0"]
    cancer [outcome,pos="2,1"]
    smoking [exposure,pos="0,1"]
    age -> cancer
    age -> smoking
    smoking -> cancer
  }')
}

test_that("a dagitty graph becomes a dag document with its roles and positions", {
  skip_if_not_installed("dagitty")
  json <- dag_json(smoking_dag())
  expect_identical(json$schema, "framework.artifact/v1")
  expect_identical(json$kind, "dag")
  expect_identical(json$source, list(language = "r", class = list("dagitty")))
  expect_match(json$dagitty, "^dag \\{")
  expect_match(json$dagitty, 'smoking [exposure,pos="0.000,1.000"]', fixed = TRUE)
  expect_match(json$dagitty, 'cancer [outcome,pos="2.000,1.000"]', fixed = TRUE)
  expect_match(json$dagitty, "age -> smoking", fixed = TRUE)
  # The text reads back as the same graph
  expect_identical(sort(names(dagitty::dagitty(json$dagitty))), c("age", "cancer", "smoking"))
  expect_null(json$labels)
  expect_null(json$code)
  expect_identical(json$analysis$effect, "total")
  expect_identical(json$analysis$adjustment_sets, list(list("age")))
  expect_identical(json$analysis$implications, list())
})

test_that("a graph without positions gets none", {
  skip_if_not_installed("dagitty")
  json <- dag_json(dagitty::dagitty("dag { a -> b -> c }"))
  expect_false(grepl("pos=", json$dagitty, fixed = TRUE))
})

test_that("adjustment sets keep 'no adjustment needed' apart from 'none exists'", {
  skip_if_not_installed("dagitty")
  # No confounding: one set, the empty one
  direct <- dag_json(dagitty::dagitty("dag { x [exposure] y [outcome] z x -> y z -> y }"))
  expect_identical(direct$analysis$adjustment_sets, list(list()))
  # A latent confounder: no set of observed variables works
  latent <- dag_json(dagitty::dagitty("dag { x [exposure] y [outcome] u [latent] x -> y u -> x u -> y }"))
  expect_identical(latent$analysis$adjustment_sets, list())
  # Two sets, each a list of names even with one name
  two <- dag_json(dagitty::dagitty("dag { x [exposure] y [outcome] a -> x a -> b b -> y x -> y }"))
  expect_setequal(vapply(two$analysis$adjustment_sets, function(set) set[[1]], ""), c("a", "b"))
  expect_true(all(lengths(two$analysis$adjustment_sets) == 1L))
})

test_that("implications map to x, y, and given", {
  skip_if_not_installed("dagitty")
  json <- dag_json(dagitty::dagitty("dag { a -> b -> c d -> c }"))
  implications <- json$analysis$implications
  has <- function(entry) any(vapply(implications, identical, logical(1), entry))
  expect_true(has(list(x = "a", y = "c", given = list("b"))))
  expect_true(has(list(x = "a", y = "d", given = list())))
  # Without an exposure and an outcome, there are no adjustment sets
  expect_null(json$analysis$adjustment_sets)
  expect_null(json$analysis$effect)
})

test_that("effect = 'direct' computes direct-effect adjustment sets", {
  skip_if_not_installed("dagitty")
  graph <- dagitty::dagitty("dag { x [exposure] y [outcome] x -> m -> y x -> y c -> m c -> y }")
  total <- unclass(framework:::.fw_dag_document(graph))
  direct <- unclass(framework:::.fw_dag_document(graph, effect = "direct"))
  expect_identical(total$analysis$adjustment_sets, list(I(character())))
  expect_identical(direct$analysis$effect, "direct")
  expect_identical(lapply(direct$analysis$adjustment_sets, as.character), list(c("c", "m")))
  expect_error(framework:::.fw_dag_document(graph, effect = "indirect"))
})

test_that("analysis that dagitty can't compute is left out", {
  skip_if_not_installed("dagitty")
  testthat::local_mocked_bindings(
    adjustmentSets = function(...) stop("boom"),
    impliedConditionalIndependencies = function(...) stop("boom"),
    .package = "dagitty"
  )
  json <- dag_json(smoking_dag())
  expect_null(json$analysis)
  expect_identical(json$kind, "dag")
})

test_that("labels come from ggdag and the labels argument wins", {
  skip_if_not_installed("dagitty")
  skip_if_not_installed("ggdag")
  graph <- ggdag::dagify(cancer ~ smoking + age, smoking ~ age,
                         exposure = "smoking", outcome = "cancer",
                         labels = c(smoking = "Smoking", cancer = "Lung cancer"))
  json <- dag_json(graph)
  expect_identical(json$labels, list(cancer = "Lung cancer", smoking = "Smoking"))

  document <- framework:::.fw_dag_document(graph, labels = c(smoking = "Smoking status", age = "Age",
                                                              nobody = "Not a node"))
  expect_identical(document$labels, list(age = "Age", cancer = "Lung cancer", smoking = "Smoking status"))
  expect_error(framework:::.fw_dag_document(graph, labels = c("unnamed")))
})

test_that("a tidy_dagitty publishes its graph and labels", {
  skip_if_not_installed("dagitty")
  skip_if_not_installed("ggdag")
  graph <- ggdag::dagify(cancer ~ smoking + age + genotype, smoking ~ age + genotype,
                         exposure = "smoking", outcome = "cancer", latent = "genotype",
                         labels = c(smoking = "Smoking", genotype = "Genotype"))
  tidy <- ggdag::tidy_dagitty(graph, seed = 1)
  json <- dag_json(tidy)
  expect_identical(json$source$class, list("tidy_dagitty"))
  expect_match(json$dagitty, "genotype [latent]", fixed = TRUE)
  # ggdag's own layout isn't sent as positions
  expect_false(grepl("pos=", json$dagitty, fixed = TRUE))
  expect_identical(json$labels, list(genotype = "Genotype", smoking = "Smoking"))
  # The latent genotype confounds smoking and cancer
  expect_identical(json$analysis$adjustment_sets, list())

  # A label set on the tidy data counts too
  tidy$data$label[tidy$data$name == "age"] <- "Age"
  expect_identical(dag_json(tidy)$labels$age, "Age")
})

test_that("code rides along when given", {
  skip_if_not_installed("dagitty")
  document <- framework:::.fw_dag_document(smoking_dag(), code = c("dag <- dagitty('dag { a -> b }')", "plot(dag)", ""))
  expect_identical(document$code, list(language = "r", text = "dag <- dagitty('dag { a -> b }')\nplot(dag)"))
  expect_null(framework:::.fw_dag_document(smoking_dag(), code = "  ")$code)
  expect_error(framework:::.fw_dag_document(smoking_dag(), code = 1))
})

test_that("only DAGs publish", {
  skip_if_not_installed("dagitty")
  expect_error(framework:::.fw_artifact_file(dagitty::dagitty("pdag { a -- b }"), withr::local_tempdir(), cloud = TRUE),
               "Only DAGs publish as a DAG; this graph is a pdag.", fixed = TRUE)
  expect_error(publish_dag(data.frame(x = 1)), "dagitty graph or a ggdag tidy_dagitty")
})

test_that("publish() and publish_dag() upload dag.json with kind dag", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("dagitty")
  cleanup <- setup_isolated_config()
  withr::defer(cleanup())
  withr::local_envvar(FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")

  sent <- list()
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      fields <- rlang::list2(...)
      sent[[length(sent) + 1L]] <<- list(fields = fields, name = basename(fields$file$path),
                                         json = jsonlite::read_json(fields$file$path, simplifyVector = FALSE))
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(version = 1L, url = "http://localhost:8080/d/abc"),
    .package = "httr2"
  )
  expect_message(publish(smoking_dag()), "Published version 1")
  expect_identical(sent[[1]]$name, "dag.json")
  expect_identical(sent[[1]]$fields$kind, "dag")
  expect_identical(sent[[1]]$fields$slug, "dag")
  expect_null(sent[[1]]$json$code)

  expect_message(url <- publish_dag(smoking_dag(), code = "dag <- dagitty('...')", slug = "smoking",
                                    title = "Smoking and cancer", visibility = "unlisted"),
                 "Published version 1")
  expect_identical(url, "http://localhost:8080/d/abc")
  expect_identical(sent[[2]]$fields$kind, "dag")
  expect_identical(sent[[2]]$fields$slug, "smoking")
  expect_identical(sent[[2]]$fields$title, "Smoking and cancer")
  expect_identical(sent[[2]]$fields$visibility, "unlisted")
  expect_identical(sent[[2]]$json$code$text, "dag <- dagitty('...')")
  expect_identical(sent[[2]]$json$source$class, list("dagitty"))
})
