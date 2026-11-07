# db_execute_file(), db_copy_from(), and read_only per call

local_db_project <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  dir.create("data")
  dir.create("sql")
  yaml::write_yaml(list(default = list(
    project_type = "project",
    connections = list(databases = list(
      local = list(driver = "sqlite", database = "data/local.db"),
      duck = list(driver = "duckdb", database = "data/local.duckdb"),
      shared = list(driver = "duckdb", database = "data/local.duckdb", read_only = TRUE),
      warehouse = list(driver = "postgres", host = "db", port = 5432, database = "a",
                       user = "u", password = "p")
    ))
  )), "settings.yml")
  dir
}

DDL <- paste0(
  "-- The study schema\n",
  "CREATE TABLE person (\n",
  "  person_id INTEGER PRIMARY KEY,\n",
  "  note VARCHAR(50) DEFAULT 'a; b'  -- a ; inside a string\n",
  ");\n",
  "/* A block comment; with a semicolon */\n",
  "CREATE TABLE visit (visit_id INTEGER, person_id INTEGER, visit_date DATE);\n",
  "INSERT INTO person (person_id) VALUES (1);\n"
)

sql_split <- function(text, driver) framework:::.fw_sql_split(text, driver)
lines_of <- function(statements) vapply(statements, `[[`, 1L, "line")
sql_of <- function(statements) vapply(statements, `[[`, "", "sql")

test_that("splitting respects quotes, comments, and dollar quotes", {
  for (driver in c("postgres", "duckdb", "mysql", "sqlite")) {
    statements <- sql_split(DDL, driver)
    expect_equal(lines_of(statements), c(2L, 7L, 8L), info = driver)
    expect_true(endsWith(statements[[1]]$sql, "-- a ; inside a string\n);"), info = driver)
  }

  body <- "CREATE FUNCTION f() RETURNS int AS $body$ SELECT 1; $body$ LANGUAGE sql;\nSELECT 2;"
  expect_length(sql_split(body, "postgres"), 2)
  expect_length(sql_split("DO $$ BEGIN PERFORM 1; END $$;\nSELECT $1;", "postgresql"), 2)
  # Outside postgres, $ is an ordinary character
  expect_length(sql_split(body, "duckdb"), 3)
  expect_length(sql_split("SELECT 'it''s; fine'; SELECT \"a;b\" FROM t;", "duckdb"), 2)
  expect_length(sql_split("SELECT 'a\\'; b'; SELECT 1; # done;\n", "mysql"), 2)
  expect_length(sql_split("SELECT `a;b` FROM t; SELECT 1", "mariadb"), 2)
  # Outside mysql a backslash escapes nothing and # is no comment
  expect_length(sql_split("SELECT 'a\\'; SELECT 1;", "postgres"), 2)
  expect_length(sql_split("-- only a comment\n;\n", "postgres"), 0)
  expect_length(sql_split("", "postgres"), 0)
  # An unterminated quote runs to the end
  expect_equal(sql_of(sql_split("SELECT 1; SELECT 'a; b", "postgres")), c("SELECT 1;", "SELECT 'a; b"))
  # A byte-order mark is dropped; non-ASCII text keeps its positions
  statements <- sql_split("﻿SELECT 'café;';\nSELECT 2;", "duckdb")
  expect_equal(sql_of(statements), c("SELECT 'café;';", "SELECT 2;"))
  expect_equal(lines_of(statements), c(1L, 2L))
})

test_that("SQLite files split with sqlite3_complete()'s rule", {
  trigger <- paste0(
    "CREATE TABLE t (a INTEGER);\n",
    "CREATE TRIGGER tr AFTER INSERT ON t BEGIN UPDATE t SET a = 1; SELECT 1; END;\n",
    "INSERT INTO t VALUES (2);\n"
  )
  expect_equal(lines_of(sql_split(trigger, "sqlite")), c(1L, 2L, 3L))
  temp <- paste0(
    "create temporary trigger tr after insert on t begin\n",
    "  insert into log values ('end;'); -- end;\n",
    "  /* end; */ update t set a = [end;];\n",
    "end;\nexplain select 1;\nselect \"end\"; create table x(a);"
  )
  expect_equal(lines_of(sql_split(temp, "sqlite")), c(1L, 5L, 6L, 6L))
  # A trigger without END never completes; the rest is one statement
  expect_length(sql_split("CREATE TRIGGER tr BEGIN SELECT 1; SELECT 2;", "sqlite"), 1)
  # The same as SQLite's own check for each prefix (RSQLite runs it via
  # complete statements; here the known answers of sqlite3_complete())
  expect_length(sql_split("CREATE TABLE end_table (a); SELECT 1 /* ; ", "sqlite"), 2)
  expect_length(sql_split("SELECT ';", "sqlite"), 1)
})

