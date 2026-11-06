#' Check if database drivers are installed
#'
#' Checks which database drivers are currently available on the system.
#' Returns a data frame showing the status of all supported database drivers.
#'
#' @param quiet Logical. If TRUE, suppresses messages. Default: FALSE
#'
#' @return A data frame with columns:
#'   - driver: Database driver name
#'   - package: Required R package
#'   - installed: Whether the package is installed
#'   - version: Package version (if installed)
#'
#' @examples
#' \donttest{
#' # Check all drivers
#' db_drivers_status()
#'
#' # Quiet mode (no messages)
#' db_drivers_status(quiet = TRUE)
#' }
#'
#' @export
db_drivers_status <- function(quiet = FALSE) {
  checkmate::assert_flag(quiet)

  # Get all supported drivers
  drivers <- c("postgres", "mysql", "mariadb", "sqlserver", "duckdb", "sqlite")

  results <- lapply(drivers, function(drv) {
    info <- .get_driver_info(drv)
    pkg <- info$package

    installed <- requireNamespace(pkg, quietly = TRUE)
    version <- if (installed) as.character(packageVersion(pkg)) else NA_character_

    data.frame(
      driver = info$name,
      package = pkg,
      installed = installed,
      version = version,
      stringsAsFactors = FALSE
    )
  })

  df <- do.call(rbind, results)

  # Remove duplicates (postgres/postgresql, mysql/mariadb, etc.)
  df <- df[!duplicated(df$package), ]

  if (!quiet) {
    message("\n=== Database Driver Status ===\n")
    message(paste(capture.output(print(df, row.names = FALSE)), collapse = "\n"))
    message("")

    missing <- df[!df$installed, ]
    if (nrow(missing) > 0) {
      message("To install missing drivers:")
      for (i in seq_len(nrow(missing))) {
        pkg <- missing$package[i]
        if (pkg == "odbc") {
          message(sprintf("  install.packages('%s')", pkg))
          message("  # Also requires ODBC driver: https://learn.microsoft.com/en-us/sql/connect/odbc/")
        } else {
          message(sprintf("  install.packages('%s')", pkg))
        }
      }
      message("")
    }
  }

  invisible(df)
}

#' Install database drivers
#'
#' Interactive helper to install one or more database drivers.
#' Provides helpful instructions and handles special cases (like ODBC).
#'
#' @param drivers Character vector. Database driver names to install
#'   (e.g., "postgres", "mysql", "duckdb"). If NULL, shows interactive menu.
#' @param repos Character. CRAN repository URL. Default: getOption("repos")
#'
#' @return NULL (invisible). Installs packages as side effect.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Install specific drivers
#' db_drivers_install(c("postgres", "mysql"))
#'
#' # Interactive mode
#' db_drivers_install()
#' }
#' }
#'
#' @export
db_drivers_install <- function(drivers = NULL, repos = getOption("repos")) {
  # Get current status
  status <- db_drivers_status(quiet = TRUE)

  if (is.null(drivers) && !interactive()) {
    stop("Name the drivers to install, such as db_drivers_install(\"postgres\"). ",
         "The menu needs an interactive session.", call. = FALSE)
  }

  if (is.null(drivers)) {
    # Interactive mode
    cat("\n=== Install Database Drivers ===\n\n")
    cat("Available drivers:\n")
    for (i in seq_len(nrow(status))) {
      installed <- if (status$installed[i]) "x" else " "
      cat(sprintf("  [%s] %s (%s)\n",
                  installed,
                  status$driver[i],
                  status$package[i]))
    }
    cat("\nEnter driver names to install (comma-separated, or 'all'): ")
    input <- readline()

    if (tolower(trimws(input)) == "all") {
      drivers <- c("postgres", "mysql", "sqlserver", "duckdb")
    } else {
      drivers <- strsplit(input, ",")[[1]]
      drivers <- trimws(drivers)
    }
  }

  drivers <- drivers[!is.na(drivers) & nzchar(trimws(drivers))]
  if (length(drivers) == 0) {
    message("No drivers named, so nothing was installed.")
    return(invisible(NULL))
  }

  # Validate driver names
  valid_drivers <- c("postgres", "postgresql", "mysql", "mariadb",
                     "sqlserver", "mssql", "duckdb", "sqlite")

  invalid <- drivers[!tolower(drivers) %in% valid_drivers]
  if (length(invalid) > 0) {
    stop(sprintf("Invalid driver names: %s\nValid options: %s",
                 paste(invalid, collapse = ", "),
                 paste(valid_drivers, collapse = ", ")),
         call. = FALSE)
  }

  # Get packages to install
  packages <- unique(sapply(drivers, function(drv) {
    .get_driver_info(drv)$package
  }))

  # Remove already installed
  to_install <- packages[!sapply(packages, function(pkg) {
    requireNamespace(pkg, quietly = TRUE)
  })]

  if (length(to_install) == 0) {
    message("All requested drivers are already installed!")
    return(invisible(NULL))
  }

  # Special handling for ODBC
  if ("odbc" %in% to_install) {
    cat("\n")
    cat("Note: SQL Server requires the 'odbc' R package AND a system ODBC driver.\n")
    cat("Install ODBC driver from: https://learn.microsoft.com/en-us/sql/connect/odbc/\n")
    cat("\n")
    cat("Continue with R package installation? (y/n): ")
    response <- readline()
    if (!tolower(trimws(response)) %in% c("y", "yes")) {
      message("Installation cancelled.")
      return(invisible(NULL))
    }
  }

  # Install packages
  message(sprintf("\nInstalling: %s", paste(to_install, collapse = ", ")))
  utils::install.packages(to_install, repos = repos)

  # Show updated status
  message("")
  db_drivers_status()

  invisible(NULL)
}

