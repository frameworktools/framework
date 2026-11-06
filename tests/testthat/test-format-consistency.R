# Behaviors the Python package matches (see framework-py's R fixtures).

test_that("environment sections replace sequences whole and merge maps", {
  base <- list(
    tags = c("alpha", "beta"),
    hooks = list(list(name = "a"), list(name = "b")),
    db = list(host = "localhost", port = 5432L),
    drop_me = "x"
  )
  override <- list(
    tags = "gamma",
    hooks = list(list(name = "prod")),
    db = list(host = "db.example.edu"),
    drop_me = NULL
  )
  merged <- framework:::.fw_merge_env(base, override)
  expect_identical(merged$tags, "gamma")
  expect_identical(merged$hooks, list(list(name = "prod")))
  expect_identical(merged$db, list(host = "db.example.edu", port = 5432L))
  expect_false("drop_me" %in% names(merged))
})

test_that("settings_read() applies a production override of a sequence of mappings", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  writeLines(c(
    "default:",
    "  hooks:",
    "    - name: a",
    "    - name: b",
    "production:",
    "  hooks:",
    "    - name: prod"
  ), "settings.yml")
  withr::local_envvar(R_CONFIG_ACTIVE = "production")
  expect_identical(settings_read()$hooks, list(list(name = "prod")))
})

test_that("settings_write(section =) finds split files from the settings file's folder", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "settings"))
  dir.create(file.path(dir, "notebooks"))
  yaml::write_yaml(list(default = list(git = "settings/git.yml")), file.path(dir, "settings.yml"))
  yaml::write_yaml(list(git = list(use_git = FALSE)), file.path(dir, "settings", "git.yml"))
  withr::local_dir(file.path(dir, "notebooks"))

  settings_write(list(git = list(use_git = TRUE)), settings_file = file.path(dir, "settings.yml"), section = "git")
  expect_true(yaml::read_yaml(file.path(dir, "settings", "git.yml"))$git$use_git)
})

test_that("data_list() includes name: path shorthand entries", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(data = list(
    inputs = list(raw = list(
      visits = "inputs/raw/visits.tsv",
      survey = list(path = "inputs/raw/survey.csv", type = "csv")
    ))
  ))), "settings.yml")
  entries <- suppressMessages(data_list())
  expect_setequal(entries$name, c("inputs.raw.visits", "inputs.raw.survey"))
  expect_identical(entries$path[entries$name == "inputs.raw.visits"], "inputs/raw/visits.tsv")
  expect_true("inputs.raw.visits" %in% framework:::.get_data_path_suggestions())
})

test_that("results timestamps are epoch seconds, and older text rows still read", {
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  init <- system.file("templates", "init.sql", package = "framework")
  sql <- strsplit(paste(readLines(init, warn = FALSE), collapse = "\n"), ";")[[1]]
  for (statement in sql[nzchar(trimws(sql))]) DBI::dbExecute(con, statement)
  DBI::dbExecute(con, "INSERT INTO results (name, type, public, blind, comment, hash, created_at, updated_at) VALUES ('old', 'table', 0, 0, '', 'h', '2024-01-02 03:04:05', '2024-01-02 03:04:05')")
  DBI::dbDisconnect(con)

  suppressMessages(save_table(data.frame(x = 1), "new_table"))

  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  stored <- DBI::dbGetQuery(con, "SELECT typeof(created_at) AS t FROM results WHERE name = 'outputs/tables/new_table.csv'")
  expect_identical(stored$t, "real")

  listed <- result_list()
  expect_identical(listed$name, c("outputs/tables/new_table.csv", "old"))
  expect_identical(listed$created_at[listed$name == "old"], "2024-01-02 03:04:05")
  expect_false(anyNA(listed$updated_at))
  expect_identical(result_list(type = "table")$name, c("outputs/tables/new_table.csv", "old"))
})

