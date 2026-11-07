#' Show Framework project status
#'
#' Displays comprehensive information about the current Framework project including:
#' - Framework package version
#' - Project configuration
#' - Git status
#' - AI assistant configuration
#' - Git hooks status
#' - Package dependencies
#' - Directory structure
#'
#' @return No return value, called for side effect of printing project status.
#' @export
#' @examples
#' \donttest{
#' if (FALSE) {
#' status()
#' }
#' }
status <- function() {
  # Check if we're in a Framework project
  if (!.has_settings_file()) {
    stop("Not in a Framework project directory (settings.yml or config.yml not found)")
  }

  message("")
  message(cli::style_bold(cli::col_blue("===================================================")))
  message(cli::style_bold(cli::col_blue("  FRAMEWORK PROJECT STATUS")))
  message(cli::style_bold(cli::col_blue("===================================================")))
  message("")

  # Framework version
  message(cli::style_bold(cli::col_yellow("Framework:")))
  fw_version <- as.character(packageVersion("framework"))
  message(sprintf("  Version: %s", fw_version))
  message("")

  # Project info
  config <- tryCatch(settings_read(), error = function(e) NULL)
  if (!is.null(config)) {
    message(cli::style_bold(cli::col_yellow("Project:")))

    if (!is.null(config$project_type)) {
      message(sprintf("  Type: %s", config$project_type))
    }
    message(sprintf("  Sensitive data: %s", if (.fw_settings_sensitive(config)) "yes" else "no"))
    mismatch <- .fw_sensitive_mismatch(config)
    if (!is.null(mismatch)) {
      message("  ", cli::col_yellow(paste("Warning:", mismatch)))
    }

    if (!is.null(config$author$name)) {
      message(sprintf("  Author: %s", config$author$name))
    }

    notebook_format <- config$scaffold$notebook_format %||% config$default_notebook_format %||%
      config$options$default_notebook_format
    if (!is.null(notebook_format)) {
      message(sprintf("  Notebook format: %s", notebook_format))
    }

    message("")
  }

  # Git status
  message(cli::style_bold(cli::col_yellow("Git:")))

  # Check if git is installed
  git_installed <- nzchar(Sys.which("git"))
  git_available <- git_installed && tryCatch({
    system("git rev-parse --git-dir", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0
  }, error = function(e) FALSE)

  if (git_available) {
    # Check if there are commits
    has_commits <- tryCatch({
      system("git rev-parse HEAD", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0
    }, error = function(e) FALSE)

    # A project inside another repository: say so, and count only this
    # project's folder
    project_root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
    outer_top <- .fw_outer_repository(project_root)
    scope <- if (!is.null(outer_top)) paste("--", shQuote(project_root)) else ""
    if (!is.null(outer_top)) {
      message(sprintf("  Inside the repository at %s (counts are for this project)", outer_top))
    }

    if (has_commits) {
      # Get current branch
      branch <- tryCatch({
        trimws(system("git branch --show-current", intern = TRUE, ignore.stderr = TRUE))
      }, error = function(e) "unknown")

      # Get commit count
      commit_count <- tryCatch({
        as.integer(system(paste("git rev-list --count HEAD", scope), intern = TRUE, ignore.stderr = TRUE))
      }, error = function(e) 0)

      # Get uncommitted changes count
      status_result <- tryCatch({
        system(paste("git status --porcelain", scope), intern = TRUE, ignore.stderr = TRUE)
      }, error = function(e) character(0))

      uncommitted <- length(status_result)

      message(sprintf("  Branch: %s", branch))
      # Nested, the count is only the commits that touch this project
      label <- if (!is.null(outer_top)) "Commits touching this project" else "Commits"
      message(sprintf("  %s: %d", label, commit_count))

      if (uncommitted > 0) {
        message("  ", cli::style_bold(cli::col_red(sprintf("Uncommitted changes: %d", uncommitted))))
      } else {
        message("  ", cli::col_green("Working tree clean"))
      }
    } else {
      message("  ", cli::style_bold(cli::col_red("No commits yet")))
    }
  } else if (!git_installed) {
    message("  Git not installed")
  } else {
    message("  Not a git repository")
  }

  message("")

  # AI assistants
  if (!is.null(config) && !is.null(config$ai)) {
    message(cli::style_bold(cli::col_yellow("AI Assistants:")))

    ai_files <- c()
    if (file.exists("CLAUDE.md")) ai_files <- c(ai_files, "CLAUDE.md")
    if (file.exists("AGENTS.md")) ai_files <- c(ai_files, "AGENTS.md")
    if (file.exists(".github/copilot-instructions.md")) {
      ai_files <- c(ai_files, ".github/copilot-instructions.md")
    }

    if (length(ai_files) > 0) {
      message(sprintf("  Files: %s", paste(ai_files, collapse = ", ")))

      if (!is.null(config$ai$canonical_file)) {
        message(sprintf("  Canonical: %s", config$ai$canonical_file))
      }
    } else {
      message("  No AI instruction files found")
    }

    message("")
  }

  # Git hooks
  hook_path <- if (git_available) .hook_path() else NULL
  if (!is.null(hook_path) && file.exists(hook_path)) {
    message(cli::style_bold(cli::col_yellow("Git Hooks:")))

    if (!is.null(config) && !is.null(config$git) && !is.null(config$git$hooks)) {
      hooks <- config$git$hooks

      if (!is.null(hooks$data_security)) {
        status <- if (isTRUE(hooks$data_security)) cli::col_green("enabled") else "disabled"
        message(sprintf("  Data security: %s", status))
      }
    }

    message("")
  }

  # renv status
  message(cli::style_bold(cli::col_yellow("Package Management:")))

  if (file.exists("renv.lock")) {
    message("  ", cli::col_green("renv: enabled"))
  } else {
    message("  renv: disabled")
  }

  message("")

  # Directories
  if (!is.null(config) && !is.null(config$directories)) {
    message(cli::style_bold(cli::col_yellow("Directories:")))

    dirs <- config$directories
    for (name in names(dirs)) {
      path <- dirs[[name]]
      exists <- dir.exists(path)
      # Missing folders are made on first use, as project_info() says
      status <- if (exists) cli::col_green("ok") else cli::col_yellow("lazy")
      message(sprintf("  %s %s -> %s", status, name, path))
    }

    message("")
  }

  # Packages
  if (!is.null(config) && !is.null(config$packages)) {
    message(cli::style_bold(cli::col_yellow("Dependencies:")))

    packages <- .get_package_requirements(config)
    # vapply: sapply() on no packages gave list(), and sum() failed
    auto_attached <- sum(vapply(packages, function(p) isTRUE(p$load), logical(1)))
    total <- length(packages)

    message(sprintf("  Total: %d package%s", total, if (total == 1) "" else "s"))
    if (auto_attached > 0) {
      message(sprintf("  Auto-attached: %d", auto_attached))
    }

    message("")
  }

  # Database connections
  if (!is.null(config) && !is.null(config$connections)) {
    # Get database connections: check databases sub-key first (GUI format), then flat (legacy)
    db_conns <- config$connections$databases
    if (is.null(db_conns) || length(db_conns) == 0) {
      db_conns <- config$connections
      if (is.list(db_conns)) {
        db_conns <- db_conns[!names(db_conns) %in% c("storage_buckets", "default_storage_bucket", "default_database", "databases")]
        db_conns <- Filter(function(x) is.list(x) && !is.null(x$driver), db_conns)
      }
    }

    if (length(db_conns) > 0) {
      message(cli::style_bold(cli::col_yellow("Database Connections:")))

      for (conn_name in names(db_conns)) {
        conn <- db_conns[[conn_name]]
        driver <- conn$driver %||% conn$type
        if (!is.null(driver)) {
          message(sprintf("  %s (%s)", conn_name, driver))
        } else {
          message(sprintf("  %s", conn_name))
        }
      }

      message("")
    }
  }

  message(cli::style_bold(cli::col_blue("===================================================")))
  message("")

  invisible(NULL)
}
