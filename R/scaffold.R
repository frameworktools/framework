#' Initialize and load the project environment
#'
#' The primary entry point for working with Framework projects. Call this at the
#' start of every notebook or script to set up your environment with all
#' configured packages, functions, and settings.
#'
#' @param config_file Path to configuration file. If NULL (default), automatically
#'   discovers settings.yml or config.yml in the project.
#'
#' @details
#' `scaffold()` performs the following steps in order:
#'
#' 1. **Standardizes working directory** - Finds and sets the project root, even when called from notebooks in subdirectories
#' 2. **Loads environment variables** - Reads secrets from `.env` file
#' 3. **Loads configuration** - Parses settings.yml for project settings
#' 4. **Sets random seed** - For reproducibility (if `seed` is configured)
#' 5. **Installs packages** - Any missing packages from the `packages` list
#' 6. **Loads packages** - Attaches all configured packages
#' 7. **Sources functions** - Loads all `.R` files from `functions/` directory
#' 8. **Sources scaffold.R** - Runs the project's `scaffold.R`, if there is one
#' 9. **Makes the first git commit** - In a git repository with no commits
#'    yet, stages every file `.gitignore` allows and commits it as
#'    "Project initialized." This covers projects whose creation skipped that
#'    commit, for example when git had no user name or email. Repositories
#'    with commits are left alone.
#'
#' After `scaffold()` completes, you have access to:
#' - All packages listed in settings.yml
#' - All functions from your `functions/` directory
#' - Settings via `settings("key")` helper function
#' - Database connections configured in your project
#'
#' @section Project Discovery:
#' When called without arguments, `scaffold()` searches for a Framework project by:
#' - Looking for settings.yml or config.yml in current and parent directories
#' - Checking for .Rproj or .code-workspace files with nearby settings
#' - Recognizing common Framework subdirectories (notebooks/, scripts/, etc.)
#'
#' This means you can call `scaffold()` from any subdirectory within your project.
#'
#' @section Configuration:
#' The settings.yml file controls what `scaffold()` loads. Key settings include:
#' - `packages`: List of R packages to install and load
#' - `seed`: Random seed for reproducibility
#' - `directories`: Custom directory paths
#' - `connections`: Database connection configurations
#'
#' @return Invisibly returns NULL. The main effects are side effects:
#'   loading packages and sourcing functions. No `config` object is created;
#'   read settings with [settings()] or [settings_read()].
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # At the top of every notebook or script:
#' library(framework)
#' scaffold()
#'
#' # Now you can use your configured packages and functions
#' # Access settings via the settings() helper:
#' settings("directories.notebooks")
#' settings("seed")
#' }
#' }
#'
#' @seealso
#' - [project_create()] to create a new Framework project
#' - [standardize_wd()] for just the working directory standardization
#' - [settings()] to access configuration values after scaffolding
#'
#' @export
scaffold <- function(config_file = NULL) {
  # Standardize working directory first (for notebooks in subdirectories)
  project_root <- standardize_wd()

  # Auto-discover settings file if not specified
  if (is.null(config_file)) {
    # Look in project root if we found it, otherwise current directory
    search_dir <- if (!is.null(project_root)) project_root else "."
    config_file <- .get_settings_file(search_dir)
    if (is.null(config_file)) {
      config_file <- NA  # Will trigger error below
    } else {
      config_file <- basename(config_file)
    }
  }

  # Fail fast if not in a Framework project
  if (is.null(project_root) || is.na(config_file)) {
    stop(
      "Could not locate a Framework project.\n",
      "scaffold() searches for a project by looking for:\n",
      "  - settings.yml or config.yml in current or parent directories\n",
      "  - .Rproj or .code-workspace file with settings file nearby\n",
      "  - Common subdirectories (notebooks/, scripts/, etc.)\n",
      "Current directory: ", getwd(), "\n",
      "To create a new project, use: project_create()"
    )
  }

  # When running in knitr, working directory might still be nested
  # so we need to check for config file relative to project root
  if (!file.exists(config_file) && !is.null(project_root)) {
    config_path_from_root <- file.path(project_root, config_file)
    if (file.exists(config_path_from_root)) {
      config_file <- config_path_from_root
    }
  }

  # Final check that config file exists
  if (!file.exists(config_file)) {
    stop(
      "Could not locate a Framework project.\n",
      "scaffold() searches for a project by looking for:\n",
      "  - settings.yml or config.yml in current or parent directories\n",
      "  - .Rproj or .code-workspace file with settings file nearby\n",
      "  - Common subdirectories (notebooks/, scripts/, etc.)\n",
      "Current directory: ", getwd(), "\n",
      "Project root found: ", if (!is.null(project_root)) project_root else "none", "\n",
      "To create a new project, use: project_create()"
    )
  }

  # Only load package if not already loaded
  if (!"package:framework" %in% search()) {
    message("Loading framework package...")
    library(framework)
  }

  .load_environment(config_file, project_root)

  # Load configuration for internal use
  config_obj <- .load_configuration(config_file)

  # Private folders are ignored by git, so a fresh checkout lacks them;
  # create them so code that saves into them works
  .fw_create_private_folders(project_root, config_obj)

  # Mark as scaffolded with timestamp
  .mark_scaffolded(project_root)

  # Ensure framework database exists
  .ensure_framework_db(project_root)

  # Set random seed for reproducibility (if configured)
  .set_random_seed(config_obj)

  # Set ggplot2 theme if configured
  .set_ggplot_theme(config_obj)

  .install_required_packages(config_obj)
  .load_libraries(config_obj)
  .load_functions(config_file, project_root)

  # Source scaffold.R if it exists in project root
  scaffold_r_path <- if (!is.null(project_root)) {
    file.path(project_root, "scaffold.R")
  } else {
    "scaffold.R"
  }
  if (file.exists(scaffold_r_path)) {
    source(scaffold_r_path)
  }

  # Create initial commit after first successful scaffold (if in git repo and no commits yet)
  .commit_after_scaffold()

  # Check git status and provide helpful reminder
  .check_git_status()
}

