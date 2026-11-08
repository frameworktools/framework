test_that("scaffold() fails fast when not in a Framework project", {
  # Ensure tempdir has no leftover settings markers from other tests
  unlink(file.path(tempdir(), "settings.yml"))
  unlink(file.path(tempdir(), "config.yml"))

  # Create a temporary empty directory
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Change to the temporary directory
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  # scaffold() should fail with clear error message
  expect_error(
    scaffold(),
    "Could not locate a Framework project",
    fixed = TRUE
  )

  expect_error(
    scaffold(),
    "scaffold\\(\\) searches for a project by looking for",
    fixed = FALSE  # Use regex for line breaks
  )

  expect_error(
    scaffold(),
    "To create a new project, use: project_create()",
    fixed = TRUE
  )
})

test_that("scaffold() works when config.yml exists", {
  # Create a temporary directory with minimal config
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Change to the temporary directory
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  # Create minimal config.yml
  writeLines(
    c(
      "default:",
      "  project_type: project",
      "  directories:",
      "    notebooks: notebooks"
    ),
    "config.yml"
  )

  # Create minimal .env file
  writeLines("", ".env")

  # scaffold() should succeed (may issue warnings about missing dirs, but shouldn't error)
  expect_no_error(scaffold())

  # Should have recorded scaffold history in the database
  history <- framework:::.get_scaffold_history(tmp_dir)
  expect_true(inherits(history$first, "POSIXct"))
  expect_true(inherits(history$last, "POSIXct"))
})

test_that("legacy post-scaffold commit uses portable git invocations", {
  skip_if_not(nzchar(Sys.which("git")), "Git is not installed")

  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  expect_equal(system2("git", "init", stdout = FALSE, stderr = FALSE), 0)
  expect_equal(
    system2(
      "git",
      c(
        "-c", "user.name=Framework-Test",
        "-c", "user.email=framework@example.com",
        "commit", "--allow-empty", "-m", "initial"
      ),
      stdout = FALSE,
      stderr = FALSE
    ),
    0
  )

  expect_silent(framework:::.commit_after_scaffold())
})

test_that(".mark_scaffolded() stores history in the project database", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  if (file.exists("framework.db")) {
    unlink("framework.db")
  }

  framework:::.mark_scaffolded(tmp_dir)

  history <- framework:::.get_scaffold_history(tmp_dir)
  expect_true(inherits(history$first, "POSIXct"))
  expect_true(inherits(history$last, "POSIXct"))
  expect_true(file.exists(file.path(tmp_dir, "framework.db")))
  expect_false(file.exists(".framework_scaffolded"))
})

test_that(".mark_scaffolded() migrates legacy marker files", {
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  legacy_path <- ".framework_scaffolded"
  legacy_lines <- c(
    "First scaffolded at: 2024-01-01 12:00:00",
    "Last scaffolded at: 2024-01-02 08:30:00"
  )
  writeLines(legacy_lines, legacy_path)

  framework:::.mark_scaffolded(tmp_dir)
  history <- framework:::.get_scaffold_history(tmp_dir)

  expect_false(file.exists(legacy_path))
  expect_equal(
    lubridate::ymd_hms("2024-01-01 12:00:00", tz = "UTC"),
    history$first
  )
  expect_true(history$last >= history$first)
})

test_that("standardize_wd() returns NULL when project not found", {
  unlink(file.path(tempdir(), "settings.yml"))
  unlink(file.path(tempdir(), "config.yml"))

  # Create a temporary empty directory
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Change to the temporary directory
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  # standardize_wd() should return NULL silently
  result <- standardize_wd()
  expect_null(result)
})

test_that("standardize_wd() finds and returns project root", {
  # Create a temporary directory with config.yml
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Change to the temporary directory
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  # Create config.yml
  writeLines(
    c(
      "default:",
      "  project_type: project"
    ),
    "config.yml"
  )

  # standardize_wd() should return the project root
  result <- standardize_wd()
  expect_equal(normalizePath(result), normalizePath(tmp_dir))
})

test_that("dotenv loads from current directory by default", {
  # Create a temporary directory
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  # Create config.yml without dotenv_location
  writeLines(
    c(
      "default:",
      "  project_type: project",
      "  directories:",
      "    notebooks: notebooks"
    ),
    "config.yml"
  )

  # Create .env in current directory
  writeLines("TEST_VAR=current_dir", ".env")

  # Clear any existing TEST_VAR
  if (Sys.getenv("TEST_VAR") != "") {
    Sys.unsetenv("TEST_VAR")
  }

  # scaffold() should load .env from current directory
  expect_no_error(scaffold())
  expect_equal(Sys.getenv("TEST_VAR"), "current_dir")
})

test_that("dotenv loads from parent directory when dotenv_location set", {
  # Create parent and child directories
  parent_dir <- tempfile()
  dir.create(parent_dir)
  child_dir <- file.path(parent_dir, "child")
  dir.create(child_dir)
  on.exit(unlink(parent_dir, recursive = TRUE))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(child_dir)

  # Create config.yml with dotenv_location pointing to parent
  writeLines(
    c(
      "default:",
      "  dotenv_location: \"../\"",
      "  project_type: project",
      "  directories:",
      "    notebooks: notebooks"
    ),
    "config.yml"
  )

  # Create .env in parent directory
  writeLines("TEST_VAR=parent_dir", file.path(parent_dir, ".env"))

  # Clear any existing TEST_VAR
  if (Sys.getenv("TEST_VAR") != "") {
    Sys.unsetenv("TEST_VAR")
  }

  # scaffold() should load .env from parent directory
  expect_no_error(scaffold())
  expect_equal(Sys.getenv("TEST_VAR"), "parent_dir")
})

