# A project's setup (its packages and skills), kept in step with Framework
# Cloud. pull_setup() brings Cloud's package list and skills into the
# project; push_setup() sends the project's package list, then its edited
# skills, back. Folders and structure are never part of the setup.
# framework-py: setup_sync.py; fw: fw setup pull / fw setup push.

.setup_lock_file <- ".framework/setup.lock.json"

.setup_lock_read <- function(root) {
  path <- file.path(root, .setup_lock_file)
  if (!file.exists(path)) return(list())
  tryCatch(jsonlite::read_json(path), error = function(e) list())
}

.setup_lock_write <- function(root, revision, server) {
  path <- file.path(root, .setup_lock_file)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  data <- list(schema = 1L, revision = revision, server = server,
               updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  writeLines(jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE), path, useBytes = TRUE)
}

# The project's server and token; an error that changes nothing without one
.setup_connection <- function(root) {
  token <- .fw_project_token(root)
  if (is.null(token)) {
    stop("Framework Cloud not reached (no project token in FW_PROJECT_TOKEN or the project's .env). Nothing changed.",
         call. = FALSE)
  }
  list(server = .fw_project_cloud_url(root), token = token)
}

# Cloud errors as setup messages: offline, no setup endpoint, and the
# server's own message (a 422) as it is
.setup_request <- function(path, connection, method = "GET", body = NULL) {
  tryCatch(
    .fw_api(path, connection$token, method = method, body = body, url = connection$server),
    httr2_http_404 = function(e) {
      stop("This Framework Cloud server has no setup endpoint yet. Nothing changed.", call. = FALSE)
    },
    httr2_http_401 = function(e) .setup_refused(e),
    httr2_http_403 = function(e) .setup_refused(e),
    httr2_http_422 = function(e) {
      stop(.setup_reason(e) %||% "Framework Cloud refused the setup", ". Nothing changed.", call. = FALSE)
    },
    httr2_failure = function(e) {
      stop("Framework Cloud not reached (", sub("\\.$", "", conditionMessage(e)), "). Nothing changed.", call. = FALSE)
    }
  )
}

.setup_reason <- function(e) {
  reason <- tryCatch(httr2::resp_body_json(e$resp)$message, error = function(err) NULL)
  if (is.character(reason) && length(reason) == 1 && nzchar(reason)) sub("\\.$", "", reason) else NULL
}

# A revoked or mistyped project token
.setup_refused <- function(e) {
  stop("Framework Cloud refused the project token (", .setup_reason(e) %||% "not accepted",
       "). Check FW_PROJECT_TOKEN in the project's .env. Nothing changed.", call. = FALSE)
}

# The project's packages as setup rows, by name
.setup_local_packages <- function(root) {
  config <- tryCatch(settings_read(file.path(root, "settings.yml")), error = function(e) list())
  rows <- list()
  for (spec in .get_package_list_from_config(config)) {
    p <- tryCatch(.normalize_package_spec(spec), error = function(e) NULL)
    if (is.null(p$name)) next
    row <- list(name = p$name, source = p$source %||% "cran", auto_attach = isTRUE(p$auto_attach))
    if (!is.null(p$version) && nzchar(p$version)) row$version <- as.character(p$version)
    if (identical(row$source, "github") && !is.null(p$repo)) row$repo <- p$repo
    rows[[p$name]] <- row
  }
  rows
}

.setup_empty <- function(x) is.null(x) || length(x) == 0 || (length(x) == 1 && (is.na(x) || !nzchar(x)))

.setup_same <- function(local, cloud) {
  source <- local$source %||% "cran"
  if (!identical(source, cloud$source %||% "cran")) return(FALSE)
  if (identical(source, "github") && !identical(local$repo, cloud$repo)) return(FALSE)
  version <- function(r) if (.setup_empty(r$version)) "" else as.character(r$version)
  identical(version(local), version(cloud)) && identical(isTRUE(local$auto_attach), isTRUE(cloud$auto_attach))
}

.setup_describe <- function(row) {
  what <- if (identical(row$source, "github")) paste("github", row$repo)
    else if (!.setup_empty(row$version)) row$version
    else if (identical(row$source, "bioc")) "Bioconductor"
    else "any version"
  if (isTRUE(row$auto_attach)) paste0(what, ", auto-attached") else what
}

.setup_names <- function(rows) paste(vapply(rows, `[[`, "", "name"), collapse = ", ")

.setup_project_name <- function(root) {
  config <- tryCatch(settings_read(file.path(root, "settings.yml")), error = function(e) list())
  name <- config$project_name
  if (is.character(name) && length(name) == 1 && nzchar(name)) name else basename(root)
}

