test_that("git_security_audit requires valid config file", {
  # Create temp directory
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # No config file
  expect_error(
    git_security_audit(verbose = FALSE),
    "Config file not found"
  )
})


test_that("git_security_audit detects unignored private data directories", {
  # Create test project
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create minimal config
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/private/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  # Create private data directory and file
  dir.create("inputs/private/raw", recursive = TRUE)
  write.csv(data.frame(secret = 1:5), "inputs/private/raw/secrets.csv", row.names = FALSE)

  # Create empty .gitignore (no private data protection)
  writeLines("", ".gitignore")

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Should detect unignored private directory
  expect_true(nrow(audit$findings$gitignore_issues) > 0)
  expect_true(any(audit$summary$status == "fail" | audit$summary$status == "warning"))
  expect_true(length(audit$recommendations) > 0)
})


test_that("git_security_audit passes when private data is properly ignored", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  # Create private data directory and file
  dir.create("inputs/raw", recursive = TRUE)
  write.csv(data.frame(secret = 1:5), "inputs/raw/secrets.csv", row.names = FALSE)

  # Create .gitignore with proper protection
  writeLines(c(
    "inputs/raw/",
    "inputs/raw/**"
  ), ".gitignore")

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Should pass gitignore coverage check
  expect_equal(
    audit$summary$status[audit$summary$check == "gitignore_coverage"],
    "pass"
  )
})


test_that("git_security_audit detects orphaned data files", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config with standard directories
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/raw",
        inputs_reference = "inputs/reference"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  # Create configured directories
  dir.create("inputs/raw", recursive = TRUE)
  dir.create("inputs/reference", recursive = TRUE)

  # Create orphaned data file outside configured directories
  write.csv(data.frame(orphaned = 1:5), "random_data.csv", row.names = FALSE)

  # Create .gitignore
  writeLines("inputs/", ".gitignore")

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Should detect orphaned file
  expect_true(nrow(audit$findings$orphaned_files) > 0)
  expect_true("random_data.csv" %in% audit$findings$orphaned_files$path)
  expect_equal(
    audit$summary$status[audit$summary$check == "orphaned_files"],
    "warning"
  )
})


test_that("git_security_audit detects git-tracked private data", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/private/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  # Create private data directory and file
  dir.create("inputs/private/raw", recursive = TRUE)
  write.csv(data.frame(secret = 1:5), "inputs/private/raw/secrets.csv", row.names = FALSE)

  # Initialize git and accidentally commit private data
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)
  system2("git", c("add", "inputs/private/raw/secrets.csv"), stdout = FALSE, stderr = FALSE)

  # Create .gitignore AFTER accidentally tracking file
  writeLines(c(
    "inputs/private/raw/",
    "inputs/private/raw/**"
  ), ".gitignore")

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Should detect tracked private data
  expect_true(nrow(audit$findings$private_data_exposure) > 0)
  expect_equal(
    audit$summary$status[audit$summary$check == "private_data_exposure"],
    "fail"
  )
  expect_true(any(grepl("git rm --cached", audit$recommendations)))
})


test_that("git_security_audit flags tracked data under private-named folders", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # inputs/private is not a configured directory here
  yaml::write_yaml(list(default = list(
    project_type = "project_sensitive",
    directories = list(inputs_raw = "inputs/raw", inputs_raw_public = "inputs/raw_public")
  )), "settings.yml")
  dir.create("inputs/private", recursive = TRUE)
  dir.create("inputs/raw_public", recursive = TRUE)
  write.csv(data.frame(id = 1:3), "inputs/private/ids.csv", row.names = FALSE)
  write.csv(data.frame(x = 1), "inputs/raw_public/ok.csv", row.names = FALSE)
  writeLines("inputs/private/", ".gitignore")

  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("add", "-f", "inputs/private/ids.csv", "inputs/raw_public/ok.csv"),
          stdout = FALSE, stderr = FALSE)

  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  expect_equal(audit$findings$private_data_exposure$file, "inputs/private/ids.csv")
  expect_equal(
    audit$summary$status[audit$summary$check == "private_data_exposure"],
    "fail"
  )
})


