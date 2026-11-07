# db_execute_file() and db_copy_from(), and splitting SQL files into
# statements. Shared with framework-py (framework/_sql.py and connections.py).

# A driver's SQL dialect: postgres, mysql, sqlserver, sqlite, duckdb, or the
# driver name itself
#' @keywords internal
.fw_sql_dialect <- function(driver) {
  driver <- tolower(as.character(driver %||% ""))
  switch(driver,
    postgresql = "postgres",
    mariadb = "mysql",
    mssql = "sqlserver",
    driver
  )
}

# The dialect of an open connection: the driver db_connect() opened it with,
# else its class
#' @keywords internal
.fw_connection_dialect <- function(con) {
  driver <- attr(con, "framework_driver", exact = TRUE)
  if (!is.null(driver)) {
    return(driver)
  }
  if (inherits(con, "SQLiteConnection")) return("sqlite")
  if (inherits(con, "duckdb_connection")) return("duckdb")
  if (inherits(con, c("PqConnection", "PostgreSQLConnection", "RedshiftConnection"))) return("postgres")
  if (inherits(con, c("MariaDBConnection", "MySQLConnection"))) return("mysql")
  if (inherits(con, "Microsoft SQL Server")) return("sqlserver")
  "generic"
}

# The statements (or SQL Server batches) in a SQL file's text: a list of
# list(sql, line), line being where the statement's first word is
#' @keywords internal
.fw_sql_split <- function(text, driver) {
  text <- sub("^\ufeff", "", enc2utf8(text))
  # Byte positions throughout: character positions in a long UTF-8 string
  # cost a scan from its start each
  Encoding(text) <- "bytes"
  driver <- .fw_sql_dialect(driver)
  spans <- if (driver == "sqlserver") {
    .fw_sql_spans_go(text)
  } else if (driver == "sqlite") {
    .fw_sql_spans_sqlite(text)
  } else {
    .fw_sql_spans_generic(text, driver)
  }
  statements <- .fw_sql_statements(text, spans$start, spans$end)
  Filter(function(s) !.fw_sql_is_empty(s$sql, driver), statements)
}

# Every regex match in text, as a data frame of start, length, and text
#' @keywords internal
.fw_sql_tokens <- function(text, pattern) {
  if (!nzchar(text)) {
    return(data.frame(start = integer(), length = integer(), text = character()))
  }
  found <- gregexpr(pattern, text, perl = TRUE, useBytes = TRUE)[[1]]
  data.frame(
    start = as.integer(found),
    length = attr(found, "match.length"),
    text = regmatches(text, list(found))[[1]],
    stringsAsFactors = FALSE
  )
}

# Spans between ";" outside quotes, comments, and PostgreSQL dollar quotes.
# MySQL also has "#" comments and backslash escapes in quotes.
#' @keywords internal
.fw_sql_spans_generic <- function(text, driver) {
  mysql <- driver == "mysql"
  quoted <- function(q) {
    if (mysql) sprintf("%s(?:\\\\[\\s\\S]|[^%s\\\\]+|%s%s)*+%s?", q, q, q, q, q)
    else sprintf("%s(?:[^%s]+|%s%s)*+%s?", q, q, q, q, q)
  }
  pattern <- paste(c(
    "--[^\\n]*",
    if (mysql) "#[^\\n]*",
    "/\\*[\\s\\S]*?(?:\\*/|\\z)",
    quoted("'"), quoted("\""), quoted("`"),
    if (driver == "postgres") "\\$([A-Za-z_][A-Za-z0-9_]*|)\\$[\\s\\S]*?(?:\\$\\1\\$|\\z)",
    ";",
    "[^;'\"`$/#-]+",
    "[\\s\\S]"
  ), collapse = "|")
  tokens <- .fw_sql_tokens(text, pattern)
  semis <- tokens$start[tokens$text == ";"]
  .fw_sql_spans_at(text, semis)
}

# Spans ending at the given ";" positions, and the rest of the text
#' @keywords internal
.fw_sql_spans_at <- function(text, semis) {
  n <- nchar(text, type = "bytes")
  data.frame(start = c(1L, semis + 1L), end = c(semis, n))
}

