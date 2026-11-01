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
  message("\033[1;34m")
  message("===================================================")
  message("  FRAMEWORK PROJECT STATUS")
  message("===================================================")
  message("\033[0m")
  message("")

  # Framework version
  message("\033[1;33m")
  message("Framework:")
  message("\033[0m")
  fw_version <- as.character(packageVersion("framework"))
  message(sprintf("  Version: %s", fw_version))
  message("")

  # Project info
  config <- tryCatch(settings_read(), error = function(e) NULL)
  if (!is.null(config)) {
    message("\033[1;33m")
    message("Project:")
    message("\033[0m")

    if (!is.null(config$project_type)) {
      message(sprintf("  Type: %s", config$project_type))
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
  message("\033[1;33m")
  message("Git:")
  message("\033[0m")

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

    if (has_commits) {
      # Get current branch
      branch <- tryCatch({
        trimws(system("git branch --show-current", intern = TRUE, ignore.stderr = TRUE))
      }, error = function(e) "unknown")

      # Get commit count
      commit_count <- tryCatch({
        as.integer(system("git rev-list --count HEAD", intern = TRUE, ignore.stderr = TRUE))
      }, error = function(e) 0)

      # Get uncommitted changes count
      status_result <- tryCatch({
        system("git status --porcelain", intern = TRUE, ignore.stderr = TRUE)
      }, error = function(e) character(0))

      uncommitted <- length(status_result)

      message(sprintf("  Branch: %s", branch))
      message(sprintf("  Commits: %d", commit_count))

      if (uncommitted > 0) {
        message(sprintf("  \033[1;31mUncommitted changes: %d\033[0m", uncommitted))
      } else {
        message("  \033[0;32mWorking tree clean\033[0m")
      }
    } else {
      message("  \033[1;31mNo commits yet\033[0m")
    }
  } else if (!git_installed) {
    message("  Git not installed")
  } else {
    message("  Not a git repository")
  }

  message("")

  # AI assistants
  if (!is.null(config) && !is.null(config$ai)) {
    message("\033[1;33m")
    message("AI Assistants:")
    message("\033[0m")

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
    message("\033[1;33m")
    message("Git Hooks:")
    message("\033[0m")

    if (!is.null(config) && !is.null(config$git) && !is.null(config$git$hooks)) {
      hooks <- config$git$hooks

      if (!is.null(hooks$data_security)) {
        status <- if (isTRUE(hooks$data_security)) "\033[0;32menabled\033[0m" else "disabled"
        message(sprintf("  Data security: %s", status))
      }
    }

    message("")
  }

  # renv status
  message("\033[1;33m")
  message("Package Management:")
  message("\033[0m")

  if (file.exists("renv.lock")) {
    message("  \033[0;32mrenv: enabled\033[0m")
  } else {
    message("  renv: disabled")
  }

  message("")

  # Directories
  if (!is.null(config) && !is.null(config$directories)) {
    message("\033[1;33m")
    message("Directories:")
    message("\033[0m")

    dirs <- config$directories
    for (name in names(dirs)) {
      path <- dirs[[name]]
      exists <- dir.exists(path)
      status <- if (exists) "\033[0;32mok\033[0m" else "\033[1;31mx\033[0m"
      message(sprintf("  %s %s -> %s", status, name, path))
    }

    message("")
  }

  # Packages
  if (!is.null(config) && !is.null(config$packages)) {
    message("\033[1;33m")
    message("Dependencies:")
    message("\033[0m")

    packages <- .get_package_requirements(config)
    auto_attached <- sum(sapply(packages, function(p) p$load))
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
      message("\033[1;33m")
      message("Database Connections:")
      message("\033[0m")

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

  message("\033[1;34m")
  message("===================================================")
  message("\033[0m")
  message("")

  invisible(NULL)
}
