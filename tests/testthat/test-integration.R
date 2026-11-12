# Integration tests against the real servers in tests/integration/compose.yml.
# Each test goes through a project's settings.yml, as users do. They never run
# on CRAN and skip when a server is not running, unless
# FW_TEST_REQUIRE_SERVERS=1 (set in CI).

local_db_project <- function(name, server, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  connection <- server[c("driver", "host", "port", "database", "user", "password")]
  yaml::write_yaml(
    list(default = list(
      project_type = "project",
      connections = list(databases = stats::setNames(list(connection), name))
    )),
    file.path(dir, "settings.yml")
  )
  withr::local_dir(dir, .local_envir = env)
  dir
}

check_database_roundtrip <- function(name, create_sql) {
  table <- paste0("fw_it_", format(Sys.time(), "%H%M%S"), sample.int(1e5, 1))
  conn <- db_connect(name)
  on.exit({
    try(DBI::dbExecute(conn, sprintf("DROP TABLE %s", table)), silent = TRUE)
    DBI::dbDisconnect(conn)
  }, add = TRUE)

  expect_true(DBI::dbIsValid(conn))
  expect_equal(db_query("SELECT 1 AS one", name)$one, 1)

  # The seeded users table from tests/integration/*/init.sql
  users <- db_query("SELECT name FROM users WHERE deleted_at IS NULL ORDER BY name", name)
  expect_true("Alice" %in% users$name)

  db_execute(sprintf(create_sql, table), name)
  db_execute(sprintf("INSERT INTO %s (id, label) VALUES (1, 'first')", table), name)
  expect_equal(db_query(sprintf("SELECT COUNT(*) AS n FROM %s", table), name)$n, 1)

  # Commit on success
  db_transaction(conn, {
    DBI::dbExecute(conn, sprintf("INSERT INTO %s (id, label) VALUES (2, 'second')", table))
  })
  expect_equal(DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", table))$n, 2)

  # Roll back on error
  expect_error(db_transaction(conn, {
    DBI::dbExecute(conn, sprintf("INSERT INTO %s (id, label) VALUES (3, 'third')", table))
    stop("boom")
  }), "boom")
  expect_equal(DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", table))$n, 2)

  # db_with() opens and closes its own connection
  n <- db_with(name, DBI::dbGetQuery(conn, sprintf("SELECT COUNT(*) AS n FROM %s", table))$n)
  expect_equal(n, 2)
}

# db_execute_file() runs a file and rolls it back when a statement fails. SQL
# Server runs a file as GO batches; a file without GO is one batch, so a
# failing statement there follows one that already ran in the same batch.
check_execute_file <- function(name, one_batch = FALSE) {
  table <- paste0("fw_it_file_", format(Sys.time(), "%H%M%S"), sample.int(1e5, 1))
  on.exit(try(db_execute(sprintf("DROP TABLE %s", table), name), silent = TRUE), add = TRUE)
  dir.create("sql", showWarnings = FALSE)
  total <- if (one_batch) 1L else 2L

  writeLines(c(
    sprintf("CREATE TABLE %s (id INTEGER, label VARCHAR(50));", table),
    sprintf("INSERT INTO %s (id, label) VALUES (1, 'a; b');", table)
  ), "sql/load.sql")
  expect_equal(db_execute_file(name, "sql/load.sql"), total)
  expect_equal(db_query(sprintf("SELECT label FROM %s", table), name)$label, "a; b")

  writeLines(c(
    sprintf("INSERT INTO %s (id, label) VALUES (2, 'dropped');", table),
    sprintf("INSERT INTO %s_nowhere (id) VALUES (1);", table)
  ), "sql/broken.sql")
  expect_error(
    db_execute_file(name, "sql/broken.sql"),
    sprintf("Statement %d of %d in broken.sql .*rolled back", total, total)
  )
  expect_equal(db_query(sprintf("SELECT COUNT(*) AS n FROM %s", table), name)$n, 1)
}

test_that("PostgreSQL works end to end through settings.yml", {
  skip_if_not_installed("RPostgres")
  server <- skip_if_no_test_server("postgres")
  local_db_project("warehouse", server)
  check_database_roundtrip("warehouse", "CREATE TABLE %s (id INTEGER PRIMARY KEY, label TEXT)")
  check_execute_file("warehouse")
})

test_that("SQL Server works end to end through settings.yml", {
  skip_if_not_installed("odbc")
  server <- skip_if_no_test_server("sqlserver")
  if (!any(grepl("SQL Server", odbc::odbcListDrivers()$name))) {
    msg <- "Microsoft ODBC Driver for SQL Server not installed"
    if (nzchar(Sys.getenv("FW_TEST_REQUIRE_SERVERS", ""))) fail(msg)
    skip(msg)
  }
  local_db_project("mssql_db", server)
  # On macOS, Microsoft's driver loads OpenSSL from Homebrew's opt/openssl,
  # which is OpenSSL 4 on current Homebrew, and the driver needs 1.x or 3.
  # That is a machine problem, not a Framework one; Linux CI runs this test.
  probe <- tryCatch({ DBI::dbDisconnect(db_connect("mssql_db")); NULL }, error = conditionMessage)
  if (!is.null(probe) && grepl("OpenSSL library could not be loaded", probe)) {
    msg <- "ODBC Driver 18 cannot load OpenSSL 3 on this machine"
    if (nzchar(Sys.getenv("FW_TEST_REQUIRE_SERVERS", ""))) fail(msg)
    skip(msg)
  }
  check_database_roundtrip("mssql_db", "CREATE TABLE %s (id INT PRIMARY KEY, label NVARCHAR(100))")
  check_execute_file("mssql_db", one_batch = TRUE)
})

test_that("MySQL works end to end through settings.yml", {
  skip_if_not_installed("RMariaDB")
  server <- skip_if_no_test_server("mysql")
  local_db_project("mysql_db", server)
  check_database_roundtrip("mysql_db", "CREATE TABLE %s (id INT PRIMARY KEY, label VARCHAR(100))")
  check_execute_file("mysql_db")
})

test_that("MariaDB works end to end through settings.yml", {
  skip_if_not_installed("RMariaDB")
  server <- skip_if_no_test_server("mariadb")
  local_db_project("maria_db", server)
  check_database_roundtrip("maria_db", "CREATE TABLE %s (id INT PRIMARY KEY, label VARCHAR(100))")
  check_execute_file("maria_db")
})

test_that("S3 storage_test() and publish() work against a real S3 server", {
  skip_if_not_installed("aws.s3")
  server <- skip_if_no_test_server("s3")
  bucket <- "framework-it"
  endpoint <- sub("^https?://", "", server$endpoint)
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = server$access_key,
    AWS_SECRET_ACCESS_KEY = server$secret_key
  )
  if (!isTRUE(suppressMessages(suppressWarnings(
    aws.s3::bucket_exists(bucket, base_url = endpoint, region = "", use_https = FALSE)
  )))) {
    aws.s3::put_bucket(bucket, base_url = endpoint, region = "", use_https = FALSE)
  }

  dir <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(
    project_type = "project",
    connections = list(
      storage_buckets = list(results = list(
        bucket = bucket,
        endpoint = server$endpoint,
        access_key = server$access_key,
        secret_key = server$secret_key,
        region = "us-east-1"
      )),
      default_storage_bucket = "results"
    )
  )), file.path(dir, "settings.yml"))
  withr::local_dir(dir)

  expect_true(suppressMessages(storage_test("results")))

  writeLines("<p>integration</p>", "report.html")
  key <- paste0("it/", format(Sys.time(), "%H%M%S"), "/report.html")
  suppressMessages(publish("report.html", dest = key, connection = "results"))
  body <- aws.s3::get_object(key, bucket = bucket, base_url = endpoint, region = "", use_https = FALSE)
  expect_match(rawToChar(body), "integration")
  aws.s3::delete_object(key, bucket = bucket, base_url = endpoint, region = "", use_https = FALSE)
})
