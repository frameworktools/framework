#' Extract package list from config
#'
#' Handles two config structures:
#' 1. New: packages = list(use_renv = ..., default_packages = ...)
#' 2. Old: packages as a flat list of package specs
#'
#' @param config Configuration object from settings_read()
#' @return List of package specifications, or empty list if none
#' @keywords internal
.get_package_list_from_config <- function(config) {
  if (is.null(config$packages)) {
    return(list())
  }

  # New structure: packages$default_packages
  if (!is.null(config$packages$default_packages)) {
    return(config$packages$default_packages)
  }

  # Old structure: packages as flat list
  # Filter out non-package entries (like use_renv boolean)
  config$packages
}

#' Parse package specification with source detection
#'
#' Parses package specifications that may include explicit sources, version pins,
#' or GitHub/Bioconductor references. Supports both scalar strings and list-style
#' entries from `settings.yml`.
#'
#' Examples:
#' - "dplyr" -> list(name = "dplyr", source = "cran")
#' - "dplyr@1.1.0" -> list(name = "dplyr", version = "1.1.0", source = "cran")
#' - "tidyverse/dplyr@main" -> list(name = "dplyr", repo = "tidyverse/dplyr", ref = "main", source = "github")
#' - list(name = "DESeq2", source = "bioc") -> list(name = "DESeq2", source = "bioc")
#'
#' @param spec Character or list describing the package
#' @return List with normalized components (name, source, version, repo, ref, auto_attach)
#' @keywords internal
.parse_package_spec <- function(spec) {
  .normalize_package_spec(spec)
}

#' Normalize package specification from config
#'
#' Converts the various package representations supported in settings.yml into a
#' consistent structure that downstream helpers can rely on.
#'
#' @param spec Character string or list describing a package dependency
#' @return List with fields: name, source, version, repo, ref, auto_attach
#' @keywords internal
.normalize_package_spec <- function(spec) {
  if (is.null(spec)) {
    return(NULL)
  }

  if (is.list(spec)) {
    return(.normalize_package_list_spec(spec))
  }

  if (is.character(spec) && length(spec) == 1) {
    return(.normalize_package_string_spec(spec))
  }

  stop("Unsupported package specification type: ", class(spec)[1])
}

.normalize_package_string_spec <- function(spec) {
  spec <- trimws(spec)
  if (identical(spec, "")) {
    stop("Package specification cannot be empty")
  }

  auto_attach <- FALSE

  # Bioconductor shorthand: bioc::pkg
  if (grepl("^bioc::", spec, ignore.case = TRUE)) {
    pkg_name <- sub("^bioc::", "", spec, ignore.case = TRUE)
    return(list(
      name = pkg_name,
      source = "bioc",
      version = NULL,
      repo = NULL,
      ref = NULL,
      auto_attach = auto_attach
    ))
  }

  # GitHub shorthand: user/repo@ref or user/repo
  if (grepl("/", spec, fixed = TRUE)) {
    parts <- strsplit(spec, "@", fixed = TRUE)[[1]]
    repo <- trimws(parts[1])
    ref <- if (length(parts) > 1) trimws(parts[2]) else "HEAD"
    pkg_name <- basename(repo)

    return(list(
      name = pkg_name,
      source = "github",
      version = NULL,
      repo = repo,
      ref = ref,
      auto_attach = auto_attach
    ))
  }

  # CRAN shorthand: package or package@version
  parts <- strsplit(spec, "@", fixed = TRUE)[[1]]
  pkg_name <- trimws(parts[1])
  version <- if (length(parts) > 1) trimws(parts[2]) else NULL

  list(
    name = pkg_name,
    source = "cran",
    version = version,
    repo = NULL,
    ref = NULL,
    auto_attach = auto_attach
  )
}