test_that("SQL Server files split into GO batches", {
  batches <- paste0(
    "CREATE TABLE t (a INT);\nINSERT INTO t VALUES (1);\nGO\n",
    "CREATE VIEW v AS SELECT a FROM t\ngo -- end\n"
  )
  expect_equal(sql_of(sql_split(batches, "sqlserver")), c(
    "CREATE TABLE t (a INT);\nINSERT INTO t VALUES (1);",
    "CREATE VIEW v AS SELECT a FROM t"
  ))
  expect_equal(lines_of(sql_split(batches, "mssql")), c(1L, 4L))
  expect_length(sql_split("SELECT 1 -- GO\nGOTO x", "sqlserver"), 1)
})

for (name in c("local", "duck")) {
  test_that(sprintf("db_execute_file() runs every statement (%s)", name), {
    if (name == "duck") skip_if_not_installed("duckdb")
    local_db_project()
    writeLines(DDL, "sql/schema.sql", sep = "")
    expect_equal(db_execute_file(name, "sql/schema.sql"), 3L)
    rows <- db_query("SELECT person_id, note FROM person", name)
    expect_equal(rows$person_id, 1)
    expect_equal(rows$note, "a; b")

    writeLines("INSERT INTO person (person_id) VALUES (2);\n\nINSERT INTO nowhere VALUES (1);\n",
               "sql/broken.sql", sep = "")
    conn <- db_connect(name)
    expect_error(
      db_execute_file(conn, "sql/broken.sql"),
      "^Statement 2 of 2 in broken\\.sql \\(line 3\\) failed: .*nowhere.* The file was rolled back\\.$"
    )
    DBI::dbDisconnect(conn, shutdown = TRUE)
    # Rolled back: person 2 was not kept
    expect_equal(db_query("SELECT count(*) AS n FROM person", name)$n, 1)
  })
}

test_that("db_execute_file(transaction = FALSE) keeps earlier statements", {
  local_db_project()
  writeLines(c("CREATE TABLE a (x INTEGER);", "INSERT INTO a VALUES (1);", "INSERT INTO nowhere VALUES (1);"),
             "sql/steps.sql")
  expect_error(
    db_execute_file("local", "sql/steps.sql", transaction = FALSE),
    "^Statement 3 of 3 in steps\\.sql \\(line 3\\) failed: no such table: nowhere$"
  )
  expect_equal(db_query("SELECT x FROM a", "local")$x, 1)
  # A file from the project root, run from a subfolder, with CRLF line ends
  dir.create("notebooks")
  writeBin(charToRaw("INSERT INTO a VALUES (2);\r\nINSERT INTO a VALUES (3);\r\n"), "sql/crlf.sql")
  withr::with_dir("notebooks", expect_equal(db_execute_file("local", "sql/crlf.sql"), 2L))
})

test_that("db_execute_file() errors", {
  local_db_project()
  expect_error(db_execute_file("local", "sql/none.sql"), "File not found: sql/none.sql", fixed = TRUE)
  db_execute("CREATE TABLE t (a INTEGER)", "local")
  writeLines("DELETE FROM t;", "sql/x.sql")
  conn <- db_connect("local", read_only = TRUE)
  on.exit(DBI::dbDisconnect(conn))
  expect_error(
    db_execute_file(conn, "sql/x.sql"),
    "Connection 'local' is read-only. db_execute_file() needs a writable connection: db_connect('local', read_only = FALSE).",
    fixed = TRUE
  )
  expect_error(db_copy_from(conn, "t", "sql/x.sql"), "db_copy_from() needs a writable connection", fixed = TRUE)
})