#' Load environment variables from .env file
#' @keywords internal
.load_environment <- function(config_file = NULL, project_root = NULL) {
  # Auto-discover settings file if not provided
  if (is.null(config_file)) {
    search_dir <- if (!is.null(project_root)) project_root else "."
    config_file <- .get_settings_file(search_dir)
    if (!is.null(config_file)) {
      config_file <- basename(config_file)
    } else {
      # No settings file found, skip env loading
      return(invisible(NULL))
    }
  }

  config <- settings_read(config_file)

  # Only check root level dotenv_location (not nested in options)
  if (!is.null(config$dotenv_location)) {
    dotenv_path <- config$dotenv_location

    # Make path absolute relative to project root
    if (!is.null(project_root) && !grepl("^(/|[A-Za-z]:)", dotenv_path)) {
      dotenv_path <- file.path(project_root, dotenv_path)
    }

    if (dir.exists(dotenv_path)) {
      dotenv_path <- file.path(dotenv_path, ".env")
    }

    if (!file.exists(dotenv_path)) {
      stop(sprintf("Dotenv file not found at '%s'", dotenv_path))
    }

    # Shell values win and empty lines are skipped, as in settings_read()
    .fw_load_dotenv(dotenv_path)
  } else {
    # Only load .env if it exists (optional for projects without secrets)
    # Look in project root if available
    env_path <- if (!is.null(project_root)) {
      file.path(project_root, ".env")
    } else {
      ".env"
    }

    if (file.exists(env_path)) {
      .fw_load_dotenv(env_path)
    }
  }
}

