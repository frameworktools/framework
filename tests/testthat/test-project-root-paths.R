# Regression tests from the 2026-11-05 audit: data and cache paths resolve
# from the project root, the catalog keeps relative paths, and the CSV
# delimiter is honoured.

local_data_project <- function(env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  withr::local_envvar(FW_CACHE_DIR = NA, FW_PROJECT_TOKEN = NA, FW_LEDGER = NA, .local_envir = env)
  dir <- create_test_project(withr::local_tempdir(.local_envir = env))
  withr::local_dir(dir, .local_envir = env)
  suppressMessages(framework:::.ensure_framework_db(dir))
  dir
}

stored_path <- function(name) {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(framework:::.find_project_root(getwd()), "framework.db"))
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT path FROM data WHERE name = ?", list(name))$path
}

test_that("data_save() writes the delimiter it records, and data_read() reads it back", {
  local_data_project()
  df <- data.frame(a = c(1.5, 2), b = c("x", "y"))
  suppressMessages(data_save(df, "inputs.intermediate.semi", type = "csv", delimiter = "semicolon"))
  expect_identical(readLines("inputs/intermediate/semi.csv")[1], "a;b")
  back <- suppressMessages(data_read("inputs.intermediate.semi"))
  expect_identical(names(back), c("a", "b"))
  expect_equal(nrow(back), 2)

  suppressMessages(data_save(df, "inputs.intermediate.tabbed", type = "csv", delimiter = "tab"))
  expect_identical(readLines("inputs/intermediate/tabbed.csv")[1], "a\tb")
})

test_that("data_read() keeps the stored path relative to the project root", {
  local_data_project()
  suppressMessages(data_save(data.frame(a = 1:3), "inputs.raw.small", type = "csv"))
  expect_identical(stored_path("inputs.raw.small"), "inputs/raw/small.csv")
  suppressMessages(data_read("inputs.raw.small"))
  expect_identical(stored_path("inputs.raw.small"), "inputs/raw/small.csv")
})

test_that("data_save(), data_read() and data_verify() work from notebooks/", {
  root <- local_data_project()
  withr::local_dir(file.path(root, "notebooks"))
  suppressMessages(data_save(mtcars, "inputs.raw.from_nb"))
  expect_true(file.exists(file.path(root, "inputs/raw/from_nb.rds")))
  expect_false(dir.exists(file.path(root, "notebooks/inputs")))
  expect_identical(stored_path("inputs.raw.from_nb"), "inputs/raw/from_nb.rds")
  expect_equal(nrow(suppressMessages(data_read("inputs.raw.from_nb"))), nrow(mtcars))
  expect_message(data_verify("inputs.raw.from_nb"), "Verified against framework.db")
})

test_that("data_verify() says so when there is nothing to compare", {
  root <- local_data_project()
  saveRDS(iris, "inputs/raw/iris.rds")
  cfg <- yaml::read_yaml("settings.yml")
  cfg$default$data <- list(inputs = list(raw = list(iris = list(path = "inputs/raw/iris.rds", type = "rds"))))
  yaml::write_yaml(cfg, "settings.yml")
  msgs <- capture.output(result <- data_verify("inputs.raw.iris"), type = "message")
  expect_true(result)
  expect_true(any(grepl("Not verified", msgs)))
  expect_false(any(grepl("\\[ok\\] Verified", msgs)))
})

test_that("db_connect() opens the project's framework.db from notebooks/", {
  root <- local_data_project()
  writeLines(c("connections:", "  databases:", "    framework:", "      driver: sqlite",
               "      database: framework.db"), "settings/connections.yml")
  withr::local_dir(file.path(root, "notebooks"))
  con <- db_connect("framework")
  on.exit(DBI::dbDisconnect(con))
  expect_true("data" %in% DBI::dbListTables(con))
  expect_false(file.exists(file.path(root, "notebooks", "framework.db")))
})

test_that("FW_CACHE_DIR is used for reads, writes and deletes", {
  root <- local_data_project()
  env_cache <- withr::local_tempdir()
  withr::local_envvar(FW_CACHE_DIR = env_cache)
  suppressMessages(cache("env_cached", 42))
  expect_true(file.exists(file.path(env_cache, "env_cached.rds")))
  expect_identical(suppressMessages(cache_get("env_cached")), 42)
  suppressMessages(cache_forget("env_cached"))
  expect_false(file.exists(file.path(env_cache, "env_cached.rds")))
})

test_that("the cache folder is relative to the project root", {
  root <- local_data_project()
  withr::local_dir(file.path(root, "notebooks"))
  suppressMessages(cache("from_nb", 1:3))
  expect_false(dir.exists(file.path(root, "notebooks", "outputs")))
  expect_true(file.exists(file.path(root, "outputs/private/cache/from_nb.rds")))
  expect_identical(suppressMessages(cache_get("from_nb")), 1:3)
})

test_that("cache_remember() hits a cached NULL and works before scaffold()", {
  dir <- create_test_project(withr::local_tempdir())
  cleanup <- setup_isolated_config(); on.exit(cleanup(), add = TRUE)
  withr::local_dir(dir)
  withr::local_envvar(FW_CACHE_DIR = NA)
  # No framework.db yet: cache_list() must not create one
  unlink("framework.db")
  expect_equal(nrow(cache_list()), 0)
  expect_false(file.exists("framework.db"))

  runs <- 0
  for (i in 1:2) suppressMessages(cache_remember("nothing", { runs <- runs + 1; NULL }))
  expect_identical(runs, 1)
  for (i in 1:2) suppressMessages(cache_remember("value", { runs <- runs + 1; "v" }))
  expect_identical(runs, 2)
})

test_that("cache_flush() removes custom-file caches too", {
  root <- local_data_project()
  suppressMessages(cache("custom", 1, file = "outputs/private/custom-cache.rds"))
  expect_true(file.exists("outputs/private/custom-cache.rds"))
  suppressMessages(cache_flush())
  expect_false(file.exists("outputs/private/custom-cache.rds"))
})

test_that("data_info() finds a bare file name and calls .tsv files tsv", {
  root <- local_data_project()
  write.csv(iris, "iris.csv", row.names = FALSE)
  writeLines("a\tb\n1\t2", "inputs/raw/t.tsv")
  expect_false(is.null(suppressMessages(data_info("iris.csv"))))
  expect_identical(suppressMessages(data_info("inputs/raw/t.tsv"))$type, "tsv")
})
