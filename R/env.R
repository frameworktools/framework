#' Create or append to .env file
#'
#' Creates a .env file (if it doesn't exist) and appends environment variables.
#' Warns if .env is not in .gitignore to prevent accidental secret exposure.
#'
#' @param ... Named arguments for environment variables (e.g., DB_PASSWORD = "secret")
#' @param comment Optional comment to add before the variables
#' @param check_gitignore Logical; if TRUE (default), warns if .env not gitignored
#'
#' @return Invisibly returns TRUE on success
#' @keywords internal
.make_env <- function(..., comment = NULL, check_gitignore = TRUE) {
  vars <- list(...)

  if (length(vars) == 0) {
    stop("No environment variables provided. Usage: .make_env(VAR_NAME = \"value\", ...)")
  }

  # Validate named arguments
  if (is.null(names(vars)) || any(names(vars) == "")) {
    stop("All arguments must be named. Usage: .make_env(VAR_NAME = \"value\", ...)")
  }

  env_path <- ".env"
  env_exists <- file.exists(env_path)

  # Check .gitignore if requested
  if (check_gitignore) {
    .check_env_gitignored()
  }

  # Build content to append
  content <- character()

  # Add blank line if file exists
  if (env_exists) {
    content <- c(content, "")
  }

  # Add comment if provided
  if (!is.null(comment) && nzchar(comment)) {
    content <- c(content, paste0("# ", comment))
  }

  # Add variables
  for (var_name in names(vars)) {
    var_value <- vars[[var_name]]
    # Quote values that contain spaces or special characters
    if (grepl("[[:space:]#]", var_value)) {
      var_value <- sprintf('"%s"', var_value)
    }
    content <- c(content, sprintf("%s=%s", var_name, var_value))
  }

  # Append or create file
  if (env_exists) {
    # Append to existing file
    existing_content <- readLines(env_path, warn = FALSE)
    writeLines(c(existing_content, content), env_path)
    message(sprintf("[ok] Appended %d variable(s) to .env", length(vars)))
  } else {
    # Create new file
    writeLines(content, env_path)
    message(sprintf("[ok] Created .env with %d variable(s)", length(vars)))
  }

  # Show what was added (without revealing values)
  message("  Variables: ", paste(names(vars), collapse = ", "))

  invisible(TRUE)
}

#' Default Framework .env template lines
#'
#' Provides the baseline .env content that ships with Framework. Other helper
#' functions (project_create(), GUI scaffolders) reuse these lines when
#' users haven't customized their own template.
#'
#' @keywords internal
env_default_template_lines <- function() {
  c(
    "# Framework environment defaults",
    "# Populate these values before running scaffold() or publishing.",
    "",
    "# ------------------------------------------------------------------",
    "# PostgreSQL connection (example)",
    "# ------------------------------------------------------------------",
    "POSTGRES_HOST=",
    "POSTGRES_PORT=5432",
    "POSTGRES_DB=",
    "POSTGRES_SCHEMA=public",
    "POSTGRES_USER=",
    "POSTGRES_PASSWORD=",
    "",
    "# ------------------------------------------------------------------",
    "# S3-compatible object storage (AWS S3, MinIO, etc.)",
    "# ------------------------------------------------------------------",
    "S3_ENDPOINT=",
    "S3_BUCKET=",
    "S3_REGION=",
    "S3_ACCESS_KEY=",
    "S3_SECRET_KEY=",
    "S3_SESSION_TOKEN="
  )
}

#' Convert env() configuration into file lines
#' @keywords internal
env_lines_from_variables <- function(vars) {
  if (is.null(vars) || length(vars) == 0) {
    return(character())
  }

  if (is.list(vars) && is.null(names(vars))) {
    # Convert unnamed list (array of kv pairs) into named list
    vars <- unlist(vars, recursive = FALSE, use.names = TRUE)
  }

  keys <- names(vars)
  if (is.null(keys)) {
    stop("Variables must be a named list when building .env content")
  }

  vapply(
    keys,
    function(key) {
      value <- vars[[key]]
      if (is.null(value)) value <- ""
      sprintf("%s=%s", toupper(key), value)
    },
    character(1),
    USE.NAMES = FALSE
  )
}

