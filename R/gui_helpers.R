#' Get Framework config directory path
#'
#' Returns the path to Framework's global configuration directory, which holds
#' user settings, the saved Framework Cloud server, and token files.
#' Uses `tools::R_user_dir("framework", "config")` by default (CRAN compliant).
#' Can be overridden with the `FW_CONFIG_HOME` environment variable.
#'
#' The Python package and the `fw` command-line tool keep their own folder
#' (`~/.config/framework`). [config_sync()] brings their settings into R's.
#'
#' @return Character string with the config directory path
#' @export
fw_config_dir <- function() {
  custom_dir <- Sys.getenv("FW_CONFIG_HOME", "")
  if (nzchar(custom_dir)) {
    return(path.expand(custom_dir))
  }

  # CRAN-compliant default: tools::R_user_dir
  tools::R_user_dir("framework", "config")
}

# The config folder of the Python package and fw. R reads it (config_sync())
# and never writes to it. Home is the user profile on Windows (R's "~" there
# is usually Documents).
#' @keywords internal
.fw_shared_config_dir <- function() {
  xdg <- Sys.getenv("XDG_CONFIG_HOME", "")
  if (nzchar(xdg)) {
    return(file.path(xdg, "framework"))
  }
  home <- if (.Platform$OS.type == "windows") Sys.getenv("USERPROFILE", path.expand("~")) else path.expand("~")
  file.path(home, ".config", "framework")
}

