#' Prepare a Cloned Project
#'
#' Gets a project ready to work in after `git clone`, on a new machine or a
#' cluster. Every step is safe to repeat, and none contacts Framework Cloud:
#'
#' 1. Make sure `.gitignore` ignores `.env`.
#' 2. Create `.env` from `.env.example` when it is missing, and list the
#'    variables that are still empty.
#' 3. Create the project folders, which git does not carry when they are
#'    empty or ignored. Absolute paths (shared drives) are left alone.
#' 4. Create `framework.db`, or add the tables a newer version needs.
#' 5. Install packages: `renv::restore()` when the project has `renv.lock`,
#'    otherwise the packages listed in settings.yml.
#' 6. Install the git hooks enabled in settings.yml.
#'
#' The Python package and `fw bootstrap` follow the same contract. From a
#' shell: `Rscript -e 'framework::bootstrap(interactive = FALSE)'`, which
#' exits with status 0 when the project is ready (even with to-dos left) and
#' 1 when a step failed.
#'
#' @param path The project folder (default: the current directory).
#' @param interactive If `TRUE`, ask for the values of empty `.env`
#'   variables. If `FALSE`, never prompt and list them as to-dos instead.
#' @param packages If `FALSE`, skip package installation.
#'
#' @return Invisibly, a list with `root`, `done` (the steps that changed
#'   something), and `todo` (things left to do by hand).
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # After cloning a project
#' framework::bootstrap()
#'
#' # In a job script on a cluster
#' framework::bootstrap(interactive = FALSE)
#' }
#' }
#'
#' @seealso [new()], [git_hooks_install()], [packages_restore()]
#' @export
bootstrap <- function(path = ".", interactive = base::interactive(), packages = TRUE) {
  checkmate::assert_string(path, min.chars = 1)
  checkmate::assert_flag(interactive)
  checkmate::assert_flag(packages)

  root <- normalizePath(path.expand(path), winslash = "/", mustWork = FALSE)
  candidates <- file.path(root, c("settings.yml", "settings.yaml", "config.yml"))
  settings_file <- candidates[file.exists(candidates)][1]
  if (!dir.exists(root) || is.na(settings_file)) {
    stop(sprintf("No settings.yml in %s. Is this a Framework project?", root), call. = FALSE)
  }

  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)
  config <- settings_read(basename(settings_file))

  language <- config$language %||% "r"
  if (!identical(language, "r")) {
    stop(sprintf(
      "This is a %s project. Prepare it with that language's Framework (in Python: python -m framework bootstrap).",
      language
    ), call. = FALSE)
  }
  .bootstrap_check_spec(root)

  done <- character()
  todo <- character()

  if (suppressMessages(.ensure_secrets_ignored(root))) {
    done <- c(done, "Added .env to .gitignore")
  }

  env <- .bootstrap_env(root, interactive)
  done <- c(done, env$done)
  todo <- c(todo, env$todo)

  created <- .bootstrap_folders(root, config)
  if (length(created) > 0) {
    done <- c(done, paste("Created folders:", paste(created, collapse = ", ")))
  }

  db_existed <- file.exists(file.path(root, "framework.db"))
  suppressMessages(.ensure_framework_db(root))
  done <- c(done, if (db_existed) "Updated framework.db" else "Created framework.db")

  if (packages) {
    done <- c(done, .bootstrap_packages(root, config))
  }

  if (file.exists(file.path(root, ".git")) &&
      isTRUE(git_hooks_install(config_file = basename(settings_file), verbose = FALSE))) {
    done <- c(done, "Installed git hooks")
  }

  for (step in done) message("\u2713 ", step)
  for (item in todo) message("\u2022 To do: ", item)
  message("Project ready: ", root)

  invisible(list(root = root, done = done, todo = todo))
}

