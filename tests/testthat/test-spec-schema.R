schema_path <- function(name) {
  path <- system.file("schema", name, package = "framework")
  if (!nzchar(path)) path <- testthat::test_path("..", "..", "inst", "schema", name)
  path
}

schema_validator <- function(name) {
  testthat::skip_if_not_installed("jsonvalidate")
  jsonvalidate::json_schema$new(schema_path(name), engine = "ajv")
}

as_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")

minimal_spec <- function() {
  list(
    spec_version = 1,
    name = "Test project",
    type = "project",
    language = "r",
    author = list(name = "A", email = "a@example.com", affiliation = ""),
    directories = list(notebooks = "notebooks", logs = "logs"),
    extra_directories = setNames(list(), character()),
    render_dirs = list(notebooks = "outputs/notebooks"),
    packages = list(
      use_renv = FALSE,
      default_packages = list(dplyr = list(source = "cran", auto_attach = TRUE))
    ),
    git = list(use_git = TRUE, hooks = list(ai_sync = FALSE), gitignore_content = ""),
    ai = list(enabled = TRUE, assistants = list(claude = TRUE), agents_md = "stub"),
    scaffold = list(
      seed_on_scaffold = FALSE, seed = "", set_theme_on_scaffold = TRUE,
      ggplot_theme = "theme_minimal"
    ),
    connections = list(
      default_database = "framework",
      databases = list(framework = list(driver = "sqlite", database = "framework.db")),
      storage_buckets = setNames(list(), character())
    ),
    security = list(sensitive = FALSE),
    env = setNames(list(), character()),
    data_hooks = setNames(list(), character()),
    files = setNames(list(), character()),
    skills = list(`framework-workflow` = list(package = TRUE))
  )
}

test_that("committed schemas match data-raw/spec_schema.R", {
  generator <- testthat::test_path("..", "..", "data-raw", "spec_schema.R")
  skip_if_not(file.exists(generator), "generator only exists in the source tree")

  out_dir <- withr::local_tempdir()
  withr::with_envvar(c(FW_SCHEMA_OUT = out_dir), {
    withr::with_dir(testthat::test_path("..", ".."), {
      suppressMessages(source("data-raw/spec_schema.R", local = new.env()))
    })
  })

  for (name in c("spec.v1.json", "layer.v1.json", "layers.v1.json")) {
    expect_identical(
      readLines(file.path(out_dir, name)),
      readLines(schema_path(name)),
      info = paste(name, "is stale; run Rscript data-raw/spec_schema.R")
    )
  }
})

test_that("a complete spec validates against the resolved schema", {
  v <- schema_validator("spec.v1.json")
  expect_true(v$validate(as_json(minimal_spec())))
})

test_that("the resolved schema rejects incomplete or malformed specs", {
  v <- schema_validator("spec.v1.json")

  missing_type <- minimal_spec()
  missing_type$type <- NULL
  expect_false(v$validate(as_json(missing_type)))

  unknown_key <- minimal_spec()
  unknown_key$surprise <- TRUE
  expect_false(v$validate(as_json(unknown_key)))

  null_dir <- minimal_spec()
  null_dir$directories$logs <- NA
  expect_false(v$validate(as_json(null_dir)))

  bad_assistant <- minimal_spec()
  bad_assistant$ai$assistants <- list(clippy = TRUE)
  expect_false(v$validate(as_json(bad_assistant)))
})

test_that("a partial layer validates, and null entries are allowed", {
  v <- schema_validator("layer.v1.json")

  layer <- list(
    directories = list(inputs_raw = NULL, inputs_private_raw = "inputs/private/raw"),
    security = list(sensitive = TRUE),
    skills = list(`framework-sensitive-data` = list(package = TRUE), old = NULL)
  )
  json <- jsonlite::toJSON(layer, auto_unbox = TRUE, null = "null")
  expect_true(v$validate(json))
})

test_that("the layer schema rejects unsafe paths and malformed entries", {
  v <- schema_validator("layer.v1.json")

  expect_false(v$validate(as_json(list(files = list(`../escape.R` = list(content = "x"))))))
  expect_false(v$validate(as_json(list(files = list(`/etc/passwd` = list(content = "x"))))))
  expect_false(v$validate(as_json(list(directories = list(raw = "../outside")))))
  expect_false(v$validate(as_json(list(skills = list(`Bad Name` = list(package = TRUE))))))
  expect_false(v$validate(as_json(list(skills = list(ok = list(package = TRUE, content = "x"))))))
  expect_false(v$validate(as_json(list(packages = list(default_packages = list(dplyr = list(auto_attach = TRUE)))))))
  expect_false(v$validate(as_json(list(env = list(`BAD-NAME` = "")))))
  expect_false(v$validate(as_json(list(data_hooks = list(inputs_raw = "fetch_raw")))))
})