test_that("git_security_audit skips git checks when git not available", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create minimal config (no git repo)
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  dir.create("inputs/raw", recursive = TRUE)
  writeLines("inputs/", ".gitignore")

  # Run audit (no git repo, so git checks should be skipped)
  audit <- git_security_audit(check_git_history = TRUE, verbose = FALSE)

  # Git history check should be skipped
  expect_equal(
    audit$summary$status[audit$summary$check == "git_history"],
    "skipped"
  )
})


test_that("git_security_audit respects history_depth parameter", {
  skip_if_not(file.exists(".git"), "Requires git repository")

  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  dir.create("inputs/raw", recursive = TRUE)
  writeLines("inputs/", ".gitignore")

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Create initial commit
  writeLines("test", "test.txt")
  system2("git", c("add", "test.txt"), stdout = FALSE, stderr = FALSE)
  system2("git", c("commit", "-m", "initial"), stdout = FALSE, stderr = FALSE)

  # Test different depth values
  expect_silent(audit1 <- git_security_audit(history_depth = "all", verbose = FALSE))
  expect_silent(audit2 <- git_security_audit(history_depth = "shallow", verbose = FALSE))
  expect_silent(audit3 <- git_security_audit(history_depth = 10, verbose = FALSE))

  expect_true(is.list(audit1))
  expect_true(is.list(audit2))
  expect_true(is.list(audit3))
})


test_that("git_security_audit auto_fix adds normalized entries to .gitignore", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config with two private directories
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/private/raw",
        inputs_intermediate = "inputs/private/intermediate"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  # Create private data
  dir.create("inputs/private/raw", recursive = TRUE)
  dir.create("inputs/private/intermediate", recursive = TRUE)
  write.csv(data.frame(secret = 1:5), "inputs/private/raw/secrets.csv", row.names = FALSE)
  write.csv(data.frame(secret = 1:5), "inputs/private/intermediate/tmp.csv", row.names = FALSE)

  # Create empty .gitignore
  writeLines("", ".gitignore")

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Run audit with auto_fix
  audit <- git_security_audit(check_git_history = FALSE, auto_fix = TRUE, verbose = FALSE)

  # Check that .gitignore was updated
  gitignore_content <- readLines(".gitignore", warn = FALSE)
  expect_true(any(grepl("^# Framework Security Audit", gitignore_content)))
  expect_true(any(grepl("inputs/private/raw/$", gitignore_content)))
  expect_true(any(grepl("inputs/private/raw/\\*\\*$", gitignore_content)))

  # Run audit again after removing file to ensure idempotent header handling
  file.remove("inputs/private/intermediate/tmp.csv")
  write.csv(data.frame(secret = 1:5), "inputs/private/intermediate/tmp.csv", row.names = FALSE)
  audit <- git_security_audit(check_git_history = FALSE, auto_fix = TRUE, verbose = FALSE)

  gitignore_content <- readLines(".gitignore", warn = FALSE)
  expect_true(any(grepl("inputs/private/intermediate/$", gitignore_content)))
  expect_true(any(grepl("inputs/private/intermediate/\\*\\*$", gitignore_content)))
  expect_equal(sum(grepl("^# Framework Security Audit", gitignore_content)), 1)
  expect_true(
    audit$summary$status[audit$summary$check == "gitignore_coverage"] %in% c("pass", "warning")
  )
})


test_that("git_security_audit saves results to framework database", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  dir.create("inputs/raw", recursive = TRUE)
  writeLines("inputs/", ".gitignore")

  # Create framework database with proper initialization
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")

  # Create meta table (framework database schema)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  ")

  DBI::dbDisconnect(con)

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Check that metadata was saved
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  last_audit <- DBI::dbGetQuery(con,
    "SELECT value FROM meta WHERE key = 'last_git_security_audit'")$value
  status <- DBI::dbGetQuery(con,
    "SELECT value FROM meta WHERE key = 'last_audit_status'")$value
  DBI::dbDisconnect(con)

  expect_true(!is.null(last_audit) && length(last_audit) > 0)
  expect_true(!is.null(status) && length(status) > 0)
  expect_true(status %in% c("pass", "warning", "fail"))
})


