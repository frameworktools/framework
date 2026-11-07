test_that("settings_read reads configuration from YAML file", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  config <- settings_read()

  expect_type(config, "list")
  expect_true("data" %in% names(config))
  expect_true("packages" %in% names(config))
  expect_true("connections" %in% names(config))
  expect_true("options" %in% names(config))
})

test_that("settings_read handles missing config file", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  expect_error(settings_read("nonexistent.yml"))
})

test_that("settings_write writes configuration to file", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  test_config <- list(
    data = list(example = "data/example.csv"),
    packages = c("dplyr", "ggplot2")
  )

  settings_write(test_config, settings_file = "test_config.yml")

  expect_true(file.exists("test_config.yml"))

  # Read it back using yaml::read_yaml (gets raw structure with "default" wrapper)
  config_raw <- yaml::read_yaml("test_config.yml")
  expect_equal(config_raw$default$data$example, "data/example.csv")
  expect_equal(config_raw$default$packages, c("dplyr", "ggplot2"))

  # Read back with settings_read
  cfg_back <- settings_read(settings_file = "test_config.yml")
  expect_equal(cfg_back$data$example, "data/example.csv")
  # Packages are a character vector when written as simple strings
  expect_equal(cfg_back$packages, c("dplyr", "ggplot2"))
})


# ============================================================================
# Config Resolution and settings() Helper Tests
# ============================================================================

test_that("settings() helper with flat config accesses directories correctly", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  config_content <- "default:
  project_type: project

  directories:
    notebooks: my_notebooks
    scripts: my_scripts
    functions: my_functions
    cache: my_cache
"
  writeLines(config_content, "config.yml")

  # Test direct access to directories
  expect_equal(settings("directories.notebooks"), "my_notebooks")
  expect_equal(settings("directories.scripts"), "my_scripts")
  expect_equal(settings("directories.functions"), "my_functions")

  # Test smart lookup (single key checks directories first)
  expect_equal(settings("notebooks"), "my_notebooks")
  expect_equal(settings("scripts"), "my_scripts")
  expect_equal(settings("functions"), "my_functions")

  # Test project_type access
  expect_equal(settings("project_type"), "project")

  # Test default values
  expect_equal(settings("nonexistent"), NULL)
  expect_equal(settings("nonexistent", default = "fallback"), "fallback")
})


test_that("settings() helper handles legacy options structure", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  # Create legacy config with options$notebook_dir
  config_content <- "default:
  options:
    notebook_dir: legacy_notebooks
    script_dir: legacy_scripts
"
  writeLines(config_content, "config.yml")

  # Smart lookup should find legacy keys
  expect_equal(settings("notebook"), "legacy_notebooks")
  expect_equal(settings("script"), "legacy_scripts")
})


test_that("settings() prioritizes directories over legacy options", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  # Config with BOTH new and legacy structures
  config_content <- "default:
  directories:
    notebooks: new_notebooks

  options:
    notebook_dir: legacy_notebooks
"
  writeLines(config_content, "config.yml")

  # Should prefer directories structure
  expect_equal(settings("notebooks"), "new_notebooks")

  # Explicit path still works
  expect_equal(settings("options.notebook_dir"), "legacy_notebooks")
})


test_that("settings_read() merges directories correctly", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  config_content <- "default:
  directories:
    notebooks: notebooks
    scripts: scripts
    cache: outputs/private/cache
"
  writeLines(config_content, "config.yml")

  cfg <- settings_read()

  # Check structure
  expect_true(!is.null(cfg$directories))
  expect_equal(cfg$directories$notebooks, "notebooks")
  expect_equal(cfg$directories$scripts, "scripts")
  expect_equal(cfg$directories$cache, "outputs/private/cache")
})


test_that("split file config with inline directories works", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  dir.create("settings", showWarnings = FALSE)

  # Main config with inline directories and split data
  config_content <- "default:
  project_type: project

  directories:
    notebooks: notebooks
    scripts: scripts
    cache: outputs/private/cache

  data: settings/data.yml
"
  writeLines(config_content, "config.yml")

  # Create data settings file
  data_content <- "data:
  example:
    path: data/example.csv
    type: csv
"
  writeLines(data_content, "settings/data.yml")

  # Test config resolution
  cfg <- settings_read()

  # Directories should be inline
  expect_equal(cfg$directories$notebooks, "notebooks")
  expect_equal(cfg$directories$scripts, "scripts")

  # Data should come from split file
  expect_true(!is.null(cfg$data$example))
  expect_equal(cfg$data$example$path, "data/example.csv")

  # Test via settings() helper
  expect_equal(settings("notebooks"), "notebooks")
  expect_equal(settings("data.example.path"), "data/example.csv")
})


test_that("make_notebook() uses new directories config", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  # Create config with custom notebook directory
  config_content <- "default:
  directories:
    notebooks: custom_notebooks
"
  writeLines(config_content, "config.yml")

  # Directory detection should use config
  result <- framework:::.get_notebook_dir_from_config()
  expect_equal(result, "custom_notebooks")
})