#' Sync Settings from the Python Package and fw
#'
#' The Python package and the `fw` command-line tool keep their settings in
#' `~/.config/framework`, and the R package keeps its own in
#' [fw_config_dir()]. `config_sync()` brings R in line with them: files that
#' are missing from R's folder, or newer in theirs, are copied into R's
#' folder. This covers user settings, the saved Framework Cloud server, and
#' token files. The cloud settings mirror and its sync state stay separate,
#' because each tool keeps its own. R only reads their folder and never
#' writes to it.
#'
#' Logins stored in the system keyring are already shared and need no sync.
#'
#' @param from The folder to sync from. Defaults to `$XDG_CONFIG_HOME/framework`,
#'   or `~/.config/framework` when `XDG_CONFIG_HOME` is unset.
#' @param dry_run Logical. List what would be copied without copying it.
#'
#' @return Invisibly, the relative paths copied (or that would be copied).
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' config_sync(dry_run = TRUE)
#' config_sync()
#' }
#' }
#'
#' @seealso [fw_config_dir()], [cloud_login()]
#' @export
config_sync <- function(from = NULL, dry_run = FALSE) {
  checkmate::assert_string(from, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(dry_run)

  from <- from %||% .fw_shared_config_dir()
  to <- fw_config_dir()
  if (!dir.exists(from)) {
    message("Nothing to sync: ", from, " does not exist.")
    return(invisible(character(0)))
  }
  if (identical(normalizePath(from, mustWork = FALSE), normalizePath(to, mustWork = FALSE))) {
    message("Nothing to sync: R already uses ", to, ".")
    return(invisible(character(0)))
  }

  files <- list.files(from, all.files = TRUE, no.. = TRUE, recursive = TRUE)
  files <- files[!startsWith(basename(files), ".")]
  # Each tool keeps its own cloud settings mirror and sync state (the hashes
  # differ between languages), so those never cross over
  files <- setdiff(files, basename(unlist(.fw_sync_paths())))
  newer <- vapply(files, function(f) {
    dest <- file.path(to, f)
    !file.exists(dest) || file.mtime(file.path(from, f)) > file.mtime(dest)
  }, logical(1))
  files <- files[newer]

  if (length(files) == 0) {
    message("[ok] R is already in line with ", from)
    return(invisible(character(0)))
  }
  if (dry_run) {
    message("Would copy into ", to, ":\n", paste0("  ", files, collapse = "\n"))
    return(invisible(files))
  }

  for (f in files) {
    dest <- file.path(to, f)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    ok <- tryCatch(
      file.copy(file.path(from, f), dest, overwrite = TRUE, copy.date = TRUE),
      error = function(e) stop(sprintf("Failed to copy '%s': %s", f, conditionMessage(e)), call. = FALSE)
    )
    if (!isTRUE(ok)) stop(sprintf("Failed to copy '%s' into %s", f, to), call. = FALSE)
    if (startsWith(basename(f), "cloud-token")) Sys.chmod(dest, mode = "0600")
  }
  message("[ok] Copied into ", to, ":\n", paste0("  ", files, collapse = "\n"))
  invisible(files)
}

#' Initialize global Framework settings
#'
#' Creates the Framework config directory (via `fw_config_dir()`) and copies
#' default settings files if they don't already exist. Also handles migration
#' from previous R versions or legacy `~/.config/framework` location.
#'
#' @param force If TRUE, overwrites existing settings (default: FALSE)
#' @return Invisibly returns NULL
#' @keywords internal
init_global_config <- function(force = FALSE) {
  config_dir <- fw_config_dir()
  settings_path <- file.path(config_dir, "settings.yml")
  projects_path <- file.path(config_dir, "projects.yml")

  # Create directory if needed
  if (!dir.exists(config_dir)) {
    dir.create(config_dir, recursive = TRUE)
    message("Created Framework settings directory: ", config_dir)
  }

  # Attempt migration from legacy location (interactive only)
  # Migrate if: no settings file exists, OR settings file looks like stale test data
  needs_migration <- !file.exists(settings_path)
  if (!needs_migration && !force && file.exists(settings_path)) {
    tryCatch({
      existing <- yaml::read_yaml(settings_path)
      # Detect stale test data: author name is placeholder or projects_root points to nonexistent path
      author_name <- existing$author$name %||% ""
      if (author_name %in% c("", "First User", "Test User", "Test Author")) {
        needs_migration <- TRUE
      }
    }, error = function(e) {
      needs_migration <<- TRUE
    })
  }
  if (needs_migration && !force && interactive()) {
    .migrate_config_from_previous(config_dir)
  }

  # Copy default settings if doesn't exist or force is TRUE
  if (!file.exists(settings_path) || force) {
    default_settings <- system.file("settings", "global-settings-default.yml", package = "framework")
    if (file.exists(default_settings)) {
      file.copy(default_settings, settings_path, overwrite = force)
      message("Initialized global settings: ", settings_path)
    } else {
      stop("Could not find default settings template in package")
    }
  }

  # Create empty projects file if doesn't exist
  if (!file.exists(projects_path)) {
    yaml::write_yaml(list(projects = list()), projects_path)
    message("Initialized projects registry: ", projects_path)
  }

  invisible(NULL)
}

#' Migrate config from previous R versions or legacy location
#'
#' Checks for configs in legacy ~/.config/framework location
#' and copies them to the current R_user_dir location if found.
#'
#' @param target_dir Target config directory
#' @return TRUE if migration occurred, FALSE otherwise
#' @keywords internal
.migrate_config_from_previous <- function(target_dir) {
  # Check legacy ~/.config/framework (pre-1.0 location)
  legacy_dir <- path.expand("~/.config/framework")
  if (dir.exists(legacy_dir) && file.exists(file.path(legacy_dir, "settings.yml"))) {
    message("Migrating settings from legacy location: ", legacy_dir)
    .copy_config_files(legacy_dir, target_dir, overwrite = TRUE)
    return(TRUE)
  }

  FALSE
}

#' Copy config files between directories
#' @param from_dir Source directory
#' @param to_dir Destination directory
#' @param overwrite Whether to overwrite existing files (default FALSE)
#' @keywords internal
.copy_config_files <- function(from_dir, to_dir, overwrite = FALSE) {
  # Copy config files
  files_to_copy <- c("settings.yml", "projects.yml", "settings-catalog.yml")
  for (f in files_to_copy) {
    src <- file.path(from_dir, f)
    if (file.exists(src)) {
      file.copy(src, file.path(to_dir, f), overwrite = overwrite)
    }
  }

  # Copy templates directory if it exists
  templates_src <- file.path(from_dir, "templates")
  if (dir.exists(templates_src)) {
    templates_dst <- file.path(to_dir, "templates")
    if (!dir.exists(templates_dst)) {
      dir.create(templates_dst, recursive = TRUE)
    }
    template_files <- list.files(templates_src, full.names = TRUE)
    for (tf in template_files) {
      file.copy(tf, templates_dst, overwrite = overwrite)
    }
  }
}

#' Get default global configuration structure
#'
#' @return List with default global configuration
#' @keywords internal
get_default_global_config <- function() {
  catalog <- load_settings_catalog(include_user = TRUE, validate = TRUE)

  project_types <- .catalog_project_type_defaults(catalog$project_types)

  defaults <- catalog$defaults %||% list()
  defaults$project_type <- defaults$project_type %||% "project"
  defaults$notebook_format <- defaults$notebook_format %||% "quarto"
  defaults$ide <- defaults$ide %||% "vscode"
  defaults$use_git <- if (is.null(defaults$use_git)) TRUE else isTRUE(defaults$use_git)
  defaults$use_renv <- if (is.null(defaults$use_renv)) FALSE else isTRUE(defaults$use_renv)
  # Handle nested scaffold structure from catalog
  scaffold <- defaults$scaffold %||% list()
  defaults$seed <- scaffold$seed %||% defaults$seed %||% "123"
  if (is.character(defaults$seed) && identical(defaults$seed, "")) {
    defaults$seed <- "123"
  }
  if (!"seed" %in% names(defaults)) {
    defaults["seed"] <- list("123")
  }
  defaults$seed_on_scaffold <- if (!is.null(scaffold$seed_on_scaffold)) {
    isTRUE(scaffold$seed_on_scaffold)
  } else if (!is.null(defaults$seed_on_scaffold)) {
    isTRUE(defaults$seed_on_scaffold)
  } else {
    FALSE
  }
  defaults$ai_support <- if (is.null(defaults$ai_support)) TRUE else isTRUE(defaults$ai_support)
  defaults$ai_assistants <- as.list(defaults$ai_assistants %||% list())
  defaults$ai_canonical_file <- defaults$ai_canonical_file %||% "CLAUDE.md"
  defaults$git_hooks <- defaults$git_hooks %||% list()
  defaults$git_hooks$ai_sync <- NULL
  defaults$git_hooks$data_security <- if (is.null(defaults$git_hooks$data_security)) FALSE else isTRUE(defaults$git_hooks$data_security)

  defaults$packages <- if (!is.null(defaults$packages) && is.list(defaults$packages)) {
    result <- lapply(defaults$packages, function(pkg) {
      if (is.character(pkg) && length(pkg) == 1) {
        # Single string like "dplyr"
        list(name = pkg, auto_attach = TRUE)
      } else if (is.list(pkg) && !is.null(pkg$name)) {
        # Already proper format
        list(
          name = as.character(pkg$name),
          auto_attach = if (is.null(pkg$auto_attach)) FALSE else isTRUE(pkg$auto_attach)
        )
      } else {
        # Skip arrays, malformed entries, etc.
        NULL
      }
    })
    # Filter out NULLs
    Filter(Negate(is.null), result)
  } else {
    list()
  }

  defaults$directories <- project_types$project$directories %||% list()

  defaults$env <- defaults$env %||% list(
    raw = paste(env_default_template_lines(), collapse = "\n")
  )

  defaults$connections <- defaults$connections %||% .default_connections_configuration()
  global_settings_path <- file.path(fw_config_dir(), "settings.yml")
  publishing <- if (file.exists(global_settings_path)) {
    tryCatch(yaml::read_yaml(global_settings_path)$publish, error = function(e) NULL)
  } else NULL


  git_defaults <- catalog$git %||% list()
  privacy_defaults <- catalog$privacy %||% list()

  list(
    project_types = project_types,
    author = list(
      name = .catalog_field_default(catalog, "author.name", "Your Name"),
      email = .catalog_field_default(catalog, "author.email", "your.email@example.com"),
      affiliation = .catalog_field_default(catalog, "author.affiliation", "Your Institution")
    ),
    defaults = defaults,
    publish = publishing %||% catalog$publish,
    git = {
      result <- list()
      if (!is.null(git_defaults$user_name) && is.character(git_defaults$user_name) && nzchar(git_defaults$user_name)) {
        result$user_name <- git_defaults$user_name
      }
      if (!is.null(git_defaults$user_email) && is.character(git_defaults$user_email) && nzchar(git_defaults$user_email)) {
        result$user_email <- git_defaults$user_email
      }
      # Force to be JSON object instead of array when empty
      if (length(result) == 0) {
        structure(list(), names = character(0))
      } else {
        result
      }
    },
    privacy = list(
      secret_scan = if (is.null(privacy_defaults$secret_scan)) FALSE else isTRUE(privacy_defaults$secret_scan),
      gitignore_template = privacy_defaults$gitignore_template %||% "gitignore"
    ),
    projects = list()
  )
}

#' Read global Framework configuration
#'
#' @param use_defaults Whether to merge with default structure (default: TRUE)
#' @return List containing global configuration
#' @export
read_frameworkrc <- function(use_defaults = TRUE) {
  # Use CRAN-compliant config directory
  config_dir <- fw_config_dir()
  new_settings_path <- file.path(config_dir, "settings.yml")
  new_projects_path <- file.path(config_dir, "projects.yml")

  # Legacy paths (for migration)
  legacy_config_path <- file.path(config_dir, "config.yml")  # Old YAML naming
  legacy_json_path <- path.expand("~/.frameworkrc.json")     # Very old JSON

  # Try new YAML settings first
  if (file.exists(new_settings_path)) {
    config <- tryCatch({
      yaml::read_yaml(new_settings_path)
    }, error = function(e) {
      warning("Failed to read ", new_settings_path, ": ", e$message)
      if (use_defaults) {
        get_default_global_config()
      } else {
        list(projects = list(), active_project = NULL)
      }
    })

    # Read projects from separate file
    if (file.exists(new_projects_path)) {
      projects_data <- tryCatch({
        yaml::read_yaml(new_projects_path)
      }, error = function(e) {
        warning("Failed to read ", new_projects_path, ": ", e$message)
        list(projects = list())
      })
      config$projects <- projects_data$projects %||% list()
    }

  } else if (file.exists(legacy_config_path)) {
    # Migrate from old config.yml naming
    message("Migrating from config.yml to settings.yml...")
    config <- tryCatch({
      yaml::read_yaml(legacy_config_path)
    }, error = function(e) {
      warning("Failed to read legacy config.yml: ", e$message)
      if (use_defaults) {
        get_default_global_config()
      } else {
        list(projects = list(), active_project = NULL)
      }
    })

    # Write to new naming
    write_frameworkrc(config)
    file.remove(legacy_config_path)  # Clean up old file

  } else if (file.exists(legacy_json_path)) {
    # Migrate from legacy JSON format
    message("Migrating from .frameworkrc.json to settings.yml...")
    config <- tryCatch({
      jsonlite::fromJSON(legacy_json_path, simplifyVector = FALSE)
    }, error = function(e) {
      warning("Failed to read legacy JSON config: ", e$message)
      if (use_defaults) {
        get_default_global_config()
      } else {
        list(projects = list(), active_project = NULL)
      }
    })

    # Write to new YAML format
    if (!dir.exists(config_dir)) {
      dir.create(config_dir, recursive = TRUE)
    }
    write_frameworkrc(config)

  } else {
    # No config exists, initialize with defaults
    message("No Framework settings found. Initializing...")
    init_global_config()

    # Read the newly created settings
    if (file.exists(new_settings_path)) {
      config <- yaml::read_yaml(new_settings_path)
    } else if (use_defaults) {
      config <- get_default_global_config()
    } else {
      config <- list(projects = list(), active_project = NULL)
    }
  }

  # Merge with defaults if requested
  if (use_defaults) {
    defaults <- get_default_global_config()
    # Only merge defaults into missing keys, don't override existing values
    for (key in names(defaults)) {
      if (!(key %in% names(config))) {
        config[[key]] <- defaults[[key]]
      } else if (key == "defaults" && is.list(config[[key]])) {
        config[[key]] <- modifyList(defaults[[key]], config[[key]], keep.null = TRUE)
      } else if (key == "project_types" && is.list(config[[key]])) {
        # CRITICAL FIX: modifyList() merges nested objects, so deleted directory fields persist.
        # We need to merge project_types, BUT completely replace directories for each type
        # to allow user deletions to override package defaults.

        # Save user's directories BEFORE merge (to preserve deletions)
        user_directories <- list()
        user_extra_directories <- list()
        for (type_name in names(config[[key]])) {
          if (!is.null(config[[key]][[type_name]]$directories)) {
            user_directories[[type_name]] <- config[[key]][[type_name]]$directories
          }
          if (!is.null(config[[key]][[type_name]]$extra_directories)) {
            user_extra_directories[[type_name]] <- config[[key]][[type_name]]$extra_directories
          }
        }

        # Merge with defaults (gets labels, descriptions, etc.)
        config[[key]] <- modifyList(defaults[[key]], config[[key]], keep.null = TRUE)

        # Restore user's directories (completely replace merged defaults)
        for (type_name in names(user_directories)) {
          config[[key]][[type_name]]$directories <- user_directories[[type_name]]
        }
        for (type_name in names(user_extra_directories)) {
          config[[key]][[type_name]]$extra_directories <- user_extra_directories[[type_name]]
        }
      }
    }

    # Backfill defaults.directories from project type when missing
    if (is.null(config$defaults$directories) && !is.null(config$project_types$project$directories)) {
      config$defaults$directories <- config$project_types$project$directories
    }
  }

  return(config)
}

#' Write global Framework configuration
#'
#' Writes the global settings file. When `config` has a `projects` element,
#' the project registry (`projects.yml`) is written too; otherwise it stays
#' as it is.
#'
#' @param config A named list, such as one from [read_frameworkrc()]. `NULL`
#'   or an empty list is an error, so a slip can't wipe the global settings.
#' @return Invisibly returns NULL
#' @export
write_frameworkrc <- function(config) {
  if (!is.list(config) || length(config) == 0 || is.null(names(config)) || any(!nzchar(names(config)))) {
    stop("config must be a named, non-empty list of settings, such as one from read_frameworkrc().", call. = FALSE)
  }
  config_dir <- fw_config_dir()
  settings_path <- file.path(config_dir, "settings.yml")
  projects_path <- file.path(config_dir, "projects.yml")

  # Create directory if needed
  if (!dir.exists(config_dir)) {
    dir.create(config_dir, recursive = TRUE)
  }

  # Split out projects into separate file
  write_projects <- "projects" %in% names(config)
  projects <- config$projects
  config$projects <- NULL

  # Fix packages structure - ensure default_packages array doesn't have names
  if (!is.null(config$defaults$packages$default_packages)) {
    # Ensure default_packages is an unnamed array
    if (is.list(config$defaults$packages$default_packages) && !is.null(names(config$defaults$packages$default_packages))) {
      config$defaults$packages$default_packages <- unname(config$defaults$packages$default_packages)
    }
  }

  # Fix extra_directories arrays for all project types
  if (!is.null(config$project_types)) {
    for (type_name in names(config$project_types)) {
      if (!is.null(config$project_types[[type_name]]$extra_directories)) {
        extra_dirs <- config$project_types[[type_name]]$extra_directories

        # If it's a named list (object), it means JSON gave us an object instead of array
        # Convert to unnamed list (array) while preserving the structure of each item
        if (is.list(extra_dirs) && !is.null(names(extra_dirs)) && any(names(extra_dirs) != "")) {
          # Strip outer names but keep each item as-is
          config$project_types[[type_name]]$extra_directories <- unname(extra_dirs)
        }
      }
    }
  }

  # Write main settings
  yaml::write_yaml(config, settings_path)

  # Write projects separately, only when given
  if (write_projects || !file.exists(projects_path)) {
    yaml::write_yaml(list(projects = projects %||% list()), projects_path)
  }

  invisible(NULL)
}

#' Add project to global configuration
#'
#' Adds a project folder to the registry (`projects.yml` in [fw_config_dir()]).
#' The registry stores only the ID, the path, and the date. The project's name
#' and type are read from its settings.yml when needed.
#'
#' @param project_dir Path to project directory
#' @param project_name Not stored. Kept so older code still runs.
#' @param project_type Not stored. Kept so older code still runs.
#' @return Invisibly returns the project ID. For a folder already in the
#'   registry, that project's existing ID.
#' @export
add_project_to_config <- function(project_dir, project_name = NULL, project_type = NULL) {
  checkmate::assert_string(project_dir, min.chars = 1)
  checkmate::assert_string(project_name, null.ok = TRUE)
  checkmate::assert_string(project_type, null.ok = TRUE)

  if (!dir.exists(project_dir)) {
    warning("Project folder does not exist: ", project_dir, call. = FALSE)
  }

  config <- read_frameworkrc()

  # Normalize the same way for folders that exist and folders that do not
  # yet, so one folder is never listed twice (/tmp and /private/tmp)
  normalize <- function(path) {
    path <- path.expand(path)
    if (file.exists(path)) return(normalizePath(path, mustWork = FALSE))
    parent <- dirname(path)
    if (file.exists(parent)) file.path(normalizePath(parent, mustWork = FALSE), basename(path)) else path
  }
  normalized_path <- normalize(project_dir)

  # Check if project already exists
  if (!is.null(config$projects) && length(config$projects) > 0) {
    existing_paths <- vapply(config$projects, function(p) normalize(as.character(p$path %||% "")), "")
    hit <- which(existing_paths == normalized_path)
    if (length(hit) > 0) {
      message("Project already in registry")
      return(invisible(as.integer(config$projects[[hit[1]]]$id)))
    }
  }

  # Generate next ID (ensure it's an integer)
  if (is.null(config$projects) || length(config$projects) == 0) {
    next_id <- 1L
  } else {
    existing_ids <- sapply(config$projects, function(p) as.integer(p$id %||% 0))
    next_id <- as.integer(max(existing_ids) + 1)
  }

  new_project <- list(
    id = next_id,
    path = normalized_path,
    created = format(Sys.Date(), "%Y-%m-%d")
  )
  # Metadata will be read from settings.yml when needed

  # Add new project
  if (is.null(config$projects)) {
    config$projects <- list()
  }
  config$projects <- c(config$projects, list(new_project))

  write_frameworkrc(config)
  invisible(next_id)
}

#' List all projects in global configuration
#'
#' @return Data frame with project information
#' @export
project_list <- function() {
  config <- read_frameworkrc()

  if (is.null(config$projects) || length(config$projects) == 0) {
    return(data.frame(
      id = integer(0),
      path = character(0),
      created = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # Convert to data frame and ensure IDs are integers
  do.call(rbind, lapply(config$projects, function(p) {
    data.frame(
      id = as.integer(p$id),
      path = as.character(p$path),
      created = as.character(p$created %||% ""),
      stringsAsFactors = FALSE
    )
  }))
}

#' Remove project from global configuration
#'
#' @param project_id Project ID to remove
#' @return Invisibly returns NULL
#' @export
remove_project_from_config <- function(project_id) {
  config <- read_frameworkrc()

  # Find project with matching ID
  if (is.null(config$projects) || length(config$projects) == 0) {
    warning("No projects in registry")
    return(invisible(NULL))
  }

  # Convert project_id to integer for comparison (handles floats like 1.0)
  target_id <- as.integer(project_id)

  # Filter out the project with matching ID
  config$projects <- Filter(function(p) {
    as.integer(p$id) != target_id
  }, config$projects)

  # Convert all IDs to integers while we're here (migration)
  config$projects <- lapply(config$projects, function(p) {
    p$id <- as.integer(p$id)
    p
  })

  write_frameworkrc(config)
  invisible(NULL)
}