# A setup row as a settings.yml package entry, keeping a local GitHub ref
.setup_entry <- function(row, local = NULL) {
  entry <- list(name = row$name, source = row$source %||% "cran")
  if (!.setup_empty(row$version)) entry$version <- row$version
  if (!.setup_empty(row$repo)) entry$repo <- row$repo
  if (identical(entry$source, "github") && identical(local$repo, row$repo) && !is.null(local$ref)) entry$ref <- local$ref
  entry$auto_attach <- isTRUE(row$auto_attach)
  entry
}

# Record the packages in settings, then install them: renv when the project
# uses it, else base R, as package_add() does
.setup_install <- function(root, rows) {
  settings_file <- file.path(root, "settings.yml")
  .packages_edit(settings_file, function(packages) {
    listed <- vapply(packages, function(p) tryCatch(.normalize_package_spec(p)$name %||% "", error = function(e) ""), "")
    for (row in rows) {
      hit <- which(listed == row$name)
      if (length(hit)) {
        local <- tryCatch(.normalize_package_spec(packages[[hit[1]]]), error = function(e) NULL)
        packages[[hit[1]]] <- .setup_entry(row, local)
      } else {
        packages <- c(packages, list(.setup_entry(row)))
      }
    }
    packages
  })
  failed <- character()
  for (row in rows) {
    ok <- tryCatch({
      .install_package(.setup_entry(row))
      # A pinned version that failed to build leaves the old one installed
      requireNamespace(row$name, quietly = TRUE) &&
        (.setup_empty(row$version) || identical(as.character(utils::packageVersion(row$name)), as.character(row$version)))
    }, error = function(e) FALSE)
    if (!isTRUE(ok)) failed <- c(failed, row$name)
  }
  if (length(failed)) {
    warning("Could not install ", paste(failed, collapse = ", "),
            ". They are recorded; run packages_install() to try again.", call. = FALSE)
  }
  .fw_refresh_agents_md(settings_file)
  message("\u2713 Packages: ", length(rows), " added or updated")
}

.setup_skills_line <- function(counts) {
  labels <- c(added = "to add", updated = "to update", replaced = "to replace (backed up)",
              edited = "locally edited (kept)", removed = "no longer in the project's setup (kept)")
  n <- vapply(names(labels), function(k) as.integer(counts[[k]] %||% 0L), integer(1))
  if (!any(n > 0)) return(NULL)
  paste0("  Skills: ", paste(n[n > 0], labels[n > 0], collapse = ", "))
}

