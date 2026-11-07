#' Get or create a connection pool
#'
#' Returns a connection pool for the specified database connection. Connection
#' pools automatically manage connection lifecycle, reuse connections across
#' operations, and handle cleanup. This is the recommended way to work with
#' databases in Framework.
#'
#' **Connection pools are stored in a package environment and reused across
#' calls.** You don't need to manage pool lifecycle - Framework handles it
#' automatically.
#'
#' @param name Character. Name of the connection in settings.yml
#' @param min_size Integer. Minimum number of connections to maintain (default: 1)
#' @param max_size Integer. Maximum number of connections allowed (default: Inf)
#' @param idle_timeout Integer. Seconds before idle connections are closed (default: 60)
#' @param validation_interval Integer. Seconds between connection health checks (default: 60)
#' @param recreate Logical. If TRUE, closes existing pool and creates new one (default: FALSE)
#'
#' @return A pool object that can be used like a regular DBI connection
#'
#' @details
#' **Advantages of connection pools:**
#' - Automatic connection reuse (faster than creating new connections)
#' - Handles connection failures gracefully (auto-reconnects)
#' - Thread-safe for Shiny apps
#' - No need to manually disconnect
#' - Health checking prevents using stale connections
#'
#' **When to use:**
#' - Long-running R sessions (notebooks, Shiny apps)
#' - Multiple database operations
#' - Any production code
#'
#' **When NOT to use:**
#' - One-off queries (use `db_query()` instead)
#' - Short scripts (overhead not worth it)
#'
#' @keywords internal
connection_pool <- function(name,
                           min_size = 1,
                           max_size = Inf,
                           idle_timeout = 60,
                           validation_interval = 60,
                           recreate = FALSE) {
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_count(min_size, positive = TRUE)
  checkmate::assert_number(max_size, lower = min_size)
  checkmate::assert_count(idle_timeout, positive = TRUE)
  checkmate::assert_count(validation_interval, positive = TRUE)
  checkmate::assert_flag(recreate)

  # Check if pool package is available
  if (!requireNamespace("pool", quietly = TRUE)) {
    stop(
      "Connection pooling requires the 'pool' package.\n\n",
      "Install with: install.packages('pool')\n\n",
      "Alternatively, use db_connect() for single-use connections.",
      call. = FALSE
    )
  }

  # Get pool environment (initialized in .onLoad)
  pools_env <- .framework_env$pools

  # Check if pool already exists
  if (exists(name, envir = pools_env) && !recreate) {
    existing_pool <- get(name, envir = pools_env)

    # Verify pool is still valid
    if (pool::dbIsValid(existing_pool)) {
      return(existing_pool)
    } else {
      # Pool is invalid, close and recreate
      message(sprintf("Existing pool '%s' is invalid, recreating...", name))
      tryCatch(pool::poolClose(existing_pool), error = function(e) NULL)
    }
  }

  # Close existing pool if recreating
  if (recreate && exists(name, envir = pools_env)) {
    tryCatch({
      old_pool <- get(name, envir = pools_env)
      pool::poolClose(old_pool)
      message(sprintf("Closed existing pool: %s", name))
    }, error = function(e) {
      warning(sprintf("Failed to close existing pool '%s': %s", name, e$message), call. = FALSE)
    })
  }

  # Get connection config
  config <- tryCatch(
    settings_read(),
    error = function(e) {
      stop(sprintf("Failed to read configuration: %s", e$message), call. = FALSE)
    }
  )

  # Look up connection: check databases sub-key first (GUI format), then flat (legacy)
  conn_config <- config$connections$databases[[name]] %||% config$connections[[name]]

  if (is.null(conn_config) || !is.list(conn_config)) {
    stop(sprintf("No connection configuration found for '%s'", name), call. = FALSE)
  }

  # Validate driver
  if (is.null(conn_config$driver)) {
    stop(sprintf("No driver specified for connection '%s'", name), call. = FALSE)
  }

  # Validate driver package
  .validate_driver(conn_config$driver)
  if (conn_config$driver %in% c("sqlite", "duckdb")) {
    conn_config$database <- .fw_project_path(conn_config$database)
  }

  # Create pool based on driver
  new_pool <- tryCatch({
    switch(conn_config$driver,
      postgres = , postgresql = .create_pool_postgres(conn_config, min_size, max_size, idle_timeout, validation_interval),
      mysql = , mariadb = .create_pool_mysql(conn_config, min_size, max_size, idle_timeout, validation_interval),
      sqlite = .create_pool_sqlite(conn_config, min_size, max_size, idle_timeout, validation_interval),
      duckdb = .create_pool_duckdb(conn_config, min_size, max_size, idle_timeout, validation_interval),
      sqlserver = , mssql = .create_pool_sqlserver(conn_config, min_size, max_size, idle_timeout, validation_interval),
      stop(sprintf("Connection pooling not supported for driver: %s", conn_config$driver), call. = FALSE)
    )
  }, error = function(e) {
    stop(sprintf("Failed to create connection pool for '%s': %s", name, e$message), call. = FALSE)
  })

  # Store pool
  assign(name, new_pool, envir = pools_env)

  new_pool
}

