#' Security audit for Framework projects
#'
#' Performs a comprehensive security audit of data files in Framework projects,
#' checking for unignored data files, git history leaks, and orphaned data files
#' outside configured directories.
#'
#' @param config_file Path to configuration file (default: auto-detect settings.yml/settings.yml)
#' @param check_git_history Logical; if TRUE (default), check git history for leaked data files
#' @param history_depth Character or numeric. "all" for full history, "shallow" for recent 100 commits,
#'   or numeric for specific commit count (default: "all")
#' @param auto_fix Logical; if TRUE, automatically update .gitignore (default: FALSE)
#' @param verbose Logical; if TRUE (default), show progress messages
#' @param extensions Character vector of data file extensions to detect (default: common data formats)
#'
#' @return A structured list containing:
#'   \describe{
#'     \item{summary}{Data frame with check names, status (pass/warning/fail), and counts}
#'     \item{findings}{List of data frames with detailed findings for each check}
#'     \item{recommendations}{Character vector of actionable recommendations}
#'     \item{audit_metadata}{List with audit timestamp, Framework version, config info,
#'       and `skipped_directories` (key -> path of folders outside the project)}
#'   }
#'
#' @details
#' The security audit performs the following checks. Each is a row of
#' `summary` (named by its `check`), and its details are in `findings` under
#' the key in brackets:
#' \itemize{
#'   \item **gitignore_coverage** (`gitignore_issues`): Verifies all private data files are in .gitignore
#'   \item **git_history** (`git_history_issues`): Scans git history for accidentally committed data files
#'   \item **orphaned_files** (`orphaned_files`): Finds data files outside configured directories
#'   \item **private_data_exposure** (`private_data_exposure`): Checks if private data is tracked by git
#'   \item **secrets_exposure** (`secrets_exposure`): Checks if `.env` files (which hold passwords and
#'     tokens) are tracked by git
#'   \item **published_outputs** (`published_outputs`): Folder publishing destinations
#'     (`publish.destinations` entries with `driver: folder`) inside the project
#'     whose folder holds files git doesn't ignore. Columns `destination`,
#'     `path`, `files` (count not ignored), and `tracked` (count of those git
#'     tracks). In a project that isn't `security: sensitive: true`, a
#'     destination with `visibility: public` (or `private: false`) is left out,
#'     since it is meant to be committed. A warning, never a failure.
#'   \item **connection_secrets** (`connection_secrets`): Passwords, secrets,
#'     tokens, and keys written into the settings' `connections` (in the
#'     settings file and the split files under `settings/`) instead of read
#'     from the environment with `env("VAR")`. Columns `file`, `key` (a dot
#'     path such as `connections.databases.omop.password`), and `tracked`.
#'     Values are never stored or printed. Fails when git tracks the file,
#'     else warns.
#' }
#'
#' The audit watches the settings' `directories` whose key starts with
#' `inputs_` or `outputs_`, `cache`, `scratch`, `logs`, and any key or path
#' named like private, confidential, or sensitive. Each file is reported once,
#' under the deepest folder that holds it. A folder outside the project is not
#' checked, since git can't commit it from here; it is listed in
#' `audit_metadata$skipped_directories` and in the printed report.
#'
#' Status levels:
#' \itemize{
#'   \item **pass**: No issues found
#'   \item **warning**: Potential issues that should be reviewed
#'   \item **fail**: Critical security issues requiring immediate action
#' }
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Basic audit (report only)
#' audit <- git_security_audit()
#' print(audit$summary)
#' View(audit$findings$orphaned_files)
#'
#' # Quick scan without git history
#' audit <- git_security_audit(check_git_history = FALSE)
#'
#' # Verbose with limited git history
#' audit <- git_security_audit(history_depth = 100, verbose = TRUE)
#'
#' # Auto-fix mode (updates .gitignore)
#' audit <- git_security_audit(auto_fix = TRUE)
#' }
#' }
#'
#' @export
git_security_audit <- function(config_file = NULL,
                           check_git_history = TRUE,
                           history_depth = "all",
                           auto_fix = FALSE,
                           verbose = TRUE,
                            extensions = c("csv", "rds", "tsv", "txt", "dat",
                                        "xlsx", "xls", "sqlite", "db",
                                        "dta", "sav", "zsav", "por",
                                        "sas7bdat", "sas7bcat", "xpt",
                                        "parquet", "feather", "arrow",
                                        "json", "xml", "h5", "hdf5")) {

  # Validate arguments
  checkmate::assert_string(config_file, min.chars = 1, null.ok = TRUE)
  checkmate::assert_logical(check_git_history, len = 1)
  checkmate::assert(
    checkmate::check_choice(history_depth, c("all", "shallow")),
    checkmate::check_number(history_depth, lower = 1)
  )
  checkmate::assert_logical(auto_fix, len = 1)
  checkmate::assert_logical(verbose, len = 1)
  checkmate::assert_character(extensions, min.len = 1)

  # Initialize results structure
  findings <- list(
    gitignore_issues = data.frame(
      file = character(),
      directory = character(),
      severity = character(),
      reason = character(),
      stringsAsFactors = FALSE
    ),
    git_history_issues = data.frame(
      commit = character(),
      file = character(),
      action = character(),
      date = character(),
      stringsAsFactors = FALSE
    ),
    orphaned_files = data.frame(
      path = character(),
      size = numeric(),
      modified = character(),
      extension = character(),
      stringsAsFactors = FALSE
    ),
    private_data_exposure = data.frame(
      file = character(),
      directory = character(),
      git_status = character(),
      stringsAsFactors = FALSE
    ),
    secrets_exposure = data.frame(
      file = character(),
      git_status = character(),
      stringsAsFactors = FALSE
    ),
    published_outputs = data.frame(
      destination = character(),
      path = character(),
      files = integer(),
      tracked = integer(),
      stringsAsFactors = FALSE
    ),
    connection_secrets = data.frame(
      file = character(),
      key = character(),
      tracked = logical(),
      stringsAsFactors = FALSE
    )
  )

  recommendations <- character()

  # Auto-discover config file
  if (is.null(config_file)) {
    config_file <- .get_settings_file()
  }

  if (is.null(config_file) || !file.exists(config_file)) {
    stop("Config file not found (expected settings.yml or config.yml)")
  }

  # Check git availability
  git_available <- .check_git_available()
  if (!git_available && verbose) {
    message("Git not available. Skipping git-specific checks.")
  }

  if (verbose) {
    message("=== Framework Security Audit ===\n")
  }

  # Read configuration
  config <- tryCatch(
    settings_read(config_file),
    error = function(e) {
      stop(sprintf("Failed to read config file: %s", e$message))
    }
  )

  # Get data directories from config. Folders outside the project are
  # skipped: git can't commit them from here.
  root <- dirname(normalizePath(config_file, winslash = "/", mustWork = TRUE))
  data_dirs <- .get_data_directories(config, verbose, root = root)
  skipped_dirs <- .outside_directories(config, root)
  tracked_files <- if (git_available) .fw_tracked_files(root) else character()

  # Check 1: gitignore coverage
  if (verbose) message("Checking .gitignore coverage...")
  gitignore_findings <- .check_gitignore_coverage(data_dirs, extensions, verbose)
  findings$gitignore_issues <- gitignore_findings$issues
  if (nrow(gitignore_findings$issues) > 0) {
    recommendations <- c(recommendations, gitignore_findings$recommendations)
  }

  # Check 2: Private data exposure (git tracking)
  if (verbose) message("Checking for exposed private data...")
  exposure_findings <- .check_private_data_exposure(data_dirs, git_available, verbose, extensions)
  findings$private_data_exposure <- exposure_findings$issues
  if (nrow(exposure_findings$issues) > 0) {
    recommendations <- c(recommendations, exposure_findings$recommendations)
  }

  # Check 3: Git history leaks
  if (check_git_history && git_available) {
    if (verbose) message("Scanning git history for data file leaks...")
    history_findings <- .check_git_history(data_dirs, extensions, history_depth, verbose)
    findings$git_history_issues <- history_findings$issues
    if (nrow(history_findings$issues) > 0) {
      recommendations <- c(recommendations, history_findings$recommendations)
    }
  }

  # Check 3b: Secrets files (.env) tracked by git
  if (verbose) message("Checking for tracked secrets files...")
  secrets_findings <- .check_secrets_exposure(git_available)
  findings$secrets_exposure <- secrets_findings$issues
  if (nrow(secrets_findings$issues) > 0) {
    recommendations <- c(recommendations, secrets_findings$recommendations)
  }

  # Check 4: Orphaned data files
  if (verbose) message("Scanning for orphaned data files...")
  orphan_findings <- .scan_for_orphaned_files(data_dirs, extensions, verbose)
  findings$orphaned_files <- orphan_findings$files
  if (nrow(orphan_findings$files) > 0) {
    recommendations <- c(recommendations, orphan_findings$recommendations)
  }

  # Check 5: Folder publishing destinations git doesn't ignore
  if (verbose) message("Checking folder publishing destinations...")
  published_findings <- .check_published_outputs(config, root, tracked_files)
  findings$published_outputs <- published_findings$issues
  recommendations <- c(recommendations, published_findings$recommendations)

  # Check 6: Passwords and tokens written into connection settings
  if (verbose) message("Checking connection settings for written-out secrets...")
  connection_findings <- .check_connection_secrets(config_file, root, tracked_files)
  findings$connection_secrets <- connection_findings$issues
  recommendations <- c(recommendations, connection_findings$recommendations)

  # Build summary
  summary <- data.frame(
    check = c("gitignore_coverage", "private_data_exposure", "git_history", "orphaned_files",
              "secrets_exposure", "published_outputs", "connection_secrets"),
    status = c(
      if (nrow(findings$gitignore_issues) == 0) "pass" else if (any(findings$gitignore_issues$severity == "critical")) "fail" else "warning",
      if (nrow(findings$private_data_exposure) == 0) "pass" else "fail",
      if (!check_git_history || !git_available) "skipped" else if (nrow(findings$git_history_issues) == 0) "pass" else "fail",
      if (nrow(findings$orphaned_files) == 0) "pass" else "warning",
      if (!git_available) "skipped" else if (nrow(findings$secrets_exposure) == 0) "pass" else "fail",
      if (nrow(findings$published_outputs) == 0) "pass" else "warning",
      if (nrow(findings$connection_secrets) == 0) "pass"
      else if (any(findings$connection_secrets$tracked)) "fail" else "warning"
    ),
    count = c(
      nrow(findings$gitignore_issues),
      nrow(findings$private_data_exposure),
      nrow(findings$git_history_issues),
      nrow(findings$orphaned_files),
      nrow(findings$secrets_exposure),
      nrow(findings$published_outputs),
      nrow(findings$connection_secrets)
    ),
    stringsAsFactors = FALSE
  )

  # Auto-fix if requested
  if (auto_fix && (nrow(findings$gitignore_issues) > 0 || nrow(findings$private_data_exposure) > 0)) {
    if (verbose) message("\nApplying auto-fix...")
    .apply_auto_fix(findings, verbose)
    recommendations <- c(recommendations, "Run git status to review .gitignore changes")
  }

  # Build audit result
  result <- list(
    summary = summary,
    findings = findings,
    recommendations = unique(recommendations),
    audit_metadata = list(
      timestamp = Sys.time(),
      framework_version = as.character(packageVersion("framework")),
      config_directories = data_dirs,
      skipped_directories = skipped_dirs,
      git_available = git_available,
      auto_fix_applied = auto_fix
    )
  )

  # Print summary if verbose
  if (verbose) {
    .print_audit_summary(result)
  }

  # Store audit in framework database
  tryCatch({
    .save_audit_result(result)
  }, error = function(e) {
    # Don't fail audit if database save fails
    if (verbose) message("Note: Could not save audit to framework database")
  })

  invisible(result)
}


