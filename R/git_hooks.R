# Git Helper Functions ----------------------------------------------------

#' Show Git Status
#'
#' Display the working tree status from the R console.
#'
#' @param short Logical; if TRUE, show short format (default: FALSE)
#'
#' @return Invisibly returns the status output as a character vector
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_status()
#' git_status(short = TRUE)
#' }
#' }
#'
#' For a project inside another git repository (the project folder is not
#' the repository's top folder), it says so: the status is the enclosing
#' repository's.
#'
#' @export
git_status <- function(short = FALSE) {
  .require_git_repo()

  # A project inside another repository has no repository of its own; say
  # whose status this is
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  top <- .fw_outer_repository(root)
  if (!is.null(top)) {
    message("This project is inside the git repository at ", top,
            ", so this is the status of that enclosing repository.")
  }

  args <- "status"
  if (short) args <- c(args, "--short")

  result <- .git_run(args)
  if (!identical(result$status, 0L)) {
    message(paste(result$output, collapse = "\n"))
    stop("git status failed", call. = FALSE)
  }
  message(paste(result$output, collapse = "\n"))
  invisible(result$output)
}


#' Stage Files for Commit
#'
#' Add file contents to the staging area.
#'
#' @param files Character vector of file paths to stage, or "." for all (default)
#'
#' @return Invisibly returns TRUE on success. Stops with git's message when
#'   nothing could be staged (a missing or ignored file, for example).
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_add()              # Stage all changes
#' git_add("README.md")   # Stage specific file
#' git_add(c("R/foo.R", "R/bar.R"))
#' }
#' }
#'
#' @export
git_add <- function(files = ".") {
  .require_git_repo()

  checkmate::assert_character(files, min.len = 1, any.missing = FALSE, min.chars = 1)

  # "--" keeps a file name that starts with "-" from being read as an option
  result <- .git_run(c("add", "--", files))
  if (!identical(result$status, 0L)) {
    message(paste(result$output, collapse = "\n"))
    stop("Staging failed", call. = FALSE)
  }

  if (length(files) == 1 && files == ".") {
    message("\u2713 Staged all changes")
  } else {
    message("\u2713 Staged: ", paste(files, collapse = ", "))
  }

  invisible(TRUE)
}


#' Commit Staged Changes
#'
#' Record changes to the repository with a commit message.
#'
#' @param message Commit message (required)
#' @param all Logical; if TRUE, automatically stage modified/deleted files (default: FALSE)
#'
#' @return Invisibly returns TRUE on success
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_commit("Fix bug in data loading")
#' git_commit("Update README", all = TRUE)  # Stage and commit
#' }
#' }
#'
#' @export
git_commit <- function(message, all = FALSE) {
  .require_git_repo()

  if (missing(message) || is.null(message) || length(message) == 0 ||
      anyNA(message) || !is.character(message) || !any(nzchar(trimws(message)))) {
    stop("Commit message is required")
  }
  # A vector is one line per element: c("Subject", "", "Body")

  # Write message to a temporary file to avoid shell/spacing issues
  msg_file <- tempfile("framework_commit_msg_")
  writeLines(message, msg_file)
  on.exit(unlink(msg_file), add = TRUE)

  args <- c("commit", "-F", msg_file)
  if (all) args <- c(args, "-a")

  result <- .git_run(args)

  if (!identical(result$status, 0L)) {
    message(paste(result$output, collapse = "\n"))
    stop("Commit failed")
  }

  message("\u2713 Committed: ", message[1])
  invisible(TRUE)
}


