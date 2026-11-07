test_that("project_create creates basic project structure", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  # Create temp path for test (don't create the directory - project_create does that)
  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  # Create minimal project
  result <- project_create(
    name = "test_project",
    location = project_dir,
    type = "project",
    author = list(name = "Test User", email = "test@example.com", affiliation = "Test Org"),
    directories = list(
      notebooks = "notebooks",
      scripts = "scripts",
      functions = "functions"
    ),
    git = list(use_git = FALSE, hooks = list(), gitignore_content = "*.Rdata\n.Rhistory")
  )

  expect_true(result$success)
  expect_true(dir.exists(result$path))

  # Check settings.yml was created (project type uses split files)
  config_path <- file.path(result$path, "settings.yml")
  expect_true(file.exists(config_path))

  # Read and validate config
  config <- yaml::read_yaml(config_path)
  expect_equal(config$default$project_name, "test_project")
  expect_equal(config$default$project_type, "project")

  # Author info is in split file for project type
  author_config <- yaml::read_yaml(file.path(result$path, "settings/author.yml"))
  expect_equal(author_config$author$name, "Test User")
  expect_equal(author_config$author$email, "test@example.com")

  # Check directories were created
  expect_true(dir.exists(file.path(result$path, "notebooks")))
  expect_true(dir.exists(file.path(result$path, "scripts")))
  expect_true(dir.exists(file.path(result$path, "functions")))

  # Check .gitignore was created
  expect_true(file.exists(file.path(result$path, ".gitignore")))
  gitignore <- readLines(file.path(result$path, ".gitignore"))
  expect_true("*.Rdata" %in% gitignore)

  # Check .Rproj file was created (name is kebab-cased)
  expect_true(file.exists(file.path(result$path, "test-project.Rproj")))

  # Check scaffold.R was created
  expect_true(file.exists(file.path(result$path, "scaffold.R")))

  # Check .env template and connections defaults exist
  env_path <- file.path(result$path, ".env")
  expect_true(file.exists(env_path))
  env_lines <- readLines(env_path)
  expect_false(any(grepl("^FRAMEWORK_DB_PATH=", env_lines)))

  connections_path <- file.path(result$path, "settings/connections.yml")
  expect_true(file.exists(connections_path))
  connections_yaml <- yaml::read_yaml(connections_path)
  expect_equal(connections_yaml$options$default_connection, "framework")
  expect_true("framework" %in% names(connections_yaml$connections))
})

test_that("project_create persists provided connections (db + storage) with defaults", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  project_dir <- tempfile("framework_conn_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  conn_config <- list(
    default_database = "warehouse",
    default_storage_bucket = "s3_bucket",
    databases = list(
      warehouse = list(
        driver = "postgres",
        host = "localhost",
        port = "5432",
        database = "analytics",
        schema = "public",
        user = "analyst",
        password = "secret"
      )
    ),
    storage_buckets = list(
      s3_bucket = list(
        bucket = "my-bucket",
        region = "us-east-1",
        endpoint = "https://s3.amazonaws.com",
        access_key = "abc",
        secret_key = "xyz"
      )
    )
  )

  result <- project_create(
    name = "conn_project",
    location = project_dir,
    type = "project",
    connections = conn_config,
    git = list(use_git = FALSE)
  )

  expect_true(result$success)

  connections_path <- file.path(result$path, "settings/connections.yml")
  expect_true(file.exists(connections_path))
  connections_yaml <- yaml::read_yaml(connections_path)

  # The split file nests everything under connections: (as spec projects do)
  connections_yaml <- connections_yaml$connections
  expect_equal(connections_yaml$default_database, "warehouse")
  expect_equal(connections_yaml$default_storage_bucket, "s3_bucket")
  expect_true("warehouse" %in% names(connections_yaml$databases))
  expect_true("s3_bucket" %in% names(connections_yaml$storage_buckets))
  expect_equal(connections_yaml$databases$warehouse$driver, "postgres")
  expect_equal(connections_yaml$storage_buckets$s3_bucket$bucket, "my-bucket")
})

test_that("project_create handles packages configuration", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  result <- project_create(
    name = "test_packages",
    location = project_dir,
    type = "project",
    packages = list(
      use_renv = FALSE,
      default_packages = list(
        list(name = "dplyr", source = "cran", auto_attach = TRUE),
        list(name = "ggplot2", source = "cran", auto_attach = TRUE)
      )
    ),
    git = list(use_git = FALSE)
  )

  expect_true(result$success)

  # Read packages split file and check packages
  packages_config <- yaml::read_yaml(file.path(result$path, "settings/packages.yml"))
  expect_false(packages_config$packages$use_renv)
  expect_length(packages_config$packages$default_packages, 2)
  expect_equal(packages_config$packages$default_packages[[1]]$name, "dplyr")
  expect_true(packages_config$packages$default_packages[[1]]$auto_attach)
})

test_that("project_create handles AI configuration", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  result <- project_create(
    name = "test_ai",
    location = project_dir,
    type = "project",
    ai = list(
      enabled = TRUE,
      assistants = c("claude", "agents"),
      canonical_file = "AGENTS.md",
      canonical_content = "# Test AI Context\n\nThis is a test."
    ),
    git = list(use_git = FALSE)
  )

  expect_true(result$success)

  # Check AI files were created
  expect_true(file.exists(file.path(result$path, "CLAUDE.md")))
  expect_true(file.exists(file.path(result$path, "AGENTS.md")))

  # Check AI settings file has correct values (split file for project type)
  ai_config <- yaml::read_yaml(file.path(result$path, "settings", "ai.yml"))
  expect_true(ai_config$ai$enabled)
  expect_equal(ai_config$ai$assistants, c("claude", "agents"))
  expect_equal(ai_config$ai$canonical_file, "AGENTS.md")
})