#' Load configuration from settings file
#' @keywords internal
.load_configuration <- function(config_file = NULL) {
  # Auto-discover if not provided
  if (is.null(config_file)) {
    config_file <- .get_settings_file(".")
    if (!is.null(config_file)) {
      config_file <- basename(config_file)
    } else {
      stop("No settings.yml or config.yml file found")
    }
  }

  settings_read(config_file)
}

#' Get package requirements from config
#' @param config Configuration object from settings_read()
#' @keywords internal
.get_package_requirements <- function(config) {
  if (is.null(config$packages)) {
    return(character())
  }

  # Get package list (handles both old and new config structures)
  package_list <- .get_package_list_from_config(config)

  # Extract package names and their loading behavior
  packages <- lapply(package_list, function(pkg) {
    spec <- tryCatch(
      .parse_package_spec(pkg),
      error = function(e) {
        warning("Failed to parse package specification: ", conditionMessage(e))
        return(NULL)
      }
    )

    if (is.null(spec)) {
      return(NULL)
    }

    list(
      name = spec$name,
      load = isTRUE(spec$auto_attach),
      spec = spec
    )
  })

  # Filter out NULLs and return
  packages <- packages[!sapply(packages, is.null)]
  packages
}

#' Install a package if not already installed
#' @param pkg_spec Package specification (may include version pin)
#' @keywords internal
.install_package <- function(pkg_spec) {
  # Parse the package specification
  spec <- .parse_package_spec(pkg_spec)

  # Check if already installed
  already_installed <- requireNamespace(spec$name, quietly = TRUE)

  # If installed and no version pin, skip
  if (already_installed && is.null(spec$version)) {
    return(invisible(TRUE))
  }

  # If installed with version pin, check version
  if (already_installed && !is.null(spec$version)) {
    installed_ver <- as.character(packageVersion(spec$name))
    if (installed_ver == spec$version) {
      return(invisible(TRUE))
    }
  }

  # Route installation based on renv status
  if (renv_enabled()) {
    .install_package_renv(spec)
  } else {
    .install_package_base(spec)
  }

  invisible(TRUE)
}

#' Install required packages from config
#' @param config Configuration object from settings_read()
#' @keywords internal
.install_required_packages <- function(config) {
  packages <- .get_package_requirements(config)
  for (pkg in packages) {
    .install_package(pkg$spec)
  }
}

#' Load all libraries specified in config
#' @param config Configuration object from settings_read()
#' @keywords internal
.load_libraries <- function(config) {
  packages <- .get_package_requirements(config)

  # Check if verbose mode is enabled
  verbose <- isTRUE(config$options$verbose_scaffold)

  for (pkg in packages) {
    if (pkg$load) {
      if (verbose) {
        message(sprintf("Loading library: %s", pkg$name))
      }
      suppressPackageStartupMessages(
        library(pkg$name, character.only = TRUE)
      )
    }
  }
}

