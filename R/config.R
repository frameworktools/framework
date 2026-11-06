#' Get settings value by dot-notation key
#'
#' Framework's primary configuration helper that supports both flat and hierarchical
#' key access using dot notation. Automatically checks common locations for
#' directory settings. Pretty-prints nested structures in interactive sessions.
#'
#' @param key Character. Dot-notation key path (e.g., "notebooks" or
#'   "directories.notebooks" or "connections.db.host"). If NULL, returns entire settings.
#' @param default Optional default value if key is not found (default: NULL)
#' @param settings_file Settings file path (default: checks "settings.yml" then "settings.yml")
#'
#' @return The settings value, or default if not found. In interactive sessions,
#'   nested structures are pretty-printed and returned invisibly.
#'
#' @details
#' For directory settings, the function checks multiple locations:
#' - Direct: `settings("notebooks")` checks `directories$notebooks`, then `options$notebook_dir`
#' - Explicit: `settings("directories.notebooks")` checks only `directories$notebooks`
#'
#' **File Discovery:**
#' - Checks `settings.yml` first (Framework's preferred convention)
#' - Falls back to `settings.yml` if settings.yml not found
#' - You can override with explicit `settings_file` parameter
#'
#' **Output Behavior:**
#' - Interactive sessions: Pretty-prints nested lists/structures and returns invisibly
#' - Non-interactive (scripts): Returns raw value without printing
#' - Simple values: Always returned directly without modification
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Get notebook directory (checks both locations)
#' settings("notebooks")
#'
#' # Get explicit nested setting
#' settings("directories.notebooks")
#' settings("connections.db.host")
#'
#' # Get entire section
#' settings("directories")  # Returns all directory settings
#' settings("connections")  # Returns all connection settings
#'
#' # View entire settings
#' settings()  # Returns full configuration
#'
#' # With default value
#' settings("missing_key", default = "fallback")
#' }
#' }
#'
#' @export
settings <- function(key = NULL, default = NULL, settings_file = NULL) {
  # Discover settings file if not specified
  if (is.null(settings_file)) {
    settings_file <- .get_settings_file()
  }

  if (is.null(settings_file)) {
    stop("No settings file found. Looking for settings.yml or config.yml")
  }

  # Read full settings
  cfg <- settings_read(settings_file)

  # If no key provided, return entire config with pretty-printing
  if (is.null(key)) {
    return(.pretty_print_config(cfg))
  }

  # Split key by dots
  parts <- strsplit(key, "\\.")[[1]]

  # For single-part keys, try smart directory lookups
  if (length(parts) == 1) {
    # Check directories first
    if (!is.null(cfg$directories[[key]])) {
      return(cfg$directories[[key]])
    }
    # Check options for legacy keys
    legacy_key <- paste0(key, "_dir")
    if (!is.null(cfg$options[[legacy_key]])) {
      return(cfg$options[[legacy_key]])
    }
  }

  # Navigate through config hierarchy
  value <- cfg
  for (part in parts) {
    if (is.list(value) && part %in% names(value)) {
      value <- value[[part]]
    } else {
      # Key not found - return default
      return(default)
    }
  }

  # Pretty-print if appropriate
  .pretty_print_config(value)
}

#' Get configuration value (alias for settings)
#'
#' Internal alias for \code{\link{settings}}.
#'
#' @param key Character. Dot-notation key path
#' @param default Optional default value if key is not found
#' @param config_file Configuration file path (default: auto-discover)
#'
#' @return The configuration value
#' @keywords internal
config <- function(key = NULL, default = NULL, config_file = NULL) {
  settings(key = key, default = default, settings_file = config_file)
}