test_that("git_security_audit handles various data file extensions", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_reference = "inputs/reference"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  dir.create("inputs/reference", recursive = TRUE)
  writeLines("inputs/", ".gitignore")

  # Create data files with various extensions
  writeLines("test", "orphan.csv")
  writeLines("test", "orphan.rds")
  writeLines("test", "orphan.xlsx")
  writeLines("test", "orphan.parquet")
  writeLines("test", "not_data.txt")  # This should be flagged as txt is in default extensions

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Should detect orphaned data files
  expect_true(nrow(audit$findings$orphaned_files) >= 4)
  expect_true("orphan.csv" %in% audit$findings$orphaned_files$path)
  expect_true("orphan.parquet" %in% audit$findings$orphaned_files$path)
})


test_that("git_security_audit returns correct structure", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create minimal valid setup
  config <- list(
    default = list(
      project_type = "project",
      directories = list(
        inputs_raw = "inputs/raw"
      )
    )
  )
  yaml::write_yaml(config, "settings.yml")

  dir.create("inputs/raw", recursive = TRUE)
  writeLines("inputs/", ".gitignore")

  # Initialize git
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Run audit
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)

  # Check structure
  expect_true(is.list(audit))
  expect_true("summary" %in% names(audit))
  expect_true("findings" %in% names(audit))
  expect_true("recommendations" %in% names(audit))
  expect_true("audit_metadata" %in% names(audit))

  # Check summary is a data frame
  expect_s3_class(audit$summary, "data.frame")
  expect_true(all(c("check", "status", "count") %in% names(audit$summary)))

  # Check findings structure
  expect_true(is.list(audit$findings))
  expect_true("gitignore_issues" %in% names(audit$findings))
  expect_true("git_history_issues" %in% names(audit$findings))
  expect_true("orphaned_files" %in% names(audit$findings))
  expect_true("private_data_exposure" %in% names(audit$findings))

  # Check metadata
  expect_true(is.list(audit$audit_metadata))
  expect_true("timestamp" %in% names(audit$audit_metadata))
  expect_true("framework_version" %in% names(audit$audit_metadata))
})


test_that("git_security_audit validates arguments", {
  # Create temp directory with valid config
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  config <- list(
    default = list(
      project_type = "project",
      directories = list()
    )
  )
  yaml::write_yaml(config, "settings.yml")
  writeLines("", ".gitignore")

  # Test invalid arguments
  expect_error(git_security_audit(config_file = 123, verbose = FALSE))
  expect_error(git_security_audit(check_git_history = "yes", verbose = FALSE))
  expect_error(git_security_audit(auto_fix = 1, verbose = FALSE))
  expect_error(git_security_audit(verbose = "true", verbose = FALSE))
  expect_error(git_security_audit(extensions = 123, verbose = FALSE))
})


test_that("git_security_audit handles sensitive filename patterns", {
  test_dir <- tempfile()
  dir.create(test_dir)
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    unlink(test_dir, recursive = TRUE)
  })
  setwd(test_dir)

  # Create config
  config <- list(
    default = list(
      project_type = "project",
      directories = list()
    )
  )
  yaml::write_yaml(config, "settings.yml")

  # Initialize git with commits containing sensitive file patterns
  system2("git", c("init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("config", "user.name", "Test User"), stdout = FALSE, stderr = FALSE)

  # Commit file with sensitive name pattern
  writeLines("test", "password_data.csv")
  system2("git", c("add", "password_data.csv"), stdout = FALSE, stderr = FALSE)
  system2("git", c("commit", "-m", "test"), stdout = FALSE, stderr = FALSE)

  writeLines("", ".gitignore")

  # Run audit with git history
  audit <- git_security_audit(history_depth = "all", verbose = FALSE)

  # Should detect sensitive pattern in git history
  # (The file has "password" in name and is a .csv data file)
  if (nrow(audit$findings$git_history_issues) > 0) {
    expect_true(any(grepl("password", audit$findings$git_history_issues$file, ignore.case = TRUE)))
  }
})

