# adopt() maps an existing folder's layout and writes only settings.yml and
# .framework/spec.json; structure_import() saves the layout on the cloud

local_folder <- function(folders, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  for (f in folders) dir.create(file.path(dir, f), recursive = TRUE)
  writeLines("x <- 1", file.path(dir, "analysis", "run.R"))
  dir
}

test_that("adopt() writes settings.yml, the spec record, and .gitignore, and nothing else", {
  dir <- local_folder(c("R", "analysis", "data/raw", "figures", "renv/library", "archive/2020"))
  before <- sort(list.files(dir, recursive = TRUE, all.files = TRUE, include.dirs = TRUE))

  suppressMessages(adopt(dir, yes = TRUE))
  after <- sort(list.files(dir, recursive = TRUE, all.files = TRUE, include.dirs = TRUE))
  expect_setequal(setdiff(after, before), c("settings.yml", ".framework", ".framework/spec.json", ".gitignore"))

  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))$default
  expect_identical(settings$directories$functions, "R")
  expect_identical(settings$directories$inputs_raw, "data/raw")
  expect_identical(settings$extra_directories[[1]]$path, "archive")
  expect_length(settings$packages$default_packages, 0)

  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(spec$type, "project")
  expect_false(spec$security$sensitive)
  expect_identical(settings$project_type, "project")
  # Only the mapped folders: none of the type's own folders or render folders
  expect_setequal(names(spec$directories), c("functions", "scripts", "inputs_raw", "outputs_figures"))
  expect_length(spec$render_dirs, 0)
  expect_identical(spec$source$origin, "r")
  expect_true(spec$source$adopted)
  withr::with_dir(dir, expect_identical(config("functions"), "R"))

  skip_if_not_installed("jsonvalidate")
  schema <- system.file("schema", "spec.v1.json", package = "framework")
  if (!nzchar(schema)) schema <- testthat::test_path("..", "..", "inst", "schema", "spec.v1.json")
  json <- paste(readLines(file.path(dir, ".framework", "spec.json")), collapse = "\n")
  expect_true(jsonvalidate::json_schema$new(schema)$validate(json))

})

test_that("adopt() refuses an existing project and needs a review or yes = TRUE", {
  dir <- local_folder(c("analysis"))
  withr::local_options(rlang_interactive = FALSE)
  expect_error(adopt(dir), "yes = TRUE")
  expect_false(file.exists(file.path(dir, "settings.yml")))

  writeLines("default: {}", file.path(dir, "settings.yml"))
  expect_error(adopt(dir, yes = TRUE), "already a Framework project")
  expect_identical(readLines(file.path(dir, "settings.yml")), "default: {}")
})

test_that("private folders warn, and yes = TRUE never marks the project sensitive", {
  dir <- local_folder(c("analysis", "data/private"))
  expect_warning(suppressMessages(adopt(dir, yes = TRUE)), "looks private")
  expect_false(jsonlite::read_json(file.path(dir, ".framework", "spec.json"))$security$sensitive)
})

test_that("the scanner skips tool and hidden folders and stops at three levels", {
  dir <- local_folder(c("analysis", ".git/objects", ".venv/lib", "node_modules/x", "a/b/c/d", ".hidden"))
  expect_identical(framework:::.adopt_scan(dir), c("a", "a/b", "a/b/c", "analysis"))
})

test_that("structure_import() sends the confirmed mapping to the cloud", {
  dir <- local_folder(c("analysis", "data/raw", "archive"))
  sent <- NULL
  local_mocked_bindings(
    .fw_require_token = function(url = NULL) "fw_test",
    .fw_api = function(path, token, method = "GET", body = NULL, url = NULL) {
      sent <<- list(path = path, method = method, body = body)
      list(key = "ada/lab-layout", name = body$name, url = "https://cloud.test/structures/ada/lab-layout")
    }
  )
  res <- suppressMessages(structure_import(dir, name = "Lab layout", yes = TRUE))
  expect_identical(res$key, "ada/lab-layout")
  expect_identical(sent$path, "/api/v1/structures")
  expect_identical(sent$method, "POST")
  expect_identical(sent$body$name, "Lab layout")
  expect_identical(sent$body$directories, list(inputs_raw = "data/raw", scripts = "analysis"))
  expect_identical(sent$body$extra_directories, list(archive = list(label = "archive", path = "archive")))
  expect_false(file.exists(file.path(dir, "settings.yml")))
})

