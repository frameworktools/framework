# Code snippets: publish_snippet() records knitr output; fw_snippet() runs a
# block through evaluate. Cloud's ArtifactSnippet (framework-cloud
# app/Support/Snippets/ArtifactSnippet.php) is the source of truth for the
# document these tests check.

snippet_types <- c("code", "output", "message", "warning", "error")

local_snippet_records <- function(env = parent.frame()) {
  state <- framework:::.framework_env
  old <- state$snippets
  state$snippets <- list()
  withr::defer(state$snippets <- old, envir = env)
}

# The document as Cloud receives it: code_snippet.json, read back.
snippet_json <- function(document) {
  dir <- withr::local_tempdir()
  path <- framework:::.fw_artifact_file(document, dir, cloud = TRUE)
  expect_identical(basename(path), "code_snippet.json")
  jsonlite::read_json(path, simplifyVector = FALSE)
}

# What ArtifactSnippet::normalize() requires of every snippet.
expect_cloud_shape <- function(json) {
  expect_identical(json$schema, "framework.artifact/v1")
  expect_identical(json$kind, "code_snippet")
  expect_true(json$source$language %in% c("r", "python", "stata"))
  blocks <- json$snippet$blocks
  expect_true(is.list(blocks) && length(blocks) >= 1L && length(blocks) <= 200L)
  for (block in blocks) {
    expect_true(block$type %in% snippet_types)
    expect_true(is.character(block$text) && length(block$text) == 1L)
    if (identical(block$type, "code")) expect_null(block$folded)
    if (!is.null(block$folded)) expect_true(is.logical(block$folded))
  }
  expect_true(any(vapply(blocks, function(b) identical(b$type, "code"), logical(1))))
  if (!is.null(json$snippet$width)) {
    expect_true(is.numeric(json$snippet$width) && json$snippet$width >= 20 && json$snippet$width <= 1000)
  }
  if (!is.null(json$source$lines)) {
    expect_length(json$source$lines, 2L)
    expect_true(json$source$lines[[2]] >= json$source$lines[[1]])
  }
  for (link in json$display$links) {
    expect_true(link$rel %in% c("notebook", "model"))
    expect_true(!is.null(link$url) || identical(link$rel, "model") && !is.null(link$artifact))
  }
}

test_that("knitr's comment prefix is removed from each line", {
  uncomment <- framework:::.fw_snippet_uncomment
  expect_identical(uncomment("## a\n##\n##   b", "##"), "a\n\n  b")
  expect_identical(uncomment("#> x\n#> y", "#>"), "x\ny")
  expect_identical(uncomment("## a", NA_character_), "## a")
  expect_identical(uncomment("## a", ""), "## a")
  # A line without the prefix is left alone
  expect_identical(uncomment("## a\nb", "##"), "a\nb")
})

test_that("hook wrappers record each piece by chunk label and pass it through unchanged", {
  local_snippet_records()
  rendered <- list()
  previous <- function(x, options) {
    rendered[[length(rendered) + 1L]] <<- x
    paste0("<", paste(x, collapse = "\n"), ">")
  }
  options <- list(label = "fit", comment = "##", results = "markup")
  source_hook <- framework:::.fw_snippet_hook("source", previous)
  output_hook <- framework:::.fw_snippet_hook("output", previous)
  warning_hook <- framework:::.fw_snippet_hook("warning", previous)

  expect_true(isTRUE(attr(source_hook, "framework_snippet_hook")))
  expect_identical(source_hook(c("x <- 1:3", "summary(x)"), options), "<x <- 1:3\nsummary(x)>")
  expect_identical(output_hook("##    Min. Max. \n##       1    3 \n", options),
                   "<##    Min. Max. \n##       1    3 \n>")
  warning_hook("## Warning: careful\n", options)
  framework:::.fw_snippet_hook("message", previous)("## other chunk\n", list(label = "other", comment = "##"))

  record <- framework:::.framework_env$snippets$fit
  expect_identical(vapply(record$blocks, `[[`, "", "type"), c("code", "output", "warning"))
  expect_identical(record$blocks[[1]]$text, "x <- 1:3\nsummary(x)")
  expect_identical(record$blocks[[2]]$text, "   Min. Max. \n      1    3 ")
  expect_identical(record$blocks[[3]]$text, "Warning: careful")
  expect_identical(framework:::.framework_env$snippets$other$blocks[[1]]$text, "other chunk")
  # The previous hook saw knitr's text, prefix and all
  expect_identical(rendered[[2]], "##    Min. Max. \n##       1    3 \n")
})