test_that("settings() handles nested paths correctly", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  config_content <- "default:
  project_type: project
  connections:
    db:
      driver: postgresql
      host: localhost
      port: 5432
      database: mydb
"
  writeLines(config_content, "config.yml")

  # Test deep nesting
  expect_equal(settings("connections.db.driver"), "postgresql")
  expect_equal(settings("connections.db.host"), "localhost")
  expect_equal(settings("connections.db.port"), 5432)

  # Test partial paths
  db_config <- settings("connections.db")
  expect_true(is.list(db_config))
  expect_equal(db_config$driver, "postgresql")
  expect_equal(db_config$host, "localhost")
})


test_that("settings_read() initializes all standard sections", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  # Minimal config
  config_content <- "default:
  project_type: project
"
  writeLines(config_content, "config.yml")

  cfg <- settings_read()

  # All standard sections should exist (may be empty lists)
  expect_true(!is.null(cfg$data))
  expect_true(!is.null(cfg$connections))
  expect_true(!is.null(cfg$git))
  expect_true(!is.null(cfg$security))
  expect_true(!is.null(cfg$packages))
  expect_true(!is.null(cfg$directories))
  expect_true(!is.null(cfg$options))
})


test_that("settings() returns NULL for missing keys", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  config_content <- "default:
  directories:
    notebooks: notebooks
"
  writeLines(config_content, "config.yml")

  # Non-existent keys
  expect_null(settings("nonexistent"))
  expect_null(settings("directories.nonexistent"))
  expect_null(settings("deeply.nested.nonexistent"))

  # With defaults
  expect_equal(settings("nonexistent", default = "default_value"), "default_value")
})


test_that("config system handles all three project types", {
  # Test project type
  tmp1 <- tempfile()
  dir.create(tmp1)
  old_wd <- getwd()
  setwd(tmp1)

  config_content <- "default:
  project_type: project
  directories:
    notebooks: notebooks
    scripts: scripts
    outputs_public: outputs/public
"
  writeLines(config_content, "config.yml")
  expect_equal(settings("project_type"), "project")
  expect_equal(settings("scripts"), "scripts")
  setwd(old_wd)
  unlink(tmp1, recursive = TRUE)

  # Test course type
  tmp2 <- tempfile()
  dir.create(tmp2)
  setwd(tmp2)

  config_content <- "default:
  project_type: course
  directories:
    notebooks: notebooks
    presentations: presentations
"
  writeLines(config_content, "config.yml")
  expect_equal(settings("project_type"), "course")
  expect_equal(settings("presentations"), "presentations")
  setwd(old_wd)
  unlink(tmp2, recursive = TRUE)

  # Test presentation type
  tmp3 <- tempfile()
  dir.create(tmp3)
  setwd(tmp3)

  config_content <- "default:
  project_type: presentation
  directories:
    functions: functions
    cache: outputs/private/cache
"
  writeLines(config_content, "config.yml")
  expect_equal(settings("project_type"), "presentation")
  expect_equal(settings("cache"), "outputs/private/cache")
  setwd(old_wd)
  unlink(tmp3, recursive = TRUE)
})


# ============================================================================
# Config Conflict and Scoped Include Tests
# ============================================================================

# Test removed - format changed: split files now wrap content under section key
# Old format had unexpected keys at root level, new format wraps everything under connections:


test_that("conflict between main config and split file triggers warning", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  dir.create("settings", showWarnings = FALSE)

  # Main config with default_connection
  config_content <- "default:
  project_type: project
  connections: settings/connections.yml
  default_connection: from_main
"
  writeLines(config_content, "config.yml")

  # Split file ALSO has default_connection (conflict!)
  connections_content <- "connections:
  db:
    host: localhost

default_connection: from_split  # CONFLICT!
"
  writeLines(connections_content, "settings/connections.yml")

  # Should warn about conflict AND scoped include violation
  expect_warning(
    cfg <- settings_read(),
    "default_connection.*defined in both"
  )

  # Main file should win
  expect_equal(cfg$default_connection, "from_main")
})


# Test removed - format changed: split files now have section-specific structure
# Old format: connections file could have options:, new format: just connections: wrapper


test_that("main file value takes precedence over split file", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  dir.create("settings", showWarnings = FALSE)

  # Main config with explicit value
  config_content <- "default:
  project_type: project
  data: settings/data.yml
  cache_enabled: true
"
  writeLines(config_content, "config.yml")

  # Split file trying to override (bad practice, should warn)
  data_content <- "data:
  example:
    path: data/example.csv

cache_enabled: false  # Trying to override!
"
  writeLines(data_content, "settings/data.yml")

  # Should warn
  expect_warning(
    cfg <- settings_read(),
    "cache_enabled.*defined in both"
  )

  # Main file wins
  expect_true(cfg$cache_enabled)
})


