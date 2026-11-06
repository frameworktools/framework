#' Execute code with a managed database connection
#'
#' Provides automatic connection lifecycle management. The connection is
#' automatically closed when the code block finishes, even if an error occurs.
#' This prevents connection leaks and ensures proper resource cleanup.
#'
#' @param connection_name Character. Name of the connection in settings.yml
#' @param code Expression to evaluate with the connection (use `conn` to access the connection)
#'
#' @return The result of evaluating `code`
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Safe - connection auto-closes
#' users <- db_with("my_db", {
#'   DBI::dbGetQuery(conn, "SELECT * FROM users WHERE active = TRUE")
#' })
#'
#' # Multiple operations with same connection
#' result <- db_with("my_db", {
#'   DBI::dbExecute(conn, "INSERT INTO users (name) VALUES ('Alice')")
#'   DBI::dbGetQuery(conn, "SELECT * FROM users")
#' })
#'
#' # Connection closes even on error
#' tryCatch(
#'   db_with("my_db", {
#'     stop("Something went wrong")  # Connection still closes
#'   }),
#'   error = function(e) message(e$message)
#' )
#' }
#' }
#'
#' @export
db_with <- function(connection_name, code) {
  checkmate::assert_string(connection_name, min.chars = 1)

  # Get connection
  conn <- db_connect(connection_name)

  # Ensure cleanup even on error
  on.exit({
    # Handle DuckDB special case (needs shutdown = TRUE)
    if (inherits(conn, "duckdb_connection")) {
      DBI::dbDisconnect(conn, shutdown = TRUE)
    } else {
      DBI::dbDisconnect(conn)
    }
  }, add = TRUE)

  # Make connection available in code block
  # Use parent.frame() so 'conn' is accessible
  eval(substitute(code), envir = list(conn = conn), enclos = parent.frame())
}


#' Check for leaked database connections
#'
#' Scans the global environment and parent frames for open database connections.
#' Useful for debugging connection leaks in interactive sessions or long-running
#' scripts.
#'
#' @param warn Logical. If TRUE (default), emits a warning if leaked connections found
#'
#' @return A data frame with information about open connections:
#'   - object_name: Name of the variable holding the connection
#'   - class: Connection class (e.g., "PqConnection", "SQLiteConnection")
#'   - valid: Whether connection is still valid
#'
#' @keywords internal
connection_check_leaks <- function(warn = TRUE) {
  checkmate::assert_flag(warn)

  # Get all objects in global environment
  env_objs <- ls(envir = .GlobalEnv)

  leaks <- list()

  for (obj_name in env_objs) {
    obj <- get(obj_name, envir = .GlobalEnv)

    # Check if it's a DBI connection
    if (inherits(obj, "DBIConnection")) {
      # Check if connection is still valid
      is_valid <- tryCatch(
        DBI::dbIsValid(obj),
        error = function(e) FALSE
      )

      leaks[[length(leaks) + 1]] <- data.frame(
        object_name = obj_name,
        class = class(obj)[1],
        valid = is_valid,
        stringsAsFactors = FALSE
      )
    }
  }

  result <- if (length(leaks) > 0) {
    do.call(rbind, leaks)
  } else {
    data.frame(
      object_name = character(0),
      class = character(0),
      valid = logical(0),
      stringsAsFactors = FALSE
    )
  }

  # Warn if leaks found
  if (warn && nrow(result) > 0) {
    valid_count <- sum(result$valid)
    if (valid_count > 0) {
      warning(sprintf(
        "Found %d open database connection%s in global environment:\n  %s\n\nConsider using connection_with() or closing with DBI::dbDisconnect()",
        valid_count,
        if (valid_count == 1) "" else "s",
        paste(result$object_name[result$valid], collapse = ", ")
      ), call. = FALSE)
    }
  }

  invisible(result)
}

#' Close all open database connections
#'
#' Safely closes all open database connections in the global environment.
#' Useful for cleaning up after interactive sessions or when resetting state.
#'
#' @param force Logical. If TRUE, closes even invalid connections. Default: FALSE
#' @param quiet Logical. If TRUE, suppresses messages. Default: FALSE
#'
#' @return Invisibly returns the number of connections closed
#'
#' @keywords internal
connection_close_all <- function(force = FALSE, quiet = FALSE) {
  checkmate::assert_flag(force)
  checkmate::assert_flag(quiet)

  leaks <- connection_check_leaks(warn = FALSE)

  if (nrow(leaks) == 0) {
    if (!quiet) {
      message("No open connections found")
    }
    return(invisible(0))
  }

  closed_count <- 0

  for (i in seq_len(nrow(leaks))) {
    obj_name <- leaks$object_name[i]
    is_valid <- leaks$valid[i]

    # Skip invalid connections unless force = TRUE
    if (!is_valid && !force) {
      if (!quiet) {
        message(sprintf("Skipping invalid connection: %s", obj_name))
      }
      next
    }

    obj <- get(obj_name, envir = .GlobalEnv)

    tryCatch({
      # Handle DuckDB special case
      if (inherits(obj, "duckdb_connection")) {
        DBI::dbDisconnect(obj, shutdown = TRUE)
      } else {
        DBI::dbDisconnect(obj)
      }

      if (!quiet) {
        message(sprintf("Closed connection: %s (%s)", obj_name, leaks$class[i]))
      }

      closed_count <- closed_count + 1
    }, error = function(e) {
      if (!quiet) {
        warning(sprintf("Failed to close connection '%s': %s", obj_name, e$message), call. = FALSE)
      }
    })
  }

  if (!quiet && closed_count > 0) {
    message(sprintf("\nClosed %d connection%s", closed_count, if (closed_count == 1) "" else "s"))
  }

  invisible(closed_count)
}