#' Push to Remote
#'
#' Push commits to the remote repository.
#'
#' @param remote Remote name (default: "origin")
#' @param branch Branch name (default: current branch). When the branch has
#'   no upstream yet, it is pushed with `--set-upstream`, so later pulls and
#'   pushes need no arguments.
#'
#' @return Invisibly returns TRUE on success
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_push()
#' git_push(remote = "origin", branch = "main")
#' }
#' }
#'
#' @export
git_push <- function(remote = "origin", branch = NULL) {
  .require_git_repo()

  checkmate::assert_string(remote, min.chars = 1)
  checkmate::assert_string(branch, min.chars = 1, null.ok = TRUE)

  args <- c("push")
  if (is.null(branch)) {
    current <- .git_run(c("symbolic-ref", "--quiet", "--short", "HEAD"))
    if (!identical(current$status, 0L) || length(current$output) == 0) {
      stop("Push failed: not on a branch. Name one with git_push(branch = ...).", call. = FALSE)
    }
    branch <- current$output[1]
  }
  # Set the upstream the first time, as `git push -u` does
  upstream <- .git_run(c("rev-parse", "--abbrev-ref", "--symbolic-full-name", paste0(branch, "@{upstream}")))
  if (!identical(upstream$status, 0L)) args <- c(args, "--set-upstream")
  args <- c(args, remote, branch)

  message("Pushing to ", remote, "...")
  result <- .git_run(args)

  if (!identical(result$status, 0L)) {
    message(paste(result$output, collapse = "\n"))
    stop("Push failed")
  }

  message("\u2713 Pushed successfully")
  invisible(TRUE)
}


#' Pull from Remote
#'
#' Fetch and integrate changes from the remote repository.
#'
#' @param remote Remote name (default: "origin")
#' @param branch Branch name (default: current branch)
#'
#' @return Invisibly returns TRUE on success
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_pull()
#' git_pull(remote = "origin", branch = "main")
#' }
#' }
#'
#' @export
git_pull <- function(remote = "origin", branch = NULL) {
  .require_git_repo()

  args <- c("pull", remote)
  if (!is.null(branch)) args <- c(args, branch)

  message("Pulling from ", remote, "...")
  result <- .git_run(args)

  if (!identical(result$status, 0L)) {
    message(paste(result$output, collapse = "\n"))
    stop("Pull failed")
  }

  message(paste(result$output, collapse = "\n"))
  invisible(TRUE)
}


#' Show Changes (Diff)
#'
#' Show changes between commits, working tree, etc.
#'
#' @param staged Logical; if TRUE, show staged changes (default: FALSE shows unstaged)
#' @param file Optional file path to show diff for specific file
#'
#' @return Invisibly returns the diff output as a character vector
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_diff()             # Show unstaged changes
#' git_diff(staged = TRUE) # Show staged changes
#' git_diff(file = "R/foo.R")
#' }
#' }
#'
#' @export
git_diff <- function(staged = FALSE, file = NULL) {
  .require_git_repo()

  checkmate::assert_flag(staged)
  checkmate::assert_character(file, min.len = 1, any.missing = FALSE, null.ok = TRUE)

  args <- "diff"
  if (staged) args <- c(args, "--staged")
  if (!is.null(file)) args <- c(args, "--", file)

  run <- .git_run(args)
  if (!identical(run$status, 0L)) {
    message(paste(run$output, collapse = "\n"))
    stop("git diff failed", call. = FALSE)
  }
  result <- run$output

  if (length(result) == 0) {
    message("No changes")
  } else {
    message(paste(result, collapse = "\n"))
  }

  invisible(result)
}


#' Show Commit Log
#'
#' Show recent commit history.
#'
#' @param n Number of commits to show (default: 10)
#' @param oneline Logical; if TRUE, show condensed one-line format (default: TRUE)
#'
#' @return Invisibly returns the log output as a character vector
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_log()
#' git_log(n = 5)
#' git_log(oneline = FALSE)  # Full format
#' }
#' }
#'
#' @export
git_log <- function(n = 10, oneline = TRUE) {
  .require_git_repo()

  checkmate::assert_count(n, positive = TRUE)
  checkmate::assert_flag(oneline)

  args <- c("log", paste0("-n", n))
  if (oneline) args <- c(args, "--oneline")

  run <- .git_run(args)
  if (!identical(run$status, 0L)) {
    # A repository with no commits has no log yet
    if (!identical(.git_run(c("rev-parse", "--verify", "--quiet", "HEAD"))$status, 0L)) {
      message("No commits yet")
      return(invisible(character()))
    }
    message(paste(run$output, collapse = "\n"))
    stop("git log failed", call. = FALSE)
  }
  result <- run$output
  message(paste(result, collapse = "\n"))
  invisible(result)
}


# Git Hooks Management ----------------------------------------------------

