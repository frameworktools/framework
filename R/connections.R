#' Get a database connection
#'
#' Gets a database connection based on the connection name in settings.yml
#' (or settings/connections.yml). SQLite and DuckDB paths are relative to the
#' project root.
#' For most use cases, prefer `db_query()` or `db_execute()` which handle
#' connection lifecycle automatically.
#'
#' @param name Character. Name of the connection in settings (e.g., "postgres")
#' @return A database connection object (DBIConnection)
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Preferred: use db_query() which auto-disconnects
#' users <- db_query("SELECT * FROM users", "postgres")
#'
#' # Manual connection management (remember to disconnect!)
#' conn <- db_connect("postgres")
#' DBI::dbListTables(conn)
#' DBI::dbDisconnect(conn)
#' }
#' }
#'
#' @export
db_connect <- function(name) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)

  config <- tryCatch(
    settings_read(),
    error = function(e) {
      stop(sprintf("Failed to read configuration: %s", e$message))
    }
  )

  # Look up connection: check databases sub-key first (GUI format), then flat (legacy)
  conn_config <- config$connections$databases[[name]] %||% config$connections[[name]]

  if (is.null(conn_config) || !is.list(conn_config)) {
    stop(sprintf("No connection configuration found for '%s'", name))
  }

  # Validate driver
  if (is.null(conn_config$driver)) {
    stop(sprintf("No driver specified for connection '%s'", name))
  }

  # File databases are relative to the project root, not the working
  # directory, so notebooks/ opens the project's database
  if (conn_config$driver %in% c("sqlite", "duckdb")) {
    conn_config$database <- .fw_project_path(conn_config$database)
  }

  # Return connection
  tryCatch(
    switch(conn_config$driver,
      postgres = .connect_postgres(conn_config),
      postgresql = .connect_postgres(conn_config),
      mysql = .connect_mysql(conn_config),
      mariadb = .connect_mysql(conn_config),
      sqlserver = .connect_sqlserver(conn_config),
      mssql = .connect_sqlserver(conn_config),
      duckdb = .connect_duckdb(conn_config),
      sqlite = .connect_sqlite(conn_config),
      stop(sprintf("Unsupported database driver for '%s': %s", name, conn_config$driver))
    ),
    error = function(e) {
      stop(sprintf("Failed to connect to '%s': %s", name, e$message))
    }
  )
}




#' List all database connections from configuration
#'
#' Lists all database connections defined in the configuration, showing the
#' connection name, driver, host, and database name (if applicable).
#'
#' @return Invisibly returns NULL after printing connection list
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # List all connections
#' db_list()
#' }
#' }
db_list <- function() {
  config <- settings_read()

  # Get database connections: check databases sub-key first (GUI format), then flat (legacy)
  db_conns <- config$connections$databases
  if (is.null(db_conns) || length(db_conns) == 0) {
    # Fallback to flat format - filter out non-connection keys
    db_conns <- config$connections
    if (is.list(db_conns)) {
      db_conns <- db_conns[!names(db_conns) %in% c("storage_buckets", "default_storage_bucket", "default_database")]
      # Only keep entries that look like connection configs (have driver key)
      db_conns <- Filter(function(x) is.list(x) && !is.null(x$driver), db_conns)
    }
  }

  if (is.null(db_conns) || length(db_conns) == 0) {
    message("No database connections found in configuration")
    return(invisible(NULL))
  }

  # Print formatted output
  message(sprintf("\n%d %s found:\n",
                  length(db_conns),
                  if (length(db_conns) == 1) "connection" else "connections"))

  for (name in names(db_conns)) {
    conn <- db_conns[[name]]

    # Connection name with driver badge
    driver <- if (!is.null(conn$driver)) toupper(conn$driver) else "UNKNOWN"
    message(sprintf("- %s [%s]", name, driver))

    # Host (if available)
    if (!is.null(conn$host)) {
      port_info <- if (!is.null(conn$port)) sprintf(":%s", conn$port) else ""
      message(sprintf("  Host: %s%s", conn$host, port_info))
    }

    # Database (if available)
    if (!is.null(conn$database) || !is.null(conn$dbname)) {
      db <- conn$database %||% conn$dbname
      message(sprintf("  Database: %s", db))
    }

    # File path (for file-based databases like SQLite, DuckDB)
    if (!is.null(conn$path)) {
      message(sprintf("  Path: %s", conn$path))
    }

    # Pool info (if enabled)
    if (isTRUE(conn$pool)) {
      message("  Connection pooling: enabled")
    }

    message("")  # Blank line between connections
  }

  invisible(NULL)
}