.normalize_package_list_spec <- function(spec) {
  auto_attach <- isTRUE(spec$auto_attach) ||
    isTRUE(spec$attached) ||
    isTRUE(spec$load) ||
    isTRUE(spec$scaffold)

  pkg_name_raw <- spec$name %||% spec$package

  base_spec <- list(
    name = NULL,
    source = NULL,
    version = NULL,
    repo = NULL,
    ref = NULL
  )

  if (!is.null(pkg_name_raw)) {
    base_spec <- tryCatch(
      .normalize_package_string_spec(pkg_name_raw),
      error = function(e) {
        list(
          name = pkg_name_raw,
          source = NULL,
          version = NULL,
          repo = NULL,
          ref = NULL,
          auto_attach = FALSE
        )
      }
    )
  }

  source <- spec$source
  if (!is.null(source)) {
    source <- tolower(as.character(source))
    if (source %in% c("bioconductor", "bioc", "bio")) {
      source <- "bioc"
    }
  }
  source <- source %||% base_spec$source %||% "cran"

  repo <- spec$repo %||% spec$source_repo %||% base_spec$repo
  ref <- spec$ref %||% spec$branch %||% spec$tag %||% base_spec$ref
  version <- spec$version %||% spec$ver %||% base_spec$version

  name <- base_spec$name %||% pkg_name_raw

  if (source == "github") {
    if (is.null(repo)) {
      if (!is.null(pkg_name_raw) && grepl("/", pkg_name_raw, fixed = TRUE)) {
        repo <- sub("@.*$", "", pkg_name_raw)
        ref <- ref %||% sub("^.*@", "", pkg_name_raw)
        if (identical(repo, ref)) {
          ref <- NULL
        }
      }
    }

    if (is.null(repo)) {
      stop("GitHub package requires a 'repo' field or a 'name' containing 'owner/repo'")
    }

    name <- basename(repo)
    if (is.null(ref) || identical(ref, repo)) {
      ref <- base_spec$ref %||% "HEAD"
    }
    if (identical(ref, "")) {
      ref <- "HEAD"
    }
    version <- NULL
  } else if (source == "bioc") {
    name <- name %||% pkg_name_raw
    if (is.null(name)) {
      stop("Bioconductor package requires a 'name' field")
    }
    repo <- NULL
    ref <- NULL
  } else if (source == "cran") {
    name <- name %||% pkg_name_raw
    if (is.null(name)) {
      stop("CRAN package requires a 'name' field")
    }
    repo <- NULL
    ref <- NULL
  }

  list(
    name = name,
    source = source,
    version = version,
    repo = repo,
    ref = ref,
    auto_attach = auto_attach
  )
}

# The package repositories to install from: getOption("repos"), with the
# cloud CRAN mirror when CRAN is unset ("@CRAN@" or missing), as under
# Rscript without a site profile
#' @keywords internal
.fw_cran_repos <- function() {
  repos <- getOption("repos")
  if (is.null(repos) || length(repos) == 0) repos <- c(CRAN = "@CRAN@")
  cran <- if ("CRAN" %in% names(repos)) repos[["CRAN"]] else NA_character_
  if (is.na(cran) || !nzchar(cran) || identical(cran, "@CRAN@")) {
    repos[["CRAN"]] <- "https://cloud.r-project.org"
  }
  repos
}

.ensure_biocmanager_installed <- function(use_renv = FALSE) {
  if (requireNamespace("BiocManager", quietly = TRUE)) {
    return(invisible(TRUE))
  }

  if (use_renv) {
    renv::install("BiocManager")
  } else {
    message("Installing BiocManager from CRAN...")
    install.packages("BiocManager")
  }

  invisible(TRUE)
}

#' Install package via renv
#'
#' Installs a package using renv, handling version pinning and GitHub sources.
#'
#' @param spec Parsed package specification from .parse_package_spec()
#' @return Invisibly returns TRUE on success
#' @keywords internal
.install_package_renv <- function(spec) {
  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }
  old <- options(repos = .fw_cran_repos())
  on.exit(options(old), add = TRUE)

  source <- spec$source %||% "cran"

  if (identical(source, "github")) {
    # Install from GitHub
    pkg_ref <- if (!is.null(spec$ref) && spec$ref != "HEAD") {
      paste0(spec$repo, "@", spec$ref)
    } else {
      spec$repo
    }
    renv::install(pkg_ref)
  } else if (identical(source, "bioc")) {
    .ensure_biocmanager_installed(use_renv = TRUE)
    renv::install(paste0("bioc::", spec$name))
  } else if (identical(source, "cran")) {
    # Install from CRAN
    if (!is.null(spec$version)) {
      pkg_ref <- paste0(spec$name, "@", spec$version)
      renv::install(pkg_ref)
    } else {
      renv::install(spec$name)
    }
  } else {
    stop("Unsupported package source: ", source)
  }

  invisible(TRUE)
}