#' Read project settings
#'
#' Reads the project settings from settings.yml or config.yml with environment-aware
#' merging and split file resolution. Auto-discovers the settings file if not specified.
#'
#' @param settings_file Path to settings file (default: auto-discover settings.yml or config.yml)
#' @param environment Active environment name (default: R_CONFIG_ACTIVE or "default")
#'
#' @return The settings as a list
#' @export
settings_read <- function(settings_file = NULL, environment = NULL) {
  # Auto-discover settings file if not specified
  if (is.null(settings_file)) {
    settings_file <- .get_settings_file()
  }

  if (is.null(settings_file)) {
    stop("No settings file found. Looking for settings.yml or config.yml")
  }
  # Validate arguments
  checkmate::assert_string(settings_file, min.chars = 1)
  checkmate::assert_string(environment, null.ok = TRUE)

  # Check file exists
  if (!file.exists(settings_file)) {
    stop(sprintf("Settings file not found: %s", settings_file))
  }

  # Detect active environment
  active_env <- environment %||%
    Sys.getenv("R_CONFIG_ACTIVE", Sys.getenv("R_CONFIG_NAME", "default"))

  # Read raw YAML
  raw_config <- tryCatch(
    .safe_read_yaml(settings_file),
    error = function(e) {
      stop(sprintf("Failed to parse settings file '%s': %s", settings_file, e$message))
    }
  )

  # Check if file has environment sections
  has_envs <- .has_environment_sections(raw_config)

  if (!has_envs) {
    # Flat file - treat entire content as default environment
    config <- raw_config
  } else {
    # Environment-scoped file
    if (!"default" %in% names(raw_config)) {
      stop(sprintf("Settings file '%s' has environment sections but no 'default' environment", settings_file))
    }

    # Start with default environment
    config <- raw_config$default

    # Merge active environment if different
    if (active_env != "default") {
      if (active_env %in% names(raw_config)) {
        config <- .fw_merge_env(config, raw_config[[active_env]])
      } else {
        warning(sprintf("Environment '%s' not found in config, using 'default'", active_env))
      }
    }
  }

  # Load .env file BEFORE resolving split files (which evaluates env() expressions)
  # This ensures environment variables are available for interpolation
  project_root <- dirname(settings_file)
  dotenv_path <- config$dotenv_location
  if (!is.null(dotenv_path)) {
    # Custom dotenv location specified
    if (!grepl("^(/|[A-Za-z]:)", dotenv_path)) {
      dotenv_path <- file.path(project_root, dotenv_path)
    }
    if (dir.exists(dotenv_path)) {
      dotenv_path <- file.path(dotenv_path, ".env")
    }
  } else {
    # Default: .env in project root
    dotenv_path <- file.path(project_root, ".env")
  }

  # The .env values are visible only while this call resolves env() and
  # !expr values. They are never left in the R session, so one project's
  # token or server cannot leak into the next project. A variable that is
  # already set wins, and empty template lines (S3_ACCESS_KEY=) are skipped.
  if (file.exists(dotenv_path)) {
    dotenv_values <- tryCatch(
      .fw_read_dotenv(dotenv_path),
      error = function(e) {
        warning(sprintf("Failed to load .env file: %s", e$message))
        character()
      }
    )
    restore_env <- .fw_scope_env(dotenv_values)
    on.exit(restore_env(), add = TRUE)
  }

  # Resolve split file references recursively (this evaluates env() in split files)
  config <- .resolve_split_files(config, active_env, settings_file, character())
  config <- .fw_lift_connections(config)

  # Initialize standard sections AFTER split file resolution (if still missing)
  for (section in c("data", "connections", "git", "security", "packages", "directories")) {
    if (is.null(config[[section]])) {
      config[[section]] <- list()
    }
  }

  # Initialize options if not present
  if (is.null(config$options)) {
    config$options <- list()
  }

  # Evaluate !expr expressions and env() calls in main config
  config <- .eval_expressions(config)

  config
}