# SQLite's sqlite3_complete() rule (complete.c), as Python's
# sqlite3.complete_statement() applies it: ";"-ended pieces accumulate until
# they form a complete statement, so CREATE TRIGGER ... BEGIN ... END; stays
# one statement. One pass over the tokens finds the same ends: a statement is
# complete when a ";" leaves the state machine in its START state.
#' @keywords internal
.fw_sql_spans_sqlite <- function(text) {
  pattern <- paste(c(
    "/\\*[\\s\\S]*?\\*/", "/\\*[\\s\\S]*",
    "--[^\\n]*",
    "\\[[^\\]]*\\]", "\\[[^\\]]*",
    "`[^`]*`", "`[^`]*",
    "\"[^\"]*\"", "\"[^\"]*",
    "'[^']*'", "'[^']*",
    "[ \\t\\n\\r\\f]+",
    ";",
    "(?:[A-Za-z0-9_$]|[^\\x00-\\x7F])+",
    "[\\s\\S]"
  ), collapse = "|")
  tokens <- .fw_sql_tokens(text, pattern)
  # Tokens: SEMI, WS, OTHER, EXPLAIN, CREATE, TEMP, TRIGGER, END (columns 1-8)
  # States: INVALID, START, NORMAL, EXPLAIN, CREATE, TRIGGER, SEMI, END (rows 1-8)
  trans <- matrix(c(
    1, 0, 2, 3, 4, 2, 2, 2,
    1, 1, 2, 3, 4, 2, 2, 2,
    1, 2, 2, 2, 2, 2, 2, 2,
    1, 3, 3, 2, 4, 2, 2, 2,
    1, 4, 2, 2, 2, 4, 5, 2,
    6, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 5, 5, 5, 5, 5, 7,
    1, 7, 5, 5, 5, 5, 5, 5
  ), nrow = 8, byrow = TRUE)
  keywords <- c(explain = 4L, create = 5L, temp = 6L, temporary = 6L, trigger = 7L, end = 8L)
  state <- 0L
  complete <- logical(nrow(tokens))
  texts <- tokens$text
  for (i in seq_along(texts)) {
    token <- texts[i]
    size <- nchar(token, type = "bytes")
    first <- substr(token, 1, 1)
    two <- substr(token, 1, 2)
    kind <- if (token == ";") {
      1L
    } else if (two == "/*") {
      if (size < 4 || substr(token, size - 1, size) != "*/") break
      2L
    } else if (two == "--" || first %in% c(" ", "\t", "\n", "\r", "\f")) {
      2L
    } else if (first %in% c("[", "`", "\"", "'")) {
      close <- if (first == "[") "]" else first
      if (size < 2 || substr(token, size, size) != close) break
      3L
    } else {
      keyword <- if (size >= 3 && size <= 9 && grepl("^[A-Za-z]+$", token, useBytes = TRUE)) {
        keywords[tolower(token)]
      } else {
        NA
      }
      if (is.na(keyword)) 3L else keyword
    }
    state <- as.integer(trans[state + 1L, kind])
    if (kind == 1L && state == 1L) {
      complete[i] <- TRUE
    }
  }
  .fw_sql_spans_at(text, tokens$start[complete])
}

# SQL Server batches: split at lines holding only GO (case-insensitive,
# optionally followed by a -- comment), as sqlcmd and SSMS do
#' @keywords internal
.fw_sql_spans_go <- function(text) {
  found <- gregexpr("(?im)^[ \\t]*GO[ \\t]*(?:--[^\\n]*)?$", text, perl = TRUE, useBytes = TRUE)[[1]]
  n <- nchar(text, type = "bytes")
  if (found[1] == -1) {
    return(data.frame(start = 1L, end = n))
  }
  starts <- as.integer(found)
  ends <- starts + attr(found, "match.length")
  data.frame(start = c(1L, ends), end = c(starts - 1L, n))
}

# The statements in text[start..end], with the line of each one's first
# word (after any leading comments)
#' @keywords internal
.fw_sql_statements <- function(text, starts, ends) {
  chunks <- substring(text, starts, ends)
  leading <- regexpr("^(?:\\s+|--[^\\n]*|/\\*[\\s\\S]*?\\*/)*", chunks, perl = TRUE, useBytes = TRUE)
  skipped <- pmax(attr(leading, "match.length"), 0L)
  newlines <- gregexpr("\n", text, fixed = TRUE, useBytes = TRUE)[[1]]
  newlines <- if (newlines[1] == -1) integer() else as.integer(newlines)
  lines <- findInterval(starts - 1L + skipped, newlines) + 1L
  Encoding(chunks) <- "UTF-8"
  sql <- trimws(chunks, whitespace = "[\\s]")
  lapply(seq_along(chunks), function(i) list(sql = sql[i], line = as.integer(lines[i])))
}

# Whether a statement holds only comments (and semicolons)
#' @keywords internal
.fw_sql_is_empty <- function(sql, driver) {
  text <- gsub("--[^\\n]*|/\\*[\\s\\S]*?\\*/", "", sql, perl = TRUE)
  if (driver == "mysql") {
    text <- gsub("#[^\\n]*", "", text, perl = TRUE)
  }
  text <- trimws(text, whitespace = "[\\s]")
  text <- gsub("^;+|;+$", "", text)
  !nzchar(trimws(text, whitespace = "[\\s]"))
}