#' Load all R files from functions directories
#' @keywords internal
.load_functions <- function(config_file = NULL, project_root = NULL) {
  # Auto-discover settings file if not provided
  if (is.null(config_file)) {
    search_dir <- if (!is.null(project_root)) project_root else "."
    config_file <- .get_settings_file(search_dir)
    if (!is.null(config_file)) {
      config_file <- basename(config_file)
    } else {
      # No settings file, use default
      func_dir_path <- if (!is.null(project_root)) {
        file.path(project_root, "functions")
      } else {
        "functions"
      }
      if (dir.exists(func_dir_path)) {
        func_files <- list.files(func_dir_path, pattern = "\\.R$", full.names = TRUE)
        for (file in func_files) {
          source(file, local = FALSE)
        }
        if (length(func_files) > 0) {
          message(sprintf("Loaded %d function(s) from %s", length(func_files), func_dir_path))
        }
      }
      return(invisible(NULL))
    }
  }

  config <- settings_read(config_file)

  # Check if user opted out of sourcing all functions (default: TRUE).
  # New projects keep it under scaffold:; older ones under options: or at
  # the top level
  source_all <- config$scaffold$source_all_functions %||%
    config$options$source_all_functions %||%
    config$source_all_functions
  if (is.null(source_all)) {
    source_all <- TRUE  # Default to including all functions
  }

  if (!isTRUE(source_all)) {
    return(invisible(NULL))
  }

  # Get function directories from config (can be list or single value)
  func_dirs <- config$directories$functions %||% config$options$functions_dir

  # Default to "functions" if not configured
  if (is.null(func_dirs)) {
    func_dirs <- "functions"
  }

  # Ensure it's a list for consistent processing
  if (!is.list(func_dirs) && is.character(func_dirs)) {
    func_dirs <- as.list(func_dirs)
  }

  # Track if we loaded any functions
  loaded_any <- FALSE

  # Load functions from each directory
  for (func_dir in func_dirs) {
    # Make path absolute relative to project root if needed
    if (!is.null(project_root) && !grepl("^(/|[A-Za-z]:)", func_dir)) {
      func_dir <- file.path(project_root, func_dir)
    }

    if (dir.exists(func_dir)) {
      func_files <- list.files(func_dir, pattern = "\\.R$", full.names = TRUE)
      if (length(func_files) > 0) {
        for (file in func_files) {
          source(file, local = FALSE)
        }
        message(sprintf("Loaded %d function(s) from %s", length(func_files), func_dir))
        loaded_any <- TRUE
      }
    }
  }

  # Only warn if no directories exist at all
  if (!loaded_any && length(func_dirs) == 1 && func_dirs[[1]] == "functions") {
    # Silent if using default and it doesn't exist (common case)
    invisible(NULL)
  } else if (!loaded_any) {
    # Warn if user explicitly configured directories but none exist
    warning(sprintf("No function directories found: %s", paste(unlist(func_dirs), collapse = ", ")))
  }
}

#' Mark project as scaffolded
#' @param project_root Optional project root where the scaffold marker should
#'   be written. Falls back to the current working directory when NULL.
#' @keywords internal
.mark_scaffolded <- function(project_root = NULL) {
  marker_path <- ".framework_scaffolded"
  if (!is.null(project_root)) {
    marker_path <- file.path(project_root, ".framework_scaffolded")
  }

  timestamp <- lubridate::now(tzone = "UTC")

  # Migrate legacy marker file if it exists (either at explicit root or CWD)
  legacy_history <- NULL
  legacy_paths <- unique(c(marker_path, ".framework_scaffolded"))

  for (legacy_path in legacy_paths) {
    if (file.exists(legacy_path)) {
      legacy_lines <- readLines(legacy_path, warn = FALSE)
      legacy_history <- .parse_scaffold_marker_lines(legacy_lines)
      # Remove the legacy marker once captured so we stop littering directories
      tryCatch(file.remove(legacy_path), warning = function(...) NULL, error = function(...) NULL)
      break
    }
  }

  # Ensure the Framework database exists before we persist metadata
  .ensure_framework_db(project_root)

  existing_history <- .get_scaffold_history(project_root)

  first_scaffold <- if (!is.null(existing_history$first)) {
    existing_history$first
  } else if (!is.null(legacy_history$first)) {
    legacy_history$first
  } else {
    timestamp
  }

  history <- list(
    first = .format_scaffold_timestamp(first_scaffold),
    last = .format_scaffold_timestamp(timestamp)
  )

  .set_metadata("scaffold_history", jsonlite::toJSON(history, auto_unbox = TRUE), project_root)

  invisible(history)
}

#' Retrieve scaffold metadata from the database
#' @keywords internal
.get_scaffold_history <- function(project_root = NULL) {
  raw <- .get_metadata("scaffold_history", project_root)
  if (is.null(raw) || is.na(raw) || trimws(raw) == "") {
    return(list())
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(raw),
    error = function(...) NULL
  )

  if (is.null(parsed)) {
    return(list())
  }

  # Parse timestamps back to POSIXct when possible
  parsed$first <- .parse_scaffold_timestamp(parsed$first)
  parsed$last <- .parse_scaffold_timestamp(parsed$last)

  parsed
}

