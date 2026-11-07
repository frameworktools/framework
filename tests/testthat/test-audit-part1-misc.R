# Regression tests from the 2026-11-05 audit (R part 1): the retired GUI,
# env_clear(), cloud_logout(), bootstrap_project_init(), and schema
# helpers.

test_that("gui() is deprecated and points to Framework Cloud", {
  expect_warning(out <- gui(), "framework.pub")
  expect_null(out)
})

test_that("env_clear() closes every graphics device and keeps framework attached", {
  env <- new.env()
  assign("a", 1, envir = env)
  assign("keep_me", 2, envir = env)
  grDevices::pdf(NULL)
  grDevices::pdf(NULL)
  on.exit(while (grDevices::dev.cur() > 1) grDevices::dev.off(), add = TRUE)
  # Detaching for real would detach testthat
  local_mocked_bindings(.env_attached_packages = function() character())
  expect_no_error(suppressMessages(env_clear(keep = "keep_me", envir = env)))
  expect_identical(ls(env), "keep_me")
  expect_identical(grDevices::dev.cur(), c(`null device` = 1L))
  expect_error(env_clear(), "globalenv")
  expect_error(env_summary(), "globalenv")
})

test_that("env_clear() never detaches framework", {
  local_mocked_bindings(sessionInfo = function() list(otherPkgs = list(framework = 1, dplyr = 1)))
  expect_identical(framework:::.env_attached_packages(), "dplyr")
})

test_that("env_summary() names the environment it summarizes", {
  env <- new.env()
  assign("x", 1:10, envir = env)
  msgs <- capture.output(env_summary(envir = env), type = "message")
  expect_false(any(grepl("Global Environment", msgs)))
  expect_true(any(grepl("Objects in the environment: 1", msgs)))
})

test_that("cloud_logout() removes the FW_TOKEN_FILE token that cloud_login() wrote", {
  cleanup <- setup_isolated_config(); on.exit(cleanup(), add = TRUE)
  token_file <- file.path(withr::local_tempdir(), "token")
  withr::local_envvar(FW_TOKEN_FILE = token_file, FW_CLOUD_TOKEN = NA, FW_CLOUD_URL = NA)
  writeLines("fw_test_token", token_file)
  expect_identical(framework:::.fw_cloud_token(), "fw_test_token")
  expect_message(cloud_logout(url = "http://127.0.0.1:18765"), "Removed")
  expect_false(file.exists(token_file))
  expect_null(framework:::.fw_cloud_token())
  expect_message(cloud_logout(url = "http://127.0.0.1:18765"), "No stored token")
})

test_that("bootstrap_project_init() writes init.R from the shipped template", {
  dir <- create_test_project(withr::local_tempdir())
  withr::local_dir(dir)
  expect_true(nzchar(system.file("templates", "init.R", package = "framework")))
  expect_true(suppressMessages(bootstrap_project_init("init.R")))
  lines <- readLines("init.R")
  expect_true(any(grepl("framework::bootstrap()", lines, fixed = TRUE)))
  expect_true(any(grepl("TestProject", lines, fixed = TRUE)))
  expect_false(any(grepl("{{PROJECT_NAME}}", lines, fixed = TRUE)))
  parsed <- parse(file = "init.R")
  expect_gt(length(parsed), 0)
})

test_that(".list_columns() returns character(0) for a missing SQLite table", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "CREATE TABLE t (a INTEGER, b TEXT)")
  expect_identical(.list_columns(con, "t"), c("a", "b"))
  expect_identical(.list_columns(con, "missing"), character(0))
})