#' Pull a Project's Setup from Framework Cloud
#'
#' Brings the project's packages and skills up to date with its setup on
#' Framework Cloud. The setup is read with the project token
#' (`GET /api/v1/projects/setup`), and the changes are listed first:
#' packages to add, packages whose version, source, or auto-attach setting
#' differs, packages only in this project, and skills to add, update, or
#' keep. Then it asks `Apply these changes? [y/n]`.
#'
#' Applying adds the new packages to the project's settings and installs
#' them (with renv when the project uses it), then runs [pull_skills()].
#' Local packages are never removed. A package whose local settings differ
#' keeps them unless `overwrite = TRUE`, which also replaces locally edited
#' skills (backed up). The revision pulled is kept in
#' `.framework/setup.lock.json` for [push_setup()]. Folders and structure
#' are never part of the setup.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param overwrite Use Cloud's settings for differing packages and replace
#'   locally edited skills.
#' @param confirm `TRUE` applies without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run List the changes and write nothing.
#' @return Invisibly, a list: `revision`, `packages` (`added`, `changed`,
#'   `differ_kept`, and `kept_local`, as names), `skills` (the
#'   [pull_skills()] result, or `NULL` when nothing was applied), `applied`,
#'   `dry_run`, and `message`.
#' @seealso [push_setup()], [pull_skills()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' pull_setup(dry_run = TRUE)
#' pull_setup()
#' }
#' }
pull_setup <- function(project_path = ".", overwrite = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  connection <- .setup_connection(root)
  setup <- .setup_request("/api/v1/projects/setup", connection)
  revision <- as.character(setup$revision %||% "")
  language <- setup$language %||% "r"
  if (identical(language, "python")) {
    stop("This is a Python project on Framework Cloud. Use framework-py's pull_setup() or fw setup pull.", call. = FALSE)
  }

  local <- .setup_local_packages(root)
  cloud <- list()
  if (identical(language, "r")) for (row in setup$packages %||% list()) cloud[[row$name]] <- row
  added <- unname(cloud[setdiff(names(cloud), names(local))])
  both <- intersect(names(cloud), names(local))
  differ <- Filter(function(n) !.setup_same(local[[n]], cloud[[n]]), both)
  kept_local <- if (identical(language, "r")) setdiff(names(local), names(cloud)) else character()

  plan <- suppressMessages(pull_skills(root, overwrite = overwrite, dry_run = TRUE))

  lines <- paste0("Setup changes from Framework Cloud (revision ", revision, "):")
  if (!identical(language, "r")) lines <- c(lines, paste0("  Packages: not managed for ", tools::toTitleCase(language), " projects; skills only"))
  if (length(added)) lines <- c(lines, paste0("  Packages to add: ", .setup_names(added)))
  if (length(differ)) {
    details <- paste(vapply(differ, function(n) {
      paste0(n, " (local ", .setup_describe(local[[n]]), ", Cloud ", .setup_describe(cloud[[n]]), ")")
    }, ""), collapse = ", ")
    tail <- if (overwrite) "Cloud's will be used" else "kept; pull_setup(overwrite = TRUE) uses Cloud's"
    lines <- c(lines, paste0("  Packages that differ: ", details, " \u2014 ", tail))
  }
  if (length(kept_local)) lines <- c(lines, paste0("  Only in this project (kept): ", paste(kept_local, collapse = ", ")))
  skills_line <- .setup_skills_line(plan$counts)
  if (!is.null(skills_line)) lines <- c(lines, skills_line)
  changes <- length(added) > 0 || (length(differ) > 0 && overwrite) ||
    any(vapply(c("added", "updated", "replaced"), function(k) (plan$counts[[k]] %||% 0L) > 0, logical(1)))
  if (!changes && !length(differ) && is.null(skills_line) && identical(language, "r")) {
    lines <- paste0("Setup is up to date with Framework Cloud (revision ", revision, ").")
  }
  for (line in lines) message(line)

  result <- list(
    revision = revision,
    packages = list(added = vapply(added, `[[`, "", "name"),
                    changed = if (overwrite) differ else character(),
                    differ_kept = if (overwrite) character() else differ,
                    kept_local = kept_local),
    skills = NULL, applied = FALSE, dry_run = dry_run, message = paste(lines, collapse = "\n"))
  if (dry_run) return(invisible(result))
  if (!changes) {
    .setup_lock_write(root, revision, connection$server)
    return(invisible(result))
  }
  if (!.fw_confirm(confirm, "Apply these changes?", "pull_setup()", dry_run_hint = TRUE)) {
    message("Nothing changed.")
    return(invisible(result))
  }

  rows <- c(added, if (overwrite) unname(cloud[differ]))
  if (length(rows)) .setup_install(root, rows)
  result$skills <- pull_skills(root, overwrite = overwrite)
  .setup_lock_write(root, revision, connection$server)
  result$applied <- TRUE
  invisible(result)
}

