# data_save() by a name already in the catalog saves to that entry and leaves
# it alone, as Stata's fw_save and framework-py do

local_entry_project <- function(env = parent.frame()) {
  dir <- create_test_project()
  withr::defer(cleanup_test_dir(dir), envir = env)
  withr::local_dir(dir, .local_envir = env)
  cfg <- yaml::read_yaml("settings.yml")
  cfg$default$data <- "settings/data.yml"
  yaml::write_yaml(cfg, "settings.yml")
  dir.create("settings", showWarnings = FALSE)
  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    "data:",
    "  inputs:",
    "    intermediate:",
    "      clean:",
    "        path: inputs/intermediate/clean.csv",
    "        type: csv",
    "        description: One row per student.",
    "        notes: kept as written"
  ), "settings/data.yml")
  dir
}

frame <- data.frame(id = 1:2, score = c(3.5, NA))

test_that("data_save() by an existing name writes the entry's file and keeps the entry", {
  local_entry_project()
  before <- readLines("settings/data.yml")
  msgs <- capture_messages(data_save(frame, "inputs.intermediate.clean"))
  expect_true(file.exists("inputs/intermediate/clean.csv"))
  expect_false(file.exists("inputs/intermediate/clean.rds"))
  expect_identical(readLines("settings/data.yml"), before)
  expect_false(any(grepl("Data spec added", msgs)))
  expect_equal(nrow(suppressMessages(data_read("inputs.intermediate.clean"))), 2)

  expect_error(
    data_save(frame, "inputs.intermediate.clean", type = "rds"),
    "is a csv file in the data catalog"
  )
  expect_error(
    data_save(frame, "inputs.intermediate.clean.rds"),
    "is a csv file in the data catalog"
  )
})

test_that("data_save() by an existing name changes only the entry's lock", {
  local_entry_project()
  suppressMessages(data_save(frame, "inputs.intermediate.clean", locked = TRUE))
  entry <- yaml::read_yaml("settings/data.yml")$data$inputs$intermediate$clean
  expect_identical(entry$description, "One row per student.")
  expect_identical(entry$notes, "kept as written")
  expect_true(entry$locked)

  suppressMessages(data_save(frame[1, ], "inputs.intermediate.clean", unlock = TRUE))
  entry <- yaml::read_yaml("settings/data.yml")$data$inputs$intermediate$clean
  expect_null(entry$locked)
  expect_identical(entry$description, "One row per student.")
})

test_that("data_add() to an existing entry keeps its other fields", {
  local_entry_project()
  writeLines("a\tb\n1\t2", "inputs/intermediate/clean.tsv")
  suppressMessages(data_add("inputs/intermediate/clean.tsv", name = "inputs.intermediate.clean"))
  entry <- yaml::read_yaml("settings/data.yml")$data$inputs$intermediate$clean
  expect_identical(entry$path, "inputs/intermediate/clean.tsv")
  expect_identical(entry$type, "tsv")
  expect_identical(entry$description, "One row per student.")
  expect_identical(entry$notes, "kept as written")
})