# A SQL or CSV file by path: relative to the project root, then the working
# directory
#' @keywords internal
.fw_db_file <- function(path) {
  checkmate::assert_string(path, min.chars = 1)
  found <- .fw_existing_file(path.expand(path))
  if (is.null(found)) {
    stop(sprintf("File not found: %s", path), call. = FALSE)
  }
  found
}

# A file's text as UTF-8, without a byte-order mark, with \n line endings
#' @keywords internal
.fw_read_text_utf8 <- function(path) {
  bytes <- readBin(path, "raw", n = file.size(path))
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  text <- sub("^\ufeff", "", text)
  gsub("\r\n?", "\n", text)
}

# A connection, or a connection name opened for the call. Returns
# list(con, name, close).
#' @keywords internal
.fw_open_db <- function(conn) {
  if (inherits(conn, "DBIConnection")) {
    name <- attr(conn, "framework_name", exact = TRUE)
    return(list(con = conn, name = name, close = FALSE))
  }
  if (!is.character(conn) || length(conn) != 1 || !nzchar(conn)) {
    stop("conn must be a connection from db_connect() or a connection name.", call. = FALSE)
  }
  list(con = db_connect(conn), name = conn, close = TRUE)
}

#' Run every statement in a SQL file
#'
#' Runs the statements in a `.sql` file in order, by default in one
#' transaction, so a failure leaves the database as it was.
#'
#' Statements end at a `;` outside single quotes (`''` escapes one), double
#' quotes, backticks, `--` and `/* */` comments, and PostgreSQL dollar quotes
#' (`$$` or `$tag$`). MySQL files also have `#` comments and backslash
#' escapes. SQLite files are split with SQLite's own rule, so a trigger's
#' `BEGIN ... END;` body stays whole. SQL Server files are split into batches
#' at lines holding only `GO`, as sqlcmd does, and each batch runs whole.
#' Statements holding only comments are dropped. MySQL's client-side
#' `DELIMITER` command is not supported.
#'
#' @param conn An open connection from [db_connect()], or a connection name,
#'   which is opened for the file and closed afterward.
#' @param path The `.sql` file. A relative path is looked for from the
#'   project root, then from the working directory. It is read as UTF-8; a
#'   byte-order mark is dropped.
#' @param transaction Run the whole file in one transaction (default). MySQL
#'   commits schema changes (CREATE, ALTER, DROP) at once whatever the client
#'   does. Pass `FALSE` for statements that cannot run in a transaction, such
#'   as PostgreSQL's `CREATE INDEX CONCURRENTLY` or `VACUUM`; each statement
#'   then commits as it runs.
#'
#' @return The number of statements (or SQL Server batches) run.
#'
#' @details A failed statement stops the file with an error naming its
#'   number and line. The connection must be writable: not opened with
#'   `read_only = TRUE` and without `read_only: true` in its settings.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' db_execute_file("warehouse", "sql/schema.sql")
#'
#' conn <- db_connect("analysis")
#' db_execute_file(conn, "sql/build.sql")
#' DBI::dbDisconnect(conn)
#' }
#' }
#'
#' @seealso [db_copy_from()], [db_transaction()]
#' @export
db_execute_file <- function(conn, path, transaction = TRUE) {
  checkmate::assert_flag(transaction)
  source <- .fw_db_file(path)
  opened <- .fw_open_db(conn)
  con <- opened$con
  if (opened$close) on.exit(DBI::dbDisconnect(con), add = TRUE)
  .fw_require_writable(con, opened$name, "db_execute_file()")

  statements <- .fw_sql_split(.fw_read_text_utf8(source), .fw_connection_dialect(con))
  total <- length(statements)
  failure <- NULL
  run_all <- function() {
    for (number in seq_along(statements)) {
      statement <- statements[[number]]
      tryCatch(
        DBI::dbExecute(con, statement$sql),
        error = function(e) {
          failure <<- sprintf(
            "Statement %d of %d in %s (line %d) failed: %s",
            number, total, basename(source), statement$line, conditionMessage(e)
          )
          stop(failure, call. = FALSE)
        }
      )
    }
  }

  if (transaction) {
    tryCatch(db_transaction(con, run_all()), error = function(e) {
      if (is.null(failure)) stop(e)
      stop(paste(failure, "The file was rolled back."), call. = FALSE)
    })
  } else {
    run_all()
  }
  total
}