#' Install Git Pre-commit Hook
#'
#' Creates a pre-commit hook that runs Framework checks based on settings.yml settings.
#'
#' @param config_file Path to configuration file (default: "settings.yml")
#' @param force Logical; if TRUE, overwrite existing hook (default: FALSE)
#' @param verbose Logical; if TRUE (default), show installation messages
#'
#' @return Invisible TRUE on success, FALSE on failure
#'
#' @details
#' Installs Framework's pre-commit script where git looks for it (worktrees
#' and `core.hooksPath` included). The script is shared with the Python
#' package and `fw`: it finds an R or Python runtime and runs the hooks
#' enabled in settings.yml, so enabling or disabling a hook later needs no
#' reinstall. A pre-commit hook Framework wrote earlier is replaced; any other
#' hook is kept unless `force = TRUE`. The enabled hooks:
#' \itemize{
#'   \item **data_security**: Run security audit to catch data leaks
#'   \item **check_sensitive_dirs**: Warn about unignored sensitive directories
#'   \item **check_notebook_outputs**: Block staged Jupyter notebooks that
#'     still hold cell outputs, which can contain data
#' }
#'
#' Hook behavior is controlled by `git.hooks.*` settings in settings.yml. The
#' `ai_sync` hook was removed in 2.0: skills and AGENTS.md replace it, and an
#' `ai_sync` setting left in settings.yml is ignored.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Install hooks based on settings.yml
#' git_hooks_install()
#'
#' # Force reinstall (overwrites existing hook)
#' git_hooks_install(force = TRUE)
#' }
#' }
#'
#' @export
git_hooks_install <- function(config_file = NULL,
                              force = FALSE,
                              verbose = TRUE) {
  # A project nested in another repository would get that repository's
  # hook, which runs from the outer top folder
  root <- if (!is.null(config_file) && file.exists(config_file)) {
    dirname(normalizePath(config_file, mustWork = TRUE))
  } else {
    tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  }
  top <- .fw_outer_repository(root)
  if (!is.null(top)) .fw_nested_repository_error(root, top)

  # Check if git repo
  if (!.is_git_repo()) {
    if (verbose) {
      message("\u2717 Not a git repository")
    }
    return(invisible(FALSE))
  }

  # Auto-discover settings file if not specified
  if (is.null(config_file)) {
    config_file <- .get_settings_file()
  }

  if (is.null(config_file)) {
    if (verbose) {
      message("\u2717 Settings file not found")
    }
    return(invisible(FALSE))
  }

  # Check if config exists
  if (!file.exists(config_file)) {
    if (verbose) {
      message("\u2717 Config file not found: ", config_file)
    }
    return(invisible(FALSE))
  }

  # Read hook configuration
  enabled <- .hooks_enabled(config_file)

  if (!any(enabled)) {
    if (verbose) {
      message("\u2139 No hooks enabled in settings.yml/config.yml")
      message("  Enable one with: git_hooks_enable(\"data_security\")")
    }
    return(invisible(FALSE))
  }

  hook_path <- .hook_path(root %||% ".")
  if (is.null(hook_path)) {
    if (verbose) {
      message("\u2717 Not a git repository")
    }
    return(invisible(FALSE))
  }
  dir.create(dirname(hook_path), recursive = TRUE, showWarnings = FALSE)

  # A hook Framework wrote earlier (R, Python, or fw) is replaced; any other
  # hook is kept unless force = TRUE
  if (file.exists(hook_path) && !force && !.is_framework_hook(hook_path)) {
    if (verbose) {
      message("\u2717 A pre-commit hook that Framework did not write already exists")
      message("  Use force=TRUE to replace it, or edit ", hook_path, " yourself")
    }
    return(invisible(FALSE))
  }

  # The shared script only finds a runtime; the checks run in .hook_run()
  hook_script <- readLines(system.file("hooks", "pre-commit", package = "framework"), warn = FALSE)

  # Write hook
  tryCatch({
    # LF line endings on every platform: the script runs under sh
    con <- file(hook_path, open = "wb")
    writeLines(hook_script, con, sep = "\n")
    close(con)
    Sys.chmod(hook_path, mode = "0755")

    if (verbose) {
      message("\u2713 Installed pre-commit hook")
      for (hook in names(enabled)[enabled]) {
        message("  \u2022 ", .hook_table()[[hook]]$label, " enabled")
      }
    }

    invisible(TRUE)
  }, error = function(e) {
    if (verbose) {
      message("\u2717 Failed to install hook: ", e$message)
    }
    invisible(FALSE)
  })
}