test_that("as-is output keeps its text, and blank pieces are skipped", {
  local_snippet_records()
  framework:::.fw_snippet_record("output", "## A heading\n", list(label = "a", comment = "##", results = "asis"))
  framework:::.fw_snippet_record("output", "\n\n", list(label = "a", comment = "##", results = "markup"))
  blocks <- framework:::.framework_env$snippets$a$blocks
  expect_length(blocks, 1L)
  expect_identical(blocks[[1]]$text, "## A heading")
})

test_that("a knit records code, output, messages, warnings, and errors, and leaves plots out", {
  skip_if_not_installed("knitr")
  local_snippet_records()
  dir <- withr::local_tempdir()
  rmd <- file.path(dir, "analysis.Rmd")
  writeLines(c(
    "```{r setup, include = FALSE}",
    "framework:::.fw_snippet_hooks_install()",
    "```",
    "",
    "```{r fit, error = TRUE}",
    "# Fit",
    "fit <- lm(mpg ~ wt, data = mtcars)",
    "message(\"fitted\")",
    "warning(\"check the residuals\")",
    "round(coef(fit), 2)",
    "plot(1:3)",
    "stop(\"boom\")",
    "```",
    "",
    "```{r quiet, message = FALSE, warning = FALSE, results = \"hide\"}",
    "message(\"hidden\")",
    "print(1)",
    "```",
    "",
    "```{r record}",
    "records <- framework:::.framework_env$snippets",
    "hooks_active <- framework:::.fw_snippet_hooks_active()",
    "```"
  ), rmd)
  env <- new.env()
  # Another test's knit can leave root.dir at a folder that's gone
  root_dir <- knitr::opts_knit$get("root.dir")
  knitr::opts_knit$set(root.dir = dir)
  withr::defer(knitr::opts_knit$set(root.dir = root_dir))
  withr::with_dir(dir, suppressMessages(knitr::knit(rmd, output = file.path(dir, "analysis.md"),
                                                    quiet = TRUE, envir = env)))
  expect_true(env$hooks_active)
  fit <- env$records$fit
  types <- vapply(fit$blocks, `[[`, "", "type")
  expect_identical(types, c("code", "message", "code", "warning", "code", "output", "code", "code", "error"))
  expect_identical(fit$blocks[[1]]$text, "# Fit\nfit <- lm(mpg ~ wt, data = mtcars)\nmessage(\"fitted\")")
  expect_identical(fit$blocks[[2]]$text, "fitted")
  expect_match(fit$blocks[[4]]$text, "^Warning.*check the residuals")
  # knitr trims the trailing space after the last value
  expect_identical(fit$blocks[[6]]$text, "(Intercept)          wt \n      37.29       -5.34")
  expect_match(fit$blocks[[9]]$text, "^Error.*boom")
  expect_false(any(grepl("##", vapply(fit$blocks, `[[`, "", "text"), fixed = TRUE)))
  # Chunk options apply: only the code of the quiet chunk
  expect_identical(vapply(env$records$quiet$blocks, `[[`, "", "type"), "code")
  # The chunk's code lines, without the fences
  expect_identical(framework:::.fw_snippet_code_lines(fit$input, fit$chunk_lines, fit$blocks), c(6L, 12L))

  json <- snippet_json(framework:::.fw_snippet_document(fit$blocks, list(language = "r", label = "fit"), fit$width))
  expect_cloud_shape(json)
  # Adjacent code blocks join
  expect_identical(vapply(json$snippet$blocks, `[[`, "", "type"),
                   c("code", "message", "code", "warning", "code", "output", "code", "error"))
  expect_identical(json$snippet$blocks[[7]]$text, "plot(1:3)\nstop(\"boom\")")
})