# An invalid .framework/spec.json means the project was damaged or edited by
# hand; stop rather than build on it
#' @keywords internal
.bootstrap_check_spec <- function(root) {
  path <- file.path(root, ".framework", "spec.json")
  if (!file.exists(path)) {
    return(invisible(NULL))
  }
  spec <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) {
      stop(".framework/spec.json is not valid JSON: ", conditionMessage(e), call. = FALSE)
    }
  )
  problems <- if (is.list(spec) && !is.null(names(spec))) spec_check(spec) else "it is not a JSON object"
  if (length(problems) > 0) {
    stop(".framework/spec.json is invalid: ", paste(problems, collapse = "; "), call. = FALSE)
  }
  invisible(NULL)
}

#' @keywords internal
.bootstrap_env <- function(root, interactive) {
  done <- character()
  todo <- character()
  env_path <- file.path(root, ".env")
  example <- file.path(root, ".env.example")

  if (!file.exists(env_path) && file.exists(example)) {
    file.copy(example, env_path)
    done <- c(done, "Created .env from .env.example")
  }
  if (!file.exists(env_path)) {
    return(list(done = done, todo = todo))
  }

  lines <- readLines(env_path, warn = FALSE)
  pattern <- "^(\\s*(export\\s+)?)([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*$"
  empty_rows <- grep(pattern, lines)
  empty <- sub(pattern, "\\3", lines[empty_rows])

  if (interactive && length(empty) > 0) {
    filled <- character()
    for (i in seq_along(empty)) {
      key <- empty[i]
      prompt <- paste0(key, " (leave empty to skip): ")
      answer <- if (.fw_secret_name(key) && requireNamespace("askpass", quietly = TRUE)) {
        askpass::askpass(prompt) %||% ""
      } else {
        readline(prompt)
      }
      answer <- trimws(answer)
      if (nzchar(answer)) {
        value <- if (grepl("[[:space:]#\"']", answer)) {
          as.character(jsonlite::toJSON(answer, auto_unbox = TRUE))
        } else {
          answer
        }
        row <- empty_rows[i]
        lines[row] <- paste0(sub(pattern, "\\1", lines[row]), key, "=", value)
        filled <- c(filled, key)
      }
    }
    if (length(filled) > 0) {
      writeLines(lines, env_path)
      done <- c(done, paste("Filled in", paste(filled, collapse = ", "), "in .env"))
    }
    empty <- setdiff(empty, filled)
  }
  if (length(empty) > 0) {
    todo <- c(todo, paste("Fill in .env:", paste(empty, collapse = ", ")))
  }
  list(done = done, todo = todo)
}

#' @keywords internal
.bootstrap_folders <- function(root, config) {
  folders <- unlist(Filter(is.character, config$directories %||% list()), use.names = FALSE)
  for (entry in config$extra_directories %||% list()) {
    if (is.list(entry) && is.character(entry$path)) folders <- c(folders, entry$path)
  }
  folders <- unique(folders[nzchar(folders)])

  created <- character()
  for (folder in folders) {
    # Shared drives and other places outside the project are not ours to make
    if (grepl("^(/|~|[A-Za-z]:[/\\\\]|\\\\\\\\)", folder)) next
    if (grepl("(^|/)\\.\\.(/|$)", folder)) next
    if (.fw_is_file_entry(folder)) next
    path <- file.path(root, folder)
    if (!dir.exists(path)) {
      dir.create(path, recursive = TRUE, showWarnings = FALSE)
      created <- c(created, folder)
    }
  }
  created
}

#' @keywords internal
.bootstrap_packages <- function(root, config) {
  if (file.exists(file.path(root, "renv.lock"))) {
    if (!requireNamespace("renv", quietly = TRUE)) {
      stop("Package restore failed: this project uses renv (renv.lock), but renv is not installed. ",
           "Install it with install.packages(\"renv\") and run bootstrap() again.", call. = FALSE)
    }
    tryCatch(
      renv::restore(project = root, prompt = FALSE),
      error = function(e) {
        stop("Package restore failed: ", conditionMessage(e), call. = FALSE)
      }
    )
    return("Restored packages (renv.lock)")
  }

  if (length(.get_package_list_from_config(config)) == 0) {
    return(character())
  }
  tryCatch(
    .install_required_packages(config),
    error = function(e) {
      stop("Package install failed: ", conditionMessage(e), call. = FALSE)
    }
  )
  "Installed packages from settings.yml"
}
