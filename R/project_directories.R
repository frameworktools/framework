#' Add custom directories to an existing project
#'
#' Adds new directories to a project's configuration and creates them on the
#' filesystem. This function is used by the GUI to allow users to add custom
#' directories to their project structure without modifying existing directories.
#'
#' @param project_path Character string. Absolute path to the project root directory.
#' @param key Character string. Internal key for the directory (e.g., "analysis_archive").
#'   An `extra_directories` entry with the same key is replaced.
#' @param label Character string. Human-readable label for the directory (e.g., "Analysis Archive").
#' @param path Character string. Relative path where the directory should be created
#'   (e.g., "analysis/archive"). Must be relative, not absolute. Parent directories
#'   will be created as needed.
#'
#' @return List with success status and directory information:
#'   \itemize{
#'     \item \code{success}: Logical indicating whether the operation succeeded
#'     \item \code{directory}: List containing key, label, path, absolute_path, and created flag
#'     \item \code{error}: Character string with error message (only present if success is FALSE)
#'   }
#'
#' @details
#' This function performs the following steps, as the Python package does:
#' \enumerate{
#'   \item Validates all input arguments
#'   \item Finds the project's settings.yml (or config.yml)
#'   \item Creates the directory on the filesystem (with recursive creation)
#'   \item Records it under `extra_directories` in that file, as
#'     `key`, `label`, and `path`. An entry with the same key is replaced,
#'     so a second call with the same key updates it.
#' }
#'
#' Core directories under `directories` are not checked or changed.
#'
#' The function follows a non-destructive, additive-only approach. It will not:
#' \itemize{
#'   \item Rename existing directories
#'   \item Delete existing directories
#'   \item Modify existing directory paths
#'   \item Change the project type
#' }
#'
#' @section Safety:
#' The function includes several safety checks:
#' \itemize{
#'   \item Rejects absolute paths (must be relative)
#'   \item Rejects paths containing ".." (no directory traversal)
#'   \item Replaces, never duplicates, an entry with the same key
#'   \item Wraps filesystem operations in error handling
#' }
#'
#' @export
#' @keywords internal
project_add_directory <- function(project_path, key, label, path) {
  # 1. VALIDATE ALL ARGUMENTS
  checkmate::assert_directory_exists(project_path)
  checkmate::assert_string(key, min.chars = 1)
  checkmate::assert_string(label, min.chars = 1)
  checkmate::assert_string(path, min.chars = 1)

  # 2. VALIDATE PATH IS RELATIVE AND SAFE
  if (grepl("^/", path) || grepl("^[A-Z]:", path)) {
    return(list(
      success = FALSE,
      error = sprintf("Path must be relative, not absolute: %s", path)
    ))
  }

  if (grepl("\\.\\.", path)) {
    return(list(
      success = FALSE,
      error = sprintf("Path cannot contain '..': %s", path)
    ))
  }

  # 3. READ PROJECT CONFIG
  # Check for settings.yml (existing projects) or config.yml (new GUI projects)
  settings_path <- file.path(project_path, "settings.yml")
  config_path <- file.path(project_path, "config.yml")

  if (file.exists(settings_path)) {
    config_path <- settings_path
  } else if (file.exists(config_path)) {
    config_path <- config_path
  } else {
    return(list(
      success = FALSE,
      error = sprintf("Project config not found (checked settings.yml and config.yml)")
    ))
  }

  tryCatch(
    {
      # 4. CREATE DIRECTORY ON FILESYSTEM
      absolute_path <- file.path(project_path, path)

      dir_created <- tryCatch(
        {
          dir.create(absolute_path, recursive = TRUE, showWarnings = FALSE)
          TRUE
        },
        error = function(e) {
          # If directory already exists, that's OK
          if (dir.exists(absolute_path)) {
            return(TRUE)
          }
          stop(sprintf("Failed to create directory '%s': %s", absolute_path, e$message))
        }
      )

      # 5. RECORD IT UNDER extra_directories (same key replaced)
      .fw_record_extra_directory(config_path, key, label, path)

      # 6. RETURN SUCCESS
      return(list(
        success = TRUE,
        directory = list(
          key = key,
          label = label,
          path = path,
          absolute_path = absolute_path,
          created = dir_created
        )
      ))
    },
    error = function(e) {
      return(list(
        success = FALSE,
        error = sprintf("Failed to add directory: %s", e$message)
      ))
    }
  )
}

# Add or replace one extra_directories entry in a project settings file.
# Entries may be a list of {key, label, path} or a map keyed by name.
.fw_record_extra_directory <- function(settings_file, key, label, path) {
  raw <- yaml::read_yaml(settings_file) %||% list()
  scoped <- is.list(raw$default)
  config <- if (scoped) raw$default else raw
  extra <- config$extra_directories %||% list()
  if (is.character(extra)) {
    stop("extra_directories points to another file; add the folder there.", call. = FALSE)
  }
  entry <- list(key = key, label = label, path = path)
  if (!is.null(names(extra)) && all(nzchar(names(extra)))) {
    extra[[key]] <- entry[c("label", "path")]
  } else {
    extra <- Filter(function(e) !identical(e$key, key), extra)
    extra[[length(extra) + 1L]] <- entry
  }
  config$extra_directories <- extra
  if (scoped) raw$default <- config else raw <- config
  yaml::write_yaml(raw, settings_file)
  invisible(TRUE)
}