test_that(".ensure_framework_db respects project root", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  }, add = TRUE)

  setwd(test_dir)
  expect_true(file.exists("framework.db"))

  # No message when framework.db already exists
  expect_silent(framework:::.ensure_framework_db())

  # Remove database and ensure it is recreated from subdirectory
  unlink("framework.db")
  dir.create(file.path(test_dir, "notebooks"), showWarnings = FALSE)
  setwd(file.path(test_dir, "notebooks"))
  expect_message(framework:::.ensure_framework_db(), "Created framework.db")
  expect_true(file.exists(file.path(test_dir, "framework.db")))
})

test_that(".set_random_seed honours seed_on_scaffold flag", {
  withr::local_seed(42)
  config <- list(
    seed = NULL,
    options = list(
      seed = 9876,
      seed_on_scaffold = TRUE
    )
  )

  expect_message(framework:::.set_random_seed(config), 'Random seed set to 9876.', fixed = TRUE)

  withr::local_seed(42)
  config$options$seed_on_scaffold <- FALSE
  expect_silent(framework:::.set_random_seed(config))
})

test_that("dotenv_location errors when file not found", {
  # Create a temporary directory
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tmp_dir)

  # Create config.yml with dotenv_location pointing to nonexistent location
  writeLines(
    c(
      "default:",
      "  dotenv_location: \"../nonexistent/\"",
      "  project_type: project"
    ),
    "config.yml"
  )

  # scaffold() should error with clear message
  expect_error(
    scaffold(),
    "Dotenv file not found at"
  )
})

test_that(".set_random_seed reads the scaffold section new projects write", {
  withr::local_envvar(FW_SEED = NA)
  withr::local_seed(42)
  config <- list(scaffold = list(seed_on_scaffold = TRUE, seed = "123"))
  expect_message(framework:::.set_random_seed(config), "Random seed set to 123.", fixed = TRUE)

  # The project's seed wins over FW_SEED, and an explicit false skips it
  withr::local_envvar(FW_SEED = "555")
  expect_message(framework:::.set_random_seed(config), "Random seed set to 123.", fixed = TRUE)
  config$scaffold$seed_on_scaffold <- FALSE
  expect_silent(framework:::.set_random_seed(config))

  # No project setting: FW_SEED turns seeding on
  expect_message(framework:::.set_random_seed(list()), "Random seed set to 555.", fixed = TRUE)
})

test_that(".set_ggplot_theme reads the scaffold section new projects write", {
  skip_if_not_installed("ggplot2")
  old <- ggplot2::theme_get()
  withr::defer(ggplot2::theme_set(old))

  config <- list(scaffold = list(set_theme_on_scaffold = TRUE, ggplot_theme = "theme_bw"))
  expect_message(framework:::.set_ggplot_theme(config), "ggplot2 theme set to theme_bw.", fixed = TRUE)

  # Turned off under scaffold: wins over an older options: setting
  config$scaffold$set_theme_on_scaffold <- FALSE
  config$options <- list(set_theme_on_scaffold = TRUE, ggplot_theme = "theme_bw")
  expect_silent(framework:::.set_ggplot_theme(config))
})

test_that("a new project's scaffold() seeds from its settings", {
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  withr::local_envvar(FW_SEED = NA)
  parent <- withr::local_tempdir()
  spec <- spec_resolve(list(list(type = "project", git = list(use_git = FALSE),
                                 scaffold = list(seed_on_scaffold = TRUE, seed = "2024"))), name = "Seeded")
  location <- file.path(parent, "seeded")
  suppressMessages(project_create(spec, location))
  config <- settings_read(file.path(location, "settings.yml"))
  expect_message(framework:::.set_random_seed(config), "Random seed set to 2024.", fixed = TRUE)
})

test_that("scaffold() creates the settings' private folders a fresh checkout lacks", {
  tmp_dir <- withr::local_tempdir()
  withr::local_dir(tmp_dir)
  writeLines(c(
    "default:",
    "  project_type: project_sensitive",
    "  directories:",
    "    notebooks: notebooks",
    "    inputs_private_intermediate: inputs/private/intermediate",
    "    inputs_public_raw: inputs/public/raw",
    "    outputs_private_figures: outputs/private/figures",
    "    elsewhere_private: ../outside_private"
  ), "settings.yml")
  writeLines("", ".env")
  msgs <- capture_messages(expect_no_error(scaffold()))
  expect_true(dir.exists("inputs/private/intermediate"))
  expect_true(dir.exists("outputs/private/figures"))
  expect_false(dir.exists("inputs/public/raw"))
  expect_false(dir.exists("notebooks"))
  expect_false(dir.exists(file.path("..", "outside_private")))
  expect_true(any(grepl("Created private folders: inputs/private/intermediate, outputs/private/figures",
                        msgs, fixed = TRUE)))
})