test_that("writing a project token makes git ignore .env first", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir()
  system2("git", c("-C", shQuote(dir), "init", "-q"), stdout = FALSE, stderr = FALSE)
  writeLines(c("*.log", "!.env"), file.path(dir, ".gitignore"))

  expect_message(framework:::.fw_write_project_token(dir, "fw_secret", "https://cloud.test"),
                 "stays out of git")
  status <- system2("git", c("-C", shQuote(dir), "check-ignore", "-q", ".env"), stdout = FALSE, stderr = FALSE)
  expect_identical(as.integer(status), 0L)

  # Already ignored: .gitignore is left alone
  before <- readLines(file.path(dir, ".gitignore"))
  writeLines("OTHER=1", file.path(dir, ".env"))
  suppressMessages(framework:::.fw_ensure_env_ignored(dir))
  expect_identical(readLines(file.path(dir, ".gitignore")), before)

  # Outside a repository, .gitignore's own rules decide
  plain <- withr::local_tempdir()
  suppressMessages(framework:::.fw_ensure_env_ignored(plain))
  expect_identical(utils::tail(readLines(file.path(plain, ".gitignore")), 1), ".env")
})

test_that("a project token is never written into a .env git tracks", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir()
  git <- function(...) system2("git", c("-C", shQuote(dir), ...), stdout = FALSE, stderr = FALSE)
  git("init", "-q")
  writeLines("A=1", file.path(dir, ".env"))
  git("add", "-f", ".env")
  expect_error(framework:::.fw_write_project_token(dir, "fw_secret", "https://cloud.test"), "git rm --cached .env")
  expect_identical(readLines(file.path(dir, ".env")), "A=1")
})

test_that("adopt() offers to register and link when signed in", {
  dir <- local_folder(c("analysis", "data/raw"))
  asked <- character()
  registered <- NULL
  local_mocked_bindings(
    .fw_cloud_token = function(url = NULL) "fw_test",
    .fw_cloud_host = function(url = NULL) "cloud.test",
    cloud_register = function(path, ...) registered <<- path,
    .structure_upload = function(mapping, name) stop("not asked for"),
    .adopt_ask = function(msg, default = FALSE) {
      asked <<- c(asked, msg)
      grepl("^Register", msg)
    },
    .adopt_readline = function(prompt) "a"
  )
  withr::local_options(rlang_interactive = TRUE)
  suppressMessages(adopt(dir))
  expect_identical(asked, "Register this project on cloud.test?")
  expect_identical(registered, dir)
})

test_that("adopt() offers the structure when the person doesn't register", {
  dir <- local_folder(c("analysis", "data/raw"))
  saved <- FALSE
  local_mocked_bindings(
    .fw_cloud_token = function(url = NULL) "fw_test",
    .fw_cloud_host = function(url = NULL) "cloud.test",
    cloud_register = function(path, ...) stop("not asked for"),
    .structure_upload = function(mapping, name) saved <<- TRUE,
    .adopt_ask = function(msg, default = FALSE) grepl("^Save", msg),
    .adopt_readline = function(prompt) "a"
  )
  withr::local_options(rlang_interactive = TRUE)
  suppressMessages(adopt(dir))
  expect_true(saved)
})

test_that("adopt() writes connections in the layout db_connect() reads", {
  skip_if_not_installed("RSQLite")
  dir <- local_folder(c("analysis"))
  suppressMessages(adopt(dir, yes = TRUE))

  connections <- yaml::read_yaml(file.path(dir, "settings.yml"))$default$connections
  expect_identical(connections$default_database, "framework")
  expect_identical(connections$databases$framework$driver, "sqlite")
  expect_null(connections$connections)
  expect_null(connections$options)

  withr::with_dir(dir, {
    con <- db_connect("framework")
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    expect_true(DBI::dbIsValid(con))
  })
})

test_that("a config.yml without Framework keys doesn't make a Framework project", {
  dir <- withr::local_tempdir()
  # sidr-pipeline's own config.yml (repository settings)
  writeLines(c("repositories:", "  data:", "    name: x"), file.path(dir, "config.yml"))
  dir.create(file.path(dir, "scripts"))
  expect_false(framework:::.has_settings_file(dir))
  expect_false(framework:::.fw_is_framework_config(file.path(dir, "config.yml")))
  # The config package's layout: default: with app keys
  writeLines(c("default:", "  trials: 5", "  dataset: data.csv"), file.path(dir, "config.yml"))
  expect_false(framework:::.has_settings_file(dir))
  suppressMessages(suppressWarnings(adopt(dir, yes = TRUE)))
  expect_true(file.exists(file.path(dir, "settings.yml")))
  expect_true(file.exists(file.path(dir, "config.yml")))
})