#' Install package without renv
#'
#' Installs a package using base R functions, handling version pinning and GitHub sources.
#'
#' @param spec Parsed package specification from .parse_package_spec()
#' @return Invisibly returns TRUE on success
#' @keywords internal
.install_package_base <- function(spec) {
  source <- spec$source %||% "cran"
  old <- options(repos = .fw_cran_repos())
  on.exit(options(old), add = TRUE)

  if (identical(source, "github")) {
    # Install from GitHub using remotes
    if (!requireNamespace("remotes", quietly = TRUE)) {
      install.packages("remotes")
    }

    pkg_ref <- if (!is.null(spec$ref) && spec$ref != "HEAD") {
      paste0(spec$repo, "@", spec$ref)
    } else {
      spec$repo
    }
    message("Installing ", spec$name, " from GitHub (", pkg_ref, ")...")
    remotes::install_github(pkg_ref)
  } else if (identical(source, "bioc")) {
    .ensure_biocmanager_installed(use_renv = FALSE)
    message("Installing ", spec$name, " from Bioconductor...")
    BiocManager::install(spec$name, update = FALSE, ask = FALSE)
  } else if (identical(source, "cran")) {
    # Install from CRAN
    if (!is.null(spec$version)) {
      # For version pinning without renv, use remotes::install_version
      if (!requireNamespace("remotes", quietly = TRUE)) {
        install.packages("remotes")
      }
      message("Installing ", spec$name, " version ", spec$version, "...")
      remotes::install_version(
        spec$name,
        version = spec$version,
        upgrade = "never"
      )
    } else {
      message("Installing ", spec$name, " from CRAN...")
      utils::install.packages(spec$name)
    }
  } else {
    stop("Unsupported package source: ", source)
  }

  invisible(TRUE)
}

#' Sync packages from settings.yml to renv
#'
#' Reads the packages list from settings.yml and installs them via renv,
#' then snapshots the result to renv.lock.
#'
#' @return Invisibly returns TRUE on success
#' @keywords internal
.sync_packages_to_renv <- function() {
  if (!renv_enabled()) {
    warning("renv is not enabled. Use renv_enable() first.")
    return(invisible(FALSE))
  }

  # Check if settings file exists
  tryCatch({
    config <- settings_read()
  }, error = function(e) {
    warning("Settings file not found")
    return(invisible(FALSE))
  })

  package_list <- .get_package_list_from_config(config)
  if (length(package_list) == 0) {
    renv::snapshot(type = "all", prompt = FALSE)
    return(invisible(TRUE))
  }

  # Install each package via renv
  for (pkg_spec in package_list) {
    spec <- tryCatch(
      .parse_package_spec(pkg_spec),
      error = function(e) {
        warning("Failed to parse package specification: ", conditionMessage(e))
        return(NULL)
      }
    )

    if (is.null(spec)) {
      next
    }

    # Check if package is already installed at correct version
    if (requireNamespace(spec$name, quietly = TRUE)) {
      if (is.null(spec$version)) {
        # No version pin, already installed - skip
        next
      } else {
        # Check if installed version matches
        installed_ver <- as.character(packageVersion(spec$name))
        if (installed_ver == spec$version) {
          next
        }
      }
    }

    # Install the package
    tryCatch(
      .install_package_renv(spec),
      error = function(e) {
        warning("Failed to install ", spec$name, ": ", e$message)
      }
    )
  }

  # Snapshot to renv.lock. type = "all" records every package in the
  # project's renv folder. The default ("implicit") keeps only packages the
  # code calls with library(), so configured packages and framework were
  # left out of the lockfile.
  renv::snapshot(type = "all", prompt = FALSE)

  invisible(TRUE)
}

