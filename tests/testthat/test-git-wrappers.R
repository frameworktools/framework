# Regression tests from the 2026-11-05 audit: git wrappers, hooks on the
# default split-settings layout, and the security audit's .gitignore globs.

local_default_project <- function(env = parent.frame()) {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  withr::local_envvar(
    GIT_AUTHOR_NAME = "Test", GIT_AUTHOR_EMAIL = "test@example.org",
    GIT_COMMITTER_NAME = "Test", GIT_COMMITTER_EMAIL = "test@example.org",
    .local_envir = env
  )
  location <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressWarnings(suppressMessages(capture.output(
    new_project("Study", location, browse = FALSE, offline = TRUE)
  )))
  withr::local_dir(location, .local_envir = env)
  location
}

local_repo <- function(env = parent.frame()) {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  withr::local_envvar(
    GIT_AUTHOR_NAME = "Test", GIT_AUTHOR_EMAIL = "test@example.org",
    GIT_COMMITTER_NAME = "Test", GIT_COMMITTER_EMAIL = "test@example.org",
    .local_envir = env
  )
  system2("git", c("init", "-q", "-b", "main"), stdout = FALSE, stderr = FALSE)
  dir
}

test_that("git_hooks_enable() and _disable() write to the split settings/git.yml", {
  local_default_project()
  expect_match(grep("git:", readLines("settings.yml"), value = TRUE)[1], "settings/git.yml")

  expect_true(suppressMessages(git_hooks_enable("data_security", verbose = FALSE)))
  expect_true(yaml::read_yaml("settings/git.yml")$git$hooks$data_security)
  expect_true(settings("git.hooks.data_security"))
  # settings.yml still points at the split file
  expect_match(grep("git:", readLines("settings.yml"), value = TRUE)[1], "settings/git.yml")

  # The legacy alias is stored under its current name
  expect_true(suppressMessages(git_hooks_enable("warn_unignored_sensitive", verbose = FALSE)))
  hooks <- yaml::read_yaml("settings/git.yml")$git$hooks
  expect_true(hooks$check_sensitive_dirs)
  expect_null(hooks$warn_unignored_sensitive)

  expect_true(suppressMessages(git_hooks_disable("check_sensitive_dirs", verbose = FALSE)))
  expect_true(suppressMessages(git_hooks_disable("data_security", verbose = FALSE)))
  expect_false(yaml::read_yaml("settings/git.yml")$git$hooks$data_security)
  # Disabling again still reports success
  expect_true(suppressMessages(git_hooks_disable("data_security", verbose = FALSE)))
})

test_that("disabling check_sensitive_dirs also clears the old alias key", {
  dir <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(git = list(hooks = list(warn_unignored_sensitive = TRUE)))),
                   file.path(dir, "settings.yml"))
  framework:::.update_hook_config("check_sensitive_dirs", FALSE, file.path(dir, "settings.yml"))
  hooks <- yaml::read_yaml(file.path(dir, "settings.yml"))$default$git$hooks
  expect_false(hooks$check_sensitive_dirs)
  expect_null(hooks$warn_unignored_sensitive)
})

test_that("git_security_audit() passes a fresh project whose .gitignore covers scratch/ and logs/", {
  local_default_project()
  dir.create("scratch", showWarnings = FALSE)
  dir.create("logs", showWarnings = FALSE)
  result <- suppressMessages(git_security_audit(check_git_history = FALSE, verbose = FALSE))
  expect_false(any(result$findings$gitignore_issues$file %in% c("scratch", "logs")))
  row <- result$summary[result$summary$check == "gitignore_coverage", ]
  expect_identical(row$status, "pass")
})

test_that(".check_path_ignored treats dir/** as ignoring the folder", {
  probe <- function(path, patterns) {
    framework:::.check_path_ignored(path, patterns) ||
      framework:::.check_path_ignored(file.path(path, ".framework-probe"), patterns)
  }
  expect_true(probe("scratch", "**/scratch/**"))
  expect_true(probe("outputs/private", "outputs/private/**"))
  expect_false(probe("scratch", "**/logs/**"))
  expect_error(git_security_audit(history_depth = "deep"), "history_depth")
})

test_that("the shared pre-commit hook runs R in a project with no .Rproj or renv.lock", {
  skip_on_os("windows")
  dir <- local_default_project()
  expect_false(any(file.exists(c("renv.lock", ".Rprofile"))))
  expect_length(Sys.glob("*.Rproj"), 0)
  hook <- readLines(system.file("hooks", "pre-commit", package = "framework"))
  # The fallback for projects with only settings.yml tries R, then Python
  fallback <- grep("-f settings.yml", hook, fixed = TRUE)
  expect_length(fallback, 1)
  expect_true(any(grepl("run_r", hook[fallback:(fallback + 3)])))
})

test_that("git_add() stops when git fails and keeps paths with spaces whole", {
  local_repo()
  writeLines("x", "my analysis.R")
  expect_message(git_add("my analysis.R"), "Staged: my analysis.R")
  staged <- system2("git", c("diff", "--cached", "--name-only"), stdout = TRUE)
  expect_identical(staged, "my analysis.R")

  expect_error(suppressMessages(git_add("missing.R")), "Staging failed")
  writeLines(".env", ".gitignore")
  writeLines("SECRET=1", ".env")
  expect_error(suppressMessages(git_add(".env")), "Staging failed")
})

test_that("git_commit() takes a multi-line message vector", {
  local_repo()
  writeLines("x", "a.R")
  suppressMessages(git_add("a.R"))
  expect_message(git_commit(c("Subject line", "", "Body text")), "Committed: Subject line")
  body <- system2("git", c("log", "-1", "--format=%B"), stdout = TRUE)
  expect_identical(body[1:3], c("Subject line", "", "Body text"))
  expect_error(git_commit(NA_character_), "required")
})

test_that("git_diff() and git_log() stop on git errors instead of returning them", {
  local_repo()
  expect_message(git_log(), "No commits yet")
  writeLines("x", "a.R")
  suppressMessages(git_add("a.R"))
  suppressMessages(git_commit("first"))
  expect_error(git_log(n = "abc"))
  expect_length(suppressMessages(git_log(n = 1)), 1)
  writeLines("y", "a.R")
  expect_match(paste(suppressMessages(git_diff(file = "a.R")), collapse = "\n"), "\\+y")
  # "--" makes a missing path an empty diff, not git's "ambiguous argument"
  expect_message(git_diff(file = "no such file.R"), "No changes")
  expect_error(suppressMessages(git_diff(staged = "yes")))
})

test_that("git wrappers work from a subdirectory of the repository", {
  local_repo()
  dir.create("notebooks")
  withr::local_dir("notebooks")
  expect_no_error(suppressMessages(git_status(short = TRUE)))
})

test_that("git_push() pushes the current branch and sets its upstream", {
  dir <- local_repo()
  remote <- file.path(withr::local_tempdir(), "remote.git")
  system2("git", c("init", "-q", "--bare", shQuote(remote)), stdout = FALSE, stderr = FALSE)
  system2("git", c("remote", "add", "origin", shQuote(remote)))
  writeLines("x", "a.R")
  suppressMessages(git_add("a.R"))
  suppressMessages(git_commit("first"))
  expect_true(suppressMessages(git_push()))
  upstream <- system2("git", c("rev-parse", "--abbrev-ref", "main@{upstream}"), stdout = TRUE)
  expect_identical(upstream, "origin/main")
  # Later pushes need no arguments
  writeLines("y", "a.R")
  suppressMessages(git_commit("second", all = TRUE))
  expect_true(suppressMessages(git_push()))
})