#' Resolve env template lines from configuration
#'
#' @param env_config Either a character string (raw .env content) or a list with
#'   `raw` and/or `variables`.
#' @return Character vector of lines ready to be written to .env
#' @keywords internal
env_resolve_lines <- function(env_config = NULL) {
  if (is.null(env_config)) {
    return(env_default_template_lines())
  }

  # Allow raw string directly
  if (is.character(env_config) && length(env_config) == 1) {
    if (!nzchar(env_config)) {
      return(env_default_template_lines())
    }
    return(strsplit(env_config, "\\r?\\n", perl = TRUE)[[1]])
  }

  # Lists may contain raw content or variables map
  if (is.list(env_config)) {
    if (!is.null(env_config$raw) && nzchar(env_config$raw)) {
      return(strsplit(env_config$raw, "\\r?\\n", perl = TRUE)[[1]])
    }
    if (!is.null(env_config$variables) && length(env_config$variables) > 0) {
      return(env_lines_from_variables(env_config$variables))
    }
  }

  env_default_template_lines()
}

#' Check if .env is gitignored
#'
#' Checks if .env is listed in .gitignore and warns if not.
#'
#' @return Invisibly returns logical indicating if .env is gitignored
#' @keywords internal
.check_env_gitignored <- function() {
  gitignore_path <- ".gitignore"

  if (!file.exists(gitignore_path)) {
    warning(
      ".gitignore not found!\n",
      "  Create one and add '.env' to prevent committing secrets.\n",
      "  Run: writeLines('.env', '.gitignore')",
      call. = FALSE
    )
    return(invisible(FALSE))
  }

  gitignore_content <- readLines(gitignore_path, warn = FALSE)

  # Check for .env entry (exact match or pattern)
  has_env <- any(grepl("^\\.env$|^\\.env\\s|^/\\.env$", gitignore_content))

  if (!has_env) {
    warning(
      ".env is NOT in .gitignore!\n",
      "  Add it to prevent accidentally committing secrets:\n",
      "  cat('\n.env', file = '.gitignore', append = TRUE)",
      call. = FALSE
    )
    return(invisible(FALSE))
  }

  invisible(TRUE)
}

#' Clear R environment
#'
#' Cleans up the R environment by removing objects, closing plots, detaching
#' packages, and running garbage collection. Does not clear the console.
#' Framework itself stays attached.
#'
#' @param keep Character vector of object names to keep (default: empty)
#' @param envir The environment to clear. Required, so nothing is removed by
#'   accident. Use `globalenv()` for your workspace.
#' @return Invisibly returns NULL
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Clean your workspace
#' env_clear(envir = globalenv())
#'
#' # Clean a specific environment
#' env_clear(envir = my_env)
#'
#' # Keep specific objects
#' env_clear(keep = c("config", "data"), envir = my_env)
#' }
#' }
env_clear <- function(keep = character(), envir) {
  if (missing(envir)) {
    stop("Name the environment to clear, such as env_clear(envir = globalenv())", call. = FALSE)
  }
  checkmate::assert_environment(envir)
  checkmate::assert_character(keep, any.missing = FALSE)

  # Remove all objects except those specified in 'keep'
  all_objects <- ls(all.names = TRUE, envir = envir)
  to_remove <- setdiff(all_objects, keep)
  if (length(to_remove) > 0) {
    rm(list = to_remove, envir = envir)
    message(sprintf("[ok] Removed %d object%s", length(to_remove), if (length(to_remove) == 1) "" else "s"))
    if (length(keep) > 0) {
      message(sprintf("  Kept: %s", paste(keep, collapse = ", ")))
    }
  } else {
    message("[ok] No objects to remove")
  }

  # Clear plots
  # dev.off() closes one device at a time
  if (dev.cur() != 1) {
    for (device in rev(dev.list())) {
      tryCatch(dev.off(device), error = function(e) invisible(NULL))
    }
    message("[ok] Cleared plot devices")
  }

  # Detach loaded packages (with dependency resolution to avoid warnings)
  pkgs <- .env_attached_packages()
  if (length(pkgs) > 0) {
    # Build dependency graph and unload in reverse topological order
    suppressWarnings({
      # Get all loaded namespaces
      loaded <- loadedNamespaces()

      # Try to unload packages, silently handling dependency issues
      for (pkg in pkgs) {
        tryCatch(
          detach(paste0("package:", pkg), unload = TRUE, character.only = TRUE),
          error = function(e) invisible(NULL)
        )
      }

      # Force unload namespaces if still loaded
      for (pkg in pkgs) {
        if (pkg %in% loadedNamespaces()) {
          tryCatch(
            unloadNamespace(pkg),
            error = function(e) invisible(NULL)
          )
        }
      }
    })
    message(sprintf("[ok] Detached %d package%s", length(pkgs), if (length(pkgs) == 1) "" else "s"))
  }

  # Run garbage collection
  gc_result <- gc(verbose = FALSE)
  message("[ok] Garbage collection complete")

  invisible(NULL)
}