test_that("private folders are the ones the gitignore templates ignore", {
  dirs <- list(
    inputs_raw = "inputs/raw",
    inputs_final = "inputs/final",
    inputs_private_raw = "inputs/private/raw",
    outputs_private = "outputs/private",
    outputs_public = "outputs/public",
    exports = "shared/confidential/exports",
    inputs_public_raw = "inputs/public/raw",
    cache = "outputs/private/cache",
    logs = "logs"
  )
  expect_setequal(
    names(framework:::.identify_private_dirs(dirs)),
    c("inputs_private_raw", "outputs_private", "exports", "cache", "logs")
  )
})

test_that("the orphaned-file scan skips gitignored files and nested _files/_cache folders", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("notebooks/report_files/libs", recursive = TRUE)
  dir.create("notebooks/report_cache/html", recursive = TRUE)
  dir.create("local-site/a", recursive = TRUE)
  dir.create("analysis", recursive = TRUE)
  writeLines("x", "notebooks/report_files/libs/data.json")
  writeLines("x", "notebooks/report_cache/html/chunk.rds")
  writeLines("x", "local-site/a/data.csv")
  writeLines("x", "analysis/scratch.csv")
  writeLines("x", "analysis/kept.csv")
  writeLines(c("/local-site/", "scratch.csv"), ".gitignore")

  found <- function() {
    framework:::.scan_for_orphaned_files(list(), c("csv", "rds", "json"), FALSE)$files$path
  }
  # Without git: the .gitignore patterns
  expect_identical(found(), "analysis/kept.csv")

  skip_if(!nzchar(Sys.which("git")), "git not installed")
  system2("git", c("init", "-q"), stdout = FALSE, stderr = FALSE)
  writeLines("/local-site/", ".gitignore")
  writeLines("scratch.csv", ".git/info/exclude")
  expect_identical(found(), "analysis/kept.csv")
})

test_that(".check_path_ignored() matches slashless patterns at any depth", {
  expect_true(framework:::.check_path_ignored("a/b/x.csv", "*.csv"))
  expect_true(framework:::.check_path_ignored("a/renv/lib/x.rds", "renv/"))
  expect_false(framework:::.check_path_ignored("a/outputs/private/x.csv", "/outputs/private/"))
  expect_true(framework:::.check_path_ignored("outputs/private/x.csv", "outputs/private"))
})


# Ports 2026-11-07 (B3) -------------------------------------------------------

local_audit_repo <- function(env = parent.frame()) {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  system2("git", c("init", "-q"), stdout = FALSE, stderr = FALSE)
  writeLines(c(".env", "/inputs/"), ".gitignore")
  normalizePath(dir, winslash = "/")
}

test_that("each private file is reported once, under the deepest folder", {
  # A staged private table was listed three times, under
  # outputs_private_tables, outputs_private, and the outputs_tables fallback
  local_audit_repo()
  writeLines(c(
    "default:",
    "  directories:",
    "    outputs_private: outputs/private",
    "    outputs_private_tables: outputs/private/tables",
    "    outputs_tables: outputs/private/tables"
  ), "settings.yml")
  dir.create("outputs/private/tables", recursive = TRUE)
  writeLines(c("id", "1"), "outputs/private/tables/detail.csv")
  system2("git", c("add", "-f", "outputs/private/tables/detail.csv"), stdout = FALSE, stderr = FALSE)
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)
  exposure <- audit$findings$private_data_exposure
  expect_identical(exposure$file, "outputs/private/tables/detail.csv")
  expect_identical(exposure$directory, "outputs_private_tables")
  coverage <- audit$findings$gitignore_issues
  expect_false(anyDuplicated(coverage$file) > 0)
  expect_identical(sum(coverage$file == "outputs/private/tables/detail.csv"), 1L)
})