#' Uninstall Git Pre-commit Hook
#'
#' Removes the Framework-managed pre-commit hook.
#'
#' @param verbose Logical; if TRUE (default), show messages
#'
#' @return Invisible TRUE if hook was removed, FALSE otherwise
#'
#' @export
git_hooks_uninstall <- function(verbose = TRUE) {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  top <- .fw_outer_repository(root)
  if (!is.null(top)) {
    if (verbose) {
      message("\u2139 No pre-commit hook of this project: it is inside the repository at ",
              top, ", whose hook was left alone")
    }
    return(invisible(FALSE))
  }
  hook_path <- .hook_path(root %||% ".")

  if (is.null(hook_path) || !file.exists(hook_path)) {
    if (verbose) {
      message("\u2139 No pre-commit hook found")
    }
    return(invisible(FALSE))
  }

  # Check if it's a Framework-managed hook
  if (!.is_framework_hook(hook_path)) {
    if (verbose) {
      message("\u26a0 The pre-commit hook was not written by Framework, so it was kept")
    }
    return(invisible(FALSE))
  }

  # Remove hook
  tryCatch({
    file.remove(hook_path)
    if (verbose) {
      message("\u2713 Removed pre-commit hook")
    }
    invisible(TRUE)
  }, error = function(e) {
    if (verbose) {
      message("\u2717 Failed to remove hook: ", e$message)
    }
    invisible(FALSE)
  })
}


#' Enable Specific Git Hook
#'
#' Enables a specific hook in settings and reinstalls the pre-commit hook.
#'
#' @param hook_name Name of hook: "data_security", "check_sensitive_dirs", or
#'   "check_notebook_outputs"
#' @param config_file Path to configuration file (default: auto-discover settings.yml or settings.yml)
#' @param verbose Logical; if TRUE (default), show messages
#'
#' @return Invisible TRUE on success
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' git_hooks_enable("check_sensitive_dirs")
#' git_hooks_enable("data_security")
#' }
#' }
#'
#' @export
git_hooks_enable <- function(hook_name, config_file = NULL, verbose = TRUE) {
  .hook_assert_not_ai_sync(hook_name)
  valid_hooks <- c(names(.hook_table()), "warn_unignored_sensitive")

  if (!hook_name %in% valid_hooks) {
    stop("Invalid hook name. Must be one of: ", paste(valid_hooks, collapse = ", "))
  }

  # Auto-discover settings file if not specified
  if (is.null(config_file)) {
    config_file <- .get_settings_file()
    if (is.null(config_file)) {
      stop("Settings file not found")
    }
  }

  # Update settings.yml/config.yml
  .update_hook_config(hook_name, TRUE, config_file)

  if (verbose) {
    message("\u2713 Enabled ", hook_name, " hook")
  }

  # Reinstall hooks
  git_hooks_install(config_file = config_file, verbose = verbose)
}


#' Disable Specific Git Hook
#'
#' Disables a specific hook in settings and reinstalls the pre-commit hook.
#'
#' @param hook_name Name of hook: "data_security", "check_sensitive_dirs", or
#'   "check_notebook_outputs"
#' @param config_file Path to configuration file (default: auto-discover settings.yml or settings.yml)
#' @param verbose Logical; if TRUE (default), show messages
#'
#' @return Invisible TRUE on success
#'
#' @export
git_hooks_disable <- function(hook_name, config_file = NULL, verbose = TRUE) {
  # Turning off the removed ai_sync hook just clears the old setting
  if (identical(hook_name, "ai_sync")) {
    if (is.null(config_file)) config_file <- .get_settings_file()
    if (!is.null(config_file)) .update_hook_config("ai_sync", FALSE, config_file)
    return(invisible(TRUE))
  }
  valid_hooks <- c(names(.hook_table()), "warn_unignored_sensitive")

  if (!hook_name %in% valid_hooks) {
    stop("Invalid hook name. Must be one of: ", paste(valid_hooks, collapse = ", "))
  }

  # Auto-discover settings file if not specified
  if (is.null(config_file)) {
    config_file <- .get_settings_file()
    if (is.null(config_file)) {
      stop("Settings file not found")
    }
  }

  # Update settings.yml/config.yml
  .update_hook_config(hook_name, FALSE, config_file)

  if (verbose) {
    message("\u2713 Disabled ", hook_name, " hook")
  }

  # Reinstall hooks (or uninstall if all disabled)
  if (!any(.hooks_enabled(config_file))) {
    git_hooks_uninstall(verbose = verbose)
    invisible(TRUE)
  } else {
    git_hooks_install(config_file = config_file, verbose = verbose)
  }
}