#' @keywords internal
.parse_scaffold_marker_lines <- function(lines) {
  if (length(lines) == 0) {
    return(list())
  }

  first_line <- lines[grepl("^First scaffolded at:", lines)][1]
  last_line <- lines[grepl("^Last scaffolded at:", lines)][1]

  list(
    first = .parse_scaffold_timestamp(sub("^First scaffolded at:\\s*", "", first_line)),
    last = .parse_scaffold_timestamp(sub("^Last scaffolded at:\\s*", "", last_line))
  )
}

#' @keywords internal
.parse_scaffold_timestamp <- function(value) {
  if (is.null(value) || is.na(value) || trimws(value) == "") {
    return(NULL)
  }

  parsed <- suppressWarnings(lubridate::ymd_hms(value, tz = "UTC"))
  if (is.na(parsed)) {
    parsed <- suppressWarnings(lubridate::ymd_hms(value))
  }
  if (is.na(parsed)) {
    return(NULL)
  }

  parsed
}

#' @keywords internal
.format_scaffold_timestamp <- function(value) {
  if (is.null(value) || is.na(value)) {
    return(NA_character_)
  }

  value_utc <- lubridate::with_tz(value, tzone = "UTC")
  format(value_utc, "%Y-%m-%dT%H:%M:%OSZ")
}

#' Ensure framework database exists with all required tables
#' @param project_root Optional project root used to resolve the database path.
#' @keywords internal
.ensure_framework_db <- function(project_root = NULL) {
  if (is.null(project_root)) {
    project_root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  }
  db_path <- if (!is.null(project_root)) file.path(project_root, "framework.db") else "framework.db"

  # Required tables and their CREATE statements
  required_tables <- list(
    results = "CREATE TABLE IF NOT EXISTS results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE,
      type TEXT,
      public BOOLEAN,
      blind BOOLEAN,
      comment TEXT,
      hash TEXT,
      last_read_at DATETIME,
      created_at DATETIME,
      updated_at DATETIME,
      deleted_at DATETIME
    )",
    data = "CREATE TABLE IF NOT EXISTS data (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE,
      path TEXT,
      type TEXT,
      delimiter TEXT,
      locked BOOLEAN,
      encrypted BOOLEAN,
      hash TEXT,
      last_read_at DATETIME,
      created_at DATETIME,
      updated_at DATETIME,
      deleted_at DATETIME
    )",
    cache = "CREATE TABLE IF NOT EXISTS cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE,
      file_path TEXT,
      hash TEXT,
      expire_at DATETIME,
      last_read_at DATETIME,
      created_at DATETIME,
      updated_at DATETIME,
      deleted_at DATETIME
    )",
    connections = "CREATE TABLE IF NOT EXISTS connections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE,
      driver TEXT,
      host TEXT,
      port INTEGER,
      database TEXT,
      schema TEXT,
      user TEXT,
      password TEXT,
      last_used_at DATETIME,
      created_at DATETIME,
      updated_at DATETIME,
      deleted_at DATETIME
    )",
    meta = "CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT,
      created_at DATETIME,
      updated_at DATETIME
    )"
  )

  db_existed <- file.exists(db_path)

  # Connect (creates file if doesn't exist)
  con <- tryCatch(
    DBI::dbConnect(RSQLite::SQLite(), db_path),
    error = function(e) {
      warning("Could not connect to framework.db: ", e$message)
      return(NULL)
    }
  )

  if (is.null(con)) {
    return(invisible(NULL))
  }

  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Get existing tables
  existing_tables <- DBI::dbListTables(con)

  # Create any missing tables

  tables_created <- character(0)
  for (table_name in names(required_tables)) {
    if (!table_name %in% existing_tables) {
      tryCatch({
        DBI::dbExecute(con, required_tables[[table_name]])
        tables_created <- c(tables_created, table_name)
      }, error = function(e) {
        warning(sprintf("Could not create table '%s': %s", table_name, e$message))
      })
    }
  }

  # Report what happened

  if (!db_existed) {
    message("\u2713 Created framework.db with schema")
  } else if (length(tables_created) > 0) {
    message(sprintf("\u2713 Added missing tables to framework.db: %s", paste(tables_created, collapse = ", ")))
  }

  invisible(NULL)
}

