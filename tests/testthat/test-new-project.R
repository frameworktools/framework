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