#' Summarize R environment
#'
#' Displays a summary of the current R environment including loaded packages,
#' objects in the global environment, and memory usage.
#'
#' @param envir The environment to summarize. Use `globalenv()` for your
#'   workspace.
#' @return Invisibly returns a list with environment information
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' env_summary(envir = my_env)
#' }
#' }
env_summary <- function(envir) {
  if (missing(envir)) {
    stop("Name the environment to summarize, such as env_summary(envir = globalenv())", call. = FALSE)
  }
  checkmate::assert_environment(envir)
  env_label <- if (identical(envir, globalenv())) "Global Environment" else {
    name <- environmentName(envir)
    if (nzchar(name)) sprintf("environment '%s'", name) else "the environment"
  }
  message("\n=== Environment Summary ===\n")

  # Session info
  si <- sessionInfo()
  message(sprintf("R Version: %s", R.version.string))
  message(sprintf("Platform: %s", si$platform))
  message("")

  # Loaded packages
  pkgs <- names(si$otherPkgs)
  if (length(pkgs) > 0) {
    message(sprintf("Loaded Packages (%d):", length(pkgs)))
    for (pkg in pkgs) {
      version <- packageVersion(pkg)
      message(sprintf("  - %s (%s)", pkg, version))
    }
  } else {
    message("Loaded Packages: none")
  }
  message("")

  # Global environment objects
  all_objects <- ls(all.names = FALSE, envir = envir)
  hidden_objects <- setdiff(ls(all.names = TRUE, envir = envir), all_objects)

  message(sprintf("Objects in %s: %d", env_label, length(all_objects)))
  if (length(all_objects) > 0) {
    # Group by class
    obj_info <- lapply(all_objects, function(x) {
      obj <- get(x, envir = envir)
      list(
        name = x,
        class = class(obj)[1],
        size = as.numeric(object.size(obj))
      )
    })

    # Show top 10 by size
    obj_df <- do.call(rbind, lapply(obj_info, function(x) {
      data.frame(name = x$name, class = x$class, size = x$size, stringsAsFactors = FALSE)
    }))
    obj_df <- obj_df[order(-obj_df$size), ]

    n_show <- min(10, nrow(obj_df))
    message(sprintf("  Top %d by size:", n_show))
    for (i in 1:n_show) {
      size_mb <- obj_df$size[i] / 1024^2
      size_str <- if (size_mb >= 1) {
        sprintf("%.1f MB", size_mb)
      } else {
        sprintf("%.1f KB", obj_df$size[i] / 1024)
      }
      message(sprintf("    %s [%s] - %s", obj_df$name[i], obj_df$class[i], size_str))
    }
  }

  if (length(hidden_objects) > 0) {
    message(sprintf("  Hidden objects: %d", length(hidden_objects)))
  }
  message("")

  # Memory usage
  gc_result <- gc(verbose = FALSE)
  mem_used_mb <- sum(gc_result[, 2])
  message(sprintf("Memory in use: %.1f MB", mem_used_mb))
  message("")

  # Return info invisibly
  invisible(list(
    r_version = R.version.string,
    platform = si$platform,
    packages = pkgs,
    n_objects = length(all_objects),
    n_hidden = length(hidden_objects),
    memory_mb = mem_used_mb
  ))
}

# Attached packages env_clear() may detach: all but framework itself
#' @keywords internal
.env_attached_packages <- function() {
  setdiff(names(sessionInfo()$otherPkgs), "framework")
}
