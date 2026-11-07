#' Execute code within a database transaction
#'
#' Wraps code execution in a database transaction with automatic
#' commit on success and rollback on error. This ensures atomicity
#' of multiple database operations.
#'
#' @param conn Database connection
#' @param code Expression or code block to execute within the transaction
#'
#' @return The result of the code expression
#'
#' @details
#' The function automatically:
#' - Begins a transaction with `DBI::dbBegin()`
#' - Executes the provided code
#' - Commits the transaction on success with `DBI::dbCommit()`
#' - Rolls back the transaction on error with `DBI::dbRollback()`
#'
#' Transactions are essential for maintaining data integrity when performing
#' multiple related operations. If any operation fails, all changes are rolled back.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' conn <- db_connect("postgres")
#'
#' # Basic transaction
#' db_transaction(conn, {
#'   DBI::dbExecute(conn, "INSERT INTO users (name, age) VALUES ('Alice', 30)")
#'   DBI::dbExecute(conn, "INSERT INTO users (name, age) VALUES ('Bob', 25)")
#' })
#'
#' # Transaction with error handling - auto-rollback on error
#' tryCatch({
#'   db_transaction(conn, {
#'     DBI::dbExecute(conn, "INSERT INTO users (name) VALUES ('Alice')")
#'     stop("Something went wrong")  # This will trigger rollback
#'   })
#' }, error = function(e) {
#'   message("Transaction failed: ", e$message)
#' })
#'
#' DBI::dbDisconnect(conn)
#' }
#' }
#'
#' @export
db_transaction <- function(conn, code) {
  # Validate arguments
  checkmate::assert_class(conn, "DBIConnection")
  if (.fw_connection_read_only(conn)) {
    stop("This connection is read-only (read_only: true in its settings). ",
         "db_transaction() needs a writable connection.", call. = FALSE)
  }

  # Check if already in a transaction
  in_transaction <- tryCatch({
    DBI::dbGetInfo(conn)$transaction
  }, error = function(e) {
    # Some drivers don't support transaction status check
    FALSE
  })

  if (isTRUE(in_transaction)) {
    # Already inside a transaction - reuse outer transaction context
    return(force(code))
  }

  started_transaction <- TRUE
  begin_error <- tryCatch({
    DBI::dbBegin(conn)
    NULL
  }, error = function(e) {
    if (grepl("cannot start a transaction", e$message, ignore.case = TRUE)) {
      started_transaction <<- FALSE
      return(NULL)
    }
    e
  })

  if (!is.null(begin_error)) {
    stop(sprintf("Failed to begin transaction: %s", begin_error$message))
  }

  if (!started_transaction) {
    return(force(code))
  }

  # Execute code with rollback on error
  tryCatch({
    # Force evaluation of code
    result <- force(code)

    # Commit transaction on success
    DBI::dbCommit(conn)

    result
  }, error = function(e) {
    # Rollback transaction on error
    tryCatch({
      DBI::dbRollback(conn)
    }, error = function(rollback_error) {
      warning(sprintf("Failed to rollback transaction: %s", rollback_error$message))
    })

    stop(sprintf("Transaction failed and was rolled back: %s", e$message), call. = FALSE)
  })
}


#' Execute code with transaction if not already in one
#'
#' Similar to `db_transaction()`, but only starts a new transaction
#' if not already in one. Useful for functions that can be called both
#' standalone and within an existing transaction.
#'
#' @param conn Database connection
#' @param code Expression or code block to execute
#'
#' @return The result of the code expression
#'
#' @keywords internal
connection_with_transaction <- function(conn, code) {
  # Validate arguments
  checkmate::assert_class(conn, "DBIConnection")

  # Check if already in a transaction
  in_transaction <- tryCatch({
    DBI::dbGetInfo(conn)$transaction
  }, error = function(e) {
    FALSE
  })

  if (isTRUE(in_transaction)) {
    # Already in transaction, just execute code
    force(code)
  } else {
    # Not in transaction, create one
    db_transaction(conn, code)
  }
}

#' Begin a database transaction
#'
#' Manually begin a database transaction. You must call `connection_commit()`
#' to save changes or `connection_rollback()` to discard them.
#'
#' **Note:** Using `db_transaction()` is preferred as it automatically
#' handles commit/rollback.
#'
#' @param conn Database connection
#'
#' @return NULL (invisible)
#'
#' @keywords internal
connection_begin <- function(conn) {
  checkmate::assert_class(conn, "DBIConnection")

  tryCatch({
    DBI::dbBegin(conn)
  }, error = function(e) {
    stop(sprintf("Failed to begin transaction: %s", e$message))
  })

  invisible(NULL)
}

#' Commit a database transaction
#'
#' Commits the current transaction, making all changes permanent.
#'
#' @param conn Database connection
#'
#' @return NULL (invisible)
#'
#' @keywords internal
connection_commit <- function(conn) {
  checkmate::assert_class(conn, "DBIConnection")

  tryCatch({
    DBI::dbCommit(conn)
  }, error = function(e) {
    stop(sprintf("Failed to commit transaction: %s", e$message))
  })

  invisible(NULL)
}

#' Rollback a database transaction
#'
#' Rolls back the current transaction, discarding all changes.
#'
#' @param conn Database connection
#'
#' @return NULL (invisible)
#'
#' @keywords internal
connection_rollback <- function(conn) {
  checkmate::assert_class(conn, "DBIConnection")

  tryCatch({
    DBI::dbRollback(conn)
  }, error = function(e) {
    stop(sprintf("Failed to rollback transaction: %s", e$message))
  })

  invisible(NULL)
}