test_that("output = FALSE sends code only, and folded marks output blocks", {
  blocks <- list(
    list(type = "code", text = "summary(fit)"),
    list(type = "output", text = "Coefficients:"),
    list(type = "output", text = "  wt -5.3"),
    list(type = "message", text = "note")
  )
  source <- list(language = "r", label = "fit")
  build <- framework:::.fw_snippet_document

  code_only <- snippet_json(build(blocks, source, 80L, output = FALSE))
  expect_identical(vapply(code_only$snippet$blocks, `[[`, "", "type"), "code")
  expect_cloud_shape(code_only)

  folded <- snippet_json(build(blocks, source, 80L, folded = TRUE))
  expect_cloud_shape(folded)
  expect_identical(vapply(folded$snippet$blocks, `[[`, "", "type"), c("code", "output", "message"))
  # Adjacent output joins
  expect_identical(folded$snippet$blocks[[2]]$text, "Coefficients:\n  wt -5.3")
  expect_true(folded$snippet$blocks[[2]]$folded)
  expect_null(folded$snippet$blocks[[1]]$folded)
  expect_null(folded$snippet$blocks[[3]]$folded)

  open <- snippet_json(build(blocks, source, 80L, folded = FALSE))
  expect_false(open$snippet$blocks[[2]]$folded)

  auto <- snippet_json(build(blocks, source, 80L))
  expect_null(auto$snippet$blocks[[2]]$folded)
  expect_null(auto$display)
  expect_identical(auto$snippet$width, 80L)

  expect_null(build(list(list(type = "output", text = "1")), source))
})

test_that("links take a notebook URL and a model slug or URL", {
  links <- framework:::.fw_snippet_links
  expect_identical(
    links(list(notebook = "https://example.org/analysis", model = "fit-model")),
    list(list(rel = "notebook", url = "https://example.org/analysis"),
         list(rel = "model", artifact = "fit-model"))
  )
  expect_identical(links(c(model = "https://example.org/m")), list(list(rel = "model", url = "https://example.org/m")))
  expect_null(links(NULL))
  expect_error(links(list(notebook = "http://example.org")), "notebook link takes an https URL")
  expect_error(links(list(model = "not a slug")), "artifact slug")
  expect_error(links(list(paper = "https://example.org")), "named")
  expect_error(links(list("https://example.org")), "named")

  json <- snippet_json(framework:::.fw_snippet_document(
    list(list(type = "code", text = "1")), list(language = "r"),
    links = list(notebook = "https://example.org/analysis", model = "fit-model")
  ))
  expect_cloud_shape(json)
  expect_identical(json$display$links[[2]], list(rel = "model", artifact = "fit-model"))
})