# Pool creation helpers for each database
.create_pool_postgres <- function(config, min_size, max_size, idle_timeout, validation_interval) {
  pool::dbPool(
    drv = RPostgres::Postgres(),
    host = config$host,
    port = as.integer(config$port %||% 5432),
    dbname = config$database,
    user = config$user,
    password = config$password %||% "",
    minSize = min_size,
    maxSize = max_size,
    idleTimeout = idle_timeout,
    validationInterval = validation_interval
  )
}

.create_pool_mysql <- function(config, min_size, max_size, idle_timeout, validation_interval) {
  pool::dbPool(
    drv = RMariaDB::MariaDB(),
    host = config$host,
    port = as.integer(config$port %||% 3306),
    dbname = config$database,
    username = config$user,
    password = config$password %||% "",
    minSize = min_size,
    maxSize = max_size,
    idleTimeout = idle_timeout,
    validationInterval = validation_interval
  )
}

.create_pool_sqlite <- function(config, min_size, max_size, idle_timeout, validation_interval) {
  pool::dbPool(
    drv = RSQLite::SQLite(),
    dbname = config$database,
    flags = if (isTRUE(config$read_only)) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC,
    minSize = min_size,
    maxSize = max_size,
    idleTimeout = idle_timeout,
    validationInterval = validation_interval
  )
}

.create_pool_duckdb <- function(config, min_size, max_size, idle_timeout, validation_interval) {
  # DuckDB config options
  duck_config <- list()
  if (!is.null(config$memory_limit)) duck_config$memory_limit <- config$memory_limit
  if (!is.null(config$threads)) duck_config$threads <- as.integer(config$threads)

  pool::dbPool(
    drv = duckdb::duckdb(),
    dbdir = config$database,
    read_only = config$read_only %||% FALSE,
    config = if (length(duck_config) > 0) duck_config else NULL,
    minSize = min_size,
    maxSize = max_size,
    idleTimeout = idle_timeout,
    validationInterval = validation_interval
  )
}

.create_pool_sqlserver <- function(config, min_size, max_size, idle_timeout, validation_interval) {
  driver <- config$driver_name %||% "ODBC Driver 18 for SQL Server"
  server <- if (!is.null(config$port)) {
    sprintf("%s,%s", config$server, config$port)
  } else {
    config$server
  }

  pool::dbPool(
    drv = odbc::odbc(),
    driver = driver,
    server = server,
    database = config$database,
    uid = config$user,
    pwd = config$password %||% "",
    TrustServerCertificate = if (!is.null(config$trust_server_certificate)) "yes" else "no",
    minSize = min_size,
    maxSize = max_size,
    idleTimeout = idle_timeout,
    validationInterval = validation_interval
  )
}