#' Load a CSV file into an existing table
#'
#' Loads a CSV file into a table, fast where the driver allows. The CSV's
#' header names the columns, which must exist in the table; other columns
#' get their defaults. Values go to the database as text (or `NULL` for the
#' values in `na`), and the database converts them to the columns' types.
#' Nothing is trimmed.
#'
#' PostgreSQL loads with `COPY ... FROM STDIN` (`DBI::dbWriteTable(copy =
#' TRUE)`), DuckDB inserts each chunk with one `INSERT ... SELECT` from a
#' registered data frame, and SQLite, MySQL, and SQL Server use
#' [DBI::dbAppendTable()]. The file is read in chunks of 50,000 rows, so a
#' large file does not need to fit in memory.
#'
#' @param conn An open connection from [db_connect()], or a connection name,
#'   which is opened for the load and closed afterward.
#' @param table The table, optionally with its schema (`"cdm.concept"`). Each
#'   part is quoted for the driver, so names keep their case.
#' @param csv The CSV file. A relative path is looked for from the project
#'   root, then from the working directory.
#' @param delim The delimiter: "comma", "tab", "semicolon", or "space".
#' @param na Values loaded as `NULL`. Default: empty fields and `NA`, as
#'   [data_read()] reads them.
#'
#' @return The number of rows loaded.
#'
#' @details The whole load runs in one transaction, so a failure loads
#'   nothing. The connection must be writable, as for [db_execute_file()].
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' db_execute_file("warehouse", "sql/schema.sql")
#' db_copy_from("warehouse", "cdm.concept", "inputs/raw/CONCEPT.csv", delim = "tab")
#' }
#' }
#'
#' @seealso [db_execute_file()]
#' @export
db_copy_from <- function(conn, table, csv, delim = "comma", na = c("", "NA")) {
  checkmate::assert_string(table, min.chars = 1)
  checkmate::assert_character(na, any.missing = FALSE)
  separators <- c(comma = ",", tab = "\t", semicolon = ";", space = " ")
  if (!is.character(delim) || length(delim) != 1 || !delim %in% names(separators)) {
    stop(sprintf("Unknown delimiter: %s. Use comma, tab, semicolon, or space", format(delim)), call. = FALSE)
  }
  source <- .fw_db_file(csv)
  opened <- .fw_open_db(conn)
  con <- opened$con
  if (opened$close) on.exit(DBI::dbDisconnect(con), add = TRUE)
  .fw_require_writable(con, opened$name, "db_copy_from()")
  driver <- .fw_connection_dialect(con)

  parts <- strsplit(table, ".", fixed = TRUE)[[1]]
  target <- switch(as.character(length(parts)),
    "1" = DBI::Id(table = parts[1]),
    "2" = DBI::Id(schema = parts[1], table = parts[2]),
    DBI::Id(catalog = parts[1], schema = parts[2], table = paste(parts[-(1:2)], collapse = "."))
  )

  loaded <- 0L
  failure <- NULL
  load_chunk <- function(chunk, position) {
    chunk <- as.data.frame(chunk, stringsAsFactors = FALSE)
    if (nrow(chunk) == 0) return(invisible(NULL))
    tryCatch(
      .fw_load_rows(con, driver, target, chunk),
      error = function(e) {
        failure <<- conditionMessage(e)
        stop(failure, call. = FALSE)
      }
    )
    loaded <<- loaded + nrow(chunk)
    invisible(NULL)
  }

  tryCatch(
    db_transaction(con, {
      readr::read_delim_chunked(
        source,
        callback = readr::SideEffectChunkCallback$new(load_chunk),
        chunk_size = .fw_copy_chunk_rows(),
        delim = separators[[delim]],
        col_types = readr::cols(.default = readr::col_character()),
        na = na,
        trim_ws = FALSE,
        progress = FALSE
      )
    }),
    error = function(e) {
      message <- failure %||% sub("^Transaction failed and was rolled back: ", "", conditionMessage(e))
      stop(sprintf(
        "Failed to load %s into %s; nothing was loaded: %s", basename(source), table, message
      ), call. = FALSE)
    }
  )
  loaded
}

#' @keywords internal
.fw_copy_chunk_rows <- function() {
  getOption("framework.copy_chunk_rows", 50000L)
}

# One chunk of text columns into the target table
#' @keywords internal
.fw_load_rows <- function(con, driver, target, chunk) {
  if (driver == "postgres") {
    DBI::dbWriteTable(con, target, chunk, append = TRUE, copy = TRUE)
    return(invisible(NULL))
  }
  if (driver == "duckdb") {
    view <- "__framework_copy"
    duckdb::duckdb_register(con, view, chunk)
    on.exit(duckdb::duckdb_unregister(con, view), add = TRUE)
    names <- paste(DBI::dbQuoteIdentifier(con, names(chunk)), collapse = ", ")
    DBI::dbExecute(con, sprintf(
      "INSERT INTO %s (%s) SELECT %s FROM %s",
      DBI::dbQuoteIdentifier(con, target), names, names, DBI::dbQuoteIdentifier(con, view)
    ))
    return(invisible(NULL))
  }
  DBI::dbAppendTable(con, target, chunk)
  invisible(NULL)
}