test_that("the source names the file from the repository top, the commit, and a repository only when given", {
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  dir <- withr::local_tempdir()
  withr::with_dir(dir, {
    system2("git", c("init", "-q"))
    system2("git", c("-c", "user.email=t@example.org", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"))
  })
  dir.create(file.path(dir, "notebooks"))
  file <- file.path(dir, "notebooks", "fit.qmd")
  writeLines("x", file)
  local_snippet_records()

  source <- withr::with_dir(dir, framework:::.fw_snippet_source(file, "fit", c(3L, 5L)))
  expect_identical(source$file, "notebooks/fit.qmd")
  expect_match(source$commit, "^[0-9a-f]{40}$")
  expect_identical(source$lines, list(3L, 5L))
  expect_null(source$repository)

  given <- withr::with_dir(dir, framework:::.fw_snippet_source(file, "fit", repository = "https://github.com/owner/repo"))
  expect_identical(given$repository, "https://github.com/owner/repo")
  expect_error(framework:::.fw_snippet_repository("git@github.com:owner/repo.git"), "https URL")

  # publish.repository in settings.yml
  yaml::write_yaml(list(publish = list(repository = "https://github.com/owner/study")), file.path(dir, "settings.yml"))
  from_settings <- withr::with_dir(dir, framework:::.fw_snippet_source(file, "fit"))
  expect_identical(from_settings$repository, "https://github.com/owner/study")
})

test_that("publish_snippet() outside a render publishes nothing and says why", {
  withr::local_options(knitr.in.progress = NULL)
  expect_message(result <- publish_snippet("fit"), "outside quarto render or rmarkdown::render")
  expect_null(result)
})

test_that("a snippet uploads as code_snippet.json with kind code_snippet", {
  skip_if_not_installed("httr2")
  cleanup <- setup_isolated_config()
  withr::defer(cleanup())
  withr::local_envvar(FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")

  sent <- list()
  response <- list(version = 2L, unchanged = FALSE, url = "http://localhost:8080/d/abc")
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      fields <- rlang::list2(...)
      sent[[length(sent) + 1L]] <<- list(fields = fields, name = basename(fields$file$path),
                                         json = jsonlite::read_json(fields$file$path, simplifyVector = FALSE))
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) response,
    .package = "httr2"
  )
  document <- framework:::.fw_snippet_document(
    list(list(type = "code", text = "summary(fit)"), list(type = "output", text = "Coefficients")),
    list(language = "r", label = "Fit Model"), 80L, folded = TRUE
  )
  expect_message(url <- framework:::.fw_snippet_publish(document, "Fit Model", visibility = "unlisted"),
                 "Published version 2: http://localhost:8080/d/abc", fixed = TRUE)
  expect_identical(url, "http://localhost:8080/d/abc")
  expect_identical(sent[[1]]$name, "code_snippet.json")
  expect_identical(sent[[1]]$fields$kind, "code_snippet")
  expect_identical(sent[[1]]$fields$slug, "fit-model")
  expect_identical(sent[[1]]$fields$title, "Fit Model")
  expect_identical(sent[[1]]$fields$visibility, "unlisted")
  expect_cloud_shape(sent[[1]]$json)

  # The same snippet again: Cloud adds no version
  response <- list(version = 2L, unchanged = TRUE, url = "http://localhost:8080/d/abc")
  expect_message(framework:::.fw_snippet_publish(document, "Fit Model"),
                 "Unchanged, still version 2: http://localhost:8080/d/abc", fixed = TRUE)
})

test_that("fw_snippet() runs the block in the caller, prints its output, and publishes code and text", {
  skip_if_not_installed("evaluate")
  published <- NULL
  testthat::local_mocked_bindings(.fw_snippet_publish = function(document, label, ...) {
    published <<- list(document = document, label = label, options = list(...))
    "https://cloud.example.org/d/abc"
  })
  dir <- withr::local_tempdir()
  script <- file.path(dir, "fit.R")
  writeLines(c(
    "library(stats)",
    "fw_snippet(\"fit-model\", {",
    "  # Fit the model",
    "  fit <- lm(mpg ~ wt, data = mtcars)",
    "  message(\"fitted\")",
    "  round(coef(fit), 2)",
    "  plot(1:3)",
    "}, folded = TRUE, visibility = \"unlisted\")"
  ), script)
  env <- new.env(parent = asNamespace("framework"))
  pdf(NULL)
  withr::defer(grDevices::dev.off())
  printed <- capture.output(expect_message(sys.source(script, envir = env, keep.source = TRUE), "fitted"))

  expect_true(exists("fit", envir = env, inherits = FALSE))
  expect_identical(printed, c("(Intercept)          wt ", "      37.29       -5.34 "))
  expect_identical(published$label, "fit-model")
  expect_identical(published$options, list(visibility = "unlisted"))
  json <- snippet_json(published$document)
  expect_cloud_shape(json)
  expect_identical(vapply(json$snippet$blocks, `[[`, "", "type"), c("code", "message", "code", "output", "code"))
  expect_identical(json$snippet$blocks[[1]]$text, "# Fit the model\nfit <- lm(mpg ~ wt, data = mtcars)\nmessage(\"fitted\")")
  expect_identical(json$snippet$blocks[[5]]$text, "plot(1:3)")
  expect_true(json$snippet$blocks[[4]]$folded)
  expect_identical(json$source$label, "fit-model")
  expect_identical(json$source$lines, list(3L, 7L))
  expect_identical(json$source$file, "fit.R")
  expect_null(json$source$deparsed)
})

test_that("fw_snippet() deparses code without source references and says so", {
  skip_if_not_installed("evaluate")
  published <- NULL
  testthat::local_mocked_bindings(.fw_snippet_publish = function(document, label, ...) {
    published <<- document
    invisible(NULL)
  })
  code <- parse(text = "fw_snippet('sum', {\n  # dropped\n  x <- 1 + 1\n  x\n}, output = FALSE)", keep.source = FALSE)
  env <- new.env(parent = asNamespace("framework"))
  expect_message(capture.output(eval(code[[1]], env)), "deparsed")
  expect_identical(env$x, 2)
  expect_identical(published$snippet$blocks, list(list(type = "code", text = "x <- 1 + 1\nx")))
  expect_true(published$source$deparsed)
  expect_null(published$source$lines)
})

test_that("fw_snippet() publishes nothing when the block fails, and rejects bad arguments", {
  skip_if_not_installed("evaluate")
  called <- FALSE
  testthat::local_mocked_bindings(.fw_snippet_publish = function(...) called <<- TRUE)
  expect_error(capture.output(fw_snippet("bad", {
    1 + 1
    stop("boom")
  })), "boom")
  expect_false(called)
  expect_error(fw_snippet("bad", 1 + 1), "braced block")
  expect_error(fw_snippet("bad", { 1 }, colour = "red"), "by name")
})