test_that("a Framework config.yml still counts, and adopt points to upgrade()", {
  dir <- withr::local_tempdir()
  is_fw <- function(lines) {
    writeLines(lines, file.path(dir, "config.yml"))
    framework:::.fw_is_framework_config(file.path(dir, "config.yml"))
  }
  expect_true(is_fw(c("default:", "  project_type: project")))
  expect_true(is_fw(c("default:", "  directories:", "    notebooks: notebooks")))
  expect_true(is_fw(c("project_name: Old")))
  expect_true(is_fw(c("default:", "  options:", "    functions_dir: functions")))
  expect_true(is_fw(c("default:", "  packages:", "    - name: dplyr", "      auto_attach: true")))
  expect_false(is_fw(c("default:", "  packages: [a, b]")))
  expect_false(is_fw("not: [valid"))
  is_fw(c("default:", "  project_type: project"))
  expect_error(adopt(dir, yes = TRUE), "upgrade\\(\\)")
})

test_that("the scanner doesn't follow symlinked folders", {
  dir <- local_folder(c("analysis", "real_data/raw"))
  skip_on_os("windows")
  file.symlink(file.path(dir, "real_data"), file.path(dir, "linked"))
  expect_identical(framework:::.adopt_scan(dir), c("analysis", "real_data", "real_data/raw"))
})

test_that("a folder set to (other folder) by hand gets a key no other folder has", {
  mapping <- list(
    directories = list(scripts = "analysis"),
    extra_directories = list(a_b = list(label = "a-b", path = "a-b"))
  )
  mapping <- framework:::.adopt_set_role(mapping, "a_b", "(other folder)")
  expect_identical(mapping$extra_directories$a_b$path, "a-b")
  expect_identical(mapping$extra_directories$a_b_2$path, "a_b")
  # A Framework key is never used for an extra directory
  mapping <- framework:::.adopt_set_role(mapping, "analysis", "(other folder)")
  expect_identical(mapping$extra_directories$analysis$path, "analysis")
  mapping <- framework:::.adopt_set_role(mapping, "Scripts", "(other folder)")
  expect_identical(mapping$extra_directories$scripts_2$path, "Scripts")
})

test_that("a folder with no subfolders can be adopted", {
  dir <- withr::local_tempdir()
  writeLines(c("```{r}", "1", "```"), file.path(dir, "analysis.qmd"))
  expect_message(adopt(dir, yes = TRUE), "No folders to map")
  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))$default
  expect_length(settings$directories, 0)
  expect_true(file.exists(file.path(dir, ".framework", "spec.json")))
  # Saving an empty layout as a structure still makes no sense
  local_mocked_bindings(.fw_require_token = function(url = NULL) "fw_test")
  expect_error(structure_import(withr::local_tempdir(), yes = TRUE), "No folders found")
})

test_that("adopt() leaves settings/ and Quarto's render folders out", {
  dir <- local_folder(c("analysis", "settings", "report_files", "notebooks/fit_cache", "outputs/notebooks"))
  expect_identical(framework:::.adopt_scan(dir), c("analysis", "notebooks", "outputs", "outputs/notebooks"))
  suppressMessages(adopt(dir, yes = TRUE))
  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))$default
  expect_identical(settings$render_dirs, list(notebooks = "outputs/notebooks"))
  expect_null(settings$extra_directories)
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(spec$render_dirs, list(notebooks = "outputs/notebooks"))
})

test_that("adopt() infers course and privacy-sensitive types from the folders", {
  dir <- local_folder(c("analysis", "slides", "modules/01", "data/raw"))
  suppressMessages(adopt(dir, yes = TRUE))
  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))$default
  expect_identical(settings$project_type, "course")
  expect_identical(settings$directories$data, "data")
  expect_identical(settings$directories$notebooks, "modules")

  dir <- local_folder(c("analysis", "inputs/private/raw", "inputs/public/raw", "outputs/private/tables"))
  suppressWarnings(suppressMessages(adopt(dir, yes = TRUE)))
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(spec$type, "project_sensitive")
  expect_true(spec$security$sensitive)
  expect_identical(spec$directories$inputs_private_raw, "inputs/private/raw")
  expect_identical(spec$directories$outputs_private_tables, "outputs/private/tables")
  expect_length(spec$skills, 0)
})