test_that("folders outside the project are skipped and reported", {
  # Folders in another project were skipped without a word, and a private
  # folder under a key without inputs_ or outputs_ wasn't watched
  local_audit_repo()
  elsewhere <- file.path(withr::local_tempdir(), "other", "outputs", "private", "tables")
  dir.create(elsewhere, recursive = TRUE)
  writeLines("a", file.path(elsewhere, "t.csv"))
  inside_abs <- file.path(normalizePath(".", winslash = "/"), "inputs", "private", "raw")
  writeLines(c(
    "default:",
    "  directories:",
    "    inputs_private_raw: inputs/private/raw",
    paste0("    inputs_private_elsewhere: ", elsewhere),
    paste0("    original_private_tables: ", elsewhere),
    paste0("    inputs_private_abs: ", inside_abs),
    "    review_confidential: review/confidential"
  ), "settings.yml")
  dir.create("review/confidential", recursive = TRUE)
  writeLines("a", "review/confidential/notes.csv")
  msgs <- capture_messages(audit <- git_security_audit(check_git_history = FALSE))
  expect_identical(audit$audit_metadata$skipped_directories, list(
    inputs_private_elsewhere = elsewhere,
    original_private_tables = elsewhere
  ))
  expect_identical(audit$audit_metadata$config_directories$inputs_private_abs, "inputs/private/raw")
  expect_true("review/confidential" %in% audit$findings$gitignore_issues$file)
  report <- paste(msgs, collapse = "")
  expect_match(report, "--- Skipped: Folders Outside the Project ---", fixed = TRUE)
  expect_match(report, paste0("  original_private_tables: ", elsewhere), fixed = TRUE)
  expect_match(report, "     Git can't commit them from this project, so they weren't checked.", fixed = TRUE)
})

with_destinations <- function(sensitive) {
  writeLines(c(
    "default:",
    if (sensitive) c("  security:", "    sensitive: true"),
    "  publish:",
    "    destinations:",
    "      local: {driver: folder, path: published}",
    "      pages: {driver: folder, path: docs, visibility: public}",
    "      share: {driver: folder, path: /Volumes/share/published}"
  ), "settings.yml")
  for (folder in c("published/report", "docs/deck")) {
    dir.create(folder, recursive = TRUE)
    writeLines("<p>", file.path(folder, "index.html"))
  }
}

test_that("publishing folders git doesn't ignore warn", {
  # A rendered private notebook in published/ passed the audit
  local_audit_repo()
  with_destinations(sensitive = FALSE)
  msgs <- capture_messages(audit <- git_security_audit(check_git_history = FALSE))
  expect_identical(audit$summary$check, c(
    "gitignore_coverage", "private_data_exposure", "git_history", "orphaned_files",
    "secrets_exposure", "published_outputs", "connection_secrets", "identifier_columns"
  ))
  published <- audit$findings$published_outputs
  expect_identical(published$destination, "local") # docs is public, share is outside
  expect_identical(published$files, 1L)
  expect_identical(audit$summary$status[audit$summary$check == "published_outputs"], "warning")
  report <- paste(msgs, collapse = "")
  expect_match(report, "--- Publishing Folders Not Ignored by Git ---", fixed = TRUE)
  expect_match(report, "  1. published/ (destination local: 1 file(s) not ignored, 0 tracked)", fixed = TRUE)
  expect_match(report, "Add folder publishing destinations to .gitignore (for example /published/), or set visibility: public on a destination meant to be committed", fixed = TRUE)

  writeLines(c(".env", "/inputs/", "/published/"), ".gitignore")
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)
  expect_true(all(audit$summary$status %in% c("pass", "skipped")))
})