CSV <- "person_id,name,visits,score\n1,Ann,3,2.5\n2,NA,,\n3,\"Lee, Jr.\",7,1\n"

for (name in c("local", "duck")) {
  test_that(sprintf("db_copy_from() loads a CSV (%s)", name), {
    if (name == "duck") skip_if_not_installed("duckdb")
    local_db_project()
    db_execute(paste(
      "CREATE TABLE people (person_id INTEGER, name VARCHAR(40), visits INTEGER,",
      "score DOUBLE PRECISION, source VARCHAR(10) DEFAULT 'csv')"
    ), name)
    writeLines(CSV, "data/people.csv", sep = "")
    expect_equal(db_copy_from(name, "people", "data/people.csv"), 3L)
    rows <- db_query("SELECT * FROM people ORDER BY person_id", name)
    expect_equal(rows$name, c("Ann", NA, "Lee, Jr."))
    expect_equal(is.na(rows$visits), c(FALSE, TRUE, FALSE))
    expect_equal(rows$score[1], 2.5)
    expect_equal(rows$source, rep("csv", 3))
    expect_equal(as.numeric(db_query("SELECT sum(visits) AS n FROM people", name)$n), 10)
  })
}

test_that("db_copy_from() loads nothing on failure", {
  local_db_project()
  withr::local_options(framework.copy_chunk_rows = 1L)
  db_execute("CREATE TABLE people (person_id INTEGER PRIMARY KEY, name TEXT)", "local")
  writeLines(c("person_id,name", "1,a", "2,b", "1,c"), "data/dupes.csv")
  expect_error(
    db_copy_from("local", "people", "data/dupes.csv"),
    "^Failed to load dupes\\.csv into people; nothing was loaded: .*UNIQUE"
  )
  expect_equal(db_query("SELECT count(*) AS n FROM people", "local")$n, 0)

  writeLines(c("person_id;name", "5;."), "data/semi.csv")
  expect_equal(db_copy_from("local", "people", "data/semi.csv", delim = "semicolon", na = "."), 1L)
  expect_true(is.na(db_query("SELECT name FROM people", "local")$name))
  expect_error(db_copy_from("local", "people", "data/semi.csv", delim = "pipe"),
               "Unknown delimiter: pipe. Use comma, tab, semicolon, or space", fixed = TRUE)
  # schema.table, quoted part by part
  writeLines(c("person_id;name", "6;."), "data/semi6.csv")
  expect_equal(db_copy_from("local", "main.people", "data/semi6.csv", delim = "semicolon", na = character()), 1L)
  expect_equal(db_query("SELECT name FROM people WHERE name = '.'", "local")$name, ".")
})

test_that("read_only per call", {
  skip_if_not_installed("duckdb")
  local_db_project()
  db_execute("CREATE TABLE t (a INTEGER)", "duck")
  # "shared" is read_only: true in the settings; a build step opens it writable
  expect_error(db_execute("INSERT INTO t VALUES (1)", "shared"), "read-only")
  conn <- db_connect("shared", read_only = FALSE)
  expect_false(framework:::.fw_connection_read_only(conn))
  DBI::dbExecute(conn, "INSERT INTO t VALUES (1)")
  DBI::dbDisconnect(conn, shutdown = TRUE)
  expect_equal(db_query("SELECT a FROM t", "shared")$a, 1)
  expect_equal(db_query("SELECT a FROM t", "duck", read_only = TRUE)$a, 1)
  conn <- db_connect("duck", read_only = TRUE)
  expect_true(framework:::.fw_connection_read_only(conn))
  DBI::dbDisconnect(conn, shutdown = TRUE)

  db_execute("CREATE TABLE t (a INTEGER)", "local")
  conn <- db_connect("local", read_only = TRUE)
  expect_true(framework:::.fw_connection_read_only(conn))
  DBI::dbDisconnect(conn)
  expect_error(
    db_connect("warehouse", read_only = TRUE),
    "read_only = TRUE applies to sqlite and duckdb files, and 'warehouse' is postgres. Connect as a database user without write access instead.",
    fixed = TRUE
  )
})
