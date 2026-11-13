test_that("scaffold sources the configured Framework functions location", {
  root <- withr::local_tempdir()
  withr::local_dir(root)
  dir.create("R")
  dir.create("legacy")
  writeLines("fw_location_probe <- function() 'mapped'", "R/probe.R")
  writeLines("fw_location_probe <- function() 'legacy'", "legacy/probe.R")
  withr::defer(if (exists("fw_location_probe", envir = globalenv())) {
    rm("fw_location_probe", envir = globalenv())
  })
  yaml::write_yaml(list(default = list(
    directories = list(functions = "R"),
    options = list(functions_dir = "legacy")
  )), "settings.yml")

  suppressMessages(framework:::.load_functions(project_root = root))
  expect_identical(fw_location_probe(), "mapped")
})

test_that("scaffold retains the legacy functions directory option", {
  root <- withr::local_tempdir()
  withr::local_dir(root)
  dir.create("legacy")
  writeLines("fw_legacy_probe <- function() 'legacy'", "legacy/probe.R")
  withr::defer(if (exists("fw_legacy_probe", envir = globalenv())) {
    rm("fw_legacy_probe", envir = globalenv())
  })
  yaml::write_yaml(list(default = list(
    options = list(functions_dir = "legacy")
  )), "settings.yml")

  suppressMessages(framework:::.load_functions(project_root = root))
  expect_identical(fw_legacy_probe(), "legacy")
})
