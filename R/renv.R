#' Check if renv is enabled for this project
#'
#' Determines whether renv integration is active by checking for the
#' `.framework_renv_enabled` marker file in the project root.
#'
#' @return Logical indicating whether renv is enabled
#' @export
#' @examples
#' if (renv_enabled()) {
#'   message("Using renv for package management")
#' }
renv_enabled <- function() {
  file.exists(".framework_renv_enabled")
}

#' Enable renv for this project
#'
#' Initializes renv integration for the current Framework project. This:
#' - Initializes renv if not already initialized
#' - Copies framework into the project's renv folder from the R
#'   installation in use. It installs framework from GitHub only when no
#'   installed copy is found.
#' - Installs the packages listed in settings.yml (with `sync = TRUE`)
#' - Writes renv.lock with every package in the project's renv folder,
#'   framework and the configured packages included
#' - Updates .gitignore to exclude renv cache
#' - Creates the `.framework_renv_enabled` marker file
#'
#' If a step fails, Framework undoes the steps before it: the marker file,
#' the files renv created, and the `.gitignore` and `.renvignore` changes.
#' The project is then as it was before the call. A package from settings.yml
#' that fails to install gives a warning and is left out of renv.lock.
#'
#' @param sync Logical; if TRUE (default), sync packages from settings.yml
#' @return Invisibly returns TRUE on success
#' @export
#' @examples
#' \donttest{
#' if (FALSE) {
#' renv_enable()
#' }
#' }
renv_enable <- function(sync = TRUE) {
  checkmate::assert_flag(sync)
  if (renv_enabled()) {
    message("renv is already enabled for this project")
    return(invisible(TRUE))
  }

  # Check if renv is installed
  if (!requireNamespace("renv", quietly = TRUE)) {
    stop(
      "renv package is required but not installed.\n",
      "Install it with: install.packages('renv')"
    )
  }

  message("Setting up renv (this may take a moment)...")

  # Record the state before any change, so a failure can undo every step.
  before <- list(
    libpaths = .libPaths(),
    lockfile = file.exists("renv.lock"),
    renv_dir = dir.exists("renv"),
    rprofile = if (file.exists(".Rprofile")) readLines(".Rprofile", warn = FALSE) else NULL,
    gitignore = if (file.exists(".gitignore")) readLines(".gitignore", warn = FALSE) else NULL,
    renvignore = file.exists(".renvignore"),
    renv_project = Sys.getenv("RENV_PROJECT", unset = NA)
  )
  done <- FALSE
  on.exit(if (!done) .fw_renv_rollback(before), add = TRUE)

  pkg_count <- 0
  # Suppress renv output during initialization (capture both stdout and stderr)
  invisible(capture.output({
    # Initialize renv if not already initialized
    if (!before$lockfile) {
      suppressMessages(renv::init(bare = TRUE, restart = FALSE))
    } else {
      suppressMessages(renv::activate())
    }

    # The marker comes first: .sync_packages_to_renv() checks it. The
    # rollback removes it if a later step fails.
    writeLines(
      paste("Enabled at:", Sys.time()),
      ".framework_renv_enabled"
    )

    # Add renv directories to .gitignore if not already present
    .update_gitignore_for_renv()

    # Create .renvignore to exclude Framework data/output directories
    .create_renvignore()

    # framework itself always goes into the project's renv folder
    .fw_renv_install_framework(before$libpaths)

    # Always install rmarkdown when notebooks exist
    # Quarto uses rmarkdown's knitr engine for R code chunks
    if (dir.exists("notebooks") || .has_settings_file()) {
      if (!requireNamespace("rmarkdown", quietly = TRUE)) {
        renv::install("rmarkdown")
      }
    }

    # Sync packages from settings.yml if requested. Per-package install
    # failures are warnings; a failed snapshot is an error.
    if (sync && .has_settings_file()) {
      config <- settings_read()
      pkg_count <- length(.get_package_list_from_config(config))
      .sync_packages_to_renv()
    } else {
      renv::snapshot(type = "all", prompt = FALSE)
    }
  }))

  done <- TRUE

  # Show clean summary
  if (pkg_count > 0) {
    message("\u2713 renv enabled (", pkg_count, " packages installed)")
  } else {
    message("\u2713 renv enabled")
  }

  invisible(TRUE)
}