test_that("the layers envelope validates and checks each layer", {
  v <- schema_validator("layers.v1.json")

  envelope <- list(
    spec_version = 1,
    name = "My Study",
    author = list(name = "A", email = "a@example.com", affiliation = ""),
    layers = list(
      list(kind = "base", key = "project", version = 3, layer = list(type = "project")),
      list(kind = "facet", key = "restricted-data", version = 1,
           layer = list(security = list(sensitive = TRUE), directories = list(inputs_raw = NULL)))
    )
  )
  expect_true(v$validate(jsonlite::toJSON(envelope, auto_unbox = TRUE, null = "null")))

  bad_layer <- envelope
  bad_layer$layers[[2]]$layer$files <- list(`../x` = list(content = ""))
  expect_false(v$validate(as_json(bad_layer)))

  bad_kind <- envelope
  bad_kind$layers[[1]]$kind <- "plugin"
  expect_false(v$validate(as_json(bad_kind)))
})

test_that("the schemas accept Python package names, hooks, and notebook formats", {
  skip_if_not_installed("jsonvalidate")
  v <- jsonvalidate::json_schema$new(schema_path("layer.v1.json"), engine = "ajv")
  layer <- list(
    language = "python",
    packages = list(default_packages = list(
      `scikit-learn` = list(source = "pypi", auto_attach = FALSE),
      python_dateutil = list(source = "pypi", auto_attach = FALSE)
    )),
    data_hooks = list(restricted = "hooks/fetch.py::fetch_data"),
    scaffold = list(notebook_format = "jupyter"),
    source = list(origin = "python")
  )
  expect_true(v$validate(jsonlite::toJSON(layer, auto_unbox = TRUE)))

  # R's own check still refuses what R cannot build
  spec <- spec_resolve(list(list(type = "project")), name = "P")
  spec$packages$default_packages$numpy <- list(source = "pypi", auto_attach = FALSE)
  spec$data_hooks$x <- "hooks/fetch.py::fetch"
  spec$scaffold$notebook_format <- "marimo"
  problems <- spec_check(spec)
  expect_match(problems, "source must be cran", all = FALSE)
  expect_match(problems, "file.R::function", all = FALSE)
  expect_match(problems, "notebook_format", all = FALSE)
})

test_that("Stata specs need no R or Python sections, and layers may omit kind", {
  skip_if_not_installed("jsonvalidate")
  v <- jsonvalidate::json_schema$new(schema_path("spec.v1.json"), engine = "ajv")
  stata <- minimal_spec()
  stata$language <- "stata"
  stata[c("render_dirs", "packages", "scaffold", "connections")] <- NULL
  expect_true(v$validate(as_json(stata)))

  python <- stata
  python$language <- "python"
  expect_false(v$validate(as_json(python)))
  expect_true(v$validate(as_json(minimal_spec())))

  layers <- jsonvalidate::json_schema$new(schema_path("layers.v1.json"), engine = "ajv")
  envelope <- list(spec_version = 1, name = "P", layers = list(list(layer = list(language = "stata"))))
  expect_true(layers$validate(jsonlite::toJSON(envelope, auto_unbox = TRUE)))
})

test_that("type is a free label, and tools and core_files are optional", {
  v <- schema_validator("spec.v1.json")
  spec <- minimal_spec()
  spec$type <- "lab_pipeline"
  spec$core_files <- FALSE
  spec$settings_layout <- "flat"
  spec$tools <- list(quarto = TRUE, quarto_slides = FALSE, renv = TRUE)
  expect_true(v$validate(as_json(spec)))

  for (bad in list(list(type = "Lab Pipeline"), list(tools = list(quarto = "yes")),
                   list(tools = list(`Quarto` = TRUE)), list(core_files = "no"),
                   list(settings_layout = "nested"))) {
    expect_false(v$validate(as_json(utils::modifyList(minimal_spec(), bad))), info = names(bad))
  }

  layer <- schema_validator("layer.v1.json")
  expect_true(layer$validate(as_json(list(tools = list(quarto = NULL, targets = TRUE)))))

  checked <- spec_check(utils::modifyList(minimal_spec(), list(type = "lab_pipeline", tools = list(renv = TRUE))))
  expect_false(any(grepl("type|tools|unknown section", checked)))
  expect_match(spec_check(utils::modifyList(minimal_spec(), list(type = "Lab"))), "lowercase id", all = FALSE)
  expect_match(spec_check(utils::modifyList(minimal_spec(), list(tools = list(renv = "on")))),
               "tools.renv must be true or false", all = FALSE)
})
