# Helper alias for internal function used in tests
db_find <- framework:::connection_find

test_that("db_connect returns SQLite connection for framework database", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  conn <- db_connect("framework")

  expect_s4_class(conn, "SQLiteConnection")

  DBI::dbDisconnect(conn)
})

test_that("db_query executes SELECT query on connection", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Query framework database
  result <- db_query("SELECT name, type FROM sqlite_master WHERE type='table'", "framework")

  expect_s3_class(result, "data.frame")
  expect_true(nrow(result) > 0)
  expect_true("name" %in% names(result))
  expect_true("type" %in% names(result))
})

test_that("db_execute runs INSERT/UPDATE commands on connection", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a test table
  db_execute("CREATE TABLE test_table (id INTEGER, name TEXT)", "framework")

  # Insert data
  rows <- db_execute("INSERT INTO test_table (id, name) VALUES (1, 'test')", "framework")

  expect_equal(rows, 1)

  # Verify data was inserted
  result <- db_query("SELECT * FROM test_table", "framework")
  expect_equal(nrow(result), 1)
  expect_equal(result$name, "test")

  # Clean up
  db_execute("DROP TABLE test_table", "framework")
})

test_that("db_query handles empty result sets correctly", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create and query empty table
  db_execute("CREATE TABLE empty_table (id INTEGER)", "framework")

  result <- db_query("SELECT * FROM empty_table", "framework")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)

  # Clean up
  db_execute("DROP TABLE empty_table", "framework")
})

test_that("db_find retrieves record by ID", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create test table and insert data
  conn <- db_connect("framework")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "CREATE TABLE test_find (id INTEGER PRIMARY KEY, value TEXT)")
  DBI::dbExecute(conn, "INSERT INTO test_find (id, value) VALUES (1, 'first')")
  DBI::dbExecute(conn, "INSERT INTO test_find (id, value) VALUES (2, 'second')")

  # Find record
  result <- db_find(conn, "test_find", 2)

  expect_equal(nrow(result), 1)
  expect_equal(result$id, 2)
  expect_equal(result$value, "second")

  # Clean up
  DBI::dbExecute(conn, "DROP TABLE test_find")
})

test_that("db_find returns empty data frame for non-existent ID", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  conn <- db_connect("framework")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  DBI::dbExecute(conn, "CREATE TABLE test_missing (id INTEGER PRIMARY KEY, value TEXT)")

  result <- db_find(conn, "test_missing", 999)

  expect_equal(nrow(result), 0)

  # Clean up
  DBI::dbExecute(conn, "DROP TABLE test_missing")
})

test_that("db_connect fails for non-existent connection name", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  expect_error(db_connect("nonexistent_connection"))
})

test_that("read_only: true opens an unwritable SQLite file and refuses writes", {
  skip_on_os("windows")
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  con <- DBI::dbConnect(RSQLite::SQLite(), "study.sqlite")
  DBI::dbWriteTable(con, "people", data.frame(id = 1:3))
  DBI::dbDisconnect(con)
  Sys.chmod("study.sqlite", "444")
  withr::defer(Sys.chmod(file.path(dir, "study.sqlite"), "644"))
  skip_if(file.access("study.sqlite", 2) == 0, "running as a user who can write read-only files")
  yaml::write_yaml(list(default = list(connections = list(databases = list(
    study = list(driver = "sqlite", database = "study.sqlite", read_only = TRUE),
    writable = list(driver = "sqlite", database = "study.sqlite")
  )))), "settings.yml")

  expect_error(db_connect("writable"), "read_only: true")
  expect_identical(nrow(db_query("SELECT * FROM people", "study")), 3L)
  expect_error(db_execute("DELETE FROM people", "study"), "read-only")
  overridden <- "Connection 'study' is read-only in its settings; read_only = FALSE can't override that."
  expect_error(db_connect("study", read_only = FALSE), overridden, fixed = TRUE)
  expect_error(db_query("DELETE FROM people", "study", read_only = FALSE), overridden, fixed = TRUE)
  expect_error(db_with("study", DBI::dbExecute(conn, "DELETE FROM people")), "readonly")

  con <- db_connect("study")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  expect_true(framework:::.fw_connection_read_only(con))
  expect_error(db_transaction(con, DBI::dbExecute(con, "DELETE FROM people")), "read-only")
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT * FROM people")), 3L)
})

test_that("ordinary SQLite connections are not read-only", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con))
  expect_false(framework:::.fw_connection_read_only(con))
})
