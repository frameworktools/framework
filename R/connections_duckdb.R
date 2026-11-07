#' Connect to a DuckDB database
#'
#' @param config Connection configuration from settings.yml
#' @return A DuckDB database connection
#' @keywords internal
.connect_duckdb <- function(config) {
  # Check if duckdb is available
  .require_driver("DuckDB", "duckdb")

  if (is.null(config$database)) {
    stop("DuckDB configuration must include 'database' path")
  }

  # Validate database path
  db_path <- normalizePath(config$database, mustWork = FALSE)
  db_dir <- dirname(db_path)

  if (!dir.exists(db_dir)) {
    stop(sprintf("Database directory does not exist: %s", db_dir))
  }

  # DuckDB-specific configuration options
  read_only <- isTRUE(config$read_only)

  # A read-only database needs no write permission
  if (!read_only && file.exists(db_path) && file.access(db_path, 2) != 0) {
    stop(sprintf(
      "No write permission for database: %s. Add read_only: true to the connection to open it read-only.",
      db_path
    ))
  }
  memory_limit <- if (!is.null(config$memory_limit)) config$memory_limit else NULL
  threads <- if (!is.null(config$threads)) config$threads else NULL

  tryCatch(
    {
      # Build config list for DuckDB
      duck_config <- list()

      if (!is.null(memory_limit)) {
        duck_config$memory_limit <- memory_limit
      }

      if (!is.null(threads)) {
        duck_config$threads <- threads
      }

      # Connect with configuration
      conn <- if (length(duck_config) > 0) {
        DBI::dbConnect(
          duckdb::duckdb(),
          dbdir = db_path,
          read_only = read_only,
          config = duck_config
        )
      } else {
        DBI::dbConnect(
          duckdb::duckdb(),
          dbdir = db_path,
          read_only = read_only
        )
      }

      conn
    },
    error = \(e) stop(sprintf("Failed to connect to DuckDB database: %s", e$message))
  )
}

#' Check if a DuckDB database exists
#'
#' @param config Connection configuration from settings.yml
#' @return TRUE if database exists, FALSE otherwise
#' @keywords internal
.check_duckdb_exists <- function(config) {
  if (is.null(config$database)) {
    return(FALSE)
  }

  normalizePath(config$database, mustWork = FALSE) |>
    file.exists()
}

#' Create a new DuckDB database
#'
#' @param config Connection configuration from settings.yml
#' @return TRUE if successful
#' @keywords internal
.create_duckdb_db <- function(config) {
  if (is.null(config$database)) {
    stop("DuckDB configuration must include 'database' path")
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
      # DuckDB creates the file automatically on connection
      DBI::dbConnect(duckdb::duckdb(), dbdir = db_path) |>
        (\(con) {
          DBI::dbDisconnect(con, shutdown = TRUE)
          TRUE
        })()
    },
    error = \(e) stop(sprintf("Failed to create DuckDB database: %s", e$message))
  )
}
