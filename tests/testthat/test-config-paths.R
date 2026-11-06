test_that("functions_dir supports single directory", {
  test_dir <- withr::local_tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create custom functions directory
  dir.create("my-functions", showWarnings = FALSE)
  writeLines("my_func <- function() 'hello'", "my-functions/test.R")

  # Create config with custom functions_dir
  writeLines(
    "default:\n  options:\n    functions_dir: my-functions",
    "settings.yml"
  )

  # Load functions
  framework:::.load_functions()

  # Verify function was loaded
  expect_true(exists("my_func"))
  expect_equal(my_func(), "hello")

  # Cleanup
  rm(my_func, envir = .GlobalEnv)
  unlink("my-functions", recursive = TRUE)
  file.remove("settings.yml")
})

test_that("functions_dir supports multiple directories", {
  test_dir <- withr::local_tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create multiple function directories
  dir.create("functions", showWarnings = FALSE)
  dir.create("helpers", showWarnings = FALSE)

  writeLines("func1 <- function() 'from functions'", "functions/func1.R")
  writeLines("func2 <- function() 'from helpers'", "helpers/func2.R")

  # Create config with list of directories
  writeLines(
    "default:\n  options:\n    functions_dir:\n      - functions\n      - helpers",
    "settings.yml"
  )

  # Load functions
  suppressMessages(framework:::.load_functions())

  # Verify both functions were loaded
  expect_true(exists("func1"))
  expect_true(exists("func2"))
  expect_equal(func1(), "from functions")
  expect_equal(func2(), "from helpers")

  # Cleanup
  rm(func1, func2, envir = .GlobalEnv)
  unlink(c("functions", "helpers"), recursive = TRUE)
  file.remove("settings.yml")
})

test_that("functions_dir defaults to 'functions' if not configured", {
  test_dir <- withr::local_tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create default functions directory
  dir.create("functions", showWarnings = FALSE)
  writeLines("default_func <- function() 'default'", "functions/test.R")

  # Create config WITHOUT functions_dir option
  writeLines("default:\n  packages:\n    - dplyr", "settings.yml")

  # Load functions - should use default "functions" dir
  suppressMessages(framework:::.load_functions())

  # Verify function was loaded
  expect_true(exists("default_func"))

  # Cleanup
  rm(default_func, envir = .GlobalEnv)
  unlink("functions", recursive = TRUE)
  file.remove("settings.yml")
})

test_that("functions_dir silent when default dir doesn't exist", {
  test_dir <- withr::local_tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create config without functions_dir (uses default)
  writeLines("default:\n  packages:\n    - dplyr", "settings.yml")

  # No functions directory exists - should be silent (not warning)
  expect_silent(framework:::.load_functions())

  file.remove("settings.yml")
})

test_that("functions_dir warns when custom dir doesn't exist", {
  test_dir <- withr::local_tempdir()
  orig_wd <- getwd()
  setwd(test_dir)
  on.exit(setwd(orig_wd))

  # Create config with custom dir that doesn't exist
  writeLines(
    "default:\n  options:\n    functions_dir: my-custom-dir",
    "settings.yml"
  )

  # Should warn because user explicitly configured it
  expect_warning(framework:::.load_functions(), "No function directories found")

  file.remove("settings.yml")
})

# Note: Tests for result_save/result_get removed - API changed to save_table/save_model/etc.
# Tests for results directories can be re-added when using the new API

test_that("custom data directories override defaults", {
  test_dir <- withr::local_tempdir()
  orig_wd <- getwd()
  setwd(test_dir)

  on.exit({
    setwd(orig_wd)
    if (file.exists("settings.yml")) file.remove("settings.yml")
  })

  # Create config with custom data dirs
  writeLines(
    "default:\n  directories:\n    cache: my-cache\n    scratch: my-scratch",
    "settings.yml"
  )

  config <- settings_read()

  # Verify custom paths override defaults
  expect_equal(config$directories$cache, "my-cache")
  expect_equal(config$directories$scratch, "my-scratch")
})