#' Execute code with a connection pool
#'
#' Convenience wrapper for working with connection pools. Gets or creates a pool
#' and makes it available as `pool` within the code block.
#'
#' @param connection_name Character. Name of the connection in settings.yml
#' @param code Expression to evaluate with the pool
#' @param ... Additional arguments passed to `connection_pool()`
#'
#' @return The result of evaluating `code`
#'
#' @keywords internal
connection_with_pool <- function(connection_name, code, ...) {
  checkmate::assert_string(connection_name, min.chars = 1)

  # Get or create pool
  pool <- connection_pool(connection_name, ...)

  # Make pool available in code block
  eval(substitute(code), envir = list(pool = pool), enclos = parent.frame())
}

#' Close a specific connection pool
#'
#' Closes and removes a connection pool. All connections in the pool are
#' gracefully closed.
#'
#' @param name Character. Name of the connection pool to close
#' @param quiet Logical. If TRUE, suppresses messages (default: FALSE)
#'
#' @return Invisibly returns TRUE if pool was closed, FALSE if it didn't exist
#'
#' @keywords internal
connection_pool_close <- function(name, quiet = FALSE) {
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_flag(quiet)

  pools_env <- .framework_env$pools

  if (!exists(name, envir = pools_env)) {
    if (!quiet) message(sprintf("No pool found for: %s", name))
    return(invisible(FALSE))
  }

  tryCatch({
    pool_obj <- get(name, envir = pools_env)
    pool::poolClose(pool_obj)
    rm(list = name, envir = pools_env)
    if (!quiet) message(sprintf("Closed pool: %s", name))
    invisible(TRUE)
  }, error = function(e) {
    warning(sprintf("Failed to close pool '%s': %s", name, e$message), call. = FALSE)
    invisible(FALSE)
  })
}

#' Close all connection pools
#'
#' Closes all active connection pools. Useful for cleanup when shutting down
#' R sessions or resetting state.
#'
#' @param quiet Logical. If TRUE, suppresses messages (default: FALSE)
#'
#' @return Invisibly returns the number of pools closed
#'
#' @keywords internal
connection_pool_close_all <- function(quiet = FALSE) {
  checkmate::assert_flag(quiet)

  pools_env <- .framework_env$pools
  pool_names <- ls(envir = pools_env)

  if (length(pool_names) == 0) {
    if (!quiet) message("No connection pools found")
    return(invisible(0))
  }

  closed_count <- 0

  for (name in pool_names) {
    if (connection_pool_close(name, quiet = TRUE)) {
      closed_count <- closed_count + 1
      if (!quiet) message(sprintf("Closed pool: %s", name))
    }
  }

  if (!quiet && closed_count > 0) {
    message(sprintf("\nClosed %d pool%s", closed_count, if (closed_count == 1) "" else "s"))
  }

  invisible(closed_count)
}

#' List active connection pools
#'
#' Shows all currently active connection pools with their status.
#'
#' @return A data frame with pool information:
#'   - name: Pool name
#'   - valid: Whether pool is valid
#'   - connections: Number of active connections (if available)
#'
#' @keywords internal
connection_pool_list <- function() {
  pools_env <- .framework_env$pools
  pool_names <- ls(envir = pools_env)

  if (length(pool_names) == 0) {
    return(data.frame(
      name = character(0),
      valid = logical(0),
      connections = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  result <- lapply(pool_names, function(name) {
    pool_obj <- get(name, envir = pools_env)

    is_valid <- tryCatch(
      pool::dbIsValid(pool_obj),
      error = function(e) FALSE
    )

    # Try to get connection count
    conn_count <- tryCatch({
      # This is pool-package specific
      if (is_valid) {
        length(pool_obj@counters$taken)
      } else {
        NA_integer_
      }
    }, error = function(e) NA_integer_)

    data.frame(
      name = name,
      valid = is_valid,
      connections = conn_count,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, result)
}
