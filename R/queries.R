#' Get data from a database query
#'
#' Gets data from a database using a query and connection name. The connection
#' is created, used, and automatically closed.
#'
#' @param query SQL query to execute
#' @param connection_name Name of the connection in settings.yml
#' @param ... Additional arguments passed to DBI::dbGetQuery
#' @param read_only Open the connection read-only (`TRUE`) or writable
#'   (`FALSE`) for this query, as [db_connect()] does. Default (`NULL`): the
#'   connection's setting. A read-only DuckDB file can be open in several
#'   processes at once, so `read_only = TRUE` lets a notebook query a database
#'   another job holds open read-only too.
#' @return A data frame with the query results
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' users <- db_query("SELECT * FROM users", "my_db")
#' }
#' }
#'
#' @export
db_query <- function(query, connection_name, ..., read_only = NULL) {
  # Validate arguments
  checkmate::assert_string(query, min.chars = 1)
  checkmate::assert_string(connection_name, min.chars = 1)

  con <- db_connect(connection_name, read_only = read_only)
  on.exit(DBI::dbDisconnect(con))

  tryCatch(
    DBI::dbGetQuery(con, query, ...),
    error = function(e) {
      stop(sprintf("Failed to execute query on connection '%s': %s", connection_name, e$message))
    }
  )
}


#' Execute a database statement
#'
#' Executes a SQL statement on a database without returning results. The connection
#' is created, used, and automatically closed.
#'
#' @param query SQL statement to execute
#' @param connection_name Name of the connection in settings.yml
#' @param ... Additional arguments passed to DBI::dbExecute
#' @return Number of rows affected
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' rows <- db_execute("DELETE FROM cache WHERE expired = TRUE", "my_db")
#' }
#' }
#'
#' @export
db_execute <- function(query, connection_name, ...) {
  # Validate arguments
  checkmate::assert_string(query, min.chars = 1)
  checkmate::assert_string(connection_name, min.chars = 1)

  con <- db_connect(connection_name)
  on.exit(DBI::dbDisconnect(con))
  if (.fw_connection_read_only(con)) {
    stop(sprintf(
      "Connection '%s' is read-only (read_only: true in its settings). db_execute() can't change it.",
      connection_name
    ), call. = FALSE)
  }

  tryCatch(
    DBI::dbExecute(con, query, ...),
    error = function(e) {
      stop(sprintf("Failed to execute statement on connection '%s': %s", connection_name, e$message))
    }
  )
}


#' Find a record by ID
#'
#' Finds a single record in a table by its ID. Supports soft-delete patterns
#' where records have a deleted_at column.
#'
#' @param conn Database connection
#' @param table_name Name of the table to query
#' @param id The ID to look up (integer or string)
#' @param with_trashed Whether to include soft-deleted records (default: FALSE).
#'   Only applies if deleted_at column exists in the table.
#'
#' @return A data frame with the record, or empty data frame if not found
#'
#' @keywords internal
connection_find <- function(conn, table_name, id, with_trashed = FALSE) {
  # Validate arguments
  checkmate::assert_class(conn, "DBIConnection")
  checkmate::assert_string(table_name, min.chars = 1)
  checkmate::assert(
    checkmate::check_integerish(id, len = 1),
    checkmate::check_string(id)
  )
  checkmate::assert_flag(with_trashed)

  # Check if deleted_at column exists in the table (cross-database)
  has_deleted_at <- .has_column(conn, table_name, "deleted_at")

  # Build query with appropriate parameter placeholder
  # PostgreSQL uses $1, most others use ?
  placeholder <- if (inherits(conn, "PqConnection")) "$1" else "?"

  query <- sprintf("SELECT * FROM %s WHERE id = %s",
                   DBI::dbQuoteIdentifier(conn, table_name),
                   placeholder)

  if (!with_trashed && has_deleted_at) {
    query <- paste0(query, " AND deleted_at IS NULL")
  }

  query <- paste0(query, " LIMIT 1")

  # Execute query
  tryCatch(
    DBI::dbGetQuery(conn, query, params = list(id)),
    error = function(e) {
      stop(sprintf("Failed to query table '%s': %s", table_name, e$message))
    }
  )
}