#' Push a Project's Setup to Framework Cloud
#'
#' Sends the project's package list, then its edited skills, to its setup on
#' Framework Cloud. The package list goes to
#' `POST /api/v1/projects/setup/packages`, first as a dry run whose changes
#' are listed with a warning: new setups, zips, and Update on GitHub use what
#' is pushed. Then it asks `Push these changes? [y/n]`. Packages only on
#' Cloud stay there unless `remove = TRUE`.
#'
#' When Cloud's setup changed since this project last pulled it (the
#' revision in `.framework/setup.lock.json`), the push is refused with "Pull
#' first"; `force = TRUE` replaces Cloud's newer changes. Edited skills then
#' go through [push_skills()], with its own warning. A push resolves the
#' project again from its blueprint's latest version.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param remove Remove packages from Cloud's setup that this project doesn't list.
#' @param force Push even when Cloud's setup changed since the last pull.
#' @param confirm `TRUE` pushes without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run List the changes and send nothing.
#' @return Invisibly, a list: `revision`, `changes` (Cloud's `added`,
#'   `changed`, `removed`, and `kept`), `applied`, `skills` (the
#'   [push_skills()] result), `dry_run`, and `message`.
#' @seealso [pull_setup()], [push_skills()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' push_setup(dry_run = TRUE)
#' push_setup()
#' }
#' }
push_setup <- function(project_path = ".", remove = FALSE, force = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(remove)
  checkmate::assert_flag(force)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  connection <- .setup_connection(root)
  # The language, and the base revision for a project that never pulled its setup
  setup <- .setup_request("/api/v1/projects/setup", connection)
  base <- .setup_lock_read(root)$revision %||% setup$revision
  language <- setup$language %||% "r"
  if (identical(language, "python")) {
    stop("This is a Python project on Framework Cloud. Use framework-py's push_setup() or fw setup push.", call. = FALSE)
  }
  if (!identical(language, "r")) {
    message("Packages are not managed for ", tools::toTitleCase(language), " projects; pushing skills only.")
    return(invisible(list(revision = setup$revision, changes = list(added = list(), changed = list(), removed = list(), kept = list()),
                          applied = FALSE, skills = push_skills(root, force = force, confirm = confirm, dry_run = dry_run),
                          dry_run = dry_run, message = "Packages are not managed for this project's language.")))
  }
  local <- .setup_local_packages(root)

  send <- function(dry) {
    body <- list(base_revision = base, packages = unname(local), remove = remove, force = force, dry_run = dry)
    tryCatch(
      .setup_request("/api/v1/projects/setup/packages", connection, method = "POST", body = body),
      httr2_http_409 = function(e) {
        current <- tryCatch(httr2::resp_body_json(e$resp)$revision, error = function(err) NULL)
        stop("Framework Cloud's setup changed since this project last pulled it (revision ", current %||% "unknown",
             "). Pull first: pull_setup(). push_setup(force = TRUE) replaces Cloud's changes.", call. = FALSE)
      })
  }

  preview <- send(TRUE)
  changes <- preview$changes %||% list()
  added <- changes$added %||% list(); changed <- changes$changed %||% list()
  removed <- changes$removed %||% list(); kept <- changes$kept %||% list()

  lines <- "Setup changes for Framework Cloud:"
  if (length(added)) lines <- c(lines, paste0("  Packages to add: ", .setup_names(added)))
  if (length(changed)) {
    details <- paste(vapply(changed, function(c) {
      paste0(c$name, " (", .setup_describe(c$from), " -> ", .setup_describe(c$to), ")")
    }, ""), collapse = ", ")
    lines <- c(lines, paste0("  Packages to change: ", details))
  }
  if (length(removed)) lines <- c(lines, paste0("  Packages to remove: ", .setup_names(removed)))
  if (length(kept)) lines <- c(lines, paste0("  On Cloud only (kept): ", .setup_names(kept)))
  pending <- length(added) + length(changed) + length(removed) > 0
  if (!pending) {
    lines[1] <- "Setup on Framework Cloud already matches this project."
  } else {
    lines <- c(lines, paste0("This changes ", .setup_project_name(root), "'s setup on Framework Cloud. ",
                             "New setups, zips, and Update on GitHub will use it."))
    beyond <- setdiff(c(vapply(added, `[[`, "", "name"), vapply(changed, `[[`, "", "name")), names(local))
    if (length(beyond)) {
      lines <- c(lines, paste0("Pushing re-resolves the project from its blueprint's latest version, ",
                               "which can update a project pinned to an older blueprint version."))
    }
    if (force && !identical(base, setup$revision)) {
      lines <- c(lines, "Cloud's newer setup changes will be replaced by this project's packages.")
    }
  }
  for (line in lines) message(line)
  result <- list(revision = preview$revision,
                 changes = list(added = added, changed = changed, removed = removed, kept = kept),
                 applied = FALSE, skills = NULL, dry_run = dry_run, message = paste(lines, collapse = "\n"))

  if (pending && !dry_run) {
    if (!.fw_confirm(confirm, "Push these changes?", "push_setup()", dry_run_hint = TRUE)) {
      message("Setup not pushed.")
      return(invisible(result))
    }
    reply <- send(FALSE)
    revision <- as.character(reply$revision %||% "")
    result$applied <- isTRUE(reply$applied); result$revision <- revision
    .setup_lock_write(root, revision, connection$server)
    done <- reply$changes %||% changes
    if (isTRUE(reply$applied)) {
      parts <- unlist(lapply(c("added", "changed", "removed"), function(k) {
        if (length(done[[k]])) paste(length(done[[k]]), k)
      }))
      message("Setup pushed: revision ", revision, " (", paste(parts, collapse = ", "), ")")
    } else {
      message("Already up to date.")
    }
  }

  # Skills need your login; the package list went with the project token
  result$skills <- tryCatch(push_skills(root, force = force, confirm = confirm, dry_run = dry_run),
                            error = function(e) {
                              message("Skills not pushed: ", conditionMessage(e))
                              NULL
                            })
  invisible(result)
}