#' Set random seed for reproducibility
#' @param config Configuration object from settings_read()
#' @keywords internal
#' @description
#' Sets the random seed for reproducibility. Checks for seed in this order:
#' 1. Project settings.yml (seed: value)
#' 2. Global ~/.frameworkrc (FW_SEED)
#' 3. Skip seeding if both are NULL or empty
.set_random_seed <- function(config) {
  # New projects write these under scaffold: (settings/scaffold.yml); older
  # ones under options: or the top level
  seed_on <- config$scaffold$seed_on_scaffold %||% config$options$seed_on_scaffold %||%
    config$seed_on_scaffold
  project_seed <- config$scaffold$seed %||% config$seed %||% config$options$seed
  project_seed <- suppressWarnings(as.integer(project_seed))
  if (length(project_seed) == 0 || is.na(project_seed)) project_seed <- NULL
  global_seed <- suppressWarnings(as.integer(Sys.getenv("FW_SEED", "")))
  if (is.na(global_seed)) global_seed <- NULL

  # The project decides: an explicit seed_on_scaffold: false skips seeding
  # even when FW_SEED is set. Without a project setting, FW_SEED turns it on.
  if (isFALSE(seed_on)) {
    return(invisible(NULL))
  }
  if (is.null(seed_on) && is.null(global_seed)) {
    return(invisible(NULL))
  }

  # The project's seed wins over the user-wide FW_SEED
  seed_value <- project_seed %||% global_seed %||% 123L

  set.seed(seed_value)
  message(sprintf("Random seed set to %s.", seed_value))

  invisible(NULL)
}

#' Set ggplot2 theme for consistent styling
#' @param config Configuration object from settings_read()
#' @keywords internal
#' @description
#' Sets ggplot2 theme if configured. Checks for theme settings in this order:
#' 1. Project settings (scaffold:, then options:, then the top level)
#' 2. Skip if set_theme_on_scaffold is FALSE or theme is empty
.set_ggplot_theme <- function(config) {
  # New projects write these under scaffold: (settings/scaffold.yml); older
  # ones under options: or the top level
  set_theme_on <- config$scaffold$set_theme_on_scaffold %||%
                  config$options$set_theme_on_scaffold %||%
                  config$set_theme_on_scaffold %||%
                  FALSE

  if (!isTRUE(set_theme_on)) {
    return(invisible(NULL))
  }

  theme_name <- config$scaffold$ggplot_theme %||%
                config$options$ggplot_theme %||%
                config$ggplot_theme %||%
                ""

  # Skip if no theme specified
  if (!nzchar(theme_name)) {
    return(invisible(NULL))
  }

  # Check if ggplot2 is available
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    warning("set_theme_on_scaffold is enabled but ggplot2 is not installed")
    return(invisible(NULL))
  }

  # Get the theme function
  theme_func <- tryCatch({
    get(theme_name, envir = asNamespace("ggplot2"))
  }, error = function(e) {
    warning(sprintf("ggplot2 theme '%s' not found, skipping theme_set()", theme_name))
    return(NULL)
  })

  if (!is.null(theme_func) && is.function(theme_func)) {
    ggplot2::theme_set(theme_func())
    message(sprintf("ggplot2 theme set to %s.", theme_name))
  }

  invisible(NULL)
}