test_that("ai_regenerate_context() stops on broken settings instead of wiping sections", {
  dir <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  packages: settings/packages.yml"),
             file.path(dir, "settings.yml"))
  dir.create(file.path(dir, "settings"))
  writeLines(c("packages:", "  default_packages: [{name: dplyr"), file.path(dir, "settings", "packages.yml"))
  agents <- c("# Study", "", "## Installed Packages <!-- @framework:regenerate -->", "", "- dplyr", "")
  writeLines(agents, file.path(dir, "AGENTS.md"))
  expect_error(ai_regenerate_context(dir), "Could not read settings")
  expect_identical(readLines(file.path(dir, "AGENTS.md")), agents)

  writeLines(c("packages:", "  default_packages:", "    - name: dplyr"), file.path(dir, "settings", "packages.yml"))
  expect_error(ai_regenerate_context(dir, sections = "nonsense"), "Unknown section")
  expect_message(ai_regenerate_context(dir, sections = "functions"), "no 'Function Reference' section")
  expect_message(ai_regenerate_context(dir, sections = "packages"), "Regenerated AI context: AGENTS.md \\(packages\\)")
})

test_that("ai_sync_context(force = TRUE) keeps the @AGENTS.md pointer", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project", ai = list(canonical_file = "AGENTS.md"))), "settings.yml")
  writeLines(c("# Agents", "Use data_read()."), "AGENTS.md")
  writeLines("@AGENTS.md", "CLAUDE.md")
  suppressWarnings(ai_sync_context(force = TRUE, verbose = FALSE))
  expect_identical(readLines("CLAUDE.md"), "@AGENTS.md")

  writeLines("old copy", ".github-copilot.md")
  dir.create(".github")
  writeLines("old copy", ".github/copilot-instructions.md")
  suppressWarnings(ai_sync_context(force = TRUE, verbose = FALSE))
  synced <- readLines(".github/copilot-instructions.md")
  expect_false(any(grepl("sync:ai-context", synced, fixed = TRUE)))
  expect_true(any(grepl("ai_sync_context()", synced, fixed = TRUE)))
})

test_that("ai_skills_update() refuses a folder that is not a project", {
  missing <- file.path(withr::local_tempdir(), "no-such-dir")
  expect_error(ai_skills_update(missing), "Not a Framework project")
  expect_false(dir.exists(missing))
})

test_that("configure_global() is quiet, checks emails, and accepts bare", {
  cleanup <- setup_isolated_config(); on.exit(cleanup(), add = TRUE)
  msgs <- capture.output(configure_global(settings = list(defaults = list(project_type = "bare"))), type = "message")
  expect_false(any(grepl("[configure_global]", msgs, fixed = TRUE)))
  expect_error(configure_global(settings = list(author = list(email = "not-an-email"))), "email")
})

test_that("add_project_to_config() returns the existing ID and checks its argument", {
  cleanup <- setup_isolated_config(); on.exit(cleanup(), add = TRUE)
  dir <- withr::local_tempdir()
  id <- add_project_to_config(dir)
  expect_identical(suppressMessages(add_project_to_config(dir)), id)
  expect_error(add_project_to_config(NULL))
  expect_error(add_project_to_config(c("a", "b")))
  expect_warning(add_project_to_config(file.path(dir, "not-yet")), "does not exist")
})

test_that("docs_export(include_internal = TRUE) keeps internal Rd files", {
  skip_if_not_installed("RSQLite")
  pkg <- withr::local_tempdir()
  dir.create(file.path(pkg, "man"))
  writeLines(c("\\name{shown}", "\\alias{shown}", "\\title{Shown}", "\\usage{shown()}", "\\description{A.}"),
             file.path(pkg, "man", "shown.Rd"))
  writeLines(c("\\name{hidden}", "\\alias{hidden}", "\\title{Hidden}", "\\usage{hidden()}", "\\description{B.}",
               "\\keyword{internal}"), file.path(pkg, "man", "hidden.Rd"))
  writeLines(c("export(shown)", "export(hidden)"), file.path(pkg, "NAMESPACE"))
  writeLines(c("Package: demo", "Version: 0.1.0"), file.path(pkg, "DESCRIPTION"))
  names_in <- function(include) {
    db <- tempfile(fileext = ".db")
    docs_export(db, man_dir = file.path(pkg, "man"), include_internal = include, verbose = FALSE)
    con <- DBI::dbConnect(RSQLite::SQLite(), db)
    on.exit(DBI::dbDisconnect(con))
    sort(DBI::dbGetQuery(con, "SELECT name FROM functions")$name)
  }
  # NAMESPACE is read from the package that holds man_dir, not the working directory
  expect_identical(names_in(FALSE), "shown")
  expect_identical(names_in(TRUE), c("hidden", "shown"))
})

