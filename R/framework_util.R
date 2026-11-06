#' Check if settings file exists
#'
#' Checks for settings.yml (preferred) or settings.yml (backward compatibility).
#'
#' @param path Optional path to check in (default: current directory)
#' @return TRUE if either file exists, FALSE otherwise
#' @keywords internal
.has_settings_file <- function(path = ".") {
  file.exists(file.path(path, "settings.yml")) || file.exists(file.path(path, "config.yml"))
}

#' Get settings file path
#'
#' Returns path to settings.yml (preferred) or config.yml (backward compatibility).
#' Walks up directory tree to find project root if not found in current directory.
#'
#' @param path Optional path to check in (default: current directory)
#' @return Path to settings file, or NULL if neither exists
#' @keywords internal
.get_settings_file <- function(path = ".") {
  # Try current directory first
  settings_path <- file.path(path, "settings.yml")
  config_path <- file.path(path, "config.yml")

  if (file.exists(settings_path)) {
    return(settings_path)
  } else if (file.exists(config_path)) {
    return(config_path)
  }

  # Not in current directory - walk up the tree to find project root
  project_root <- .find_project_root(path)

  if (is.null(project_root)) {
    return(NULL)
  }

  # Return the settings file from project root
  settings_path <- file.path(project_root, "settings.yml")
  config_path <- file.path(project_root, "config.yml")

  if (file.exists(settings_path)) {
    return(settings_path)
  } else if (file.exists(config_path)) {
    return(config_path)
  } else {
    return(NULL)
  }
}

#' Find project root by walking up directory tree
#'
#' @param start_dir Starting directory for search
#' @return Path to project root, or NULL if not found
#' @keywords internal
.find_project_root <- function(start_dir) {
  current <- normalizePath(start_dir, mustWork = FALSE)
  max_depth <- 10  # Prevent infinite loops
  depth <- 0

  while (depth < max_depth) {
    # Check if settings file exists in current directory
    if (.has_settings_file(current)) {
      return(current)
    }

    # Move up one directory
    parent <- dirname(current)
    if (parent == current) {
      # Hit filesystem root
      return(NULL)
    }
    current <- parent
    depth <- depth + 1
  }

  return(NULL)
}

#' Standardize Working Directory for Framework Projects
#'
#' This function helps standardize the working directory when working with
#' framework projects, especially useful in Quarto/RMarkdown documents that
#' may be rendered from subdirectories.
#'
#' @param project_root Character string specifying the project root directory.
#'   If NULL (default), the function will attempt to find it automatically.
#'
#' @return Invisibly returns the standardized project root path.
#'
#' @details
#' The function looks for common framework project indicators:
#' - settings.yml or settings.yml file
#' - .Rprofile file
#' - Being in common subdirectories (scratch, work)
#'
#' It sets both the regular working directory and knitr's root.dir option
#' if knitr is available.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' library(framework)
#' standardize_wd()
#' scaffold()
#' }
#' }
#'
#' @export
standardize_wd <- function(project_root = NULL) {
  # If no project root specified, try to find it
  if (is.null(project_root)) {
    current <- getwd()

    # First, try walking up the directory tree to find settings file
    project_root <- .find_project_root(current)

    # If not found by walking up, try other heuristics
    if (is.null(project_root)) {
      search_paths <- list(
        # If we're in project root and R subdirectory exists
        list(
          condition = .has_settings_file("R"),
          path = file.path(current, "R")
        ),
        # If we can find an .Rprofile in parent with R/settings
        list(
          condition = file.exists("../.Rprofile") && .has_settings_file("../R"),
          path = file.path(dirname(current), "R")
        )
      )

      # Try each search pattern
      for (search in search_paths) {
        if (search$condition) {
          project_root <- search$path
          break
        }
      }
    }

    # Last resort: check for .Rproj or .code-workspace files in current and parent directories
    if (is.null(project_root)) {
      # Walk up looking for .Rproj or .code-workspace file
      check_dir <- current
      max_depth <- 10  # Prevent infinite loops
      depth <- 0

      while (depth < max_depth) {
        # Check for .Rproj files
        rproj_files <- list.files(
          path = check_dir,
          pattern = "\\.Rproj$",
          full.names = TRUE,
          recursive = FALSE
        )

        # Check for .code-workspace files
        workspace_files <- list.files(
          path = check_dir,
          pattern = "\\.code-workspace$",
          full.names = TRUE,
          recursive = FALSE
        )

        if (length(rproj_files) > 0 || length(workspace_files) > 0) {
          # Found project marker - check if settings file is in R/ subdirectory
          r_dir <- file.path(check_dir, "R")
          if (dir.exists(r_dir) && .has_settings_file(r_dir)) {
            project_root <- r_dir
            break
          }
          # Or check if settings file is in same directory as project marker
          if (.has_settings_file(check_dir)) {
            project_root <- check_dir
            break
          }
        }

        # Move up one directory
        parent <- dirname(check_dir)
        if (parent == check_dir) break  # Hit filesystem root
        check_dir <- parent
        depth <- depth + 1
      }
    }
  }
  
  # Validate and set the working directory
  if (!is.null(project_root) && dir.exists(project_root)) {
    # Normalize the path
    project_root <- normalizePath(project_root, mustWork = TRUE)

    # Detect if we're running inside document rendering engines (knitr/Quarto/etc.)
    in_knitr <- isTRUE(getOption("knitr.in.progress"))
    in_quarto <- nzchar(Sys.getenv("QUARTO_RENDER")) ||
      nzchar(Sys.getenv("QUARTO_PROJECT_DIR")) ||
      isTRUE(getOption("quarto.is_rendering"))
    in_rstudio_notebook <- isTRUE(getOption("rstudio.notebook.executing"))
    in_render_context <- in_knitr || in_quarto || in_rstudio_notebook

    # Set knitr working directory if available (affects future chunks)
    if (requireNamespace("knitr", quietly = TRUE)) {
      knitr::opts_knit$set(root.dir = project_root)
    }

    # Change working directory for current session
    # In knitr/Quarto contexts, suppress the "changed working directory" warning
    # since we're intentionally managing this via root.dir option
    if (in_render_context) {
      suppressWarnings(setwd(project_root))
    } else {
      old_wd <- setwd(project_root)
    }

  } else {
    # Return NULL silently - let calling function (scaffold) handle the error
    project_root <- NULL
  }

  invisible(project_root)
}

# A project-relative path made absolute against the project root, so code
# run from notebooks/ or another subfolder finds the same files. Absolute
# paths, and any path outside a project, are returned unchanged.
#' @keywords internal
.fw_project_path <- function(path, root = NULL) {
  if (is.null(path) || length(path) != 1 || is.na(path) || !nzchar(path)) {
    return(path)
  }
  if (grepl("^(/|~|[A-Za-z]:[/\\\\]|\\\\\\\\)", path) || identical(path, ":memory:")) {
    return(path)
  }
  root <- root %||% tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (is.null(root)) {
    return(path)
  }
  file.path(root, path)
}
