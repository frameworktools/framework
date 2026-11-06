#' Configure Author Information
#'
#' Interactively set author information in settings.yml (or settings.yml for legacy projects).
#' This information is
#' used in notebooks, reports, and other documents.
#'
#' @param name Character. Author name (optional, prompts if not provided)
#' @param email Character. Author email (optional, prompts if not provided)
#' @param affiliation Character. Author affiliation/institution (optional, prompts if not provided)
#' @param interactive Logical. If TRUE, prompts for missing values. Default TRUE.
#'
#' @return Invisibly returns updated config
#'
#' @keywords internal
configure_author <- function(name = NULL, email = NULL, affiliation = NULL, interactive = TRUE) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(email, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(affiliation, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(interactive)

  # Read current config
  config_path <- .get_settings_file()
  if (is.null(config_path)) {
    stop("settings.yml or config.yml not found. Run framework::project_create() first.")
  }

  config <- settings_read(config_path)

  # Get current values for defaults
  current_name <- config$author$name
  current_email <- config$author$email
  current_affiliation <- config$author[["affiliation"]]

  # Interactive prompts if values not provided
  if (interactive) {
    if (is.null(name)) {
      default_msg <- if (!is.null(current_name)) sprintf(" [%s]", current_name) else ""
      cat(sprintf("Author name%s: ", default_msg))
      input <- readline()
      name <- if (nzchar(input)) input else current_name
    }

    if (is.null(email)) {
      default_msg <- if (!is.null(current_email)) sprintf(" [%s]", current_email) else ""
      cat(sprintf("Author email%s: ", default_msg))
      input <- readline()
      email <- if (nzchar(input)) input else current_email
    }

    if (is.null(affiliation)) {
      default_msg <- if (!is.null(current_affiliation)) sprintf(" [%s]", current_affiliation) else ""
      cat(sprintf("Author affiliation%s: ", default_msg))
      input <- readline()
      affiliation <- if (nzchar(input)) input else current_affiliation
    }
  }

  # Update config
  if (!is.null(name)) config$author$name <- name
  if (!is.null(email)) config$author$email <- email
  if (!is.null(affiliation)) config$author$affiliation <- affiliation

  # Write config
  settings_write(config, config_path)

  message("\u2713 Author information updated in ", basename(config_path))
  if (!is.null(name)) message(sprintf("  Name: %s", name))
  if (!is.null(email)) message(sprintf("  Email: %s", email))
  if (!is.null(affiliation)) message(sprintf("  Affiliation: %s", affiliation))

  invisible(config)
}


#' Configure Data Source
#'
#' Interactively add a data source to settings.yml (or settings.yml for legacy projects). Data sources are defined
#' with dot-notation paths (e.g., "source.private.survey") and include metadata
#' like file path, type, and whether the data is locked.
#'
#' @param path Character. Dot-notation path for the data source (e.g., "source.private.survey")
#' @param file Character. File path to the data file
#' @param type Character. Data type: "csv", "tsv", "rds", "excel", "stata", "spss", "sas", or "auto"
#' @param locked Logical. If TRUE, file is read-only and errors on changes
#' @param interactive Logical. If TRUE, prompts for missing values. Default TRUE.
#'
#' @return Invisibly returns updated config
#'
#' @keywords internal
configure_data <- function(path = NULL, file = NULL, type = NULL, locked = FALSE, interactive = TRUE) {
  # Validate arguments
  checkmate::assert_string(path, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(file, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(type, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(locked)
  checkmate::assert_flag(interactive)

  # Read current config
  config_path <- .get_settings_file()
  if (is.null(config_path)) {
    stop("settings.yml or config.yml not found. Run framework::project_create() first.")
  }

  config <- settings_read(config_path)

  # Interactive prompts
  if (interactive) {
    if (is.null(path)) {
      cat("Data source path (e.g., 'source.private.survey'): ")
      path <- readline()
      if (!nzchar(path)) stop("Data source path is required")
    }

    if (is.null(file)) {
      cat("File path (e.g., 'inputs/raw/survey.csv'): ")
      file <- readline()
      if (!nzchar(file)) stop("File path is required")
    }

    if (is.null(type)) {
      cat("Data type [csv/tsv/rds/excel/stata/spss/sas/auto]: ")
      type_input <- readline()
      type <- if (nzchar(type_input)) type_input else "auto"
    }

    cat("Lock file (prevent modifications)? [y/N]: ")
    locked_input <- readline()
    if (tolower(locked_input) %in% c("y", "yes")) {
      locked <- TRUE
    }
  }

  # Validate type
  valid_types <- c("csv", "tsv", "rds", "excel", "stata", "spss", "sas", "auto")
  if (!type %in% valid_types) {
    stop(sprintf("Invalid type '%s'. Must be one of: %s",
                 type, paste(valid_types, collapse = ", ")))
  }

  # Parse dot-notation path and create nested structure
  path_parts <- strsplit(path, "\\.")[[1]]
  if (length(path_parts) < 1) {
    stop("Invalid data source path. Use dot notation (e.g., 'source.private.survey')")
  }

  # Build nested list
  data_entry <- list(
    path = file,
    type = type
  )
  if (locked) {
    data_entry$locked <- TRUE
  }

  # Navigate to the right location in config$data
  if (is.null(config$data)) {
    config$data <- list()
  }

  # Build nested structure by directly accessing config$data
  # This works because we're modifying config$data directly, not a copy
  if (length(path_parts) == 1) {
    # Simple path - direct assignment
    config$data[[path_parts[1]]] <- data_entry
  } else {
    # Nested path - build structure from top down
    # Create nested list structure recursively
    expr <- "config$data"
    for (i in seq_along(path_parts)) {
      part <- path_parts[i]
      if (i < length(path_parts)) {
        # Intermediate level - ensure it exists
        eval_expr <- parse(text = expr)
        current <- eval(eval_expr)
        if (is.null(current[[part]])) {
          # Create the intermediate level
          assign_expr <- sprintf("%s$%s <- list()", expr, part)
          eval(parse(text = assign_expr))
        }
        expr <- sprintf("%s$%s", expr, part)
      } else {
        # Last level - assign the data entry
        assign_expr <- sprintf("%s$%s <- data_entry", expr, part)
        eval(parse(text = assign_expr))
      }
    }
  }

  # Write config
  settings_write(config, config_path)

  message(sprintf("\u2713 Data source '%s' added to %s", path, basename(config_path)))
  message(sprintf("  File: %s", file))
  message(sprintf("  Type: %s", type))
  if (locked) message("  Locked: yes")
  message(sprintf("\nLoad with: data_read(\"%s\")", path))

  invisible(config)
}


#' Configure Database Connection
#'
#' Interactively add a database connection to settings.yml (or settings.yml for legacy projects). Connections can be
#' defined inline or in a split file (settings/connections.yml).
#'
#' @param name Character. Connection name (e.g., "db", "warehouse")
#' @param driver Character. Database driver: "sqlite", "postgresql", "mysql", etc.
#' @param host Character. Database host (for network databases)
#' @param port Integer. Database port (for network databases)
#' @param database Character. Database name
#' @param user Character. Database user (for network databases)
#' @param password Character. Database password (stored in .env)
#' @param interactive Logical. If TRUE, prompts for missing values. Default TRUE.
#'
#' @return Invisibly returns updated config
#'
#' @keywords internal
configure_connection <- function(name = NULL, driver = NULL, host = NULL,
                                  port = NULL, database = NULL, user = NULL,
                                  password = NULL, interactive = TRUE) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(driver, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(host, min.chars = 1, null.ok = TRUE)
  checkmate::assert_int(port, lower = 1, upper = 65535, null.ok = TRUE)
  checkmate::assert_string(database, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(user, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(password, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(interactive)

  # Read current config
  config_path <- .get_settings_file()
  if (is.null(config_path)) {
    stop("settings.yml or config.yml not found. Run framework::project_create() first.")
  }

  config <- settings_read(config_path)

  # Interactive prompts
  if (interactive) {
    if (is.null(name)) {
      cat("Connection name (e.g., 'db', 'warehouse'): ")
      name <- readline()
      if (!nzchar(name)) stop("Connection name is required")
    }

    if (is.null(driver)) {
      cat("Database driver [sqlite/postgresql/mysql]: ")
      driver <- readline()
      if (!nzchar(driver)) stop("Database driver is required")
    }

    # Different prompts based on driver
    if (driver == "sqlite") {
      if (is.null(database)) {
        cat("Database file path (e.g., 'data/mydb.db'): ")
        database <- readline()
        if (!nzchar(database)) stop("Database path is required")
      }
    } else {
      # Network database prompts
      if (is.null(host)) {
        cat("Host [localhost]: ")
        host_input <- readline()
        host <- if (nzchar(host_input)) host_input else "localhost"
      }

      if (is.null(port)) {
        default_port <- if (driver == "postgresql") 5432 else if (driver == "mysql") 3306 else NULL
        port_msg <- if (!is.null(default_port)) sprintf(" [%d]", default_port) else ""
        cat(sprintf("Port%s: ", port_msg))
        port_input <- readline()
        port <- if (nzchar(port_input)) as.integer(port_input) else default_port
      }

      if (is.null(database)) {
        cat("Database name: ")
        database <- readline()
        if (!nzchar(database)) stop("Database name is required")
      }

      if (is.null(user)) {
        cat("Username: ")
        user <- readline()
        if (!nzchar(user)) stop("Username is required")
      }

      # Suggest storing password in .env
      cat("\nFor security, store password in .env file.\n")
      cat(sprintf("Add this line to .env: %s_PASSWORD=your_password\n", toupper(name)))
      cat("Skip password prompt? [Y/n]: ")
      skip_pw <- readline()
      if (!tolower(skip_pw) %in% c("n", "no")) {
        password <- sprintf("!expr Sys.getenv(\"%s_PASSWORD\")", toupper(name))
      } else if (is.null(password)) {
        cat("Password (will be visible): ")
        password <- readline()
      }
    }
  }

  # Build connection config
  conn_config <- list(driver = driver)

  if (driver == "sqlite") {
    conn_config$database <- database
  } else {
    conn_config$host <- host
    if (!is.null(port)) conn_config$port <- port
    conn_config$database <- database
    if (!is.null(user)) conn_config$user <- user
    if (!is.null(password)) conn_config$password <- password
  }

  # Add to config
  if (is.null(config$connections)) {
    config$connections <- list()
  }
  config$connections[[name]] <- conn_config

  # Write config
  settings_write(config, config_path)

  message(sprintf("\u2713 Connection '%s' added to %s", name, basename(config_path)))
  message(sprintf("  Driver: %s", driver))
  if (driver == "sqlite") {
    message(sprintf("  Database: %s", database))
  } else {
    message(sprintf("  Host: %s", host))
    if (!is.null(port)) message(sprintf("  Port: %d", port))
    message(sprintf("  Database: %s", database))
    if (!is.null(user)) message(sprintf("  User: %s", user))
  }
  message(sprintf("\nUse with: db_query(\"SELECT * FROM table\", \"%s\")", name))

  invisible(config)
}


#' Configure Package Dependencies
#'
#' Interactively add package dependencies to settings.yml (or settings.yml for legacy projects). Packages can be
#' installed from CRAN, GitHub, or Bioconductor, with version pinning support.
#'
#' @param package Character. Package name (e.g., "dplyr", "tidyverse/dplyr")
#' @param auto_attach Logical. If TRUE, package is loaded automatically during scaffold()
#' @param version Character. Version constraint (e.g., "@1.1.0", "@main" for GitHub)
#' @param interactive Logical. If TRUE, prompts for missing values. Default TRUE.
#'
#' @return Invisibly returns updated config
#'
#' @details
#' ## Package Specifications
#'
#' - CRAN: "dplyr", "ggplot2"
#' - CRAN with version: "dplyr@1.1.0"
#' - GitHub: "tidyverse/dplyr", "user/repo@branch"
#' - GitHub with tag: "user/repo@v1.2.3"
#'
#' @keywords internal
configure_packages <- function(package = NULL, auto_attach = TRUE, version = NULL, interactive = TRUE) {
  # Validate arguments
  checkmate::assert_string(package, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(auto_attach)
  checkmate::assert_string(version, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(interactive)

  # Read current config
  config_path <- .get_settings_file()
  if (is.null(config_path)) {
    stop("settings.yml or config.yml not found. Run framework::project_create() first.")
  }

  config <- settings_read(config_path)

  # Interactive prompts
  if (interactive) {
    if (is.null(package)) {
      cat("Package name (e.g., 'dplyr', 'tidyverse/dplyr@main'): ")
      package <- readline()
      if (!nzchar(package)) stop("Package name is required")
    }

    if (is.null(version) && !grepl("@", package)) {
      cat("Version (optional, e.g., '@1.1.0' or leave blank): ")
      version_input <- readline()
      if (nzchar(version_input)) {
        version <- version_input
        if (!grepl("^@", version)) {
          version <- paste0("@", version)
        }
      }
    }

    cat("Auto-attach during scaffold()? [Y/n]: ")
    attach_input <- readline()
    if (tolower(attach_input) %in% c("n", "no")) {
      auto_attach <- FALSE
    }
  }

  # Combine package and version if provided
  if (!is.null(version) && !grepl("@", package)) {
    package <- paste0(package, version)
  }

  # Initialize packages list if needed
  if (is.null(config$packages)) {
    config$packages <- list()
  }

  # Determine which list to work with (new vs old structure)
  # Guard against atomic vectors (character, etc.) which don't support $
  has_nested_structure <- is.list(config$packages) && !is.null(config$packages$default_packages)
  package_list <- if (has_nested_structure) {
    config$packages$default_packages
  } else {
    config$packages
  }

  # Initialize if empty
  if (is.null(package_list)) {
    package_list <- list()
  }

  # Check if package already exists
  package_base <- sub("@.*$", "", package)
  existing_idx <- NULL
  if (is.list(package_list) && length(package_list) > 0) {
    for (i in seq_along(package_list)) {
      pkg <- package_list[[i]]
      if (is.character(pkg)) {
        if (sub("@.*$", "", pkg) == package_base) {
          existing_idx <- i
          break
        }
      } else if (is.list(pkg)) {
        if (sub("@.*$", "", pkg$name) == package_base) {
          existing_idx <- i
          break
        }
      }
    }
  }

  # Add or update package
  pkg_entry <- list(name = package, auto_attach = auto_attach)

  if (!is.null(existing_idx)) {
    package_list[[existing_idx]] <- pkg_entry
    message(sprintf("\u2713 Updated package '%s' in %s", package, basename(config_path)))
  } else {
    package_list <- c(package_list, list(pkg_entry))
    message(sprintf("\u2713 Added package '%s' to %s", package, basename(config_path)))
  }

  # Write back to the correct location
  if (has_nested_structure) {
    config$packages$default_packages <- package_list
  } else {
    config$packages <- package_list
  }

  message(sprintf("  Auto-attach: %s", if (auto_attach) "yes" else "no"))
  message("\nRun scaffold() to install and load packages")

  # Write config
  settings_write(config, config_path)

  invisible(config)
}


#' Configure Project Directories
#'
#' Interactively configure project directory structure in settings.yml (or settings.yml for legacy projects).
#' Directories control where Framework creates and looks for files.
#'
#' @param directory Character. Directory name to configure (e.g., "notebooks", "scripts")
#' @param path Character. Path for the directory
#' @param interactive Logical. If TRUE, prompts for missing values. Default TRUE.
#'
#' @return Invisibly returns updated config
#'
#' @details
#' ## Standard Directories
#'
#' - `notebooks` - Where make_notebook() creates files
#' - `scripts` - Where make_script() creates files
#' - `functions` - Where scaffold() looks for custom functions
#' - `inputs_raw` - Source data, as received
#' - `inputs_intermediate` - Cleaned-but-input datasets
#' - `inputs_final` - Curated analytic datasets
#' - `inputs_reference` - External documentation/codebooks
#' - `outputs_private` - Working artifacts (tables/figures/models)
#' - `outputs_public` - Share-ready artifacts
#' - `outputs_docs` - Narrative/report outputs (private)
#' - `outputs_docs_public` - Narrative/report outputs (public)
#' - `cache` - Cached computation results
#' - `scratch` - Temporary workspace
#' - `logs` - Run logs and cluster job output
#'
#' @keywords internal
configure_directories <- function(directory = NULL, path = NULL, interactive = TRUE) {
  # Validate arguments
  checkmate::assert_string(directory, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(path, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(interactive)

  # Read current config
  config_path <- .get_settings_file()
  if (is.null(config_path)) {
    stop("settings.yml or config.yml not found. Run framework::project_create() first.")
  }

  config <- settings_read(config_path)

  # Standard directory names
  standard_dirs <- c(
    "notebooks", "scripts", "functions",
    "inputs_raw", "inputs_intermediate", "inputs_final",
    "inputs_reference",
    "outputs_private", "outputs_public",
    "outputs_docs", "outputs_docs_public",
    "cache", "scratch", "logs"
  )

  # Interactive prompts
  if (interactive) {
    if (is.null(directory)) {
      cat("Directory name (e.g., 'notebooks', 'scripts'): ")
      cat(sprintf("\nStandard directories: %s\n", paste(standard_dirs, collapse = ", ")))
      cat("Directory: ")
      directory <- readline()
      if (!nzchar(directory)) stop("Directory name is required")
    }

    # Show current value if it exists
    current_path <- config$directories[[directory]]
    if (!is.null(current_path)) {
      cat(sprintf("Current path: %s\n", current_path))
    }

    if (is.null(path)) {
      cat(sprintf("New path for '%s': ", directory))
      path <- readline()
      if (!nzchar(path)) stop("Directory path is required")
    }
  }

  # Initialize directories if needed
  if (is.null(config$directories)) {
    config$directories <- list()
  }

  # Update directory
  config$directories[[directory]] <- path

  # Write config
  settings_write(config, config_path)

  message(sprintf("\u2713 Directory '%s' set to '%s' in %s", directory, path, basename(config_path)))

  # Create directory if it doesn't exist
  if (!dir.exists(path)) {
    cat(sprintf("Create directory '%s'? [Y/n]: ", path))
    create_input <- if (interactive) readline() else "y"
    if (!tolower(create_input) %in% c("n", "no")) {
      dir.create(path, recursive = TRUE, showWarnings = FALSE)
      message(sprintf("  Created directory: %s", path))
    }
  }

  invisible(config)
}


# Internal validation helpers for configure_global()

.validate_author <- function(author) {
  if (is.null(author)) return(invisible(TRUE))

  checkmate::assert_list(author)
  # Allow empty strings for all author fields (they're optional)
  if (!is.null(author$name) && nzchar(author$name)) {
    checkmate::assert_string(author$name, min.chars = 1)
  }
  if (!is.null(author$email) && nzchar(author$email)) {
    checkmate::assert_string(author$email, min.chars = 1)
    if (!grepl("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", author$email)) {
      stop("author$email does not look like an email address: ", author$email, call. = FALSE)
    }
  }
  if (!is.null(author[["affiliation"]]) && nzchar(author[["affiliation"]])) {
    checkmate::assert_string(author[["affiliation"]], min.chars = 1)
  }
  if (!is.null(author$orcid)) checkmate::assert_string(author$orcid)
  if (!is.null(author$url)) checkmate::assert_string(author$url)
  if (!is.null(author$affiliations)) {
    checkmate::assert_list(author$affiliations)
    for (aff in author$affiliations) {
      checkmate::assert_list(aff)
      checkmate::assert_string(aff$name, min.chars = 1)
    }
  }

  invisible(TRUE)
}

.validate_defaults <- function(defaults) {
  if (is.null(defaults)) return(invisible(TRUE))

  checkmate::assert_list(defaults)

  # Validate project_type
  if (!is.null(defaults$project_type)) {
    checkmate::assert_choice(defaults$project_type,
                              choices = c("project", "project_sensitive", "presentation", "course", "bare"))
  }

  # Validate notebook_format
  if (!is.null(defaults$notebook_format)) {
    checkmate::assert_choice(defaults$notebook_format,
                              choices = c("quarto", "rmarkdown", "jupyter"))
  }

  # Validate ide
  if (!is.null(defaults$ide)) {
    checkmate::assert_choice(defaults$ide,
                              choices = c("vscode", "positron", "rstudio", "both", "none"))
  }

  # Validate booleans
  if (!is.null(defaults$use_git)) {
    checkmate::assert_flag(defaults$use_git)
  }
  if (!is.null(defaults$use_renv)) {
    checkmate::assert_flag(defaults$use_renv)
  }
  if (!is.null(defaults$seed_on_scaffold)) {
    checkmate::assert_flag(defaults$seed_on_scaffold)
  }
  if (!is.null(defaults$ai_support)) {
    checkmate::assert_flag(defaults$ai_support)
  }

  # Validate seed (can be NULL, numeric, or character)
  if (!is.null(defaults$seed)) {
    if (!is.numeric(defaults$seed) && !is.character(defaults$seed)) {
      stop("seed must be numeric or character")
    }
  }

  # Validate ai_assistants is a list or character vector
  if (!is.null(defaults$ai_assistants)) {
    checkmate::assert(
      checkmate::check_character(defaults$ai_assistants),
      checkmate::check_list(defaults$ai_assistants)
    )
  }

  # Validate packages is a list
  if (!is.null(defaults$packages)) {
    checkmate::assert_list(defaults$packages)
  }

  # Validate directories is a list
  if (!is.null(defaults$directories)) {
    checkmate::assert_list(defaults$directories)
  }

  # Validate git_hooks is a list
  if (!is.null(defaults$git_hooks)) {
    checkmate::assert_list(defaults$git_hooks)
  }

  if (!is.null(defaults$env)) {
    if (is.list(defaults$env)) {
      if (!is.null(defaults$env$raw)) {
        checkmate::assert_string(defaults$env$raw, min.chars = 0)
      }
      if (!is.null(defaults$env$variables)) {
        checkmate::assert_list(defaults$env$variables)
        if (length(defaults$env$variables) > 0 && is.null(names(defaults$env$variables))) {
          stop("defaults.env.variables must be a named list of key/value pairs")
        }
      }
    } else {
      checkmate::assert_string(defaults$env, min.chars = 0)
    }
    # Global settings sync to the cloud and seed every new project's .env
    env <- if (is.list(defaults$env)) defaults$env else list(raw = defaults$env)
    secrets <- .fw_secret_env_values(env$raw, env$variables)
    if (length(secrets) > 0) {
      stop(sprintf(
        "defaults.env: secret-looking variables must be empty in global settings (%s). Set the values in each project's .env.",
        paste(secrets, collapse = ", ")
      ))
    }
  }

  if (!is.null(defaults$connections)) {
    checkmate::assert_list(defaults$connections)
    if (!is.null(defaults$connections$options)) {
      checkmate::assert_list(defaults$connections$options)
      if (!is.null(defaults$connections$options$default_connection)) {
        checkmate::assert_string(defaults$connections$options$default_connection, min.chars = 1)
      }
    }
    if (!is.null(defaults$connections$connections)) {
      checkmate::assert_list(defaults$connections$connections)
      if (length(defaults$connections$connections) > 0 && is.null(names(defaults$connections$connections))) {
        stop("defaults.connections.connections must be a named list (connection entries keyed by name)")
      }
    }
  }

  invisible(TRUE)
}

.validate_projects <- function(projects) {
  if (is.null(projects)) return(invisible(TRUE))

  checkmate::assert_list(projects)

  invisible(TRUE)
}

.validate_active_project <- function(active_project) {
  if (is.null(active_project)) return(invisible(TRUE))

  checkmate::assert_string(active_project, min.chars = 1)

  invisible(TRUE)
}

.validate_projects_root <- function(projects_root) {
  if (is.null(projects_root)) return(invisible(TRUE))

  checkmate::assert_string(projects_root, min.chars = 1)

  invisible(TRUE)
}

.validate_project_types <- function(project_types) {
  if (is.null(project_types)) return(invisible(TRUE))

  checkmate::assert_list(project_types, names = "strict")

  for (type_name in names(project_types)) {
    entry <- project_types[[type_name]]
    checkmate::assert_list(entry, names = "unique")
    if (!is.null(entry$label) && nzchar(entry$label)) checkmate::assert_string(entry$label, min.chars = 1)
    if (!is.null(entry$description) && nzchar(entry$description)) checkmate::assert_string(entry$description, min.chars = 1)
    if (!is.null(entry$directories)) {
      # Accept both list and character vector (JSON arrays become character vectors)
      checkmate::assert(
        checkmate::check_list(entry$directories),
        checkmate::check_character(entry$directories)
      )
      for (dir_name in names(entry$directories)) {
        dir_value <- entry$directories[[dir_name]]
        # Skip empty strings (sent by GUI when field is cleared)
        if (!is.null(dir_value) && is.character(dir_value) && nzchar(dir_value)) {
          checkmate::assert_string(dir_value, min.chars = 1)
        }
      }
    }
    # Validate directories_enabled (should be a list of logicals)
    if (!is.null(entry$directories_enabled)) {
      checkmate::assert_list(entry$directories_enabled)
      for (key in names(entry$directories_enabled)) {
        checkmate::assert_logical(entry$directories_enabled[[key]], len = 1)
      }
    }
    if (!is.null(entry$quarto)) {
      checkmate::assert_list(entry$quarto)
      if (!is.null(entry$quarto$render_dir) && nzchar(entry$quarto$render_dir)) {
        checkmate::assert_string(entry$quarto$render_dir, min.chars = 1)
      }
    }
    if (!is.null(entry$notebook_template) && nzchar(entry$notebook_template)) {
      checkmate::assert_string(entry$notebook_template, min.chars = 1)
    }

    # Validate extra_directories
    if (!is.null(entry$extra_directories)) {
      checkmate::assert_list(entry$extra_directories)

      # Track keys to detect duplicates
      seen_keys <- character()

      for (i in seq_along(entry$extra_directories)) {
        dir_entry <- entry$extra_directories[[i]]

        # Must be a list with required fields
        if (!is.list(dir_entry)) {
          stop(sprintf("Project type '%s': extra_directories[%d] must be an object/list", type_name, i))
        }

        # Validate required fields
        if (is.null(dir_entry$key) || !nzchar(dir_entry$key)) {
          stop(sprintf("Project type '%s': extra_directories[%d] missing required field 'key'", type_name, i))
        }
        if (is.null(dir_entry$label) || !nzchar(dir_entry$label)) {
          stop(sprintf("Project type '%s': extra_directories[%d] missing required field 'label'", type_name, i))
        }
        if (is.null(dir_entry$path) || !nzchar(dir_entry$path)) {
          stop(sprintf("Project type '%s': extra_directories[%d] missing required field 'path'", type_name, i))
        }
        if (is.null(dir_entry$type) || !nzchar(dir_entry$type)) {
          stop(sprintf("Project type '%s': extra_directories[%d] missing required field 'type'", type_name, i))
        }

        # Validate key format (alphanumeric + underscore only)
        if (!grepl("^[a-zA-Z0-9_]+$", dir_entry$key)) {
          stop(sprintf("Project type '%s': extra_directories key '%s' must contain only letters, numbers, and underscores",
                       type_name, dir_entry$key))
        }

        # Check for duplicate keys
        if (dir_entry$key %in% seen_keys) {
          stop(sprintf("Project type '%s': duplicate extra_directories key '%s'", type_name, dir_entry$key))
        }
        seen_keys <- c(seen_keys, dir_entry$key)

        # Validate type
        valid_types <- c("input", "workspace", "output", "input_private", "input_public", "output_private", "output_public")
        if (!dir_entry$type %in% valid_types) {
          stop(sprintf("Project type '%s': extra_directories type '%s' must be one of: %s",
                       type_name, dir_entry$type, paste(valid_types, collapse = ", ")))
        }

        # Validate path is relative (no leading slash)
        if (grepl("^/", dir_entry$path)) {
          stop(sprintf("Project type '%s': extra_directories path '%s' must be relative (no leading slash)",
                       type_name, dir_entry$path))
        }

        # Prevent path traversal
        if (grepl("\\.\\.", dir_entry$path)) {
          stop(sprintf("Project type '%s': extra_directories path '%s' cannot contain '..' (path traversal)",
                       type_name, dir_entry$path))
        }
      }
    }
  }

  invisible(TRUE)
}

.validate_git_profile <- function(git) {
  if (is.null(git)) return(invisible(TRUE))

  checkmate::assert_list(git)
  # Empty strings are allowed (means use system git config)
  if (!is.null(git$user_name)) checkmate::assert_string(git$user_name, min.chars = 0)
  if (!is.null(git$user_email)) checkmate::assert_string(git$user_email, min.chars = 0)

  invisible(TRUE)
}

.validate_privacy <- function(privacy) {
  if (is.null(privacy)) return(invisible(TRUE))

  checkmate::assert_list(privacy)
  if (!is.null(privacy$secret_scan)) checkmate::assert_flag(privacy$secret_scan)
  if (!is.null(privacy$gitignore_template) && nzchar(privacy$gitignore_template)) {
    checkmate::assert_string(privacy$gitignore_template, min.chars = 1)
  }

  invisible(TRUE)
}


#' Configure Global Framework Settings
#'
#' Unified function for reading and writing global Framework settings. They
#' are stored in `settings.yml` and the project registry in `projects.yml`,
#' both in [fw_config_dir()].
#' This function provides a single source of truth for global configuration,
#' used by both the CLI and GUI interfaces.
#'
#' @param settings List. Settings to update (partial updates supported)
#' @param validate Logical. Validate settings before saving (default: TRUE)
#'
#' @return Invisibly returns updated global configuration
#'
#' @details
#' ## Global Settings Structure
#'
#' - `author` - Author information (name, email, affiliation)
#' - `defaults` - Project defaults
#'   - `project_type` - Default project type ("project", "project_sensitive",
#'     "presentation", "course", "bare")
#'   - `notebook_format` - Default notebook format ("quarto", "rmarkdown", "jupyter")
#'   - `ide` - IDE preference ("vscode", "rstudio", "both", "none")
#'   - `use_git` - Initialize git repositories by default
#'   - `use_renv` - Enable renv by default
#'   - `seed` - Default random seed
#'   - `seed_on_scaffold` - Set seed during scaffold()
#'   - `ai_support` - Enable AI assistant support
#'   - `ai_assistants` - List of AI assistants ("claude", "agents", etc.)
#'   - `ai_canonical_file` - Canonical AI instruction file
#'   - `packages` - Default package list
#'   - `directories` - Default directory structure
#'   - `git_hooks` - Git hook preferences
#' - `projects` - Registered projects list
#' - `active_project` - Currently active project path
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Update author information
#' configure_global(settings = list(
#'   author = list(
#'     name = "Jane Doe",
#'     email = "jane@example.com"
#'   )
#' ))
#'
#' # Update default project type
#' configure_global(settings = list(
#'   defaults = list(
#'     project_type = "presentation"
#'   )
#' ))
#'
#' # Get current settings (read-only)
#' current <- configure_global()
#' }
#' }
#'
#' @export
configure_global <- function(settings = NULL, validate = TRUE) {
  # Read current config
  current <- read_frameworkrc(use_defaults = TRUE)

  # If no settings provided, just return current config
  if (is.null(settings)) {
    return(invisible(current))
  }

  # Validate settings is a list
  checkmate::assert_list(settings, null.ok = FALSE)

  # Merge settings with current config (deep merge, keeping NULL values)
  updated <- modifyList(current, settings, keep.null = TRUE)

  # Ensure global section exists and preserve incoming global.projects_root
  if (!is.null(settings$global$projects_root)) {
    if (is.null(updated$global)) updated$global <- list()
    updated$global$projects_root <- settings$global$projects_root
  }

  # CRITICAL FIX: modifyList() doesn't handle unnamed lists (arrays) correctly
  # It replaces them with empty lists. We need to manually restore extra_directories
  # for all project types after the merge.
  # ALSO: modifyList() merges nested objects, so deleted directory fields persist.
  # We need to completely replace directories and extra_directories from settings.
  if (!is.null(settings$project_types)) {
    for (type_name in names(settings$project_types)) {
      # Replace directories completely (don't merge, to allow deletions)
      if (!is.null(settings$project_types[[type_name]]$directories)) {
        # Filter out empty strings sent by GUI when fields are cleared
        dirs <- settings$project_types[[type_name]]$directories
        # Handle both character vectors (from JSON) and lists
        if (is.character(dirs)) {
          dirs <- as.list(dirs[nzchar(dirs)])
        } else {
          dirs <- Filter(function(x) !is.null(x) && nzchar(x), dirs)
        }
        updated$project_types[[type_name]]$directories <- dirs
      }
      # Replace extra_directories completely (bypassing modifyList's broken array behavior)
      if (!is.null(settings$project_types[[type_name]]$extra_directories)) {
        updated$project_types[[type_name]]$extra_directories <-
          settings$project_types[[type_name]]$extra_directories
      }
      # Replace directories_enabled completely (toggle states for each directory)
      if (!is.null(settings$project_types[[type_name]]$directories_enabled)) {
        updated$project_types[[type_name]]$directories_enabled <-
          settings$project_types[[type_name]]$directories_enabled
      }
    }
  }

  # CRITICAL FIX: Same issue with defaults.packages array
  if (!is.null(settings$defaults$packages)) {
    updated$defaults$packages <- settings$defaults$packages
  }
  if (!is.null(settings$defaults$connections)) {
    updated$defaults$connections <- settings$defaults$connections
  }
  if (!is.null(settings$defaults$env)) {
    updated$defaults$env <- settings$defaults$env
  }

  # Normalize seed values: treat empty lists/booleans as unset (NULL) so validation passes
  sanitize_seed <- function(value) {
    if (is.null(value)) return(NULL)
    if (is.list(value) && length(value) == 0) return(NULL)
    if (is.logical(value)) return(NULL)
    value
  }

  updated$defaults["seed"] <- list(sanitize_seed(updated$defaults$seed))
  if (!is.null(updated$defaults$scaffold)) {
    updated$defaults$scaffold["seed"] <- list(sanitize_seed(updated$defaults$scaffold$seed))
  }

  # Validate if requested
  if (validate) {
    .validate_author(updated$author)
    .validate_defaults(updated$defaults)
    .validate_projects(updated$projects)
    .validate_projects_root(updated$projects_root)
    .validate_projects_root(updated$global$projects_root)  # Also validate nested v2 format
    .validate_project_types(updated$project_types)
    .validate_git_profile(updated$git)
    .validate_privacy(updated$privacy)
  }

  if (!is.null(updated$projects_root)) {
    if (!nzchar(updated$projects_root)) {
      updated$projects_root <- NULL
    } else {
      updated$projects_root <- path.expand(updated$projects_root)
    }
  }

  # Handle v2 global.projects_root (nested under global)
  if (!is.null(updated$global$projects_root)) {
    if (!nzchar(updated$global$projects_root)) {
      updated$global$projects_root <- NULL
    } else {
      updated$global$projects_root <- path.expand(updated$global$projects_root)
    }
  }

  if (!is.null(updated$project_types) && !is.null(updated$project_types$project$directories)) {
    updated$defaults$directories <- updated$project_types$project$directories
  }

  # Convert paths to tilde notation before saving (for portability)
  updated_for_save <- updated

  if (!is.null(updated_for_save$projects_root)) {
    updated_for_save$projects_root <- .path_to_tilde(updated_for_save$projects_root)
  }
  if (!is.null(updated_for_save$global$projects_root)) {
    updated_for_save$global$projects_root <- .path_to_tilde(updated_for_save$global$projects_root)
  }

  # Write updated config
  write_frameworkrc(updated_for_save)

  if (validate) {
    message("[ok] Global settings updated in ", file.path(fw_config_dir(), "settings.yml"))
  }

  invisible(updated)
}

#' Get Global Configuration Setting
#'
#' Retrieve a specific setting from the global configuration file (~/.frameworkrc.json).
#' This is a helper function primarily for use by the CLI script.
#'
#' @param key Character. The setting key to retrieve (e.g., "defaults.ide", "author.name")
#' @param default Character. Default value if setting is not found (default: "")
#' @param print Logical. If TRUE, prints the value (for bash consumption). Default TRUE.
#'
#' @return The setting value as a character string
#'
#' @keywords internal
get_global_setting <- function(key, default = "", print = TRUE) {
  checkmate::assert_string(key)
  checkmate::assert_string(default)
  checkmate::assert_flag(print)

  config <- read_frameworkrc(use_defaults = TRUE)

  # Navigate nested keys (e.g., "defaults.ide" -> config$defaults$ide)
  keys <- strsplit(key, "\\.")[[1]]
  value <- config

  for (k in keys) {
    if (is.list(value) && k %in% names(value)) {
      value <- value[[k]]
    } else {
      value <- default
      break
    }
  }

  # Convert to character
  result <- if (is.null(value)) {
    default
  } else if (is.character(value)) {
    value
  } else if (is.logical(value)) {
    tolower(as.character(value))
  } else {
    as.character(value)
  }

  if (print) {
    message(result)
  }

  invisible(result)
}

#' Convert Path to Tilde Notation
#'
#' Internal helper to convert absolute paths to tilde notation for portable storage.
#' Paths like "/Users/username/code" become "~/code" for cross-platform compatibility.
#'
#' @param path Character. Absolute path to convert
#'
#' @return Character. Path with tilde notation if under home directory, otherwise unchanged
#'
#' @keywords internal
#' @noRd
.path_to_tilde <- function(path) {
  # Return unchanged if NULL, empty, or already uses tilde
  if (is.null(path) || path == "" || grepl("^~", path)) {
    return(path)
  }

  # Get home directory (cross-platform)
  home <- path.expand("~")

  # Fallback to environment variables if path.expand fails
  if (is.null(home) || home == "~") {
    home <- Sys.getenv("HOME")
    if (home == "") {
      home <- Sys.getenv("USERPROFILE")  # Windows fallback
    }
  }

  # Normalize paths for comparison (handle trailing slashes, etc.)
  home <- normalizePath(home, mustWork = FALSE)
  path_normalized <- normalizePath(path, mustWork = FALSE)

  # Replace home directory with tilde if path starts with home
  if (startsWith(path_normalized, home)) {
    # Get the relative portion after home directory
    relative_part <- substr(path_normalized, nchar(home) + 1, nchar(path_normalized))

    # Remove leading slash if present
    relative_part <- sub("^[/\\\\]", "", relative_part)

    # Remove trailing slash from relative part
    relative_part <- sub("[/\\\\]$", "", relative_part)

    # Construct tilde path
    if (relative_part == "") {
      return("~")
    } else {
      return(file.path("~", relative_part))
    }
  }

  # Return unchanged if not under home directory
  return(path)
}
