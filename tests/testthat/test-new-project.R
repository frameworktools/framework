# new_project() builds layers and creates the project the same way
# framework.pub does, with tools, package sets, and skill sets

local_new <- function(type = "project", ..., env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  location <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(new_project("Study", location, type = type, browse = FALSE, ...))
  location
}

test_that("Framework's project structure keeps its layout, Quarto, and skills", {
  dir <- local_new()
  expect_true(file.exists(file.path(dir, "settings", "packages.yml")))
  expect_true(file.exists(file.path(dir, "_quarto.yml")))
  expect_true(file.exists(file.path(dir, "scaffold.R")))
  expect_true(file.exists(file.path(dir, ".env")))
  settings <- settings_read(file.path(dir, "settings.yml"))
  expect_true(settings$tools$quarto)
  expect_true(dir.exists(file.path(dir, "inputs", "raw")))
  expect_true(file.exists(file.path(dir, "AGENTS.md")))
  expect_true(any(grepl("ggplot2-exploring", readLines(file.path(dir, "AGENTS.md")))))
})

test_that("tools, package sets, and skill sets are applied", {
  dir <- local_new(tools = c("quarto_slides", "targets"), package_sets = "tidyverse-analysis",
                   skill_sets = "framework")
  settings <- settings_read(file.path(dir, "settings.yml"))
  expect_true(settings$tools$quarto_slides)
  expect_true(settings$tools$targets)
  expect_true(file.exists(file.path(dir, "_targets.R")))
  pkgs <- vapply(settings$packages$default_packages, `[[`, "", "name")
  expect_true(all(c("targets", "dplyr", "lubridate") %in% pkgs))
  skills <- list.files(file.path(dir, ".claude", "skills"))
  expect_true("framework-workflow" %in% skills)
  expect_false("ggplot2-exploring" %in% skills)
})

test_that("a named logical turns a structure's tool off", {
  dir <- local_new(tools = c(quarto = FALSE, targets = TRUE))
  expect_false(file.exists(file.path(dir, "_quarto.yml")))
  expect_false(settings_read(file.path(dir, "settings.yml"))$tools$quarto)
  expect_error(local_new(tools = c(quarto = FALSE, quarto_slides = TRUE)), "another tool you chose needs it")
})

test_that("bare has no core files, and unknown tools are errors", {
  dir <- local_new("bare")
  expect_false(file.exists(file.path(dir, "scaffold.R")))
  expect_false(file.exists(file.path(dir, ".env")))
  expect_false(file.exists(file.path(dir, "_quarto.yml")))
  expect_error(local_new(tools = "pants"), "Unknown tool")
  expect_error(local_new(type = "Bad Type"), "pattern")
})

test_that("make_notebook() follows the tools when Quarto is off", {
  expect_identical(framework:::.default_notebook_type(list()), "quarto")
  expect_identical(framework:::.default_notebook_type(list(tools = list(quarto = TRUE))), "quarto")
  expect_identical(framework:::.default_notebook_type(list(tools = list(quarto = FALSE, jupyter = TRUE))), "jupyter")

  dir <- local_new(tools = c(quarto = FALSE, jupyter = TRUE))
  withr::local_dir(dir)
  path <- suppressMessages(make_notebook("First look"))
  expect_match(path, "first-look\\.ipynb$")
  nb <- jsonlite::read_json(path)
  expect_identical(nb$metadata$kernelspec$name, "ir")
  expect_identical(unlist(nb$cells[[2]]$source), "framework::scaffold()")
  expect_true("IRkernel" %in% vapply(settings_read()$packages$default_packages, `[[`, "", "name"))
})

test_that("make_notebook() reads the project's scaffold.notebook_format", {
  dir <- local_new()
  withr::local_dir(dir)
  scaffold_file <- file.path("settings", "scaffold.yml")
  settings <- yaml::read_yaml(scaffold_file)
  settings$scaffold$notebook_format <- "jupyter"
  yaml::write_yaml(settings, scaffold_file)
  path <- suppressMessages(make_notebook("First look"))
  expect_match(path, "first-look\\.ipynb$")

  expect_no_error(spec_resolve(list(list(scaffold = list(workflow = "jupyter", notebook_format = "jupyter"))), name = "Jupyter"))
})

test_that("scaffold.workflow must fit the notebook format", {
  resolve <- function(scaffold) spec_resolve(list(list(scaffold = scaffold)), name = "W")
  expect_no_error(resolve(list(workflow = "quarto", notebook_format = "rmarkdown")))
  expect_no_error(resolve(list(workflow = "scripts", notebook_format = "script")))
  expect_no_error(resolve(list(workflow = "jupyter")))
  expect_error(resolve(list(workflow = "scripts", notebook_format = "quarto")), "does not fit the scripts workflow")
  expect_error(resolve(list(workflow = "jupyter", notebook_format = "rmarkdown")), "does not fit the jupyter workflow")
  expect_error(resolve(list(workflow = "marimo")), "must be quarto, jupyter, or scripts")
})

test_that("a Scripts-only project makes R scripts in its scripts folder", {
  dir <- local_new()
  withr::local_dir(dir)
  scaffold_file <- file.path("settings", "scaffold.yml")
  settings <- yaml::read_yaml(scaffold_file)
  settings$scaffold$notebook_format <- NULL
  settings$scaffold$workflow <- "scripts"
  yaml::write_yaml(settings, scaffold_file)
  path <- suppressMessages(make_notebook("Clean data"))
  expect_identical(path, file.path("scripts", "clean-data.R"))
})

test_that("the Jupyter kernel step is only offered", {
  withr::local_options(rlang_interactive = FALSE)
  expect_message(res <- framework:::.offer_jupyter_kernel(), "installspec")
  expect_false(res)
})

test_that("new() makes a Standard Project by default, and bare on request", {
  seen <- NULL
  local_mocked_bindings(
    .fw_cloud_token = function(...) NULL,
    new_project = function(name = NULL, location = NULL, type = NULL, ...) {
      seen <<- type
      invisible(NULL)
    }
  )
  new("Study", tempfile(), browse = FALSE)
  expect_identical(seen, "project")
  new("Study", tempfile(), type = "bare", browse = FALSE)
  expect_identical(seen, "bare")
})