test_that("new() writes a .gitignore and never commits .env", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  parent <- withr::local_tempdir()
  location <- file.path(parent, "smoke")
  suppressMessages(new(name = "Smoke Study", location = location, type = "project", browse = FALSE))

  expect_true(file.exists(file.path(location, ".gitignore")))
  expect_true(file.exists(file.path(location, ".env")))
  tracked <- system2("git", c("-C", location, "ls-files"), stdout = TRUE)
  expect_false(".env" %in% tracked)
  expect_true(".gitignore" %in% tracked)
})

test_that("the safety net adds .env to a .gitignore that misses it", {
  dir <- withr::local_tempdir()
  writeLines("*.csv", file.path(dir, ".gitignore"))
  expect_true(suppressMessages(framework:::.ensure_secrets_ignored(dir)))
  expect_true(".env" %in% readLines(file.path(dir, ".gitignore")))
  expect_false(framework:::.ensure_secrets_ignored(dir))

  dir2 <- withr::local_tempdir()
  suppressMessages(framework:::.ensure_secrets_ignored(dir2))
  expect_true(".env" %in% readLines(file.path(dir2, ".gitignore")))
})

test_that("git_security_audit() fails when .env is tracked", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines("FW_PROJECT_TOKEN=fw_secret", ".env")
  writeLines("FW_PROJECT_TOKEN=", ".env.example")
  system2("git", c("init", "-q"))
  system2("git", c("add", "-f", ".env", ".env.example", "settings.yml"))

  result <- suppressMessages(git_security_audit(check_git_history = FALSE, verbose = FALSE))
  row <- result$summary[result$summary$check == "secrets_exposure", ]
  expect_identical(row$status, "fail")
  expect_identical(result$findings$secrets_exposure$file, ".env")
  expect_match(result$recommendations, "Rotate", all = FALSE)
})

test_that("a later !.env line cannot re-include .env", {
  dir <- withr::local_tempdir()
  writeLines(c(".env", "*.csv", "!.env"), file.path(dir, ".gitignore"))
  expect_true(suppressMessages(framework:::.ensure_secrets_ignored(dir)))
  expect_identical(utils::tail(readLines(file.path(dir, ".gitignore")), 1), ".env")

  skip_if(!nzchar(Sys.which("git")), "git not installed")
  writeLines("SECRET=1", file.path(dir, ".env"))
  system2("git", c("-C", dir, "init", "-q"))
  expect_true(framework:::.secrets_ignored_by_git(dir))
  writeLines(c(".env", "!.env"), file.path(dir, ".gitignore"))
  expect_false(framework:::.secrets_ignored_by_git(dir))
})

test_that("project creation does not commit .env when .gitignore content negates it", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  parent <- withr::local_tempdir()
  location <- file.path(parent, "negated")
  suppressMessages(project_create(
    name = "Negated", location = location, type = "project",
    git = list(use_git = TRUE, hooks = list(), gitignore_content = ".env\n!.env")
  ))
  tracked <- system2("git", c("-C", location, "ls-files"), stdout = TRUE)
  expect_false(".env" %in% tracked)
})

test_that("projects from a spec can connect to their framework database", {
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  parent <- withr::local_tempdir()
  location <- file.path(parent, "connected")
  spec <- spec_resolve(list(list(type = "project", git = list(use_git = FALSE))), name = "Connected")
  suppressMessages(project_create(spec, location))
  expect_true("connections" %in% names(yaml::read_yaml(file.path(location, "settings", "connections.yml"))))

  withr::local_dir(location)
  config <- settings_read()
  expect_identical(config$connections$databases$framework$driver, "sqlite")
  con <- db_connect("framework")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  expect_true(DBI::dbIsValid(con))
})

test_that("settings_read() repairs connections written without a wrapper", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("settings")
  yaml::write_yaml(list(default = list(connections = "settings/connections.yml")), "settings.yml")
  yaml::write_yaml(list(
    default_database = "framework",
    databases = list(framework = list(driver = "sqlite", database = "framework.db")),
    storage_buckets = setNames(list(), character())
  ), "settings/connections.yml")
  config <- settings_read()
  expect_identical(config$connections$default_database, "framework")
  expect_identical(config$connections$databases$framework$driver, "sqlite")
  expect_null(config$databases)
})
