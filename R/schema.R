#' Check if a column exists in a table (S3 generic)
#'
#' Cross-database method to check if a column exists in a table.
#' Uses database-specific introspection methods via S3 dispatch.
#'
#' @param conn Database connection (DBIConnection)
#' @param table_name Character. Name of the table
#' @param column_name Character. Name of the column to check
#'
#' @return Logical. TRUE if column exists, FALSE otherwise. The name must
#'   match exactly, including case.
#' @keywords internal
#' @export
#' @name dot-has_column
#' 
#' @examples
#' \donttest{
#' if (FALSE) {
#' conn <- db_connect("my_db")
#' has_deleted_at <- .has_column(conn, "users", "deleted_at")
#' DBI::dbDisconnect(conn)
#' }
#' }
.has_column <- function(conn, table_name, column_name) {
  UseMethod(".has_column")
}

#' @describeIn dot-has_column SQLite implementation using PRAGMA
#' @keywords internal
#' @export
#' @export
.has_column.SQLiteConnection <- function(conn, table_name, column_name) {
  checkmate::assert_class(conn, "SQLiteConnection")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  tryCatch({
    table_info <- DBI::dbGetQuery(
      conn,
      sprintf("PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(conn, table_name))
    )
    column_name %in% table_info$name
  }, error = function(e) {
    warning(sprintf("Could not check column existence: %s", e$message))
    FALSE
  })
}

#' @describeIn dot-has_column PostgreSQL implementation using information_schema
#' @keywords internal
#' @export
.has_column.PqConnection <- function(conn, table_name, column_name) {
  checkmate::assert_class(conn, "PqConnection")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  tryCatch({
    # PostgreSQL information_schema query
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = $1 AND column_name = $2",
      params = list(tolower(table_name), tolower(column_name))
    )
    nrow(result) > 0
  }, error = function(e) {
    warning(sprintf("Could not check column existence: %s", e$message))
    FALSE
  })
}

#' @describeIn dot-has_column MySQL/MariaDB implementation using information_schema
#' @keywords internal
#' @export
.has_column.MariaDBConnection <- function(conn, table_name, column_name) {
  checkmate::assert_class(conn, "MariaDBConnection")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  tryCatch({
    # Get current database name
    db_name <- DBI::dbGetQuery(conn, "SELECT DATABASE() as db")$db

    # MySQL/MariaDB information_schema query
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_schema = ? AND table_name = ? AND column_name = ?",
      params = list(db_name, table_name, column_name)
    )
    nrow(result) > 0
  }, error = function(e) {
    warning(sprintf("Could not check column existence: %s", e$message))
    FALSE
  })
}

#' @describeIn dot-has_column SQL Server implementation using information_schema
#' @keywords internal
#' @export
`.has_column.Microsoft SQL Server` <- function(conn, table_name, column_name) {
  checkmate::assert_class(conn, "Microsoft SQL Server")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  tryCatch({
    # SQL Server information_schema query
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = ? AND column_name = ?",
      params = list(table_name, column_name)
    )
    nrow(result) > 0
  }, error = function(e) {
    warning(sprintf("Could not check column existence: %s", e$message))
    FALSE
  })
}

#' @describeIn dot-has_column DuckDB implementation using information_schema
#' @keywords internal
#' @export
.has_column.duckdb_connection <- function(conn, table_name, column_name) {
  checkmate::assert_class(conn, "duckdb_connection")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  tryCatch({
    # DuckDB information_schema query
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = ? AND column_name = ?",
      params = list(table_name, column_name)
    )
    nrow(result) > 0
  }, error = function(e) {
    warning(sprintf("Could not check column existence: %s", e$message))
    FALSE
  })
}

#' @describeIn dot-has_column Default implementation for unknown database types
#' @keywords internal
#' @export
.has_column.default <- function(conn, table_name, column_name) {
  checkmate::assert_class(conn, "DBIConnection")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert_string(column_name, min.chars = 1)

  tryCatch({
    # Generic INFORMATION_SCHEMA approach (SQL standard)
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = ? AND column_name = ?",
      params = list(table_name, column_name)
    )
    nrow(result) > 0
  }, error = function(e) {
    warning(sprintf("Could not check column existence: %s. Database type may not be supported.", e$message))
    FALSE
  })
}

#' List all tables in a database (S3 generic)
#'
#' Cross-database method to list all tables.
#' Uses database-specific methods via S3 dispatch.
#'
#' @param conn Database connection (DBIConnection)
#'
#' @return Character vector of table names
#' @keywords internal
#' @export
#' @name dot-list_tables
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' conn <- db_connect("my_db")
#' tables <- .list_tables(conn)
#' DBI::dbDisconnect(conn)
#' }
#' }
.list_tables <- function(conn) {
  UseMethod(".list_tables")
}

