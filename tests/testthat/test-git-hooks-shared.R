local_git_project <- function(hooks = list(data_security = TRUE), env = parent.frame()) {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  system2("git", c("init", "-q"), stdout = FALSE, stderr = FALSE)
  yaml::write_yaml(list(default = list(
    project_type = "project_sensitive",
    directories = list(inputs_raw = "inputs/raw"),
    git = list(hooks = hooks)
  )), "settings.yml")
  dir
}

test_that("git_hooks_install writes the shared script and replaces Framework hooks only", {
  local_git_project()
  shared <- readLines(system.file("hooks", "pre-commit", package = "framework"))
  expect_true(any(grepl("Framework pre-commit hook", shared)))

  expect_true(git_hooks_install(verbose = FALSE))
  expect_identical(readLines(".git/hooks/pre-commit"), shared)

  # R 1.x hooks are replaced without force
  writeLines(c("#!/usr/bin/env bash", "# Framework Git Hooks", "exit 0"), ".git/hooks/pre-commit")
  expect_true(git_hooks_install(verbose = FALSE))
  expect_identical(readLines(".git/hooks/pre-commit"), shared)

  # Someone else's hook is kept unless forced
  writeLines(c("#!/bin/sh", "echo mine"), ".git/hooks/pre-commit")
  expect_false(git_hooks_install(verbose = FALSE))
  expect_identical(readLines(".git/hooks/pre-commit"), c("#!/bin/sh", "echo mine"))
  expect_false(git_hooks_uninstall(verbose = FALSE))
  expect_true(git_hooks_install(force = TRUE, verbose = FALSE))
  expect_true(git_hooks_uninstall(verbose = FALSE))
  expect_false(file.exists(".git/hooks/pre-commit"))
})

test_that("git_hooks_install follows core.hooksPath", {
  local_git_project()
  system2("git", c("config", "core.hooksPath", "githooks"), stdout = FALSE, stderr = FALSE)
  expect_true(git_hooks_install(verbose = FALSE))
  expect_true(file.exists("githooks/pre-commit"))
  expect_false(file.exists(".git/hooks/pre-commit"))
})

test_that(".hook_run passes outside a project and blocks tracked private data", {
  dir <- withr::local_tempdir()
  withr::with_dir(dir, expect_identical(.hook_run("pre-commit"), 0L))

  local_git_project()
  expect_identical(suppressMessages(.hook_run("pre-commit")), 0L)
  expect_identical(suppressMessages(.hook_run("post-commit")), 1L)

  dir.create("inputs/private", recursive = TRUE)
  write.csv(data.frame(id = 1:3), "inputs/private/ids.csv", row.names = FALSE)
  writeLines("inputs/private/", ".gitignore")
  system2("git", c("add", "-f", "inputs/private/ids.csv"), stdout = FALSE, stderr = FALSE)
  expect_message(status <- .hook_run("pre-commit"), "Data security check failed")
  expect_identical(status, 1L)
})

test_that("check_sensitive_dirs warns and continues without a terminal", {
  local_git_project(hooks = list(check_sensitive_dirs = TRUE))
  dir.create("outputs/private", recursive = TRUE)
  dir.create("notes/confidential", recursive = TRUE)
  writeLines("outputs/private/", ".gitignore")
  expect_identical(.hook_unignored_sensitive_dirs(), "notes/confidential")

  testthat::local_mocked_bindings(.hook_confirm = function(question) NA)
  expect_message(status <- .hook_run("pre-commit"), "Non-interactive mode")
  expect_identical(status, 0L)

  testthat::local_mocked_bindings(.hook_confirm = function(question) FALSE)
  expect_message(status <- .hook_run("pre-commit"), "Commit aborted")
  expect_identical(status, 1L)
})

test_that("the ai_sync hook is removed", {
  local_git_project(hooks = list(ai_sync = TRUE))
  # An old ai_sync: true alone installs nothing
  expect_false(git_hooks_install(verbose = FALSE))
  expect_false(file.exists(".git/hooks/pre-commit"))
  expect_identical(.hook_run("pre-commit"), 0L)
  expect_error(git_hooks_enable("ai_sync", verbose = FALSE), "removed in framework 2.0")
  expect_true(git_hooks_disable("ai_sync", verbose = FALSE))
  expect_false(yaml::read_yaml("settings.yml")$default$git$hooks$ai_sync)
  expect_false("ai_sync" %in% suppressMessages(git_hooks_list())$hook)
})

test_that("ai_sync_context() is deprecated", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  expect_warning(try(ai_sync_context(verbose = FALSE), silent = TRUE), "deprecated")
})