test_that("multiple split files can coexist without conflicts", {
  tmp <- tempfile()
  dir.create(tmp)
  old_wd <- getwd()
  setwd(tmp)
  on.exit({
    setwd(old_wd)
    unlink(tmp, recursive = TRUE)
  })

  dir.create("settings", showWarnings = FALSE)

  # Main config with multiple split files
  config_content <- "default:
  project_type: project
  connections: settings/connections.yml
  data: settings/data.yml
"
  writeLines(config_content, "config.yml")

  # Connections file (clean)
  connections_content <- "connections:
  db:
    host: localhost
"
  writeLines(connections_content, "settings/connections.yml")

  # Data file (clean)
  data_content <- "data:
  example:
    path: data/example.csv
"
  writeLines(data_content, "settings/data.yml")

  # Should not warn (both files are clean)
  expect_no_warning(
    cfg <- settings_read()
  )

  # Both sections should be merged
  expect_equal(cfg$connections$db$host, "localhost")
  expect_equal(cfg$data$example$path, "data/example.csv")
})

# ---- settings() Helper Tests ----

test_that("settings() returns entire config when no key provided", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  cfg <- settings()
  expect_type(cfg, "list")
  expect_true("directories" %in% names(cfg))
  expect_true("packages" %in% names(cfg))
})

test_that("settings() accesses nested values with dot notation", {
  test_dir <- create_test_project(type = "project")
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Test nested access - get whatever directories exist
  dirs <- settings("directories")
  if (length(dirs) > 0) {
    first_key <- names(dirs)[1]
    first_value <- settings(paste0("directories.", first_key))
    expect_equal(first_value, dirs[[first_key]])
  }
})

test_that("settings() returns default for missing keys", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Missing key with default
  result <- settings("missing.key", default = "fallback")
  expect_equal(result, "fallback")

  # Missing key without default
  result <- settings("missing.key")
  expect_null(result)
})

test_that("settings() returns entire sections as lists", {
  test_dir <- create_test_project(type = "project")
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Get entire directories section
  dirs <- settings("directories")
  expect_type(dirs, "list")
  expect_true(length(dirs) > 0)  # Should have at least some directories
})

test_that("settings() handles smart directory lookups", {
  test_dir <- create_test_project(type = "project")
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Single-word key should check directories section
  # Get whatever directories exist and test smart lookup
  dirs <- settings("directories")
  if (length(dirs) > 0) {
    first_key <- names(dirs)[1]
    # Smart lookup (no "directories." prefix)
    smart_result <- settings(first_key)
    # Should match the direct access
    expect_equal(smart_result, dirs[[first_key]])
  }
})

test_that("settings() returns raw values in non-interactive mode", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Tests run in non-interactive mode
  # Should return raw list, not invisible
  dirs <- settings("directories")
  expect_type(dirs, "list")
  expect_visible(dirs)
})

test_that("settings() works with deep nesting", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create config with deep nesting
  yaml::write_yaml(list(
    default = list(
      project_type = "project",
      level1 = list(
        level2 = list(
          level3 = list(
            value = "deep_value"
          )
        )
      )
    )
  ), "config.yml")

  # Access deep value
  result <- settings("level1.level2.level3.value")
  expect_equal(result, "deep_value")

  # Access intermediate level
  level2 <- settings("level1.level2")
  expect_type(level2, "list")
  expect_true("level3" %in% names(level2))
})

test_that("settings_write(section =) keeps a flat file flat", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "settings.yml")
  yaml::write_yaml(list(project_type = "project", directories = list(notebooks = "notebooks")), path)

  settings_write(list(notebooks = "nb", scripts = "scripts"), settings_file = path, section = "directories")
  raw <- yaml::read_yaml(path)
  expect_null(raw$default)
  expect_identical(raw$project_type, "project")
  expect_identical(raw$directories, list(notebooks = "nb", scripts = "scripts"))
  expect_identical(settings_read(path)$directories$notebooks, "nb")

  # Files with environments still write into the active one
  yaml::write_yaml(list(default = list(directories = list(notebooks = "notebooks"))), path)
  settings_write(list(notebooks = "nb"), settings_file = path, section = "directories")
  expect_identical(yaml::read_yaml(path)$default$directories$notebooks, "nb")
})

test_that("settings_write(section =) merges a split file under its section key", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "settings.yml")
  dir.create(file.path(dir, "settings"))
  yaml::write_yaml(list(default = list(connections = "settings/connections.yml")), path)
  split <- file.path(dir, "settings", "connections.yml")
  yaml::write_yaml(list(connections = list(db = list(driver = "sqlite"))), split)

  settings_write(list(other = list(driver = "postgres")), settings_file = path, section = "connections")
  settings_write(list(connections = list(third = list(driver = "mysql"))), settings_file = path, section = "connections")
  written <- yaml::read_yaml(split)
  expect_identical(names(written), "connections")
  expect_setequal(names(written$connections), c("db", "other", "third"))

  # An older split file without the wrapper gets one
  yaml::write_yaml(list(db = list(driver = "sqlite")), split)
  settings_write(list(other = list(driver = "postgres")), settings_file = path, section = "connections")
  expect_setequal(names(yaml::read_yaml(split)$connections), c("db", "other"))
})