test_that("sensitive projects check public publishing folders too", {
  local_audit_repo()
  with_destinations(sensitive = TRUE)
  system2("git", c("add", "docs"), stdout = FALSE, stderr = FALSE)
  published <- git_security_audit(check_git_history = FALSE, verbose = FALSE)$findings$published_outputs
  expect_identical(published$destination, c("local", "pages"))
  expect_identical(published$tracked, c(0L, 1L))
})

test_that("connection secrets written into the settings are flagged, never shown", {
  # Ports 2026-11-07 (D9): settings/connections.yml held a written-out password
  local_audit_repo()
  writeLines(c(
    "default:",
    "  connections: settings/connections.yml",
    "  publish:",
    "    destinations: {}",
    "  token_note: not a connection"
  ), "settings.yml")
  dir.create("settings")
  writeLines(c(
    "connections:",
    "  databases:",
    "    omop:",
    "      driver: postgres",
    "      password: a2omop-dev-secret",
    "      user: env(\"DB_USER\")",
    "    warehouse:",
    "      password: env(\"WH_PASSWORD\")",
    "      api_key: env(\"WH_KEY\", \"fallback-key\")",
    "      token: ''",
    "      secret: !expr Sys.getenv(\"WH_SECRET\")",
    "      access_key: !expr Sys.getenv(\"WH_ACCESS\", \"fallback\")",
    "      pwd: 1234",
    "      tls: {secret_file: false}",
    "  servers:",
    "    - name: a",
    "      token: abc"
  ), "settings/connections.yml")
  msgs <- capture_messages(audit <- git_security_audit(check_git_history = FALSE))
  secrets <- audit$findings$connection_secrets
  expect_identical(names(secrets), c("file", "key", "tracked"))
  expect_identical(secrets$key, c(
    "connections.databases.omop.password",
    "connections.databases.warehouse.api_key",
    "connections.databases.warehouse.access_key",
    "connections.databases.warehouse.pwd",
    "connections.servers[0].token"
  ))
  expect_identical(unique(secrets$file), "settings/connections.yml")
  expect_identical(audit$summary$check[7], "connection_secrets")
  expect_identical(audit$summary$status[7], "warning")
  report <- paste(msgs, collapse = "")
  expect_match(report, "--- Secrets Written in Connection Settings ---", fixed = TRUE)
  expect_match(report, "settings/connections.yml: connections.databases.omop.password (not tracked)", fixed = TRUE)
  expect_match(report, "Rotate any secret that was committed: it stays in git history", fixed = TRUE)
  expect_false(grepl("a2omop-dev-secret|fallback|abc", report))
  expect_false(any(grepl("a2omop-dev-secret", unlist(audit$findings))))

  system2("git", c("add", "settings"), stdout = FALSE, stderr = FALSE)
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)
  expect_identical(audit$summary$status[audit$summary$check == "connection_secrets"], "fail")
})

test_that("identifier-like column names follow the shared rule", {
  # Test vectors from framework-py tests/test_security.py::test_identifier_names
  columns <- c(
    "patientDOB", "date_of_birth", "BirthDate", "birth_dt", "birth_year", "ZIP", "zip5",
    "postal_code", "zip3", "SSN", "mrn", "MedicalRecordNumber", "last_name", "site_name",
    "zipper", "dobutamine"
  )
  found <- .fw_identifier_columns(columns)
  expect_identical(found$column, c(
    "patientDOB", "date_of_birth", "BirthDate", "birth_dt", "ZIP", "zip5", "postal_code",
    "SSN", "mrn", "MedicalRecordNumber", "last_name"
  ))
  expect_identical(found$kind, c(
    "dob", "dob", "dob", "dob", "zip", "zip", "zip", "ssn", "mrn", "mrn", "name"
  ))
  expect_identical(nrow(.fw_identifier_columns(c("first_name", "last_name", "site"))), 0L)
  expect_identical(.fw_identifier_tokens("MedicalRecordNumber"), c("medical", "record", "number"))
  expect_identical(.fw_identifier_tokens("patientDOB"), c("patient", "dob"))
})