# Parse a .env file into a named character vector, in file order. The
# rules match the dotenv package and framework-py: `#` lines and blank
# lines are skipped, `export ` is allowed, matching outer quotes are removed,
# and a line that does not match is an error. Later keys win.
#' @keywords internal
.fw_read_dotenv <- function(path) {
  if (!file.exists(path)) {
    return(stats::setNames(character(), character()))
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[!grepl("^#", lines) & nzchar(trimws(lines))]
  pattern <- "^\\s*(?:export\\s+)?([^=]+)=(['\"]?)(.*)\\2\\s*$"
  ok <- grepl(pattern, lines, perl = TRUE)
  if (!all(ok)) {
    stop(sprintf("Cannot parse .env line: %s", substr(lines[!ok][1], 1, 40)))
  }
  keys <- sub(pattern, "\\1", lines, perl = TRUE)
  values <- sub(pattern, "\\3", lines, perl = TRUE)
  values <- stats::setNames(values, keys)
  values[!duplicated(keys, fromLast = TRUE)]
}

# Set .env values for a short time and return a function that undoes it.
# Only names that are unset (or empty) in the session are set, and empty
# values are skipped, so a shell credential is never replaced or blanked.
#' @keywords internal
.fw_scope_env <- function(values) {
  values <- values[nzchar(values) & nzchar(names(values))]
  values <- values[!nzchar(Sys.getenv(names(values), unset = ""))]
  if (length(values) > 0) {
    do.call(Sys.setenv, as.list(values))
  }
  added <- names(values)
  function() {
    if (length(added) > 0) Sys.unsetenv(added)
    invisible(NULL)
  }
}

# Load a .env file into the R session for good, without replacing variables
# that are already set and without setting empty values. For code that
# means to set up the session, such as scaffold(). Values an earlier load
# set are removed first, so the last project's values do not carry over
# (framework-py's dotenv.load() does the same).
#' @keywords internal
.fw_load_dotenv <- function(path) {
  values <- .fw_read_dotenv(path)
  undo <- .fw_dotenv_loaded$undo
  if (is.function(undo)) undo()
  .fw_dotenv_loaded$undo <- .fw_scope_env(values)
  invisible(NULL)
}

.fw_dotenv_loaded <- new.env(parent = emptyenv())


# Projects created by 2.0 development builds wrote settings/connections.yml
# without a `connections:` wrapper, so its keys landed at the top level.
# Move them back under `connections` where every reader looks.
#' @keywords internal
.fw_lift_connections <- function(config) {
  keys <- c("databases", "storage_buckets", "default_database", "default_storage_bucket")
  stray <- intersect(keys, names(config))
  if (length(stray) == 0) {
    return(config)
  }
  connections <- config$connections
  if (!is.list(connections)) connections <- list()
  for (key in stray) {
    if (is.null(connections[[key]]) || length(connections[[key]]) == 0) {
      connections[key] <- list(config[[key]])
    }
    config[[key]] <- NULL
  }
  config$connections <- connections
  config
}

# Helper: Check if config has environment sections
.has_environment_sections <- function(config) {
  if (!is.list(config) || length(config) == 0) {
    return(FALSE)
  }

  # Check if top-level keys look like environment names
  # Common environment names: default, production, development, test, staging
  env_keywords <- c("default", "production", "development", "test", "testing", "staging")
  top_keys <- names(config)

  # If we have a 'default' key, assume environment sections
  if ("default" %in% top_keys) {
    return(TRUE)
  }

  # Otherwise, check if keys match common environment names
  matches <- sum(top_keys %in% env_keywords)
  return(matches > 0)
}


# Helper: Resolve split file references recursively
.resolve_split_files <- function(config, environment, parent_file, visited_files, config_root = NULL, main_config_keys = NULL) {
  # Track which keys are file references
  file_refs <- character()

  # First call: set config_root to parent file's directory and remember main config keys
  if (is.null(config_root)) {
    config_root <- dirname(parent_file)
    main_config_keys <- names(config)
  }

  for (key in names(config)) {
    value <- config[[key]]

    # Check if value looks like a file reference
    if (is.character(value) && length(value) == 1 && grepl("\\.ya?ml$", value, ignore.case = TRUE)) {
      file_refs <- c(file_refs, key)

      # Resolve file path relative to config root (not parent file!)
      file_path <- .resolve_file_path(value, config_root)

      # Normalize path for circular reference check
      file_path_norm <- normalizePath(file_path, mustWork = FALSE)

      # Check if file exists
      if (!file.exists(file_path_norm)) {
        stop(sprintf("%s not found (referenced from %s)", value, basename(parent_file)))
      }

      # Circular reference check
      if (file_path_norm %in% visited_files) {
        stop(sprintf("Circular reference detected: %s", paste(c(visited_files, file_path_norm), collapse = " -> ")))
      }

      # Read raw split file
      raw_split <- tryCatch(
        .safe_read_yaml(file_path_norm),
        error = function(e) {
          stop(sprintf("Failed to parse split file '%s': %s", value, e$message))
        }
      )

      # Check if split file has environment sections
      has_envs <- .has_environment_sections(raw_split)

      if (!has_envs) {
        # Flat split file - use as-is
        split_config <- raw_split
      } else {
        # Environment-scoped split file
        if (!"default" %in% names(raw_split)) {
          stop(sprintf("Split file '%s' has environment sections but no 'default' environment", value))
        }

        # Merge environments (same logic as main config)
        split_config <- raw_split$default
        if (environment != "default" && environment %in% names(raw_split)) {
          split_config <- .fw_merge_env(split_config, raw_split[[environment]])
        }
      }

      # Recursively resolve nested split files (preserve config_root and main_config_keys)
      split_config <- .resolve_split_files(split_config, environment, file_path_norm, c(visited_files, file_path_norm), config_root, main_config_keys)

      # Evaluate !expr in split file
      split_config <- .eval_expressions(split_config)

      # Merge split file contents into main config
      # Main file wins for conflicts
      for (split_key in names(split_config)) {
        if (split_key == key) {
          # This is the section key (e.g., 'connections' in connections.yml)
          # Replace the file reference with the actual data
          config[[split_key]] <- split_config[[split_key]]
        } else if (split_key %in% names(config)) {
          if (split_key %in% file_refs) {
            # This key is another file reference, not a conflict - skip
            next
          } else {
            # Conflict: key already exists (either from main config or previous split file)
            # Check if it's a simple value (not a file ref string)
            is_real_value <- !is.character(config[[split_key]]) ||
                            length(config[[split_key]]) != 1 ||
                            !grepl("\\.ya?ml$", config[[split_key]], ignore.case = TRUE)

            if (is_real_value) {
              # Special case: 'options' key can exist in both main and split files
              # Merge if both are lists, skip with no warning if already present
              if (split_key == "options") {
                if (is.list(config$options) && is.list(split_config$options)) {
                  # Merge options sections (main config wins for conflicts)
                  config$options <- modifyList(split_config$options, config$options)
                }
                # Otherwise silently skip - options can exist in multiple split files
              } else if (split_key %in% main_config_keys) {
                # Conflict with main config - warn
                warning(sprintf(
                  "Key '%s' defined in both main config and '%s'. Using value from main config.",
                  split_key,
                  value
                ))
              } else {
                # Conflict with another split file - warn
                warning(sprintf(
                  "Key '%s' already defined, ignoring value from '%s'",
                  split_key,
                  value
                ))
              }
            } else {
              # This is a file reference that will be processed later, not a conflict
              config[[split_key]] <- split_config[[split_key]]
            }
          }
        } else {
          # No conflict - merge from split
          config[[split_key]] <- split_config[[split_key]]
        }
      }

      # Note: No need to remove file reference - if split_key == key, we already replaced it above
      # If split_key != key (split file has different top-level keys), the reference stays as a string
      # which is harmless
    }
  }

  config
}


# Helper: Resolve file path relative to config root directory
.resolve_file_path <- function(file_path, config_root_dir) {
  # If absolute, return as-is
  if (grepl("^/", file_path) || grepl("^[A-Za-z]:", file_path)) {
    return(file_path)
  }

  # Relative path - resolve relative to config root directory
  file.path(config_root_dir, file_path)
}


# Helper: Evaluate !expr expressions and env() calls
.eval_expressions <- function(x) {
  if (is.list(x)) {
    # Recursively process lists - preserve names!
    result <- lapply(x, .eval_expressions)
    names(result) <- names(x)
    result
  } else if (is.character(x) && length(x) == 1) {
    # Check for !expr marker
    if (grepl("^!expr\\s+", x)) {
      expr_string <- sub("^!expr\\s+", "", x)

      # Evaluate in controlled environment
      # WARNING: This evaluates arbitrary R code - only use trusted configs!
      tryCatch(
        eval(parse(text = expr_string), envir = new.env(parent = baseenv())),
        error = function(e) {
          stop(sprintf("Failed to evaluate expression '%s': %s", expr_string, e$message))
        }
      )
    } else if (grepl("^env\\(.*\\)$", x)) {
      # Handle env() syntax - cleaner alternative to !expr Sys.getenv()
      # Extract arguments: env("VAR") or env("VAR", "default")
      env_args <- gsub("^env\\(\"(.*?)\"(?:,\\s*\"(.*?)\")?\\)$", "\\1,\\2", x)
      env_args <- strsplit(env_args, ",")[[1]]
      env_args <- trimws(env_args)

      # Get environment variable with optional default
      if (length(env_args) == 2 && env_args[2] != "") {
        Sys.getenv(env_args[1], env_args[2])
      } else {
        Sys.getenv(env_args[1])
      }
    } else {
      x
    }
  } else {
    x
  }
}

# Helper function to process package configurations
#
# Ensures consistent format for package configurations by converting simple strings
# to named lists with default values. For example:
#
# Input:  list("dplyr", list(name = "readr", attached = FALSE))
# Output: list(list(name = "dplyr", attached = FALSE),
#             list(name = "readr", attached = FALSE))
#
# @param packages List of package configurations, where each item is either:
#   - A character string (package name)
#   - A list with 'name' and optional 'attached' fields
# @return List of package configurations, all in list format with 'name' and 'attached' fields
.process_packages <- function(packages) {
  if (is.null(packages)) {
    return(NULL)
  }

  # Convert simple strings to named lists
  lapply(packages, function(pkg) {
    if (is.character(pkg) && !is.list(pkg)) {
      list(name = pkg, attached = FALSE)
    } else {
      pkg
    }
  })
}

# Helper function to safely read YAML files
#
# Reads a YAML file while suppressing the "incomplete final line" warning
# as long as the YAML is valid. Preserves !expr tags as strings for later evaluation.
#
# @param file Path to YAML file
# @return Parsed YAML content
.safe_read_yaml <- function(file) {
  # Read file content with warnings suppressed
  content <- readLines(file, warn = FALSE)
  # Parse YAML - handlers preserve !expr as strings for later evaluation
  yaml::yaml.load(
    paste(content, collapse = "\n"),
    handlers = list(
      expr = function(x) paste0("!expr ", x)
    )
  )
}

# Overlay an environment section (for example production) on default.
# Named maps merge recursively; everything else, sequences included, is
# replaced whole. modifyList() would leave a sequence of mappings unchanged
# and replace a sequence of scalars, depending on how yaml typed it. A null
# value removes the key, as with modifyList().
#' @keywords internal
.fw_merge_env <- function(base, override) {
  if (!is.list(base) || is.null(names(base)) || !is.list(override) || is.null(names(override))) {
    return(override)
  }
  for (key in names(override)) {
    value <- override[[key]]
    if (is.null(value)) {
      base[[key]] <- NULL
    } else if (is.list(value) && !is.null(names(value)) && is.list(base[[key]]) && !is.null(names(base[[key]]))) {
      base[[key]] <- .fw_merge_env(base[[key]], value)
    } else {
      base[key] <- list(value)
    }
  }
  base
}

#' Write project settings
#'
#' Writes the project settings to settings.yml or config files
#' @param settings The settings list to write
#' @param settings_file The settings file path (default: auto-detect settings.yml/config.yml)
#' @param section Optional section to update (e.g. "data")
#' @return Invisibly returns NULL.
#' @export
settings_write <- function(settings, settings_file = NULL, section = NULL) {
  # Validate arguments
  checkmate::assert_list(settings)
  checkmate::assert_string(settings_file, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(section, min.chars = 1, null.ok = TRUE)

  # Auto-discover settings file when not provided
  if (is.null(settings_file)) {
    settings_file <- .get_settings_file()
    if (is.null(settings_file)) {
      # Default to creating settings.yml when none exist yet
      settings_file <- "settings.yml"
    }
  }

  if (!is.null(section)) {

    # Check if settings file exists
    if (!file.exists(settings_file)) {
      stop(sprintf("Settings file '%s' does not exist. Use settings_write(settings) without 'section' to create it first.", settings_file))
    }

    # Read current settings
    current <- tryCatch(
      yaml::read_yaml(settings_file),
      error = function(e) {
        stop(sprintf("Failed to read settings file '%s': %s", settings_file, e$message))
      }
    )

    # Get current environment from R_CONFIG_ACTIVE or default
    env <- Sys.getenv("R_CONFIG_ACTIVE", Sys.getenv("R_CONFIG_NAME", "default"))

    # A flat file (no default: or other environment sections) keeps its
    # sections at the top level, as settings_read() reads them
    scoped <- .has_environment_sections(current)
    value <- if (scoped) current[[env]][[section]] else current[[section]]

    # Check if this section uses a split file
    if (is.character(value) && grepl("^settings/", value)) {
      # This is a split file, update that instead. Its path is relative to
      # the settings file's folder, not the working directory.
      split_file <- file.path(dirname(settings_file), value)
      if (file.exists(split_file)) {
        # Read current split file
        split_settings <- tryCatch(
          yaml::read_yaml(split_file),
          error = function(e) {
            stop(sprintf("Failed to read split file '%s': %s", split_file, e$message))
          }
        )
        # Split files keep their values under the section key
        # (connections: in settings/connections.yml). Accept values with or
        # without that wrapper, and wrap an older file that lacks it.
        values <- if (identical(names(settings), section)) settings[[section]] else settings
        if (is.null(split_settings)) split_settings <- list()
        if (length(split_settings) > 0 && is.null(split_settings[[section]])) {
          split_settings <- stats::setNames(list(split_settings), section)
        }
        split_settings[[section]] <- modifyList(split_settings[[section]] %||% list(), values)
        # Write back to split file
        tryCatch(
          yaml::write_yaml(split_settings, split_file),
          error = function(e) {
            stop(sprintf("Failed to write split file '%s': %s", split_file, e$message))
          }
        )
      } else {
        stop(sprintf("Split file '%s' does not exist", split_file))
      }
    } else {
      # This is a direct section in settings.yml
      if (scoped) {
        current[[env]][[section]] <- settings
      } else {
        if (is.null(current)) current <- list()
        current[[section]] <- settings
      }
      tryCatch(
        yaml::write_yaml(current, settings_file),
        error = function(e) {
          stop(sprintf("Failed to write settings file '%s': %s", settings_file, e$message))
        }
      )
    }
  } else {
    # Writing entire settings - wrap in "default" section if not already wrapped
    if (!"default" %in% names(settings)) {
      settings <- list(default = settings)
    }

    tryCatch(
      yaml::write_yaml(settings, settings_file),
      error = function(e) {
        stop(sprintf("Failed to write settings file '%s': %s", settings_file, e$message))
      }
    )
  }

  invisible(NULL)
}

#' Pretty-print configuration values (internal)
#'
#' Intelligently formats configuration output based on session type.
#' In interactive sessions, pretty-prints nested structures. In scripts,
#' returns raw values.
#'
#' @param value Configuration value to format
#' @return In interactive mode with complex values: invisible return after printing.
#'   Otherwise: raw value.
#' @keywords internal
.pretty_print_config <- function(value) {
  # Only pretty-print in interactive sessions for complex structures
  if (interactive() && (is.list(value) || length(value) > 1)) {
    cat("Configuration:\n")
    str(value, max.level = 3, give.attr = FALSE, comp.str = "  ")
    invisible(value)
  } else {
    # Return raw value for scripts or simple values
    value
  }
}
