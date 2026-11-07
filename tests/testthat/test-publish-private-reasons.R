# Confirming notebooks and objects that can show private data (parity B1)

local_reasons_project <- function(sensitive, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  settings <- list(
    project_name = "Test",
    data = list(inputs = list(
      ids = "inputs/private/raw/ids.csv",
      flagged = list(path = "inputs/raw/flagged.csv", private = TRUE),
      survey = "inputs/raw/survey.csv"
    )),
    publish = list(default = "site", destinations = list(
      site = list(driver = "folder", path = "site", visibility = "public")
    ))
  )
  if (sensitive) settings$security <- list(sensitive = TRUE)
  yaml::write_yaml(list(default = settings), "settings.yml")
  testthat::local_mocked_bindings(.fw_project_token = function(...) NULL, .env = env)
  dir
}

test_that("sensitive projects confirm objects and notebooks", {
  local_reasons_project(sensitive = TRUE)
  frame <- data.frame(n = 1)
  expect_warning(
    expect_error(publish(frame, slug = "counts"), "include_private = TRUE"),
    "sensitive: true), and this data frame can show it"
  )
  expect_warning(expect_error(publish_data(frame, "tables/counts.csv"), "include_private = TRUE"), "sensitive")
  dir.create("notebooks")
  writeLines(c("---", "title: S", "---", "", "```{r}", "x <- 1", "```"), "notebooks/summary.qmd")
  expect_warning(
    expect_error(publish_notebook("notebooks/summary.qmd"), "Not publishing this from a non-interactive session"),
    "the rendered notebook summary.qmd can show it"
  )
  expect_warning(expect_error(publish("notebooks/summary.qmd"), "include_private = TRUE"), "sensitive")
  expect_false(dir.exists("site"))
  expect_true(nzchar(suppressMessages(publish(frame, slug = "counts", include_private = TRUE))))
  expect_true(file.exists("site/counts/artifact.json"))
})

test_that("an interactive session confirms an object once", {
  local_reasons_project(sensitive = TRUE)
  testthat::local_mocked_bindings(is_interactive = function(...) TRUE, .package = "rlang")
  asked <- 0L
  answer <- FALSE
  testthat::local_mocked_bindings(askYesNo = function(...) {
    asked <<- asked + 1L
    answer
  }, .package = "utils")
  expect_error(suppressWarnings(publish(data.frame(n = 1), slug = "counts")), "Cancelled")
  answer <- TRUE
  suppressWarnings(suppressMessages(publish(data.frame(n = 1), slug = "counts")))
  expect_identical(asked, 2L)
  expect_true(file.exists("site/counts/artifact.json"))
})

test_that("other projects publish objects without asking", {
  local_reasons_project(sensitive = FALSE)
  expect_no_warning(suppressMessages(publish(data.frame(n = 1), slug = "counts")))
  expect_true(file.exists("site/counts/artifact.json"))
})

test_that("notebook strings that name private data are found", {
  local_reasons_project(sensitive = FALSE)
  writeLines(c(
    "---", "title: A", "---", "", "This is private work.", "", "```{r}",
    'a <- data_read("inputs/private/raw/ids.csv")',
    "b <- data_read('inputs.ids')",
    'c <- data_read("inputs.flagged")',
    'd <- data_read("inputs.survey")',
    'e <- data_read("inputs.private.raw.other")',
    'f <- data_read("inputs.ids")',
    'print("private results are not shown")',
    "```"
  ), "a.qmd")
  expect_identical(framework:::.fw_notebook_private_reads("a.qmd"), c(
    "inputs/private/raw/ids.csv", "inputs.ids", "inputs.flagged", "inputs.private.raw.other"
  ))
  writeLines(paste0(
    '{"cells": [{"cell_type": "markdown", "source": ["\\"inputs/private/x.csv\\""]},',
    ' {"cell_type": "code", "source": ["df <- data_read(\\"inputs.ids\\")"]}]}'
  ), "b.ipynb")
  expect_identical(framework:::.fw_notebook_private_reads("b.ipynb"), "inputs.ids")
  writeLines(c("```{r}", 'x <- "inputs\\\\Confidential\\\\a.csv"', 'y <- "my secret_sensitive_notes"',
               paste0('z <- "', strrep("a", 495), '/private"'), "```"), "c.Rmd")
  expect_identical(framework:::.fw_notebook_private_reads("c.Rmd"), "inputs\\\\Confidential\\\\a.csv")
})

test_that("a notebook reading private data needs confirmation in any project", {
  local_reasons_project(sensitive = FALSE)
  dir.create("notebooks")
  writeLines(c("```{r}", 'data_read("inputs.ids")', "```"), "notebooks/report.qmd")
  expect_warning(
    expect_error(publish_notebook("notebooks/report.qmd"), "include_private = TRUE"),
    "report.qmd reads private data: inputs.ids.", fixed = TRUE
  )
  reasons <- framework:::.fw_publish_reasons("notebooks/report.qmd")
  expect_identical(reasons, "report.qmd reads private data: inputs.ids.")
  writeLines(c("```{r}", paste0('data_read("inputs/private/', 1:5, '.csv")'), "```"), "notebooks/many.qmd")
  expect_identical(
    framework:::.fw_publish_reasons("notebooks/many.qmd"),
    "many.qmd reads private data: inputs/private/1.csv, inputs/private/2.csv, inputs/private/3.csv, and 2 more."
  )
})