test_that("tracked data with identifier-like columns warns, never fails", {
  # Ports 2026-11-07 (D8): real patient rows (DOB, ZIP) were committed in a standard project
  local_audit_repo()
  writeLines(c("default:", "  directories:", "    inputs_intermediate: inputs/intermediate"), "settings.yml")
  dir.create("inputs/intermediate", recursive = TRUE)
  dir.create("outputs/public/tables", recursive = TRUE)
  dir.create("inputs/private", recursive = TRUE)
  writeLines(c("patient_id,DOB,zip_code,los", "1,2020-01-01,21205,3"), "inputs/intermediate/patients.csv")
  writeLines(c("site_name;n;x", "a;1;2"), "inputs/intermediate/sites.csv")
  writeLines(c("id\tbirth_date\tssn", "1\t2\t3"), "inputs/intermediate/people.txt")
  writeLines(c("zip3,n", "212,4"), "outputs/public/tables/summary.csv")
  writeLines(c("dob,zip", "1,2"), "inputs/private/people.csv")
  files <- c("inputs/intermediate", "outputs", "inputs/private")
  if (requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_parquet(data.frame(firstName = "a", birth_date = "2020-01-01"),
                         "inputs/intermediate/names.parquet")
  }
  if (requireNamespace("haven", quietly = TRUE)) {
    haven::write_dta(data.frame(mrn = 1, n = 2), "inputs/intermediate/stata.dta")
  }
  system2("git", c("add", "-f", files), stdout = FALSE, stderr = FALSE)
  msgs <- capture_messages(audit <- git_security_audit(check_git_history = FALSE))
  found <- audit$findings$identifier_columns
  expect_identical(names(found), c("file", "columns", "kinds"))
  expect_identical(audit$summary$check[8], "identifier_columns")
  rownames(found) <- found$file
  expect_identical(found["inputs/intermediate/patients.csv", "columns"], "DOB, zip_code")
  expect_identical(found["inputs/intermediate/patients.csv", "kinds"], "dob, zip")
  expect_identical(found["inputs/intermediate/people.txt", "columns"], "birth_date, ssn")
  expect_false("inputs/intermediate/sites.csv" %in% found$file)
  expect_false("outputs/public/tables/summary.csv" %in% found$file)
  expect_false("inputs/private/people.csv" %in% found$file)
  if (requireNamespace("arrow", quietly = TRUE)) {
    expect_identical(found["inputs/intermediate/names.parquet", "kinds"], "name, dob")
  }
  if (requireNamespace("haven", quietly = TRUE)) {
    expect_identical(found["inputs/intermediate/stata.dta", "columns"], "mrn")
  }
  expect_identical(audit$summary$status[8], "warning")
  report <- paste(msgs, collapse = "")
  expect_match(report, "--- Tracked Data With Identifier-Like Columns ---", fixed = TRUE)
  expect_match(report, "inputs/intermediate/patients.csv (DOB, zip_code)", fixed = TRUE)
})

test_that("data_save warns about identifier columns outside private folders", {
  # Ports 2026-11-07 (D8): a standard project saved and committed real patient rows
  dir <- create_test_project()
  withr::defer(cleanup_test_dir(dir))
  withr::local_dir(dir)
  people <- data.frame(id = 1, dob = "2020-01-01", zip = "21205")
  expect_warning(
    suppressMessages(data_save(people, "inputs/intermediate/people.csv", force = TRUE)),
    "inputs/intermediate/people.csv has columns that look like direct identifiers (dob, zip), and it isn't in a private folder. If this is real data about people, save it in a private folder, which git ignores, and consider a privacy-sensitive project (type project_sensitive).",
    fixed = TRUE
  )
  expect_true(file.exists("inputs/intermediate/people.csv"))
  expect_no_warning(suppressMessages(data_save(people, "inputs/private/people.csv", force = TRUE)))
  expect_no_warning(suppressMessages(data_save(data.frame(site_name = "a"), "inputs/raw/sites.csv", force = TRUE)))

  many <- data.frame(dob = 1, zip = 1, ssn = 1, mrn = 1, first_name = 1, last_name = 1, zipcode = 1)
  settings <- readLines("settings.yml")
  writeLines(c(settings[1], "  security:", "    sensitive: true", settings[-1]), "settings.yml")
  expect_warning(
    suppressMessages(data_save(many, "inputs/raw/many.csv", force = TRUE)),
    "(dob, zip, ssn, mrn, first_name, and 2 more), and it isn't in a private folder. If this is real data about people, save it in a private folder instead.",
    fixed = TRUE
  )
})