test_that("adopt() takes sensitive = TRUE and a type without asking", {
  dir <- local_folder(c("analysis", "data/private"))
  expect_warning(suppressMessages(adopt(dir, yes = TRUE, sensitive = TRUE)), "looks private")
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_true(spec$security$sensitive)
  expect_identical(spec$type, "project")
  expect_true(yaml::read_yaml(file.path(dir, "settings.yml"))$default$security$sensitive)

  dir <- local_folder(c("analysis", "data/raw"))
  res <- suppressMessages(adopt(dir, yes = TRUE, type = "project_sensitive"))
  expect_identical(res$type, "project_sensitive")
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(spec$type, "project_sensitive")
  expect_true(spec$security$sensitive)

  dir <- local_folder(c("analysis", "slides"))
  res <- suppressMessages(adopt(dir, yes = TRUE, type = "course"))
  expect_identical(res$directories$slides, "slides")

  expect_error(adopt(local_folder("analysis"), yes = TRUE, type = "project_sensitive", sensitive = FALSE),
               "sensitive data")
  expect_error(adopt(local_folder("analysis"), yes = TRUE, type = "lab"))
})

test_that("without sensitive = TRUE, adopt() says how to turn it on", {
  dir <- local_folder(c("analysis", "data/private"))
  msgs <- character()
  withCallingHandlers(
    suppressWarnings(adopt(dir, yes = TRUE)),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }
  )
  expect_true(any(grepl("sensitive = TRUE", msgs)))
})

test_that("adopt() turns git on when the folder is a git repository", {
  dir <- local_folder(c("analysis"))
  dir.create(file.path(dir, ".git"))
  suppressMessages(adopt(dir, yes = TRUE))
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_true(spec$git$use_git)
  expect_true(yaml::read_yaml(file.path(dir, "settings.yml"))$default$git$enabled)

  dir <- local_folder(c("analysis"))
  suppressMessages(adopt(dir, yes = TRUE))
  expect_false(jsonlite::read_json(file.path(dir, ".framework", "spec.json"))$git$use_git)
})

test_that("adopt() merges the spec's .gitignore rules and never removes a line", {
  dir <- local_folder(c("analysis", "data/private", "notes/private-2024"))
  writeLines(c("# mine", "*.csv", "", "notes.txt", ".env"), file.path(dir, ".gitignore"))
  suppressWarnings(suppressMessages(adopt(dir, yes = TRUE)))
  lines <- readLines(file.path(dir, ".gitignore"))
  expect_identical(lines[1:5], c("# mine", "*.csv", "", "notes.txt", ".env"))
  expect_true("# Added by framework::adopt()" %in% lines)
  # data/private/ is covered by **/private/**; notes/private-2024/ needs its own rule
  expect_false("/data/private/" %in% readLines(file.path(dir, ".gitignore")))
  for (rule in c("framework.db", "**/private/**", "/.quarto/", "**/*.quarto_ipynb", "/notes/private-2024/")) {
    expect_true(rule %in% lines, info = rule)
  }
  expect_identical(sum(lines == ".env"), 1L)
  # The spec records the .gitignore the project has
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(spec$git$gitignore_content, paste(lines, collapse = "\n"))
})

test_that("adopt() leaves out a .gitignore rule that would hide tracked files", {
  skip_if(!nzchar(Sys.which("git")))
  dir <- local_folder(c("analysis"))
  writeLines("source('renv/activate.R')", file.path(dir, ".Rprofile"))
  git <- function(...) suppressWarnings(system2("git", c("-C", shQuote(dir), ...), stdout = FALSE, stderr = FALSE))
  git("init", "-q")
  git("add", ".Rprofile")
  msgs <- character()
  withCallingHandlers(adopt(dir, yes = TRUE),
                      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  lines <- readLines(file.path(dir, ".gitignore"))
  expect_false(".Rprofile" %in% lines)
  expect_true(".env" %in% lines)
  expect_true(any(grepl("Left out of .gitignore.*\\.Rprofile", msgs)))
})