test_that("project_create handles scaffold configuration", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  result <- project_create(
    name = "test_scaffold",
    location = project_dir,
    type = "project",
    scaffold = list(
      seed_on_scaffold = TRUE,
      seed = "20241109",
      set_theme_on_scaffold = TRUE,
      ggplot_theme = "theme_bw"
    ),
    git = list(use_git = FALSE)
  )

  expect_true(result$success)

  # scaffold() sets the seed and theme from settings, so scaffold.R only
  # names them and doesn't set them a second time
  scaffold <- readLines(file.path(result$path, "scaffold.R"))
  expect_false(any(grepl("^\\s*set.seed\\(", scaffold)))
  expect_false(any(grepl("^\\s*ggplot2::theme_set", scaffold)))
  expect_true(any(grepl("seed 20241109, theme theme_bw", scaffold, fixed = TRUE)))

  # Check scaffold split file
  scaffold_config <- yaml::read_yaml(file.path(result$path, "settings/scaffold.yml"))
  expect_true(scaffold_config$scaffold$seed_on_scaffold)
  expect_equal(scaffold_config$scaffold$seed, "20241109")
  expect_equal(scaffold_config$scaffold$ggplot_theme, "theme_bw")
})

test_that("project_create handles extra directories", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  result <- project_create(
    name = "test_extra_dirs",
    location = project_dir,
    type = "project",
    directories = list(notebooks = "notebooks"),
    extra_directories = list(
      list(key = "custom_data", label = "Custom Data", path = "data/custom", type = "input"),
      list(key = "reports", label = "Reports", path = "outputs/reports", type = "output_public")
    ),
    git = list(use_git = FALSE)
  )

  expect_true(result$success)

  # Check extra directories were created
  expect_true(dir.exists(file.path(result$path, "data/custom")))
  expect_true(dir.exists(file.path(result$path, "outputs/reports")))

  # Check main settings.yml has extra_directories (inline in main file)
  config <- yaml::read_yaml(file.path(result$path, "settings.yml"))
  expect_length(config$default$extra_directories, 2)
  expect_equal(config$default$extra_directories[[1]]$key, "custom_data")
})

test_that("project_create applies git hooks and use_git from inputs", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  result <- project_create(
    name = "test_git_hooks",
    location = project_dir,
    type = "project",
    git = list(
      use_git = TRUE,
      user_name = "Git User",
      user_email = "git@example.com",
      hooks = list(
        ai_sync = TRUE,
        data_security = FALSE,
        check_sensitive_dirs = TRUE
      )
    )
  )

  expect_true(result$success)

  # Git config is in split file
  git_config <- yaml::read_yaml(file.path(result$path, "settings/git.yml"))
  expect_true(git_config$git$enabled)
  expect_equal(git_config$git$user_name, "Git User")
  expect_equal(git_config$git$user_email, "git@example.com")
  expect_true(git_config$git$hooks$ai_sync)
  expect_false(git_config$git$hooks$data_security)
  expect_true(git_config$git$hooks$check_sensitive_dirs)
})

test_that("project_create fails if directory already exists", {
  skip_on_cran()

  # Use a single temp path for the project
  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  # Create first project
  result1 <- project_create(
    name = "duplicate_test",
    location = project_dir,
    type = "project",
    git = list(use_git = FALSE)
  )

  expect_true(result1$success)

  # Try to create another project at the same location (should fail)
  expect_error(
    project_create(
      name = "duplicate_test",
      location = project_dir,
      type = "project",
      git = list(use_git = FALSE)
    ),
    "already exists"
  )
})

test_that("project_create validates required parameters", {
  expect_error(framework::project_create(name = "", location = "~/test"), "at least 1 characters")
  expect_error(framework::project_create(name = "test", location = ""), "at least 1 characters")
  expect_error(framework::project_create(name = "test", location = "~/test", type = "invalid"), "Must be element of set")
})

test_that("project_create handles different project types", {
  skip_if_not_installed("yaml")
  skip_on_cran()

  # Create a parent temp directory to hold all project directories
  parent_dir <- tempfile("framework_test_")
  dir.create(parent_dir)
  on.exit(unlink(parent_dir, recursive = TRUE), add = TRUE)

  # Test each project type
  for (type in c("project", "project_sensitive", "course", "presentation")) {
    project_dir <- file.path(parent_dir, paste0("test_", type))
    result <- project_create(
      name = paste0("test_", type),
      location = project_dir,
      type = type,
      git = list(use_git = FALSE)
    )

    expect_true(result$success, info = paste("Failed for type:", type))

    # project and project_sensitive use settings.yml with split files
    # course and presentation use settings.yml as single file
    config_path <- file.path(result$path, "settings.yml")
    expect_true(file.exists(config_path), info = paste("settings.yml not found for type:", type))

    config <- yaml::read_yaml(config_path)
    expect_equal(config$default$project_type, type, info = paste("Wrong type in config for:", type))
  }
})