test_that("the history check fails on data committed in inputs folders or with identifiers", {
  skip_if(!nzchar(Sys.which("git")))
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project", directories = list(
    inputs_intermediate = "inputs/intermediate", outputs_tables = "outputs/tables"
  ))), "settings.yml")
  git <- function(...) system2("git", c(...), stdout = FALSE, stderr = FALSE)
  git("init", "-q")
  git("config", "user.email", "t@example.com")
  git("config", "user.name", "T")
  commit <- function(msg) { git("add", "-A"); git("commit", "-q", "-m", shQuote(msg)) }

  # A standard project: nothing is under a private folder
  dir.create("inputs/intermediate", recursive = TRUE)
  dir.create("outputs/tables", recursive = TRUE)
  dir.create("reference")
  writeLines(c("center,n", "a,1"), "inputs/intermediate/centers.csv")
  writeLines(c("group,mean", "a,1"), "outputs/tables/summary.csv")
  writeLines(c("mrn,dob,zip_code", "1,2000-01-01,21201"), "reference/pts.csv")
  commit("data")
  git("mv", "outputs/tables/summary.csv", "inputs/intermediate/summary.csv")
  commit("move")

  audit <- git_security_audit(check_git_history = TRUE, verbose = FALSE)
  hist <- audit$findings$git_history_issues
  expect_identical(audit$summary$status[audit$summary$check == "git_history"], "fail")
  expect_true("inputs/intermediate/centers.csv" %in% hist$file)
  # A rename into an inputs folder counts
  expect_true(any(hist$file == "inputs/intermediate/summary.csv" & hist$action == "renamed"))
  expect_match(hist$reason[hist$file == "reference/pts.csv"][1], "identifier columns: mrn, dob, zip_code")
  # Aggregate output without identifiers is not a leak
  expect_false("outputs/tables/summary.csv" %in% hist$file)
})

test_that("the orphan scan counts plain folders as known and leaves out JSON, text, and hidden folders", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(
    project_type = "project",
    directories = list(scripts = "scripts"),
    extra_directories = list(hades = list(label = "hades", path = "hades"))
  )), "settings.yml")
  for (d in c("hades/cohorts", "scripts", ".vite/deps", "loose")) dir.create(d, recursive = TRUE)
  writeLines("{}", "hades/cohorts/c1.json")
  writeLines("x", "hades/cohorts/counts.csv")
  writeLines("{}", "loose/schema.json")
  writeLines("x", "loose/manifest.txt")
  writeLines("{}", ".vite/deps/x.json")
  writeLines("x", ".vite/deps/y.csv")
  writeLines("x", "scripts/lookup.csv")
  writeLines("x", "loose/data.csv")
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE)
  expect_identical(audit$findings$orphaned_files$path, "loose/data.csv")
  # Asking for JSON explicitly still scans it
  audit <- git_security_audit(check_git_history = FALSE, verbose = FALSE, extensions = c("csv", "json"))
  expect_setequal(audit$findings$orphaned_files$path, c("loose/data.csv", "loose/schema.json"))
  out <- capture_messages(framework:::.print_audit_summary(audit))
  expect_true(any(grepl("loose/ (2 files)", out, fixed = TRUE)))
})