# Put framework into the project's renv folder. Copy the installed version
# (renv::hydrate() reads the libraries in use before renv started) so the
# lockfile records the framework this project was built with. Install from
# GitHub only when no installed copy exists.
.fw_renv_install_framework <- function(sources = .libPaths()) {
  installed <- find.package("framework", lib.loc = sources, quiet = TRUE)
  if (length(installed) > 0) {
    renv::hydrate(packages = "framework", sources = sources, prompt = FALSE, report = FALSE)
  } else {
    renv::install("frameworktools/framework", rebuild = FALSE, prompt = FALSE)
  }
  invisible(TRUE)
}

# Undo a failed renv_enable(): remove what it created and restore what it
# changed, so the project is not left marked enabled without a lockfile.
.fw_renv_rollback <- function(before) {
  unlink(".framework_renv_enabled")
  if (!before$lockfile) unlink("renv.lock")
  if (!before$renv_dir) unlink("renv", recursive = TRUE)
  if (is.null(before$rprofile)) unlink(".Rprofile") else writeLines(before$rprofile, ".Rprofile")
  if (is.null(before$gitignore)) unlink(".gitignore") else writeLines(before$gitignore, ".gitignore")
  if (!before$renvignore) unlink(".renvignore")
  .libPaths(before$libpaths)
  if (is.na(before$renv_project)) Sys.unsetenv("RENV_PROJECT") else Sys.setenv(RENV_PROJECT = before$renv_project)
  invisible(NULL)
}

#' Disable renv for this project
#'
#' Deactivates renv integration while preserving renv.lock for future use.
#' Removes the `.framework_renv_enabled` marker file.
#'
#' @param keep_renv Logical; if TRUE (default), keep renv.lock and renv/ directory
#' @return Invisibly returns TRUE on success
#' @export
#' @examples
#' \donttest{
#' if (FALSE) {
#' renv_disable()
#' }
#' }
renv_disable <- function(keep_renv = TRUE) {
  if (!renv_enabled()) {
    message("renv is not currently enabled for this project")
    return(invisible(TRUE))
  }

  # Deactivate renv if active
  if (requireNamespace("renv", quietly = TRUE)) {
    renv::deactivate()
  }

  # Remove marker file
  if (file.exists(".framework_renv_enabled")) {
    file.remove(".framework_renv_enabled")
  }

  if (keep_renv) {
    message(
      "\n",
      "\u2139 renv disabled\n\n",
      "Your renv.lock file has been preserved.\n",
      "Use renv_enable() to re-activate renv integration."
    )
  } else {
    # Remove renv files
    if (file.exists("renv.lock")) file.remove("renv.lock")
    if (dir.exists("renv")) unlink("renv", recursive = TRUE)

    message(
      "\n",
      "\u2139 renv disabled and removed\n\n",
      "All renv files have been deleted.\n",
      "Use renv_enable() to set up renv from scratch."
    )
  }

  invisible(TRUE)
}

#' Update .gitignore for renv
#'
#' Adds renv-related entries to .gitignore if they don't already exist.
#'
#' @return Invisibly returns NULL
#' @keywords internal
.update_gitignore_for_renv <- function() {
  gitignore_path <- ".gitignore"

  # Create .gitignore if it doesn't exist
  if (!file.exists(gitignore_path)) {
    writeLines("", gitignore_path)
  }

  existing <- readLines(gitignore_path, warn = FALSE)

  # Entries to add
  renv_entries <- c(
    "",
    "# renv",
    "renv/library/",
    "renv/local/",
    "renv/cellar/",
    "renv/lock/",
    "renv/python/",
    "renv/sandbox/",
    "renv/staging/"
  )

  # Only add if not already present
  if (!any(grepl("^# renv$", existing))) {
    writeLines(c(existing, renv_entries), gitignore_path)
    message("Updated .gitignore with renv entries")
  }

  invisible(NULL)
}

#' Create .renvignore file for Framework projects
#'
#' Creates a .renvignore file that excludes Framework data and output
#' directories from renv dependency scanning.
#'
#' @return Invisibly returns NULL
#' @keywords internal
.create_renvignore <- function() {
  renvignore_path <- ".renvignore"

  # Skip if already exists
  if (file.exists(renvignore_path)) {
    return(invisible(NULL))
  }

  renvignore_content <- c(
    "# Exclude Framework data and output directories from renv tracking",
    "data/",
    "results/",
    "scratch/",
    "work/",
    "",
    "# R project files",
    "*.Rproj",
    ".Rproj.user",
    "",
    "# Framework markers",
    ".framework_renv_enabled"
  )

  writeLines(renvignore_content, renvignore_path)

  invisible(NULL)
}