#' @describeIn dot-list_tables Default implementation using DBI::dbListTables
#' @keywords internal
#' @export
.list_tables.default <- function(conn) {
  checkmate::assert_class(conn, "DBIConnection")

  tryCatch({
    DBI::dbListTables(conn)
  }, error = function(e) {
    warning(sprintf("Could not list tables: %s", e$message))
    character(0)
  })
}

#' List all columns in a table (S3 generic)
#'
#' Cross-database method to list all columns in a table.
#' Uses database-specific introspection methods via S3 dispatch.
#'
#' @param conn Database connection (DBIConnection)
#' @param table_name Character. Name of the table
#'
#' @return Character vector of column names
#' @keywords internal
#' @export
#' @name dot-list_columns
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' conn <- db_connect("my_db")
#' columns <- .list_columns(conn, "users")
#' DBI::dbDisconnect(conn)
#' }
#' }
.list_columns <- function(conn, table_name) {
  UseMethod(".list_columns")
}

#' @describeIn dot-list_columns SQLite implementation using PRAGMA
#' @keywords internal
#' @export
.list_columns.SQLiteConnection <- function(conn, table_name) {
  checkmate::assert_class(conn, "SQLiteConnection")
  checkmate::assert_string(table_name, min.chars = 1)

  tryCatch({
    table_info <- DBI::dbGetQuery(
      conn,
      sprintf("PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(conn, table_name))
    )
    # A missing table gives a 0-row result whose name column is logical
    as.character(table_info$name)
  }, error = function(e) {
    warning(sprintf("Could not list columns: %s", e$message))
    character(0)
  })
}

#' @describeIn dot-list_columns PostgreSQL implementation using information_schema
#' @keywords internal
#' @export
.list_columns.PqConnection <- function(conn, table_name) {
  checkmate::assert_class(conn, "PqConnection")
  checkmate::assert_string(table_name, min.chars = 1)

  tryCatch({
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = $1
       ORDER BY ordinal_position",
      params = list(tolower(table_name))
    )
    result$column_name
  }, error = function(e) {
    warning(sprintf("Could not list columns: %s", e$message))
    character(0)
  })
}

#' @describeIn dot-list_columns MySQL/MariaDB implementation using information_schema
#' @keywords internal
#' @export
.list_columns.MariaDBConnection <- function(conn, table_name) {
  checkmate::assert_class(conn, "MariaDBConnection")
  checkmate::assert_string(table_name, min.chars = 1)

  tryCatch({
    db_name <- DBI::dbGetQuery(conn, "SELECT DATABASE() as db")$db

    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_schema = ? AND table_name = ?
       ORDER BY ordinal_position",
      params = list(db_name, table_name)
    )
    result$column_name
  }, error = function(e) {
    warning(sprintf("Could not list columns: %s", e$message))
    character(0)
  })
}

#' @describeIn dot-list_columns SQL Server implementation using information_schema
#' @keywords internal
#' @export
`.list_columns.Microsoft SQL Server` <- function(conn, table_name) {
  checkmate::assert_class(conn, "Microsoft SQL Server")
  checkmate::assert_string(table_name, min.chars = 1)

  tryCatch({
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = ?
       ORDER BY ordinal_position",
      params = list(table_name)
    )
    result$column_name
  }, error = function(e) {
    warning(sprintf("Could not list columns: %s", e$message))
    character(0)
  })
}

#' @describeIn dot-list_columns DuckDB implementation using information_schema
#' @keywords internal
#' @export
.list_columns.duckdb_connection <- function(conn, table_name) {
  checkmate::assert_class(conn, "duckdb_connection")
  checkmate::assert_string(table_name, min.chars = 1)

  tryCatch({
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = ?
       ORDER BY ordinal_position",
      params = list(table_name)
    )
    result$column_name
  }, error = function(e) {
    warning(sprintf("Could not list columns: %s", e$message))
    character(0)
  })
}

#' @describeIn dot-list_columns Default implementation using information_schema
#' @keywords internal
#' @export
.list_columns.default <- function(conn, table_name) {
  checkmate::assert_class(conn, "DBIConnection")
  checkmate::assert_string(table_name, min.chars = 1)

  tryCatch({
    # Try DBI::dbListFields first
    fields <- DBI::dbListFields(conn, table_name)
    if (length(fields) > 0) {
      return(fields)
    }

    # Fallback to information_schema
    result <- DBI::dbGetQuery(
      conn,
      "SELECT column_name
       FROM information_schema.columns
       WHERE table_name = ?
       ORDER BY ordinal_position",
      params = list(table_name)
    )
    result$column_name
  }, error = function(e) {
    warning(sprintf("Could not list columns: %s", e$message))
    character(0)
  })
}