#' Snapshot current package versions to renv.lock
#'
#' Internal wrapper around renv::snapshot(). Use packages_snapshot() instead.
#'
#' @param prompt Logical; if TRUE, prompt before creating snapshot
#' @return Invisibly returns TRUE on success
#' @keywords internal
renv_snapshot <- function(prompt = FALSE) {
  if (!renv_enabled()) {
    stop(
      "renv is not enabled for this project.\n",
      "Use renv_enable() to enable renv integration."
    )
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  message("Creating snapshot of current package versions...")
  renv::snapshot(prompt = prompt)

  message(cli::col_green(cli::symbol$tick), " Snapshot saved to renv.lock")

  invisible(TRUE)
}

#' Restore packages from renv.lock
#'
#' Internal wrapper around renv::restore(). Use packages_restore() instead.
#'
#' @param prompt Logical; if TRUE, prompt before restoring
#' @return Invisibly returns TRUE on success
#' @keywords internal
renv_restore <- function(prompt = FALSE) {
  if (!renv_enabled()) {
    stop(
      "renv is not enabled for this project.\n",
      "Use renv_enable() to enable renv integration."
    )
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  if (!file.exists("renv.lock")) {
    stop("No renv.lock file found. Run renv_snapshot() first.")
  }

  message("Restoring packages from renv.lock...")
  renv::restore(prompt = prompt)

  message(cli::col_green(cli::symbol$tick), " Packages restored successfully!")

  invisible(TRUE)
}

#' Show package status
#'
#' Internal wrapper around renv::status(). Use packages_status() instead.
#'
#' @return Invisibly returns the status object from renv::status()
#' @keywords internal
renv_status <- function() {
  if (!renv_enabled()) {
    stop(
      "renv is not enabled for this project.\n",
      "Use renv_enable() to enable renv integration."
    )
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  renv::status()
}

#' Sync packages with renv.lock
#'
#' Internal function that resolves inconsistencies between installed packages
#' and renv.lock by restoring then snapshotting.
#'
#' @param prompt Logical; if TRUE, prompt before making changes
#' @return Invisibly returns TRUE on success
#' @keywords internal
renv_sync <- function(prompt = FALSE) {
  if (!renv_enabled()) {
    stop(
      "renv is not enabled for this project.\n",
      "Use renv_enable() to enable renv integration."
    )
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  message("Synchronizing packages with renv.lock...")
  message("")

  # Step 1: Install missing packages
  message("1. Installing missing packages...")
  tryCatch({
    renv::restore(prompt = prompt)
  }, error = function(e) {
    # renv::restore() throws an error if nothing to restore, which is fine
    if (!grepl("nothing to restore", e$message, ignore.case = TRUE)) {
      warning("Error during restore: ", e$message)
    }
  })

  # Step 2: Record installed packages to renv.lock
  message("2. Recording installed packages to renv.lock...")
  renv::snapshot(prompt = prompt)

  message("")
  message(cli::col_green(cli::symbol$tick), " Packages synchronized!")
  message("")
  message("All packages are now consistent with renv.lock")

  invisible(TRUE)
}

#' Update packages
#'
#' Internal wrapper around renv::update(). Use packages_update() instead.
#'
#' @param packages Character vector of package names to update, or NULL for all
#' @return Invisibly returns TRUE on success
#' @keywords internal
renv_update <- function(packages = NULL) {
  if (!renv_enabled()) {
    stop(
      "renv is not enabled for this project.\n",
      "Use renv_enable() to enable renv integration."
    )
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  if (is.null(packages)) {
    message("Updating all packages...")
    renv::update()
  } else {
    message("Updating ", length(packages), " package(s)...")
    renv::update(packages = packages)
  }

  message(cli::col_green(cli::symbol$tick), " Packages updated!")

  invisible(TRUE)
}

#' Add a package to the project
#'
#' Records a package in the project's settings (in `settings/packages.yml`
#' when the project uses split settings files, otherwise in `settings.yml`)
#' and installs it if it isn't installed yet. Recording the package is what
#' makes it reproducible: [scaffold()] and [packages_install()] install
#' everything listed, and auto-attached packages are loaded by [scaffold()].
#'
#' Adding a package that is already listed replaces its entry, so this is
#' also how to pin a version or turn auto-attach on or off.
#'
#' Afterward, the Installed Packages section of the project's AI context file
#' (`ai.canonical_file`, else AGENTS.md, else CLAUDE.md) is rewritten from the
#' package settings, so agents see the new package. Only the section marked
#' `<!-- @framework:regenerate -->` changes; remove the marker to opt out.
#'
#' @param package Package specification: `"janitor"`, a pinned CRAN version
#'   (`"dplyr@1.1.0"`), a GitHub repository (`"tidyverse/dplyr@main"`), or a
#'   Bioconductor package (`"bioc::DESeq2"`).
#' @param auto_attach Logical. Whether [scaffold()] loads the package. Default
#'   FALSE.
#' @param install Logical. Install the package now if it isn't installed (or
#'   the installed version doesn't match a pin). Default TRUE. If the install
#'   fails, the settings are left as they were and `package_add()` stops.
#'
#' @return Invisibly, the package entry that was recorded.
#' @export
#'
#' @seealso [packages_list()], [packages_install()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' package_add("janitor")
#' package_add("forcats", auto_attach = TRUE)
#' package_add("tidyverse/dplyr@main")
#' package_add("dplyr@1.1.0")
#' }
#' }
package_add <- function(package, auto_attach = FALSE, install = TRUE) {
  checkmate::assert_string(package, min.chars = 1)
  checkmate::assert_flag(auto_attach)
  checkmate::assert_flag(install)

  settings_file <- .get_settings_file()
  if (is.null(settings_file)) {
    stop("No settings.yml found. Run package_add() inside a Framework project.", call. = FALSE)
  }

  spec <- .normalize_package_spec(package)
  # R package names: letters, digits, and dots, starting with a letter and
  # not ending in a dot (as the Python package checks its names)
  if (!is.character(spec$name) || !grepl("^[A-Za-z][A-Za-z0-9.]*[A-Za-z0-9]$", spec$name)) {
    stop("Not a valid package name: ", package, call. = FALSE)
  }
  entry <- list(name = spec$name, source = spec$source)
  if (!is.null(spec$version)) entry$version <- spec$version
  if (!is.null(spec$repo)) entry$repo <- spec$repo
  if (!is.null(spec$ref)) entry$ref <- spec$ref
  entry$auto_attach <- auto_attach

  find_entry <- function(packages) {
    names_listed <- vapply(packages, function(p) {
      tryCatch(.normalize_package_spec(p)$name %||% "", error = function(e) "")
    }, character(1))
    which(names_listed == entry$name)
  }
  previous <- NULL
  .packages_edit(settings_file, function(packages) {
    hit <- find_entry(packages)
    if (length(hit) > 0) {
      previous <<- packages[[hit[1]]]
      packages[[hit[1]]] <- entry
      message("Updated ", entry$name, " in the project's packages")
    } else {
      packages <- c(packages, list(entry))
      message("Added ", entry$name, " to the project's packages")
    }
    packages
  })

  if (install) {
    installed <- tryCatch({
      .install_package(entry)
      requireNamespace(entry$name, quietly = TRUE)
    }, error = function(e) {
      warning("Failed to install ", entry$name, ": ", conditionMessage(e), call. = FALSE)
      FALSE
    })
    if (!installed) {
      # Leave settings as they were, so a typo or failed install is not recorded
      .packages_edit(settings_file, function(packages) {
        hit <- find_entry(packages)
        if (length(hit) == 0) return(packages)
        if (is.null(previous)) packages[-hit[1]] else {
          packages[[hit[1]]] <- previous
          packages
        }
      })
      stop(entry$name, " could not be installed, so it was not added. ",
           "Use install = FALSE to record it anyway.", call. = FALSE)
    }
  }

  .fw_refresh_agents_md(settings_file)
  invisible(entry)
}

#' Add a package set to the project
#'
#' Adds a package set's packages to an existing project. Packages the project
#' already lists are left as they are. The rest are recorded as
#' [package_add()] records them, with each package's source, repository, and
#' auto-attach setting from the set. Sets also stack at creation with
#' `new_project(package_sets = ...)`. As with [package_add()], the Installed
#' Packages section of the project's AI context file is then rewritten.
#'
#' A set is one of Framework's built-in sets for R, such as
#' `"tidyverse-analysis"` or `"bayes-r"`. See [package_sets_list()]. When you
#' are signed in to Framework Cloud, a handle such as `"@yourname/lab-tools"` adds one
#' of your account's sets.
#'
#' @param set Package set id or Framework Cloud handle.
#' @param install Logical. Install the added packages now. Default TRUE. A
#'   failed install leaves the package recorded and warns.
#'
#' @return Invisibly, a list with `added` and `present`: the names of the
#'   packages added and those the project already listed.
#' @export
#'
#' @seealso [package_sets_list()], [package_add()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' package_set_add("bayes-r")
#' package_set_add("tidy-omop", install = FALSE)
#' }
#' }
package_set_add <- function(set, install = TRUE) {
  checkmate::assert_string(set, min.chars = 1)
  checkmate::assert_flag(install)

  settings_file <- .get_settings_file()
  if (is.null(settings_file)) {
    stop("No settings.yml found. Run package_set_add() inside a Framework project.", call. = FALSE)
  }

  definition <- .fw_package_set(set)
  wanted <- definition$layer$packages$default_packages %||% list()
  entries <- lapply(names(wanted), function(name) {
    pkg <- wanted[[name]]
    entry <- list(name = name, source = pkg$source %||% "cran")
    if (!is.null(pkg$version)) entry$version <- pkg$version
    if (!is.null(pkg$repo)) entry$repo <- pkg$repo
    if (!is.null(pkg$ref)) entry$ref <- pkg$ref
    entry$auto_attach <- isTRUE(pkg$auto_attach)
    entry
  })

  added <- list()
  present <- character()
  .packages_edit(settings_file, function(packages) {
    listed <- vapply(packages, function(p) {
      tryCatch(.normalize_package_spec(p)$name %||% "", error = function(e) "")
    }, character(1))
    for (entry in entries) {
      if (entry$name %in% listed) {
        present <<- c(present, entry$name)
      } else {
        packages <- c(packages, list(entry))
        added <<- c(added, list(entry))
      }
    }
    packages
  })

  added_names <- vapply(added, `[[`, "", "name")
  if (length(added_names) > 0) {
    message("Added ", length(added_names), " package(s) from ", definition$name, ": ",
            paste(added_names, collapse = ", "))
    .fw_refresh_agents_md(settings_file)
  } else {
    message("The project already lists every package in ", definition$name, ".")
  }
  if (length(present) > 0) {
    message("Already listed: ", paste(present, collapse = ", "))
  }

  if (install && length(added) > 0) {
    failed <- character()
    for (entry in added) {
      ok <- tryCatch({
        .install_package(entry)
        requireNamespace(entry$name, quietly = TRUE)
      }, error = function(e) FALSE)
      if (!isTRUE(ok)) failed <- c(failed, entry$name)
    }
    if (length(failed) > 0) {
      warning("Could not install ", paste(failed, collapse = ", "),
              ". They are recorded; run packages_install() to try again.", call. = FALSE)
    }
  }

  invisible(list(added = added_names, present = present))
}

# Rewrite the Installed Packages section of the project's AI context file
# (ai.canonical_file, else AGENTS.md, else CLAUDE.md) from the package
# settings, as ai_regenerate_context(sections = "packages") does. Only a file
# with the marked heading changes. A file that can't be read or written is
# skipped quietly. Shared with framework-py.
#' @keywords internal
.fw_refresh_agents_md <- function(settings_file) {
  root <- dirname(settings_file)
  config <- tryCatch(settings_read(settings_file), error = function(e) NULL)
  if (is.null(config)) return(invisible(NULL))

  canonical <- config$ai$canonical_file
  candidates <- c(
    if (is.character(canonical) && length(canonical) == 1 && nzchar(canonical)) canonical,
    "AGENTS.md", "CLAUDE.md"
  )
  ai_file <- NULL
  for (candidate in candidates) {
    candidate_path <- file.path(root, candidate)
    if (file.exists(candidate_path) && !dir.exists(candidate_path)) {
      ai_file <- candidate
      break
    }
  }
  if (is.null(ai_file)) return(invisible(NULL))
  ai_path <- file.path(root, ai_file)

  content <- tryCatch(
    paste(readLines(ai_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) NULL,
    warning = function(w) NULL
  )
  if (is.null(content)) return(invisible(NULL))
  if (!grepl("## Installed Packages <!-- @framework:regenerate -->", content, fixed = TRUE)) {
    return(invisible(NULL))
  }

  updated <- tryCatch(
    .replace_section(content, "Installed Packages", .generate_packages_section(config)),
    error = function(e) content
  )
  if (identical(updated, content)) return(invisible(NULL))
  written <- tryCatch({
    writeLines(enc2utf8(updated), ai_path, useBytes = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (isTRUE(written)) {
    message("\u2713 Updated the package list in ", basename(ai_file))
  }
  invisible(NULL)
}

#' List package sets
#'
#' Framework's built-in package sets for R projects. Add one to a project
#' with [package_set_add()], or at creation with
#' `new_project(package_sets = ...)`.
#'
#' @return A data frame with `id`, `name`, `description`, and `packages` (the
#'   package names, comma-separated).
#' @export
#'
#' @seealso [package_set_add()]
#'
#' @examples
#' package_sets_list()
package_sets_list <- function() {
  sets <- Filter(function(d) "r" %in% unlist(d$language), .fw_package_sets())
  data.frame(
    id = vapply(sets, `[[`, "", "id"),
    name = vapply(sets, `[[`, "", "name"),
    description = vapply(sets, `[[`, "", "description"),
    packages = vapply(sets, function(d) {
      paste(names(d$layer$packages$default_packages), collapse = ", ")
    }, ""),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

# One package set for an R project: a built-in set by id (or its
# "framework/" handle), or an account's set by handle, resolved by
# Framework Cloud as new_project() resolves chosen sets
#' @keywords internal
.fw_package_set <- function(set, language = "r") {
  if (grepl("/", set, fixed = TRUE) && !startsWith(set, "framework/")) {
    return(.fw_cloud_package_set(set, language))
  }
  id <- sub("^framework/", "", set)
  sets <- .fw_package_sets()
  available <- names(Filter(function(d) language %in% unlist(d$language), sets))
  definition <- sets[[id]]
  if (is.null(definition)) {
    stop("Unknown package set: ", id, ". Available: ", paste(available, collapse = ", "), call. = FALSE)
  }
  if (!language %in% unlist(definition$language)) {
    stop("The ", definition$name, " package set isn't available for R projects. Available: ",
         paste(available, collapse = ", "), call. = FALSE)
  }
  definition
}

#' @keywords internal
.fw_cloud_package_set <- function(handle, language = "r") {
  token <- .fw_cloud_token()
  if (is.null(token)) {
    stop(handle, " is a Framework Cloud package set. Sign in with cloud_login() first.", call. = FALSE)
  }
  url <- .fw_cloud_url()
  res <- .fw_resolve_request(list(language = language, package_sets = list(handle)), token, url)
  if (!identical(res$status, "ok")) {
    stop(.fw_cloud_host(url), " can't be reached (", res$reason, "), so ", handle,
         " can't be looked up.", call. = FALSE)
  }
  for (notice in res$notices) message(notice)
  entry <- Find(function(layer) identical(layer$key, handle), res$envelope$layers %||% list())
  if (is.null(entry)) {
    stop("The ", handle, " package set isn't available for R projects.", call. = FALSE)
  }
  list(id = handle, name = handle, layer = entry$layer)
}

# Apply `edit` to the project's package list and write it back where it lives:
# a split file (settings/packages.yml) or the packages section of the main
# settings file. Handles both the default_packages structure and the older
# flat list.
#' @keywords internal
.packages_edit <- function(settings_file, edit) {
  env <- Sys.getenv("R_CONFIG_ACTIVE", Sys.getenv("R_CONFIG_NAME", "default"))
  main <- .fw_read_yaml(settings_file)
  section <- if (!is.null(main[[env]])) main[[env]]$packages else main$packages

  edit_node <- function(node) {
    node <- node %||% list(default_packages = list())
    # A flat list of names reads back from YAML as a character vector
    if (is.character(node)) node <- as.list(node)
    if (is.list(node) && !is.null(names(node)) && any(names(node) %in% c("default_packages", "use_renv"))) {
      node$default_packages <- edit(node$default_packages %||% list())
    } else {
      node <- edit(node)
    }
    node
  }

  if (is.character(section) && length(section) == 1 && grepl("\\.ya?ml$", section)) {
    split_file <- file.path(dirname(settings_file), section)
    if (!file.exists(split_file)) {
      stop("Split file '", section, "' does not exist", call. = FALSE)
    }
    split <- .fw_read_yaml(split_file) %||% list()
    if ("packages" %in% names(split)) {
      .fw_yaml_set(split_file, "packages", edit_node(split$packages))
    } else {
      .fw_write_yaml(edit_node(split), split_file)
    }
    return(invisible(split_file))
  }

  .fw_yaml_set(settings_file, c(if (!is.null(main[[env]])) env, "packages"), edit_node(section))
  invisible(settings_file)
}

#' Install packages from configuration
#'
#' Installs all packages defined in the configuration that are not already installed.
#' This is the same logic used in scaffold(), but exposed as a standalone function.
#'
#' @return Invisibly returns TRUE on success
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Install all configured packages
#' packages_install()
#' }
#' }
packages_install <- function() {
  config <- settings_read()

  package_list <- .get_package_list_from_config(config)
  if (length(package_list) == 0) {
    message("No packages found in configuration")
    return(invisible(TRUE))
  }

  # Use the same logic as scaffold()
  message("Installing packages from configuration...")
  .install_required_packages(config)
  message("\nPackages installed!")

  invisible(TRUE)
}


#' Update packages from configuration
#'
#' Updates packages defined in the configuration. If renv is enabled, uses renv::update().
#' Otherwise, reinstalls packages using standard installation methods.
#'
#' @param packages Character vector of specific packages to update, or NULL to update all
#' @return Invisibly returns TRUE on success
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Update all packages
#' packages_update()
#'
#' # Update specific packages
#' packages_update(c("dplyr", "ggplot2"))
#' }
#' }
packages_update <- function(packages = NULL) {
  if (!renv_enabled()) {
    stop("renv is not enabled. Use renv_enable() first.")
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  if (is.null(packages)) {
    message("Updating all packages...")
    renv::update()
  } else {
    message("Updating ", length(packages), " package(s)...")
    renv::update(packages = packages)
  }

  message(cli::col_green(cli::symbol$tick), " Packages updated!")

  invisible(TRUE)
}


#' List all packages from configuration
#'
#' Lists all packages defined in the configuration, showing the package name,
#' version pin (if specified), and source (CRAN or GitHub).
#'
#' @return Invisibly returns NULL after printing package list
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # List all packages
#' packages_list()
#' }
#' }
packages_list <- function() {
  config <- settings_read()

  package_list <- .get_package_list_from_config(config)
  if (length(package_list) == 0) {
    message("No packages found in configuration")
    return(invisible(NULL))
  }

  # Print formatted output
  message(sprintf("\n%d %s found:\n",
                  length(package_list),
                  if (length(package_list) == 1) "package" else "packages"))

  for (pkg_spec in package_list) {
    spec <- tryCatch(
      .parse_package_spec(pkg_spec),
      error = function(e) {
        warning("Failed to parse package specification: ", conditionMessage(e))
        return(NULL)
      }
    )

    if (is.null(spec)) {
      next
    }

    source_label <- switch(
      spec$source,
      github = sprintf("GitHub: %s%s",
        spec$repo,
        if (!is.null(spec$ref) && spec$ref != "HEAD") paste0("@", spec$ref) else ""
      ),
      bioc = "Bioconductor",
      cran = "CRAN",
      toupper(spec$source)
    )

    version_label <- if (!is.null(spec$version)) sprintf(" (v%s)", spec$version) else ""

    message(sprintf("- %s [%s]%s", spec$name, source_label, version_label))
    message(sprintf("  Auto-attach: %s", if (isTRUE(spec$auto_attach)) "yes" else "no"))
    message("")
  }

  invisible(NULL)
}


#' Snapshot current package library (renv)
#'
#' Wrapper around `renv::snapshot()` that requires Framework's renv integration
#' to be enabled first.
#'
#' @param prompt Logical. If TRUE, renv prompts before writing the snapshot.
#' @return Invisibly returns TRUE on success.
#' @export
packages_snapshot <- function(prompt = FALSE) {
  if (!renv_enabled()) {
    stop("renv is not enabled. Use renv_enable() first.")
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  renv::snapshot(prompt = prompt)
  invisible(TRUE)
}

#' Restore packages from renv.lock
#'
#' Wrapper around `renv::restore()` that requires Framework's renv integration
#' to be enabled first.
#'
#' @param prompt Logical. If TRUE, renv prompts before restoring.
#' @return Invisibly returns TRUE on success.
#' @export
packages_restore <- function(prompt = FALSE) {
  if (!renv_enabled()) {
    stop("renv is not enabled. Use renv_enable() first.")
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  renv::restore(prompt = prompt)
  invisible(TRUE)
}

#' Show package status
#'
#' With Framework's renv integration on, a wrapper around `renv::status()`.
#' With renv off, there is no lockfile to compare with, so it reports which
#' packages in settings.yml are installed instead of stopping.
#'
#' @return With renv on, the status object returned by `renv::status()`.
#'   With renv off, invisibly a data frame with columns `package`,
#'   `installed`, and `version`, one row per package in settings.yml.
#' @export
packages_status <- function() {
  if (!renv_enabled()) {
    return(.packages_status_without_renv())
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("renv package is required but not installed")
  }

  renv::status()
}

# packages_status() with renv off: which configured packages are installed
.packages_status_without_renv <- function() {
  config <- tryCatch(settings_read(), error = function(e) list())
  specs <- lapply(.get_package_list_from_config(config), function(spec) {
    tryCatch(.parse_package_spec(spec), error = function(e) NULL)
  })
  names <- unique(vapply(Filter(Negate(is.null), specs), function(x) x$name, character(1)))
  versions <- vapply(names, function(name) {
    if (!nzchar(system.file(package = name))) return(NA_character_)
    as.character(utils::packageVersion(name))
  }, character(1), USE.NAMES = FALSE)
  status <- data.frame(package = names, installed = !is.na(versions), version = versions,
                       stringsAsFactors = FALSE)

  message("renv is off for this project, so there is no renv.lock to compare with. ",
          "Turn it on with renv_enable().")
  if (nrow(status) == 0) {
    message("No packages in settings.yml.")
  } else {
    missing <- status$package[!status$installed]
    message(sprintf("%d of %d packages in settings.yml are installed.",
                    sum(status$installed), nrow(status)))
    if (length(missing) > 0) {
      message("Not installed: ", paste(missing, collapse = ", "),
              ". Run packages_install().")
    }
  }
  invisible(status)
}