#' List Git Hook Status
#'
#' Shows which hooks are enabled and their current status.
#'
#' @param config_file Path to configuration file (default: auto-discover settings.yml or settings.yml)
#'
#' @return Data frame with hook information
#'
#' @export
git_hooks_list <- function(config_file = NULL) {
  # Auto-discover settings file if not specified
  if (is.null(config_file)) {
    config_file <- .get_settings_file()
  }

  if (is.null(config_file)) {
    message("\u2717 Settings file not found")
    return(invisible(NULL))
  }

  if (!file.exists(config_file)) {
    message("\u2717 Config file not found: ", config_file)
    return(invisible(NULL))
  }

  enabled <- .hooks_enabled(config_file)

  # The enclosing repository's hook is not this project's
  root <- dirname(normalizePath(config_file, mustWork = TRUE))
  top <- .fw_outer_repository(root)
  hook_path <- if (is.null(top)) .hook_path(root) else NULL
  hook_installed <- !is.null(hook_path) && file.exists(hook_path) && .is_framework_hook(hook_path)

  df <- data.frame(
    hook = names(enabled),
    enabled = unname(enabled),
    description = vapply(.hook_table(), `[[`, "", "description", USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )

  message("=== Framework Git Hooks ===\n")
  if (!is.null(top)) {
    message("Pre-commit hook: none (this project is inside the repository at ", top, ")")
  } else {
    message("Pre-commit hook: ", if (hook_installed) "installed" else "not installed")
  }
  message("")

  for (i in seq_len(nrow(df))) {
    status_icon <- if (df$enabled[i]) "\u2713" else "\u2717"
    message(sprintf("%s %s - %s", status_icon, df$hook[i], df$description[i]))
  }

  message("\nCommands:")
  message("  git_hooks_enable(\"data_security\")")
  message("  git_hooks_disable(\"data_security\")")
  message("  git_hooks_install()")
  message("  git_hooks_uninstall()")

  invisible(df)
}


# Internal helpers --------------------------------------------------------

#' Check if current directory is a git repository
#' @keywords internal
.is_git_repo <- function() {
  # .git is a file in worktrees and submodules. Below the top level, ask git.
  if (file.exists(".git")) {
    return(TRUE)
  }
  .git_available() && identical(.git_run(c("rev-parse", "--is-inside-work-tree"))$status, 0L)
}

# Run git with each argument quoted for the shell, so paths with spaces
# stay one argument. Returns the combined output and the exit status.
#' @keywords internal
.git_run <- function(args) {
  output <- suppressWarnings(system2("git", shQuote(args), stdout = TRUE, stderr = TRUE))
  status <- attr(output, "status")
  attributes(output) <- NULL
  list(output = output, status = if (is.null(status)) 0L else as.integer(status))
}

#' Check if git is available on the system
#' @return TRUE if git is available, FALSE otherwise
#' @keywords internal
.git_available <- function() {
  nzchar(Sys.which("git"))
}

#' Require git repository or stop
#' @keywords internal
.require_git_repo <- function() {
  if (!.git_available()) {
    stop("Git is not installed or not in PATH. Please install git to use this feature.")
  }
  if (!.is_git_repo()) {
    stop("Not a git repository. Run 'git init' first.")
  }
}

#' Get git hook setting with optional alias fallback
#' @keywords internal
.get_hook_setting <- function(key, alias = NULL, config_file = NULL, default = FALSE) {
  value <- config(key, config_file = config_file, default = default)
  if (!is.null(alias) && identical(value, default)) {
    value <- config(alias, config_file = config_file, default = default)
  }
  value
}


# The pre-commit checks, keyed by their git.hooks setting
#' @keywords internal
.hook_table <- function() {
  list(
    data_security = list(
      label = "Data security check",
      description = "Block commits that track private data or secrets"
    ),
    check_sensitive_dirs = list(
      label = "Sensitive directories check",
      description = "Warn about unignored sensitive directories",
      alias = "git.hooks.warn_unignored_sensitive"
    ),
    check_notebook_outputs = list(
      label = "Notebook outputs check",
      description = "Block Jupyter notebooks committed with cell outputs"
    )
  )
}

# Named logical: which checks the settings turn on
#' @keywords internal
.hooks_enabled <- function(config_file) {
  vapply(names(.hook_table()), function(hook) {
    isTRUE(tryCatch(
      .get_hook_setting(paste0("git.hooks.", hook), alias = .hook_table()[[hook]]$alias,
                        config_file = config_file, default = FALSE),
      error = function(e) FALSE
    ))
  }, logical(1))
}

# The top folder of the git repository holding a project, when that is a
# folder above the project, else NULL. Such a project has no hooks of its
# own: git runs the outer repository's hooks from the outer top folder.
#' @keywords internal
.fw_outer_repository <- function(root) {
  if (is.null(root) || !dir.exists(root) || !.git_available()) return(NULL)
  top <- .fw_git(root, "rev-parse", "--show-toplevel")
  if (!.fw_git_ok(top) || length(top) == 0 || !nzchar(top[1])) return(NULL)
  top <- normalizePath(top[1], winslash = "/", mustWork = FALSE)
  if (identical(top, normalizePath(root, winslash = "/", mustWork = FALSE))) NULL else top
}

#' @keywords internal
.fw_nested_repository_error <- function(root, top) {
  stop("The project at ", root, " is inside the git repository at ", top,
       ", so its hooks would be that repository's hooks and run from its top folder. ",
       "Framework installs hooks only for a project at the top of its own repository. ",
       "Run git init in the project to give it one.", call. = FALSE)
}

# Where git looks for the pre-commit hook (worktrees and core.hooksPath
# included), or NULL outside a repository
#' @keywords internal
.hook_path <- function(root = ".") {
  if (!.git_available()) {
    return(NULL)
  }
  path <- suppressWarnings(system2(
    "git", c("-C", shQuote(root), "rev-parse", "--git-path", "hooks/pre-commit"),
    stdout = TRUE, stderr = FALSE
  ))
  if (!is.null(attr(path, "status")) || length(path) == 0 || !nzchar(path[1])) {
    return(NULL)
  }
  path <- path[1]
  if (!grepl("^(/|[A-Za-z]:)", path)) {
    path <- file.path(root, path)
  }
  path
}

#' @keywords internal
.hook_assert_not_ai_sync <- function(hook_name) {
  if (identical(hook_name, "ai_sync")) {
    stop("The ai_sync hook was removed in framework 2.0. Skills and AGENTS.md ",
         "replace it, so there is nothing to sync.", call. = FALSE)
  }
}

# Markers of a hook Framework wrote: the shared script, and R 1.x's own
#' @keywords internal
.is_framework_hook <- function(path) {
  head <- tryCatch(readLines(path, n = 10, warn = FALSE), error = function(e) character())
  any(grepl("Framework pre-commit hook|Framework Git Hooks", head))
}

#' Run the checks for a git hook
#'
#' Called by the shared pre-commit script (`inst/hooks/pre-commit`) as
#' `framework:::.hook_run("pre-commit")`, from the repository root. Runs the
#' checks enabled under `git: hooks:` in the settings. A folder without a
#' settings file passes, so the hook never blocks commits outside a Framework
#' project.
#'
#' @param name The hook. Only "pre-commit" exists.
#' @return The exit status for git: 0 to allow the commit, 1 to block it.
#' @keywords internal
.hook_run <- function(name = "pre-commit") {
  if (!identical(name, "pre-commit")) {
    message("Framework hook: unknown hook '", name, "'")
    return(1L)
  }
  candidates <- c("settings.yml", "settings.yaml", "config.yml")
  config_file <- candidates[file.exists(candidates)][1]
  if (is.na(config_file)) {
    return(0L)
  }

  setting <- function(key, alias = NULL) {
    isTRUE(tryCatch(
      .get_hook_setting(key, alias = alias, config_file = config_file, default = FALSE),
      error = function(e) FALSE
    ))
  }

  if (setting("git.hooks.check_sensitive_dirs", "git.hooks.warn_unignored_sensitive") &&
      !.hook_check_sensitive_dirs()) {
    return(1L)
  }

  if (setting("git.hooks.check_notebook_outputs") && !.hook_check_notebook_outputs()) {
    return(1L)
  }

  if (setting("git.hooks.data_security")) {
    result <- tryCatch(
      git_security_audit(config_file = config_file, verbose = FALSE),
      error = function(e) {
        message("\u2717 Data security check could not run: ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(result) || any(result$summary$status == "fail")) {
      if (!is.null(result)) {
        failed <- result$summary[result$summary$status == "fail", , drop = FALSE]
        for (i in seq_len(nrow(failed))) {
          message(sprintf("  %s: %d issue(s)", failed$check[i], failed$count[i]))
        }
      }
      message("\u2717 Data security check failed")
      message("Run framework::git_security_audit() for details")
      return(1L)
    }
  }

  0L
}

# Folders named like private, confidential, sensitive, cache, or scratch
# that git does not ignore (the folder or an ancestor)
#' @keywords internal
.hook_unignored_sensitive_dirs <- function(root = ".") {
  dirs <- list.dirs(root, full.names = FALSE, recursive = TRUE)
  dirs <- dirs[nzchar(dirs)]
  dirs <- dirs[!grepl("(^|/)(\\.git|\\.venv|node_modules|renv)(/|$)", dirs)]
  found <- dirs[grepl("private|confidential|sensitive|cache|scratch", basename(dirs), ignore.case = TRUE)]
  if (length(found) == 0) {
    return(character())
  }

  ancestors <- function(path) {
    out <- path
    while (dirname(path) != ".") {
      path <- dirname(path)
      out <- c(out, path)
    }
    out
  }
  candidates <- unique(unlist(lapply(found, ancestors)))
  input <- tempfile("fw_check_ignore_")
  on.exit(unlink(input), add = TRUE)
  writeLines(candidates, input)
  ignored <- suppressWarnings(system2(
    "git", c("-C", shQuote(root), "check-ignore", "--no-index", "--stdin"),
    stdin = input, stdout = TRUE, stderr = FALSE
  ))
  found[!vapply(found, function(f) any(ancestors(f) %in% ignored), logical(1))]
}

# Ask on the terminal, even inside a git hook. NA when there is no terminal.
#' @keywords internal
.hook_confirm <- function(question) {
  device <- if (.Platform$OS.type == "windows") "CON" else "/dev/tty"
  tryCatch({
    con <- file(device, open = "r+")
    on.exit(close(con), add = TRUE)
    cat(question, file = con)
    answer <- readLines(con, n = 1, warn = FALSE)
    tolower(trimws(answer[1] %||% "")) %in% c("y", "yes")
  }, error = function(e) NA, warning = function(w) NA)
}

#' @keywords internal
.hook_check_sensitive_dirs <- function(root = ".") {
  folders <- .hook_unignored_sensitive_dirs(root)
  if (length(folders) == 0) {
    return(TRUE)
  }
  message("\u26a0 Warning: Found sensitive directories that are NOT gitignored:")
  for (folder in folders) message("  - ", folder)
  message("")
  message("These directories may contain sensitive data and should be added to .gitignore.")
  message("Pattern-based .gitignore entries like '**/private/**' will automatically catch them.")
  message("")
  answer <- .hook_confirm("Continue with commit anyway? (y/N) ")
  if (is.na(answer)) {
    message("(Non-interactive mode: continuing with warning)")
    return(TRUE)
  }
  if (!answer) {
    message("Commit aborted. Add directories to .gitignore and try again.")
  }
  answer
}


# Staged .ipynb files whose staged copy has outputs or execution counts in
# a code cell. Outputs can hold printed data.
#' @keywords internal
.hook_notebooks_with_outputs <- function(root = ".") {
  staged <- suppressWarnings(system2(
    "git", c("-C", shQuote(root), "-c", "core.quotepath=off",
             "diff", "--cached", "--name-only", "--diff-filter=ACMR"),
    stdout = TRUE, stderr = FALSE
  ))
  notebooks <- staged[grepl("\\.ipynb$", staged, ignore.case = TRUE)]
  notebooks[vapply(notebooks, function(path) {
    text <- suppressWarnings(system2(
      "git", c("-C", shQuote(root), "show", shQuote(paste0(":", path))),
      stdout = TRUE, stderr = FALSE
    ))
    nb <- tryCatch(jsonlite::fromJSON(paste(text, collapse = "\n"), simplifyVector = FALSE),
                   error = function(e) NULL)
    if (is.null(nb)) return(FALSE)
    any(vapply(nb$cells %||% list(), function(cell) {
      identical(cell$cell_type, "code") &&
        (length(cell$outputs %||% list()) > 0 || !is.null(cell$execution_count))
    }, logical(1)))
  }, logical(1))]
}

#' @keywords internal
.hook_check_notebook_outputs <- function(root = ".") {
  notebooks <- .hook_notebooks_with_outputs(root)
  if (length(notebooks) == 0) {
    return(TRUE)
  }
  message("\u2717 These notebooks have saved outputs, which can contain data:")
  for (nb in notebooks) message("  - ", nb)
  message("")
  message("Clear the outputs, then stage the notebooks again. In Jupyter, use")
  message("Edit > Clear All Outputs, or run:")
  for (nb in notebooks) message("  jupyter nbconvert --clear-output --inplace ", shQuote(nb))
  FALSE
}


#' Update hook configuration in settings.yml, or in its split git file
#'
#' Projects made by new_project() store `git: settings/git.yml`. The hook
#' setting is then written to that file, as framework-py does. The legacy
#' alias `warn_unignored_sensitive` is stored as `check_sensitive_dirs`.
#' @keywords internal
.update_hook_config <- function(hook_name, enabled, config_file) {
  if (!file.exists(config_file)) {
    stop("Config file not found: ", config_file)
  }

  aliases <- c(warn_unignored_sensitive = "check_sensitive_dirs")
  if (hook_name %in% names(aliases)) {
    hook_name <- aliases[[hook_name]]
  }
  set_hook <- function(git) {
    if (!is.list(git)) git <- list()
    hooks <- if (is.list(git$hooks)) git$hooks else list()
    hooks[[hook_name]] <- enabled
    # An old alias key would otherwise keep a disabled check turned on
    for (alias in names(aliases)[aliases == hook_name]) hooks[[alias]] <- NULL
    git$hooks <- hooks
    git
  }

  # Read config
  config_content <- yaml::read_yaml(config_file, eval.expr = FALSE)
  if (is.null(config_content)) config_content <- list()

  has_envs <- !is.null(config_content$default) && is.list(config_content$default)
  env_config <- if (has_envs) config_content$default else config_content

  reference <- env_config$git
  if (is.character(reference) && length(reference) == 1 && grepl("\\.ya?ml$", reference)) {
    split_file <- if (grepl("^(/|[A-Za-z]:)", reference)) reference else file.path(dirname(config_file), reference)
    split <- if (file.exists(split_file)) yaml::read_yaml(split_file, eval.expr = FALSE) else NULL
    if (!is.list(split)) split <- list()
    # A split file holds its section under `git:`, or the bare keys
    if (!is.null(split$git) || length(split) == 0) {
      split$git <- set_hook(split$git)
    } else {
      split <- set_hook(split)
    }
    dir.create(dirname(split_file), recursive = TRUE, showWarnings = FALSE)
    yaml::write_yaml(split, split_file)
    return(invisible(TRUE))
  }

  env_config$git <- set_hook(env_config$git)

  if (has_envs) {
    config_content$default <- env_config
  } else {
    config_content <- env_config
  }

  # Write back
  yaml::write_yaml(config_content, config_file)

  invisible(TRUE)
}