test_that("ledger_list() keeps its columns when the ledger is empty", {
  withr::local_envvar(FW_PROJECT_TOKEN = "fw_mock")
  local_mocked_bindings(.fw_api = function(...) list(entries = list()))
  result <- suppressMessages(ledger_list())
  expect_identical(names(result), c("sequence", "name", "hash", "size_bytes", "recorded_at"))
  expect_equal(nrow(result), 0)
})

test_that("the project's token is found from a subfolder", {
  dir <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(project_type = "project")), file.path(dir, "settings.yml"))
  writeLines(c("export FW_PROJECT_TOKEN=fw_from_root", "FW_CLOUD_URL=http://127.0.0.1:18765"), file.path(dir, ".env"))
  dir.create(file.path(dir, "notebooks"))
  withr::local_dir(file.path(dir, "notebooks"))
  withr::local_envvar(FW_PROJECT_TOKEN = NA, FW_CLOUD_URL = NA)
  expect_identical(framework:::.fw_project_token(), "fw_from_root")
  expect_identical(framework:::.fw_project_cloud_url(), "http://127.0.0.1:18765")
})

test_that("load_settings_catalog() rejects an override that empties project_types", {
  cleanup <- setup_isolated_config(); on.exit(cleanup(), add = TRUE)
  user_path <- framework:::.framework_catalog_user_path()
  dir.create(dirname(user_path), recursive = TRUE, showWarnings = FALSE)
  writeLines("project_types: null", user_path)
  expect_error(load_settings_catalog(), "project_types")
})

test_that("db_drivers_install() does not prompt when there is nothing to do", {
  expect_message(db_drivers_install(character(0)), "No drivers named")
  skip_if(interactive())
  expect_error(db_drivers_install(), "interactive")
})

test_that("data_list() shows no [NA] badge for shorthand entries", {
  dir <- create_test_project(withr::local_tempdir())
  withr::local_dir(dir)
  cfg <- yaml::read_yaml("settings.yml")
  cfg$default$data <- list(inputs = list(raw = list(short = "inputs/raw/short.csv")))
  yaml::write_yaml(cfg, "settings.yml")
  msgs <- capture.output(result <- data_list(), type = "message")
  expect_false(any(grepl("[NA]", msgs, fixed = TRUE)))
  expect_null(rownames(result) |> setdiff(as.character(seq_len(nrow(result)))) |> (\(x) if (length(x)) x else NULL)())
})

test_that("ai_regenerate_context() keeps the blank line before the next heading", {
  dir <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  packages:", "    default_packages:", "      - name: dplyr"),
             file.path(dir, "settings.yml"))
  agents <- c("# Study", "", "## Installed Packages <!-- @framework:regenerate -->", "", "- old", "",
              "## Notes", "", "Keep this.")
  writeLines(agents, file.path(dir, "AGENTS.md"))
  suppressMessages(ai_regenerate_context(dir, sections = "packages"))
  once <- readLines(file.path(dir, "AGENTS.md"))
  notes <- which(once == "## Notes")
  expect_identical(once[notes - 1L], "")
  expect_true(nzchar(once[notes - 2L]))
  suppressMessages(ai_regenerate_context(dir, sections = "packages"))
  expect_identical(readLines(file.path(dir, "AGENTS.md")), once)

  # A section that already lost its blank line gets it back
  text <- "## A <!-- @framework:regenerate -->\n\nold\n## B\n\nb\n"
  expect_identical(framework:::.replace_section(text, "A", "new"),
                   "## A <!-- @framework:regenerate -->\n\nnew\n\n## B\n\nb\n")
})