#' List all connections (databases and object storage)
#'
#' Prints both database connections defined under `connections:` and object
#' storage profiles (S3-compatible buckets). Use this to see everything Framework
#' can talk to from your config.
#'
#' @return Invisibly returns NULL after printing summaries.
#' @export
connections_list <- function() {
  config <- settings_read()
  storage_buckets <- config$connections$storage_buckets
  default_storage <- config$connections$default_storage_bucket %||% config$default_storage_bucket

  # Get database connections: check databases sub-key first (GUI format), then flat (legacy)
  db_conns <- config$connections$databases
  if (is.null(db_conns) || length(db_conns) == 0) {
    db_conns <- config$connections
    if (is.list(db_conns)) {
      db_conns <- db_conns[!names(db_conns) %in% c("storage_buckets", "default_storage_bucket", "default_database", "databases")]
      # Only keep entries that look like connection configs (have driver key)
      db_conns <- Filter(function(x) is.list(x) && !is.null(x$driver), db_conns)
    } else {
      db_conns <- list()
    }
  }

  if (!length(storage_buckets) && length(config$storage_buckets)) {
    storage_buckets <- config$storage_buckets
  }

  if (is.null(default_storage) && !is.null(config$default_storage_bucket)) {
    default_storage <- config$default_storage_bucket
  }

  if (!length(storage_buckets)) {
    storage_buckets <- list()
  }

  has_db <- length(db_conns) > 0
  has_storage <- length(storage_buckets) > 0

  if (!has_db && !has_storage) {
    message("No connections found in configuration")
    return(invisible(NULL))
  }

  if (has_db) {
    message(sprintf("\n%d database %s:\n",
                    length(db_conns),
                    if (length(db_conns) == 1) "connection" else "connections"))

    for (name in names(db_conns)) {
      conn <- db_conns[[name]]
      if (!is.list(conn)) next

      driver <- if (!is.null(conn$driver)) toupper(conn$driver) else "UNKNOWN"
      message(sprintf("- %s [%s]", name, driver))

      if (!is.null(conn$host)) {
        port_info <- if (!is.null(conn$port)) sprintf(":%s", conn$port) else ""
        message(sprintf("  Host: %s%s", conn$host, port_info))
      }

      if (!is.null(conn$database) || !is.null(conn$dbname)) {
        db <- conn$database %||% conn$dbname
        message(sprintf("  Database: %s", db))
      }

      if (!is.null(conn$path)) {
        message(sprintf("  Path: %s", conn$path))
      }

      message("")
    }
  }

  if (has_storage) {
    message(sprintf("\n%d object storage %s:\n",
                    length(storage_buckets),
                    if (length(storage_buckets) == 1) "connection" else "connections"))

    for (name in names(storage_buckets)) {
      conn <- storage_buckets[[name]]
      if (!is.list(conn)) next

      provider <- conn$provider %||% conn$driver %||% conn$type %||% "s3"
      marker <- if (!is.null(default_storage) && identical(name, default_storage)) " (default)" else ""
      message(sprintf("- %s [%s]%s", name, toupper(provider), marker))

      if (!is.null(conn$bucket)) {
        message(sprintf("  Bucket: %s", conn$bucket))
      }

      if (!is.null(conn$region)) {
        message(sprintf("  Region: %s", conn$region))
      }

      if (!is.null(conn$endpoint)) {
        message(sprintf("  Endpoint: %s", conn$endpoint))
      }

      if (!is.null(conn$prefix) && nzchar(conn$prefix)) {
        message(sprintf("  Prefix: %s", conn$prefix))
      }

      message("")
    }
  }

  invisible(NULL)
}