test_that("the hook explains when no runtime has framework installed", {
  skip_on_os("windows")
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  system2("git", c("init", "-q"), stdout = FALSE, stderr = FALSE)
  file.create("demo.Rproj", "pyproject.toml")

  # Rscript and python3 exist, but neither has the framework package
  bin <- file.path(dir, "bin")
  dir.create(bin)
  for (tool in c("Rscript", "python3")) {
    writeLines(c("#!/bin/sh", "echo \"$0 ran: $*\" >> \"$HOOK_LOG\"", "exit 1"), file.path(bin, tool))
    Sys.chmod(file.path(bin, tool), "0755")
  }
  log <- file.path(dir, "calls.log")
  git_dir <- dirname(Sys.which("git"))
  withr::local_envvar(PATH = paste(bin, git_dir, "/usr/bin", "/bin", sep = ":"), HOOK_LOG = log)

  hook <- system.file("hooks", "pre-commit", package = "framework")
  out <- suppressWarnings(system2("sh", hook, stdout = TRUE, stderr = TRUE))
  expect_identical(attr(out, "status"), 1L)
  expect_match(paste(out, collapse = "\n"), "found neither R with framework 2.0 or later nor Python with framework-py")

  # Each runtime was only probed, never asked to run the hook
  calls <- readLines(log)
  expect_length(calls, 2)
  expect_match(calls[1], "Rscript ran: -e ok <- requireNamespace")
  expect_match(calls[2], "python3 ran: -c import framework")
})

test_that("check_notebook_outputs blocks staged notebooks with outputs", {
  local_git_project(hooks = list(check_notebook_outputs = TRUE))
  notebook <- function(path, outputs = list(), count = NULL) {
    cell <- list(cell_type = "code", execution_count = count, metadata = structure(list(), names = character()),
                 outputs = outputs, source = list("head(df)"))
    jsonlite::write_json(list(cells = list(cell), metadata = structure(list(), names = character()),
                              nbformat = 4, nbformat_minor = 5),
                         path, auto_unbox = TRUE, null = "null")
  }
  dir.create("notebooks")
  notebook("notebooks/clean.ipynb")
  notebook("notebooks/ran.ipynb", count = 1)
  notebook("notebooks/printed data.ipynb",
           outputs = list(list(output_type = "stream", name = "stdout", text = list("id 1"))))
  notebook("notebooks/unstaged.ipynb", count = 3)
  system2("git", c("add", "notebooks/clean.ipynb", "notebooks/ran.ipynb", shQuote("notebooks/printed data.ipynb")),
          stdout = FALSE, stderr = FALSE)

  expect_setequal(.hook_notebooks_with_outputs(), c("notebooks/ran.ipynb", "notebooks/printed data.ipynb"))
  expect_message(status <- .hook_run("pre-commit"), "saved outputs")
  expect_identical(status, 1L)

  # The staged copy counts, not the working file
  notebook("notebooks/ran.ipynb")
  notebook("notebooks/printed data.ipynb")
  expect_length(.hook_notebooks_with_outputs(), 2)
  system2("git", c("add", "notebooks"), stdout = FALSE, stderr = FALSE)
  system2("git", c("rm", "-q", "--cached", "notebooks/unstaged.ipynb"), stdout = FALSE, stderr = FALSE)
  expect_identical(.hook_run("pre-commit"), 0L)
})

test_that("git_hooks_enable knows check_notebook_outputs", {
  local_git_project(hooks = list())
  expect_true(suppressMessages(git_hooks_enable("check_notebook_outputs")))
  expect_true(yaml::read_yaml("settings.yml")$default$git$hooks$check_notebook_outputs)
  df <- suppressMessages(git_hooks_list())
  expect_true(df$enabled[df$hook == "check_notebook_outputs"])
})

test_that("git hooks refuse a project nested inside another repository", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  outer <- withr::local_tempdir()
  system2("git", c("-C", shQuote(outer), "init", "-q"), stdout = FALSE, stderr = FALSE)
  outer_hook <- file.path(outer, ".git", "hooks", "pre-commit")
  writeLines(c("#!/bin/sh", "# Framework pre-commit hook", "exit 0"), outer_hook)

  project <- file.path(outer, "examples", "study")
  dir.create(project, recursive = TRUE)
  writeLines(c("default:", "  git:", "    hooks:", "      data_security: true"), file.path(project, "settings.yml"))
  withr::local_dir(project)

  expect_error(git_hooks_install(verbose = FALSE), "inside the git repository at")
  expect_message(git_hooks_uninstall(), "inside the repository at")
  expect_true(file.exists(outer_hook))
  expect_message(git_hooks_list(), "inside the repository at")
  expect_message(git_status(), "status of that enclosing repository")
  expect_true(file.exists(outer_hook))

  # A project at the top of its own repository is unaffected
  system2("git", c("-C", shQuote(project), "init", "-q"), stdout = FALSE, stderr = FALSE)
  expect_null(framework:::.fw_outer_repository(project))
  expect_true(suppressMessages(git_hooks_install()))
  expect_true(file.exists(file.path(project, ".git", "hooks", "pre-commit")))
})