#' Check if git is available
#' @keywords internal
.check_git_available <- function() {
  git_check <- tryCatch(
    {
      system2("git", "--version", stdout = TRUE, stderr = TRUE)
      TRUE
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )

  if (!git_check) {
    return(FALSE)
  }

  git_dir_exists <- dir.exists(".git")

  in_git_repo <- tryCatch(
    {
      result <- system2("git", c("rev-parse", "--show-toplevel"), stdout = TRUE, stderr = FALSE)
      is.null(attr(result, "status")) && length(result) > 0
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )

  git_dir_exists || in_git_repo
}


#' Get data directories from config
#'
#' A settings folder counts when its key starts with `inputs_` or `outputs_`,
#' is `cache`, `scratch`, or `logs`, or when its key or path is named like
#' private, confidential, or sensitive (`original_private_tables`). Folders
#' outside the project are left out (see `.outside_directories()`): git can't
#' commit them from here. An absolute path inside the project becomes the
#' path from the root.
#' @keywords internal
.get_data_directories <- function(config, verbose, root = ".") {
  dirs <- list()
  config_dirs <- .configured_directories(config)

  for (key in names(config_dirs)) {
    dir_path <- config_dirs[[key]]
    if (.fw_outside_root(root, dir_path)) {
      next
    }
    if (grepl("^(inputs|outputs)_", key) || key %in% c("cache", "scratch", "logs") ||
        grepl("private|confidential|sensitive", key, ignore.case = TRUE) ||
        .fw_private_segment(dir_path)) {
      dirs[[key]] <- .fw_relative_folder(root, dir_path)
    }
  }

  # Add common fallback directories if not explicitly configured
  fallback_inputs <- c("raw", "intermediate", "final")
  for (name in fallback_inputs) {
    key <- paste0("inputs_", name)
    path <- file.path("inputs", name)
    if (!key %in% names(dirs) && dir.exists(path)) {
      dirs[[key]] <- path
    }
  }

  # Check for docs directory at root level
  if (!"docs" %in% names(dirs) && dir.exists("docs")) {
    dirs[["docs"]] <- "docs"
  }

  fallback_outputs <- c("", "tables", "figures", "models", "notebooks", "docs", "final", "cache", "scratch")
  for (name in fallback_outputs) {
    if (identical(name, "")) {
      key <- "outputs_private"
      path <- "outputs/private"
    } else {
      key <- paste0("outputs_", name)
      path <- file.path("outputs", "private", name)
    }

    if (!key %in% names(dirs) && dir.exists(path)) {
      dirs[[key]] <- path
    }
  }

  fallback_public <- c("", "tables", "figures", "models", "notebooks", "docs", "final")
  for (name in fallback_public) {
    if (identical(name, "")) {
      key <- "outputs_public"
      path <- "outputs/public"
    } else {
      key <- paste0("outputs_", name, "_public")
      path <- file.path("outputs", "public", name)
    }

    if (!key %in% names(dirs) && dir.exists(path)) {
      dirs[[key]] <- path
    }
  }

  if (verbose && length(dirs) > 0) {
    message(sprintf("Monitoring %d data directories", length(dirs)))
  }

  dirs
}


# The settings' directories as strings, without a leading ./ or trailing /
#' @keywords internal
.configured_directories <- function(config) {
  config_dirs <- config$directories
  if (!is.list(config_dirs)) return(list())
  out <- list()
  for (key in names(config_dirs)) {
    value <- config_dirs[[key]]
    if (!is.character(value) || length(value) != 1 || is.na(value) || !nzchar(value)) next
    out[[key]] <- sub("/+$", "", sub("^\\./", "", value))
  }
  out
}

# A folder path with a segment named like private, confidential, or sensitive
#' @keywords internal
.fw_private_segment <- function(path) {
  grepl("(^|/)[^/]*(private|confidential|sensitive)[^/]*(/|$)",
        gsub("\\\\", "/", path), ignore.case = TRUE)
}

# The folder as an absolute, normalized path (relative to root unless
# absolute, ~ expanded)
#' @keywords internal
.fw_folder_abs <- function(root, folder) {
  path <- path.expand(folder)
  if (!grepl("^(/|[A-Za-z]:|\\\\)", path)) path <- file.path(root, path)
  .fw_normalize_path(path)
}

# Whether a settings folder (relative to root unless absolute) is outside it
#' @keywords internal
.fw_outside_root <- function(root, folder) {
  base <- sub("/+$", "", .fw_normalize_path(root))
  path <- sub("/+$", "", .fw_folder_abs(root, folder))
  if (.Platform$OS.type == "windows") {
    base <- tolower(base)
    path <- tolower(path)
  }
  !(identical(path, base) || startsWith(path, paste0(base, "/")))
}

# A folder inside the project, as the path from the root ("." for the root)
#' @keywords internal
.fw_relative_folder <- function(root, folder) {
  if (!grepl("^(/|[A-Za-z]:|\\\\|~)", folder)) return(folder)
  base <- sub("/+$", "", .fw_normalize_path(root))
  path <- sub("/+$", "", .fw_folder_abs(root, folder))
  if (nchar(path) <= nchar(base)) return(".")
  substring(path, nchar(base) + 2)
}

# Settings folders outside the project, which the audit skips and reports:
# key -> path as configured
#' @keywords internal
.outside_directories <- function(config, root = ".") {
  config_dirs <- .configured_directories(config)
  config_dirs[vapply(config_dirs, function(path) .fw_outside_root(root, path), logical(1))]
}

# Folders with the deepest first (most path segments), keeping settings order
# among equals
#' @keywords internal
.deepest_first <- function(dirs) {
  if (length(dirs) == 0) return(dirs)
  depth <- vapply(dirs, function(path) {
    parts <- strsplit(sub("^\\./", "", as.character(path[1])), "[/\\\\]+")[[1]]
    length(parts[nzchar(parts) & parts != "."])
  }, numeric(1))
  dirs[order(-depth)]
}


#' Identify directories that should be treated as private/sensitive
#' @keywords internal
.identify_private_dirs <- function(data_dirs) {
  if (length(data_dirs) == 0) {
    return(data_dirs)
  }

  # Private means what the gitignore templates ignore: folders whose key or
  # path names them private (or confidential or sensitive), plus cache,
  # scratch, and logs. inputs/raw in a standard project is not private;
  # sensitive projects put their inputs under private folders.
  keep <- vapply(names(data_dirs), function(name) {
    if (grepl("_public", name)) {
      return(FALSE)
    }
    path <- data_dirs[[name]]
    segments <- if (is.character(path)) strsplit(path[1], "[/\\\\]+")[[1]] else character()
    grepl("private", name) ||
      any(grepl("private|confidential|sensitive", segments, ignore.case = TRUE)) ||
      name %in% c("cache", "scratch", "logs")
  }, logical(1))

  data_dirs[keep]
}


#' Check gitignore coverage for data files
#' @keywords internal
.check_gitignore_coverage <- function(data_dirs, extensions, verbose) {
  issues <- data.frame(
    file = character(),
    directory = character(),
    severity = character(),
    reason = character(),
    stringsAsFactors = FALSE
  )

  recommendations <- character()

  # Read .gitignore if it exists
  if (!file.exists(".gitignore")) {
    recommendations <- c(recommendations, "Create a .gitignore file to protect sensitive data")
    return(list(issues = issues, recommendations = recommendations))
  }

  gitignore_patterns <- readLines(".gitignore", warn = FALSE)

  # Check each private data directory, deepest first, reporting each folder
  # and file once under the deepest key: settings keys and the fallbacks can
  # name the same folder twice (outputs_private_tables and outputs_tables)
  private_dirs <- .deepest_first(.identify_private_dirs(data_dirs))
  reported <- character()

  for (dir_name in names(private_dirs)) {
    dir_path <- private_dirs[[dir_name]]

    if (!dir.exists(dir_path) || dir_path %in% reported) {
      next
    }
    reported <- c(reported, dir_path)

    # Check if directory itself is ignored. A pattern such as
    # `**/scratch/**` ignores only what is inside the folder, which git
    # treats as ignoring the folder, so test a path inside it too.
    is_ignored <- .check_path_ignored(dir_path, gitignore_patterns) ||
      .check_path_ignored(file.path(sub("/+$", "", dir_path), ".framework-probe"), gitignore_patterns)

    if (!is_ignored) {
      issues <- rbind(issues, data.frame(
        file = dir_path,
        directory = dir_name,
        severity = "critical",
        reason = "Private data directory not in .gitignore",
        stringsAsFactors = FALSE
      ))
    }

    # Check files within directory
    files <- list.files(dir_path, recursive = TRUE, full.names = TRUE)
    files <- files[!files %in% reported]
    reported <- c(reported, files[vapply(files, .is_data_file, logical(1), extensions = extensions)])
    for (file in files) {
      if (.is_data_file(file, extensions)) {
        if (!.check_path_ignored(file, gitignore_patterns)) {
          issues <- rbind(issues, data.frame(
            file = file,
            directory = dir_name,
            severity = "critical",
            reason = "Private data file not in .gitignore",
            stringsAsFactors = FALSE
          ))
        }
      }
    }
  }

  if (nrow(issues) > 0) {
    recommendations <- c(
      recommendations,
      "Add private data directories to .gitignore",
      "Review all private data files for git tracking"
    )
  }

  list(issues = issues, recommendations = recommendations)
}


#' Check if private data is tracked by git
#' @keywords internal
.check_private_data_exposure <- function(data_dirs, git_available, verbose, extensions = character()) {
  issues <- data.frame(
    file = character(),
    directory = character(),
    git_status = character(),
    stringsAsFactors = FALSE
  )

  recommendations <- character()

  if (!git_available) {
    return(list(issues = issues, recommendations = recommendations))
  }

  # Get all tracked files
  tracked_files <- tryCatch(
    system2("git", c("ls-files"), stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )

  if (length(tracked_files) == 0) {
    return(list(issues = issues, recommendations = recommendations))
  }

  # Check each private directory, deepest first, so each file is reported
  # once under the deepest folder that holds it
  private_dirs <- .deepest_first(.identify_private_dirs(data_dirs))

  for (dir_name in names(private_dirs)) {
    dir_path <- private_dirs[[dir_name]]

    if (!dir.exists(dir_path)) {
      next
    }

    # Check if any tracked files are in this private directory
    dir_prefix <- paste0(sub("/+$", "", sub("^\\./", "", dir_path)), "/")
    exposed_files <- tracked_files[startsWith(tracked_files, dir_prefix)]
    exposed_files <- exposed_files[!exposed_files %in% issues$file]

    for (file in exposed_files) {
      issues <- rbind(issues, data.frame(
        file = file,
        directory = dir_name,
        git_status = "tracked",
        stringsAsFactors = FALSE
      ))
    }
  }

  # Data files under any folder named like private, confidential, or sensitive
  # count too, even when that folder is not a configured directory (for
  # example inputs/private in a sensitive project, added with git add -f)
  if (length(extensions) > 0) {
    ext_pattern <- paste0("\\.(", paste(extensions, collapse = "|"), ")$")
    folders <- dirname(tracked_files)
    named_private <- grepl("(^|/)[^/]*(private|confidential|sensitive)[^/]*(/|$)",
                           folders, ignore.case = TRUE) &
      grepl(ext_pattern, tracked_files, ignore.case = TRUE) &
      !tracked_files %in% issues$file
    for (file in tracked_files[named_private]) {
      issues <- rbind(issues, data.frame(
        file = file,
        directory = dirname(file),
        git_status = "tracked",
        stringsAsFactors = FALSE
      ))
    }
  }

  if (nrow(issues) > 0) {
    recommendations <- c(
      recommendations,
      "CRITICAL: Private data files are tracked by git!",
      "Run: git rm --cached <file> to untrack files",
      "Add files to .gitignore before committing"
    )
  }

  list(issues = issues, recommendations = recommendations)
}


#' Check for secrets files tracked by git
#'
#' Flags `.env` files (and variants such as `.env.local`) that git tracks.
#' Example files (`.env.example`, `.env.template`, `.env.sample`) are allowed.
#' @keywords internal
.check_secrets_exposure <- function(git_available) {
  issues <- data.frame(file = character(), git_status = character(), stringsAsFactors = FALSE)
  if (!git_available) {
    return(list(issues = issues, recommendations = character()))
  }

  tracked <- tryCatch(
    system2("git", c("ls-files"), stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
  base <- basename(tracked)
  secret <- grepl("^\\.env(\\..+)?$", base) & !grepl("\\.(example|template|sample)$", base)
  files <- tracked[secret]
  if (length(files) == 0) {
    return(list(issues = issues, recommendations = character()))
  }

  issues <- data.frame(file = files, git_status = "tracked", stringsAsFactors = FALSE)
  list(
    issues = issues,
    recommendations = c(
      "CRITICAL: Secrets files are tracked by git!",
      sprintf("Run: git rm --cached %s, then commit", paste(files, collapse = " ")),
      "Add .env to .gitignore",
      "Rotate any passwords or tokens in those files (including FW_PROJECT_TOKEN): they stay in git history"
    )
  )
}

#' Check git history for leaked data files
#' @keywords internal
.check_git_history <- function(data_dirs, extensions, history_depth, verbose) {
  issues <- data.frame(
    commit = character(),
    file = character(),
    action = character(),
    date = character(),
    stringsAsFactors = FALSE
  )

  recommendations <- character()

  # Build pattern for data file extensions
  ext_pattern <- paste0("\\.(", paste(extensions, collapse = "|"), ")$")

  # Determine depth argument
  depth_arg <- if (is.numeric(history_depth)) {
    as.character(history_depth)
  } else if (history_depth == "shallow") {
    "100"
  } else {
    NULL  # All history
  }

  # Build git log command
  # Note: Use system() instead of system2() to avoid shell interpretation issues with git format strings
  # The %H, %ad, %s placeholders need to be passed directly to git, not interpreted by shell
  git_cmd <- sprintf(
    "git log --all '--pretty=format:%%H|%%ad|%%s' --date=iso --name-status%s",
    if (!is.null(depth_arg)) paste0(" -", depth_arg) else ""
  )

  # Get git log
  log_output <- tryCatch(
    {
      output <- system(git_cmd, intern = TRUE)
      if (is.null(attr(output, "status"))) output else character()
    },
    error = function(e) character()
  )

  if (length(log_output) == 0) {
    return(list(issues = issues, recommendations = recommendations))
  }

  # Parse git log output
  current_commit <- NULL
  current_date <- NULL

  private_dirs <- .identify_private_dirs(data_dirs)

  for (line in log_output) {
    # Check if this is a commit line
    if (grepl("^[a-f0-9]{40}\\|", line)) {
      parts <- strsplit(line, "\\|")[[1]]
      current_commit <- substr(parts[1], 1, 8)  # Short hash
      current_date <- parts[2]
    } else if (grepl("^[AMD]\t", line) && !is.null(current_commit)) {
      # This is a file change line
      parts <- strsplit(line, "\t")[[1]]
      action <- parts[1]
      file <- parts[2]

      # Check if it's a data file in a private directory
      if (grepl(ext_pattern, file, ignore.case = TRUE)) {
        # Check if file is in any private directory
        is_private <- any(vapply(names(private_dirs), function(dir_name) {
          startsWith(file, private_dirs[[dir_name]])
        }, logical(1)))

        if (is_private || grepl("(private|secret|confidential)", file, ignore.case = TRUE)) {
          issues <- rbind(issues, data.frame(
            commit = current_commit,
            file = file,
            action = switch(action,
                          "A" = "added",
                          "M" = "modified",
                          "D" = "deleted",
                          action),
            date = current_date,
            stringsAsFactors = FALSE
          ))
        }
      }
    }
  }

  if (nrow(issues) > 0) {
    recommendations <- c(
      recommendations,
      "CRITICAL: Private data files found in git history!",
      "Consider using git-filter-repo or BFG Repo-Cleaner to remove sensitive data",
      "Consult: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository"
    )
  }

  list(issues = issues, recommendations = recommendations)
}


#' Scan for orphaned data files outside configured directories
#' @keywords internal
.scan_for_orphaned_files <- function(data_dirs, extensions, verbose) {
  orphaned <- data.frame(
    path = character(),
    size = numeric(),
    modified = character(),
    extension = character(),
    stringsAsFactors = FALSE
  )

  recommendations <- character()

  # Build pattern for data files
  ext_pattern <- paste0("\\.(", paste(extensions, collapse = "|"), ")$")

  # Folders to skip at any depth: tool folders, plus the *_files and *_cache
  # folders Quarto and knitr write next to a rendered document
  exclude_dirs <- c(
    ".git", ".Rproj.user", "renv", "packrat",
    ".framework_cache", ".quarto", "node_modules"
  )
  exclude_pattern <- paste0(
    "(^|/)(", paste(gsub(".", "\\.", exclude_dirs, fixed = TRUE), collapse = "|"),
    "|[^/]*_cache|[^/]*_files)/"
  )

  # Framework internal files to exclude (these are managed by Framework)
  exclude_files <- c(
    "framework.db",           # Framework database
    ".framework_renv_enabled", # renv marker
    ".framework_scaffolded",   # legacy scaffold marker
    ".initiated"               # init marker
  )

  # Get all configured directory paths
  configured_paths <- unlist(data_dirs, use.names = FALSE)

  # Scan project root
  all_files <- list.files(".", recursive = TRUE, full.names = TRUE, include.dirs = FALSE)
  all_files <- all_files[!grepl(exclude_pattern, sub("^\\./", "", all_files))]
  all_files <- all_files[grepl(ext_pattern, all_files, ignore.case = TRUE)]
  # Files git ignores never reach the repository
  all_files <- all_files[!.fw_gitignored(sub("^\\./", "", all_files))]

  for (file in all_files) {
    # Skip Framework internal files
    file_name <- sub("^\\./", "", file)
    if (file_name %in% exclude_files) {
      next
    }

    # Check if it's a data file
    if (grepl(ext_pattern, file, ignore.case = TRUE)) {
      # Check if it's in any configured directory
      in_configured_dir <- any(sapply(configured_paths, function(d) {
        startsWith(file, paste0("./", d)) || startsWith(file, d)
      }))

      if (!in_configured_dir) {
        file_info <- file.info(file)
        orphaned <- rbind(orphaned, data.frame(
          path = sub("^\\./", "", file),
          size = file_info$size,
          modified = as.character(file_info$mtime),
          extension = tools::file_ext(file),
          stringsAsFactors = FALSE
        ))
      }
    }
  }

  if (nrow(orphaned) > 0) {
    recommendations <- c(
      recommendations,
      sprintf("Found %d data file(s) outside configured directories", nrow(orphaned)),
      "Move orphaned files to appropriate data directories",
      "Add data file locations to settings.yml if they represent new data storage"
    )
  }

  list(files = orphaned, recommendations = recommendations)
}


#' Which paths git ignores
#'
#' In a git work tree, asks `git check-ignore` (which reads every .gitignore,
#' .git/info/exclude, and the global excludes file; tracked files are never
#' ignored). Elsewhere, matches the project's .gitignore patterns.
#'
#' @param paths Paths relative to `root`
#' @param root The folder the paths are relative to (default: the working directory)
#' @return Logical vector, TRUE where the path is ignored
#' @keywords internal
.fw_gitignored <- function(paths, root = ".") {
  if (length(paths) == 0) return(logical())
  git <- Sys.which("git")
  if (nzchar(git)) {
    inside <- suppressWarnings(system2(git, c("-C", shQuote(root), "rev-parse", "--is-inside-work-tree"),
                                       stdout = TRUE, stderr = FALSE))
    if (identical(inside, "true")) {
      # Exit status 1 means nothing is ignored, so no warning
      ignored <- .fw_git_check_ignore(paths, root = root)
      return(paths %in% ignored)
    }
  }
  gitignore <- file.path(root, ".gitignore")
  if (!file.exists(gitignore)) return(rep(FALSE, length(paths)))
  patterns <- readLines(gitignore, warn = FALSE)
  vapply(paths, .check_path_ignored, logical(1), gitignore_patterns = patterns, USE.NAMES = FALSE)
}

#' Check if path is ignored by .gitignore patterns
#'
#' Follows the gitignore rules that matter here: a pattern without a slash
#' (apart from a trailing one) matches at any depth, and a matched folder
#' ignores everything inside it.
#' @keywords internal
.check_path_ignored <- function(path, gitignore_patterns) {
  # Normalize path
  path <- gsub("^\\./", "", path)

  is_ignored <- FALSE

  # Check each pattern
  for (pattern in gitignore_patterns) {
    # Skip comments and empty lines
    if (grepl("^\\s*#", pattern) || grepl("^\\s*$", pattern)) {
      next
    }

    # Handle negation patterns
    is_negation <- startsWith(pattern, "!")
    if (is_negation) {
      pattern <- substring(pattern, 2)
    }

    pattern <- trimws(pattern, which = "right")

    # Store original pattern for directory matching
    orig_pattern <- pattern

    # A pattern with no slash but a trailing one matches at any depth
    anywhere <- !grepl("/", sub("/$", "", pattern))

    # Strip leading / (anchors to root, but paths are already root-relative)
    pattern <- sub("^/", "", pattern)

    # Convert gitignore pattern to regex using placeholders to avoid
    # substitutions interfering with each other
    pattern <- gsub("\\.", "\\\\.", pattern)         # Escape dots
    pattern <- gsub("\\*\\*/", "\001", pattern)      # **/ → placeholder
    pattern <- gsub("/\\*\\*$", "\002", pattern)     # /** at end → placeholder
    pattern <- gsub("\\*\\*", "\003", pattern)       # ** (remaining) → placeholder
    pattern <- gsub("\\*", "[^/]*", pattern)         # * → single path segment
    pattern <- gsub("\001", "(.*/)?", pattern)       # restore **/ → any dirs
    pattern <- gsub("\002", "/.*", pattern)           # restore /** → everything inside
    pattern <- gsub("\003", ".*", pattern)            # restore ** → anything

    # A matched folder ignores everything inside it. Remove a trailing /
    # and match the path itself or anything under it.
    pattern <- paste0(sub("/$", "", pattern), "(/.*)?")
    if (anywhere) pattern <- paste0("(.*/)?", pattern)

    # Check if path matches
    if (grepl(paste0("^", pattern, "$"), path)) {
      if (is_negation) {
        is_ignored <- FALSE  # Negation overrides previous ignores
      } else {
        is_ignored <- TRUE
      }
    }
  }

  is_ignored
}


# Files git tracks, staged ones included, as paths from root
#' @keywords internal
.fw_tracked_files <- function(root = ".") {
  out <- tryCatch(
    suppressWarnings(system2("git", c("-C", shQuote(root), "-c", "core.quotepath=off", "ls-files"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character()
  )
  if (!is.null(attr(out, "status"))) return(character())
  sub("\r$", "", as.character(out))
}

#' Folder publishing destinations git should ignore
#'
#' The `publish.destinations` entries with `driver: folder` whose `path`
#' (relative to the project root unless absolute, `~` expanded) is inside the
#' project and isn't the root itself. In a project with
#' `security: sensitive: true` every one counts; in other projects one with
#' `visibility: public` or `private: false` is left out, since it is meant to
#' be committed (a GitHub Pages `docs/`).
#'
#' @param config The settings, as from [settings_read()], or a list with
#'   `publish` and `security`.
#' @param root The project root.
#' @return Named character vector: destination name -> path from the root.
#' @keywords internal
.folder_destinations <- function(config, root = ".") {
  destinations <- if (is.list(config$publish)) config$publish$destinations else NULL
  sensitive <- is.list(config$security) && isTRUE(config$security$sensitive)
  found <- character()
  for (name in names(destinations)) {
    options <- destinations[[name]]
    if (!is.list(options) || !identical(options$driver, "folder")) next
    path <- options$path
    if (!is.character(path) || length(path) != 1 || is.na(path) || !nzchar(path)) next
    path <- sub("/+$", "", sub("^\\./", "", path))
    if (!nzchar(path) || .fw_outside_root(root, path)) next
    public <- identical(options$visibility, "public") || identical(options$private, FALSE)
    if (public && !sensitive) next
    relative <- .fw_relative_folder(root, path)
    if (!identical(relative, ".")) found[[name]] <- relative
  }
  found
}

#' Check folder publishing destinations that git doesn't ignore
#'
#' Rendered notebooks and exported tables in a folder destination can be
#' committed. A destination is a finding when its folder holds files that git
#' doesn't ignore.
#' @keywords internal
.check_published_outputs <- function(config, root = ".", tracked = character()) {
  issues <- data.frame(
    destination = character(),
    path = character(),
    files = integer(),
    tracked = integer(),
    stringsAsFactors = FALSE
  )
  folders <- .folder_destinations(config, root)
  for (name in names(folders)) {
    folder <- folders[[name]]
    if (!dir.exists(file.path(root, folder))) next
    files <- list.files(file.path(root, folder), recursive = TRUE, all.files = TRUE, no.. = TRUE)
    files <- sort(file.path(folder, files), method = "radix")
    exposed <- files[!.fw_gitignored(files, root = root)]
    if (length(exposed) > 0) {
      issues <- rbind(issues, data.frame(
        destination = name,
        path = folder,
        files = length(exposed),
        tracked = sum(exposed %in% tracked),
        stringsAsFactors = FALSE
      ))
    }
  }
  recommendations <- if (nrow(issues) > 0) {
    paste0("Add folder publishing destinations to .gitignore (for example /published/), ",
           "or set visibility: public on a destination meant to be committed")
  } else {
    character()
  }
  list(issues = issues, recommendations = recommendations)
}


# Whether a credential value is written out: anything but missing, empty, a
# mapping or list, a boolean, env("VAR"), or !expr Sys.getenv("VAR"). A
# default (env("VAR", "x"), Sys.getenv("VAR", "x")) is written out too, as
# are numbers.
#' @keywords internal
.fw_literal_secret <- function(value) {
  if (is.null(value) || is.list(value) || is.logical(value) || length(value) == 0) return(FALSE)
  if (!is.character(value)) return(TRUE)
  value <- value[1]
  if (is.na(value) || !nzchar(value)) return(FALSE)
  text <- trimws(value)
  env_call <- regmatches(text, regexec('^env\\("(.*?)"(?:,\\s*"(.*?)")?\\)$', text, perl = TRUE))[[1]]
  if (length(env_call) > 0) {
    return(length(env_call) >= 3 && !is.na(env_call[3]) && nzchar(env_call[3]))
  }
  if (grepl("^!expr\\s+", value)) {
    code <- trimws(sub("^!expr\\s+", "", value))
    system <- regmatches(code, regexec(
      "^Sys\\.getenv\\(\\s*(['\"])(.*?)\\1\\s*(?:,\\s*(?:unset\\s*=\\s*)?(['\"])(.*?)\\3\\s*)?\\)$",
      code, perl = TRUE
    ))[[1]]
    if (length(system) == 0) return(TRUE)
    return(length(system) >= 5 && !is.na(system[5]) && nzchar(system[5]))
  }
  TRUE
}

# Dot paths of credential keys with written-out values under `connections`
#' @keywords internal
.fw_secret_keys <- function(node, path = "", inside = FALSE) {
  found <- character()
  if (is.list(node) && !is.null(names(node)) && all(nzchar(names(node)))) {
    for (i in seq_along(node)) {
      key <- names(node)[i]
      value <- node[[i]]
      here <- if (nzchar(path)) paste0(path, ".", key) else key
      within <- inside || identical(key, "connections")
      if (within && grepl("password|passwd|pwd|secret|token|api_?key|access_key", key, ignore.case = TRUE) &&
          .fw_literal_secret(value)) {
        found <- c(found, here)
      } else {
        found <- c(found, .fw_secret_keys(value, here, within))
      }
    }
  } else if (is.list(node)) {
    for (i in seq_along(node)) {
      found <- c(found, .fw_secret_keys(node[[i]], sprintf("%s[%d]", path, i - 1L), inside))
    }
  }
  found
}

#' Check for secrets written into connection settings
#'
#' Reads the settings file the audit read and every `.yml`/`.yaml` file under
#' the project's `settings/` folder, without evaluating anything (`!expr`
#' stays text). Under any key named `connections`, a key whose name matches
#' `password|passwd|pwd|secret|token|api_?key|access_key` (any case) is a
#' finding when its value is written out rather than read from the
#' environment. Values are never stored or printed.
#' @keywords internal
.check_connection_secrets <- function(config_file, root = ".", tracked = character()) {
  issues <- data.frame(file = character(), key = character(), tracked = logical(),
                       stringsAsFactors = FALSE)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  files <- normalizePath(config_file, winslash = "/", mustWork = TRUE)
  folder <- file.path(root, "settings")
  if (dir.exists(folder)) {
    split <- list.files(folder, pattern = "\\.ya?ml$", recursive = TRUE, full.names = TRUE,
                        ignore.case = TRUE)
    files <- c(files, sort(normalizePath(split, winslash = "/"), method = "radix"))
  }
  for (file in unique(files)) {
    document <- tryCatch(
      yaml::read_yaml(file, eval.expr = FALSE,
                      handlers = list(expr = function(x) paste0("!expr ", x))),
      error = function(e) NULL
    )
    if (is.null(document)) next
    keys <- .fw_secret_keys(document)
    if (length(keys) == 0) next
    relative <- if (startsWith(file, paste0(root, "/"))) substring(file, nchar(root) + 2) else file
    issues <- rbind(issues, data.frame(file = relative, key = keys, tracked = relative %in% tracked,
                                       stringsAsFactors = FALSE))
  }
  recommendations <- if (nrow(issues) > 0) {
    c('Move connection passwords and tokens to .env and refer to them with env("VARIABLE") in the settings',
      "Rotate any secret that was committed: it stays in git history")
  } else {
    character()
  }
  list(issues = issues, recommendations = recommendations)
}


#' Check if file is a data file based on extension
#' @keywords internal
.is_data_file <- function(file, extensions) {
  ext <- tolower(tools::file_ext(file))
  ext %in% extensions
}


#' Apply auto-fix for common issues
#' @keywords internal
.apply_auto_fix <- function(findings, verbose) {
  gitignore_path <- ".gitignore"

  # Create .gitignore if it doesn't exist
  if (!file.exists(gitignore_path)) {
    writeLines("", gitignore_path)
  }

  existing <- readLines(gitignore_path, warn = FALSE)
  header_line <- "# Framework Security Audit - Auto-generated"

  normalize_relative <- function(paths) {
    vapply(paths, function(path) {
      if (is.na(path) || !nzchar(path)) {
        return(NA_character_)
      }

      normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
      cwd <- normalizePath(".", winslash = "/", mustWork = TRUE)

      if (startsWith(normalized, paste0(cwd, "/"))) {
        normalized <- substr(normalized, nchar(cwd) + 2, nchar(normalized))
      }

      normalized <- gsub("^\\./", "", normalized)
      normalized <- gsub("/+", "/", normalized)
      normalized <- gsub("/$", "", normalized)
      normalized
    }, character(1), USE.NAMES = FALSE)
  }

  dirs_to_add <- character()

  if (nrow(findings$gitignore_issues) > 0) {
    dirs_to_add <- c(dirs_to_add, findings$gitignore_issues$file)
  }

  if (nrow(findings$private_data_exposure) > 0) {
    dirs_to_add <- c(dirs_to_add, dirname(findings$private_data_exposure$file))
  }

  dirs_to_add <- unique(na.omit(normalize_relative(dirs_to_add)))
  dirs_to_add <- dirs_to_add[dirs_to_add != ""]

  if (length(dirs_to_add) == 0) {
    return(invisible(NULL))
  }

  new_lines <- character()
  header_present <- any(trimws(existing) == header_line)

  if (!header_present) {
    new_lines <- c(new_lines, "", header_line)
  }

  for (dir_path in dirs_to_add) {
    dir_entry <- paste0(dir_path, "/")
    glob_entry <- paste0(dir_path, "/**")

    if (!dir_entry %in% existing && !dir_entry %in% new_lines) {
      new_lines <- c(new_lines, dir_entry)
    }

    if (!glob_entry %in% existing && !glob_entry %in% new_lines) {
      new_lines <- c(new_lines, glob_entry)
    }
  }

  # If header was added but no patterns, avoid writing redundant lines
  pattern_lines <- new_lines[nzchar(new_lines) & !startsWith(new_lines, "#")]
  if (length(pattern_lines) == 0) {
    return(invisible(NULL))
  }

  writeLines(c(existing, new_lines), gitignore_path)

  if (verbose) {
    message(sprintf("Added %d director%s to .gitignore",
                   length(dirs_to_add),
                   if (length(dirs_to_add) == 1) "y" else "ies"))
  }

  invisible(NULL)
}


#' Print audit summary
#' @keywords internal
.print_audit_summary <- function(result) {
  message("\n=== Security Audit Summary ===\n")

  for (i in seq_len(nrow(result$summary))) {
    check <- result$summary[i, ]
    status_icon <- switch(check$status,
                         "pass" = "\u2713",
                         "warning" = "\u26A0",
                         "fail" = "\u2717",
                         "skipped" = "-")

    status_label <- switch(check$status,
                          "pass" = "PASS",
                          "warning" = "WARNING",
                          "fail" = "FAIL",
                          "skipped" = "SKIPPED")

    message(sprintf("%s %s: %s (%d issues)",
                   status_icon,
                   status_label,
                   gsub("_", " ", check$check),
                   check$count))
  }

  # Show detailed findings for issues
  has_issues <- FALSE

  if (nrow(result$findings$gitignore_issues) > 0) {
    has_issues <- TRUE
    message("\n--- Gitignore Coverage Issues ---")
    for (i in seq_len(nrow(result$findings$gitignore_issues))) {
      issue <- result$findings$gitignore_issues[i, ]
      message(sprintf("  %d. [%s] %s",
                     i,
                     toupper(issue$severity),
                     issue$file))
      message(sprintf("     Directory: %s", issue$directory))
      message(sprintf("     Reason: %s\n", issue$reason))
    }
  }

  if (nrow(result$findings$private_data_exposure) > 0) {
    has_issues <- TRUE
    message("\n--- Private Data Exposure (Git Tracked) ---")
    for (i in seq_len(nrow(result$findings$private_data_exposure))) {
      issue <- result$findings$private_data_exposure[i, ]
      message(sprintf("  %d. %s (tracked in git)",
                     i,
                     issue$file))
      message(sprintf("     Directory: %s\n", issue$directory))
    }
  }

  if (nrow(result$findings$git_history_issues) > 0) {
    has_issues <- TRUE
    message("\n--- Git History Leaks ---")
    for (i in seq_len(min(10, nrow(result$findings$git_history_issues)))) {
      issue <- result$findings$git_history_issues[i, ]
      message(sprintf("  %d. %s (%s in commit %s)",
                     i,
                     issue$file,
                     issue$action,
                     issue$commit))
      message(sprintf("     Date: %s\n", issue$date))
    }
    if (nrow(result$findings$git_history_issues) > 10) {
      message(sprintf("     ... and %d more issues in git history\n",
                     nrow(result$findings$git_history_issues) - 10))
    }
  }

  if (nrow(result$findings$orphaned_files) > 0) {
    has_issues <- TRUE
    message("\n--- Orphaned Data Files ---")
    for (i in seq_len(min(10, nrow(result$findings$orphaned_files)))) {
      issue <- result$findings$orphaned_files[i, ]
      size_kb <- round(issue$size / 1024, 1)
      message(sprintf("  %d. %s (%s KB, .%s)",
                     i,
                     issue$path,
                     size_kb,
                     issue$extension))
    }
    if (nrow(result$findings$orphaned_files) > 10) {
      message(sprintf("     ... and %d more orphaned files\n",
                     nrow(result$findings$orphaned_files) - 10))
    }
    message("")
  }

  if (nrow(result$findings$published_outputs %||% data.frame()) > 0) {
    has_issues <- TRUE
    message("\n--- Publishing Folders Not Ignored by Git ---")
    message(paste(.audit_finding_lines(result, "published_outputs"), collapse = "\n"))
  }

  if (nrow(result$findings$connection_secrets %||% data.frame()) > 0) {
    has_issues <- TRUE
    message("\n--- Secrets Written in Connection Settings ---")
    message(paste(.audit_finding_lines(result, "connection_secrets"), collapse = "\n"))
  }

  skipped <- result$audit_metadata$skipped_directories
  if (length(skipped) > 0) {
    message("\n--- Skipped: Folders Outside the Project ---")
    for (key in names(skipped)) {
      message(sprintf("  %s: %s", key, skipped[[key]]))
    }
    message("     Git can't commit them from this project, so they weren't checked.")
  }

  # Show recommendations
  if (length(result$recommendations) > 0) {
    message("\n=== Recommendations ===\n")
    for (i in seq_along(result$recommendations)) {
      message(sprintf("  %d. %s", i, result$recommendations[i]))
    }
  }

  # Overall status
  has_failures <- any(result$summary$status == "fail")
  has_warnings <- any(result$summary$status == "warning")

  message("")
  if (has_failures) {
    message("\u2717 AUDIT FAILED - Critical security issues found")
    message("\nTo view detailed findings:")
    message("  audit <- git_security_audit()")
    message("  View(audit$findings$gitignore_issues)")
    message("  View(audit$findings$private_data_exposure)")
  } else if (has_warnings) {
    message("\u26A0 AUDIT PASSED WITH WARNINGS - Review findings")
    message("\nTo view detailed findings:")
    message("  audit <- git_security_audit()")
    message("  View(audit$findings$orphaned_files)")
  } else {
    message("\u2713 AUDIT PASSED - No security issues found")
  }
  message("")
}


# The numbered report lines for one check's findings (at most ten, then a
# count of the rest)
#' @keywords internal
.audit_finding_lines <- function(result, check) {
  frame <- result$findings[[check]]
  if (is.null(frame) || nrow(frame) == 0) return(character())
  lines <- character()
  for (i in seq_len(min(10, nrow(frame)))) {
    row <- frame[i, , drop = FALSE]
    lines <- c(lines, switch(check,
      published_outputs = sprintf("  %d. %s/ (destination %s: %d file(s) not ignored, %d tracked)",
                                  i, row$path, row$destination, as.integer(row$files),
                                  as.integer(row$tracked)),
      connection_secrets = sprintf("  %d. %s: %s (%s)", i, row$file, row$key,
                                   if (isTRUE(row$tracked)) "tracked in git" else "not tracked")
    ))
  }
  if (nrow(frame) > 10) {
    lines <- c(lines, sprintf("     ... and %d more", nrow(frame) - 10))
  }
  lines
}


#' Save audit result to framework database
#' @keywords internal
.save_audit_result <- function(result) {
  if (!file.exists("framework.db")) {
    return(invisible(NULL))
  }

  # Store summary statistics
  .set_metadata("last_git_security_audit", as.character(result$audit_metadata$timestamp))

  overall_status <- if (any(result$summary$status == "fail")) {
    "fail"
  } else if (any(result$summary$status == "warning")) {
    "warning"
  } else {
    "pass"
  }

  .set_metadata("last_audit_status", overall_status)
  .set_metadata("last_audit_issues", sum(result$summary$count))

  invisible(NULL)
}