#' Check if a connection is ready to use
#'
#' Diagnoses whether a configured database connection can be established.
#' Checks driver availability and configuration validity without actually
#' connecting to the database.
#'
#' @param connection_name Character. Name of the connection in config.yml
#'
#' @return A list with diagnostic information:
#'   - ready: Logical. TRUE if connection appears ready
#'   - driver: Driver name
#'   - package: Required package
#'   - package_installed: Whether package is available
#'   - config_valid: Whether configuration appears valid
#'   - messages: Character vector of diagnostic messages
#'
#' @keywords internal
connection_check <- function(connection_name) {
  checkmate::assert_string(connection_name, min.chars = 1)

  messages <- character()
  ready <- TRUE

  # 1. Check if connection exists in config
  cfg <- tryCatch(
    settings_read(),
    error = function(e) {
      messages <<- c(messages, sprintf("Failed to read settings.yml/config.yml: %s", e$message))
      ready <<- FALSE
      NULL
    }
  )

  if (is.null(cfg)) {
    return(list(
      ready = FALSE,
      driver = NA_character_,
      package = NA_character_,
      package_installed = FALSE,
      config_valid = FALSE,
      messages = messages
    ))
  }

  # 2. Check if connection is defined
  if (is.null(cfg$connections) || is.null(cfg$connections[[connection_name]])) {
    messages <- c(messages,
                  sprintf("Connection '%s' not found in settings.yml/config.yml", connection_name))
    return(list(
      ready = FALSE,
      driver = NA_character_,
      package = NA_character_,
      package_installed = FALSE,
      config_valid = FALSE,
      messages = messages
    ))
  }

  conn_config <- cfg$connections[[connection_name]]

  # 3. Check driver
  if (is.null(conn_config$driver)) {
    messages <- c(messages, "Connection missing 'driver' field")
    ready <- FALSE
    driver <- NA_character_
    package <- NA_character_
  } else {
    driver <- conn_config$driver
    info <- tryCatch(
      .get_driver_info(driver),
      error = function(e) {
        messages <<- c(messages, sprintf("Unknown driver: %s", driver))
        ready <<- FALSE
        NULL
      }
    )

    if (is.null(info)) {
      package <- NA_character_
    } else {
      package <- info$package
    }
  }

  # 4. Check package availability
  package_installed <- FALSE
  if (!is.na(package)) {
    package_installed <- requireNamespace(package, quietly = TRUE)
    if (!package_installed) {
      messages <- c(messages,
                    sprintf("Driver package '%s' not installed", package),
                    sprintf("Install with: install.packages('%s')", package))
      ready <- FALSE
    }
  }

  # 5. Validate config fields by driver type
  config_valid <- TRUE
  if (!is.na(driver) && package_installed) {
    required_fields <- switch(
      tolower(driver),
      postgres = , postgresql = c("host", "database", "user"),
      mysql = , mariadb = c("host", "database", "user"),
      sqlserver = , mssql = c("server", "database"),
      duckdb = "database",
      sqlite = "database",
      character()
    )

    missing <- setdiff(required_fields, names(conn_config))
    if (length(missing) > 0) {
      messages <- c(messages,
                    sprintf("Connection missing required fields: %s",
                            paste(missing, collapse = ", ")))
      config_valid <- FALSE
      ready <- FALSE
    }
  }

  # 6. Build result
  result <- list(
    ready = ready,
    driver = if (is.na(driver)) NA_character_ else driver,
    package = if (is.na(package)) NA_character_ else package,
    package_installed = package_installed,
    config_valid = config_valid,
    messages = if (length(messages) == 0) "Connection appears ready" else messages
  )

  # Print summary if not ready
  if (!ready) {
    message(sprintf("\n=== Connection Check: %s ===\n", connection_name))
    message(sprintf("Driver: %s", if (is.na(driver)) "(not set)" else driver))
    message(sprintf("Package: %s", if (is.na(package)) "(unknown)" else package))
    message(sprintf("Package installed: %s", if (package_installed) "yes" else "no"))
    message(sprintf("Config valid: %s\n", if (config_valid) "yes" else "no"))
    message("Issues:")
    for (msg in messages) {
      message(sprintf("  - %s", msg))
    }
    message("")
  }

  invisible(result)
}