#' Check git status and provide helpful reminder
#' @keywords internal
.check_git_status <- function() {
  # Check if git is installed
  if (!nzchar(Sys.which("git"))) {
    return(invisible(NULL))
  }

  # Check if we're in a git repo
  git_available <- tryCatch({
    result <- system2("git", c("rev-parse", "--git-dir"), stdout = TRUE, stderr = TRUE)
    !is.null(attr(result, "status")) && attr(result, "status") == 0 || is.null(attr(result, "status"))
  }, error = function(e) FALSE, warning = function(w) FALSE)

  if (!git_available) {
    return(invisible(NULL))
  }

  # Check for uncommitted changes
  status_result <- tryCatch({
    system2("git", c("status", "--porcelain"), stdout = TRUE, stderr = FALSE)
  }, error = function(e) NULL, warning = function(w) NULL)

  if (is.null(status_result) || length(status_result) == 0) {
    return(invisible(NULL))
  }

  # Count changes
  n_changes <- length(status_result)

  if (n_changes > 0) {
    invisible(NULL)
  }

  invisible(NULL)
}

#' Create initial commit after first successful scaffold
#' @keywords internal
#' @note This function is now deprecated. Initial commits are created during project_create()
#'   instead of scaffold(). Kept for backward compatibility with older projects.
.commit_after_scaffold <- function() {
  # Check if git is installed
  if (!nzchar(Sys.which("git"))) {
    return(invisible(NULL))
  }

  # Check if we're in a repo
  git_available <- tryCatch({
    system2(
      "git",
      c("rev-parse", "--git-dir"),
      stdout = FALSE,
      stderr = FALSE
    ) == 0
  }, error = function(e) FALSE, warning = function(w) FALSE)

  if (!git_available) {
    return(invisible(NULL))
  }

  # Check if there are any commits yet
  has_commits <- tryCatch({
    system2(
      "git",
      c("rev-parse", "HEAD"),
      stdout = FALSE,
      stderr = FALSE
    ) == 0
  }, error = function(e) FALSE, warning = function(w) FALSE)

  # Only create commit if this is first scaffold (no commits yet)
  # This handles the case where older projects initialized before project_create() created commits
  if (!has_commits) {
    # No commits yet - add and commit everything
    tryCatch({
      # Add all files (including any created after project_create, like .github/)
      system2("git", c("add", "-A"), stdout = FALSE, stderr = FALSE)
      commit_result <- system2(
        "git",
        c("commit", "-m", shQuote("Project initialized.")),
        stdout = FALSE,
        stderr = FALSE
      )
      if (commit_result == 0) {
        message("\u2713 Initial commit created")
      }
    }, error = function(e) {
      # Silent failure - user may not have git configured
      invisible(NULL)
    })
  }

  invisible(NULL)
}

# Create the settings' private folders that don't exist: directories whose
# key contains "private" and not "public" (inputs_private_raw), inside the
# project. Returns the folders created, invisibly.
#' @keywords internal
.fw_create_private_folders <- function(project_root, config) {
  if (is.null(project_root) || !is.list(config)) return(invisible(character()))
  dirs <- .configured_directories(config)
  keys <- tolower(names(dirs))
  dirs <- dirs[grepl("private", keys, fixed = TRUE) & !grepl("public", keys, fixed = TRUE)]
  dirs <- dirs[!vapply(dirs, function(p) .fw_outside_root(project_root, p), logical(1))]
  made <- character()
  for (folder in unique(unlist(dirs, use.names = FALSE))) {
    path <- .fw_folder_abs(project_root, folder)
    if (!dir.exists(path) && dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
      made <- c(made, .fw_relative_folder(project_root, folder))
    }
  }
  if (length(made) > 0) message("Created private folders: ", paste(made, collapse = ", "))
  invisible(made)
}
