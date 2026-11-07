#' Connect to a SQLite database
#'
#' @param config Connection configuration from settings.yml
#' @return A SQLite database connection
#' @keywords internal
.connect_sqlite <- function(config) {
  if (is.null(config$database)) {
    stop("SQLite configuration must include 'database' path")
  }

  # Validate database path
  db_path <- normalizePath(config$database, mustWork = FALSE)
  db_dir <- dirname(db_path)

  if (!dir.exists(db_dir)) {
    stop(sprintf("Database directory does not exist: %s", db_dir))
  }

  # read_only: true opens the file with SQLITE_RO, so a file without write
  # permission (chmod 444) opens, and every write fails
  read_only <- isTRUE(config$read_only)
  if (read_only && !file.exists(db_path)) {
    stop(sprintf("Read-only database does not exist: %s", db_path))
  }
  if (!read_only && file.exists(db_path) && file.access(db_path, 2) != 0) {
    stop(sprintf(
      "No write permission for database: %s. Add read_only: true to the connection to open it read-only.",
      db_path
    ))
  }

  flags <- if (read_only) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC
  tryCatch(
    {
      DBI::dbConnect(RSQLite::SQLite(), db_path, flags = flags)
    },
    error = \(e) stop(sprintf("Failed to connect to SQLite database: %s", e$message))
  )
}

#' Whether a connection was opened read-only
#'
#' SQLite connections opened with `read_only: true` (SQLITE_RO) and DuckDB
#' connections opened with `read_only: true`.
#'
#' @param con A DBI connection
#' @return TRUE or FALSE
#' @keywords internal
.fw_connection_read_only <- function(con) {
  if (inherits(con, "SQLiteConnection")) {
    flags <- as.integer(con@flags)
    return(bitwAnd(flags, 1L) == 1L && bitwAnd(flags, 2L) == 0L)
  }
  if (inherits(con, "duckdb_connection")) {
    return(isTRUE(tryCatch(con@driver@read_only, error = function(e) FALSE)))
  }
  FALSE
}

#' Check if a SQLite database exists
#'
#' @param config Connection configuration from settings.yml
#' @return TRUE if database exists, FALSE otherwise
#' @keywords internal
.check_sqlite_exists <- function(config) {
  if (is.null(config$database)) {
    return(FALSE)
  }

  normalizePath(config$database, mustWork = FALSE) |>
    file.exists()
}

#' Create a new SQLite database
#'
#' @param config Connection configuration from settings.yml
#' @return TRUE if successful
#' @keywords internal
.create_sqlite_db <- function(config) {
  if (is.null(config$database)) {
    stop("SQLite configuration must include 'database' path")
  }

  db_path <- normalizePath(config$database, mustWork = FALSE)
  db_dir <- dirname(db_path)

  # Create directory if it doesn't exist
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE)
  }

  # Check if we can create the file
  if (file.exists(db_path) && file.access(db_path, 2) != 0) {
    stop(sprintf("No write permission for database: %s", db_path))
  }

  tryCatch(
    {
      DBI::dbConnect(RSQLite::SQLite(), db_path) |>
        (\(con) {
          DBI::dbDisconnect(con)
          TRUE
        })()
    },
    error = \(e) stop(sprintf("Failed to create SQLite database: %s", e$message))
  )
}
