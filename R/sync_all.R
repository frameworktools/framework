# Everything that syncs with Framework Cloud, in one call: a project's
# packages, its skills, and its data registry. pull_all() lists every change
# from Cloud, asks once, and applies each part; push_all() does the same in
# the other direction. Each part keeps its own revision and lock file:
# .framework/setup.lock.json for packages, skills.lock.json for skills, and
# data.lock.json for the data registry. pull_skills() / push_skills() and
# pull_data_registry() / push_data_registry() sync one part.
# framework-py: sync_all.py; fw: fw pull / fw push.

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

# --- Parts -----------------------------------------------------------------
#
# Each part's plan is a list: `title` (shown above its lines), `lines`
# (indented details), `warnings` (what a push affects), `state` (shown
# instead of "up to date" when there are no lines), `quiet` (nothing worth
# showing), `pending` (something to apply), and `apply`, a function that
# applies it. A plan that can't be made carries `error` instead.

.sync_plan <- function(label, make) {
  plan <- tryCatch(make(), error = function(e) {
    list(error = sub("\\s*Nothing changed\\.?$", "", conditionMessage(e)), pending = FALSE, quiet = FALSE)
  })
  plan$label <- label
  plan$title <- plan$title %||% label
  plan
}

# The combined change list, by part. `refused` describes a part whose plan failed.
.sync_lines <- function(parts, heading, current, refused) {
  if (all(vapply(parts, function(p) isTRUE(p$quiet), logical(1)))) return(current)
  lines <- heading
  for (part in parts) {
    if (!is.null(part$error)) {
      lines <- c(lines, paste0(part$label, ": ", refused, ". ", part$error))
    } else if (!length(part$lines) && !length(part$warnings)) {
      lines <- c(lines, paste0(part$title, ": ", part$state %||% "up to date"))
    } else {
      lines <- c(lines, paste0(part$title, ":"), part$lines, if (length(part$warnings)) paste0("  ", part$warnings))
    }
  }
  lines
}

# Apply each part in turn. A part that fails doesn't stop the others.
.sync_apply <- function(parts) {
  out <- list(applied = character(), current = character(), failed = list(), values = list())
  for (name in names(parts)) {
    part <- parts[[name]]
    if (!is.null(part$error)) {
      out$failed[[part$label]] <- part$error
      next
    }
    value <- tryCatch(list(ok = part$apply()), error = function(e) list(error = conditionMessage(e)))
    if (!is.null(value$error)) {
      out$failed[[part$label]] <- sub("\\s*Nothing changed\\.?$", "", value$error)
    } else {
      out$values[name] <- list(value$ok)
      if (isTRUE(part$pending)) out$applied <- c(out$applied, part$label) else out$current <- c(out$current, part$label)
    }
  }
  out
}

# Which parts were applied and which weren't, when one failed
.sync_partial <- function(fn, done, outcome) {
  reasons <- vapply(names(outcome$failed), function(n) {
    paste0(n, " (", sub("\\.$", "", outcome$failed[[n]]), ")")
  }, "")
  paste0(fn, " did not finish. ", done, ": ",
         if (length(outcome$applied)) paste(outcome$applied, collapse = ", ") else "nothing",
         ". ", if (length(outcome$current)) paste0("Already in step: ", paste(outcome$current, collapse = ", "), ". "),
         "Not ", tolower(done), ": ", paste(reasons, collapse = "; "), ".")
}

.sync_skill_names <- function(plans) paste(vapply(plans, `[[`, "", "name"), collapse = ", ")

# --- Pull ------------------------------------------------------------------

.setup_skills_line <- function(counts) {
  labels <- c(added = "to add", updated = "to update", replaced = "to replace (backed up)",
              edited = "locally edited (kept)", removed = "no longer in the project's setup (kept)")
  n <- vapply(names(labels), function(k) as.integer(counts[[k]] %||% 0L), integer(1))
  if (!any(n > 0)) return(NULL)
  paste0("  ", paste(n[n > 0], labels[n > 0], collapse = ", "))
}

# Packages: what Cloud's package list adds or changes here
.setup_pull_plan <- function(root, setup, overwrite, connection) {
  revision <- as.character(setup$revision %||% "")
  language <- setup$language %||% "r"
  settle <- function() .setup_lock_write(root, revision, connection$server)
  none <- list(added = character(), changed = character(), differ_kept = character(), kept_local = character())
  if (!identical(language, "r")) {
    return(list(title = "Packages", state = paste0("not managed for ", tools::toTitleCase(language), " projects"),
                quiet = TRUE, pending = FALSE, revision = revision, packages = none, apply = settle))
  }
  local <- .setup_local_packages(root)
  cloud <- list()
  for (row in setup$packages %||% list()) cloud[[row$name]] <- row
  added <- unname(cloud[setdiff(names(cloud), names(local))])
  differ <- Filter(function(n) !.setup_same(local[[n]], cloud[[n]]), intersect(names(cloud), names(local)))
  kept_local <- setdiff(names(local), names(cloud))

  lines <- character()
  if (length(added)) lines <- c(lines, paste0("  Packages to add: ", .setup_names(added)))
  if (length(differ)) {
    details <- paste(vapply(differ, function(n) {
      paste0(n, " (local ", .setup_describe(local[[n]]), ", Cloud ", .setup_describe(cloud[[n]]), ")")
    }, ""), collapse = ", ")
    tail <- if (overwrite) "Cloud's will be used" else "kept; pull_all(overwrite = TRUE) uses Cloud's"
    lines <- c(lines, paste0("  Packages that differ: ", details, " \u2014 ", tail))
  }
  if (length(kept_local)) lines <- c(lines, paste0("  Only in this project (kept): ", paste(kept_local, collapse = ", ")))
  rows <- c(added, if (overwrite) unname(cloud[differ]))
  # Packages only in this project are listed, but don't make it out of step
  list(title = paste0("Packages (revision ", revision, ")"), lines = lines, quiet = !length(added) && !length(differ),
       pending = length(rows) > 0, revision = revision,
       packages = list(added = vapply(added, `[[`, "", "name"),
                       changed = if (overwrite) differ else character(),
                       differ_kept = if (overwrite) character() else differ,
                       kept_local = kept_local),
       apply = function() {
         if (length(rows)) .setup_install(root, rows)
         settle()
       })
}

# Skills: what pull_skills() would add, update, or keep
.skills_pull_plan <- function(root, overwrite) {
  plan <- suppressMessages(pull_skills(root, overwrite = overwrite, dry_run = TRUE))
  lines <- .setup_skills_line(plan$counts)
  for (skill in plan$skills) {
    line <- switch(skill$status,
      edited = paste0("  Kept (locally edited): ", skill$name, " \u2014 pull_all(overwrite = TRUE) replaces it"),
      replaced = paste0("  Replaced (old copy in .framework/skills-backups/): ", skill$name),
      removed = paste0("  No longer in the project's setup (kept): ", skill$name),
      unavailable = paste0("  Not in this version of framework: ", skill$name),
      NULL)
    lines <- c(lines, line)
  }
  if (identical(plan$source, "package")) {
    lines <- c(lines, "  Framework Cloud's skill list not read; using the package skills for this project type")
  }
  if (length(lines)) lines <- c(lines, if (length(plan$notes)) paste0("  ", plan$notes))
  pending <- any(vapply(c("added", "updated", "replaced"), function(k) (plan$counts[[k]] %||% 0L) > 0, logical(1)))
  list(lines = lines, quiet = !length(lines), pending = pending, plan = plan,
       apply = function() {
         if (!pending) return(NULL)
         result <- suppressMessages(pull_skills(root, overwrite = overwrite))
         message("\u2713 ", result$message)
         result
       })
}

#' Pull Everything from Framework Cloud
#'
#' Brings everything that syncs up to date with the project on Framework
#' Cloud, in one call: its packages, its skills, and its data registry. Each
#' part is read with the project token, and the changes are listed together,
#' grouped by part (Packages, Skills, Data registry). Then it asks
#' `Apply these changes? [y/n]` once.
#'
#' Packages: new ones are added to the project's settings and installed
#' (with renv when the project uses it). Local packages are never removed.
#' Skills: missing ones are added and unedited ones updated, as
#' [pull_skills()] does. Data registry: new entries are written into the
#' settings' data section, as [pull_data_registry()] does; data files never
#' move. Local edits win everywhere: a package or entry whose local settings
#' differ, and a locally edited skill, are kept unless `overwrite = TRUE`
#' (edited skills are backed up first).
#'
#' The revisions pulled are kept in `.framework/setup.lock.json` (packages)
#' and `.framework/data.lock.json` (data registry) for [push_all()]. When a
#' part can't be read or applied, the others still are, and the error names
#' which parts were applied and which weren't.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param overwrite Use Cloud's settings for differing packages and data
#'   entries, and replace locally edited skills.
#' @param confirm `TRUE` applies without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run List the changes and write nothing.
#' @return Invisibly, a list: `packages` (`revision`, and `added`,
#'   `changed`, `differ_kept`, and `kept_local`, as names), `skills` (the
#'   [pull_skills()] result: the plan, or what was applied),
#'   `data_registry` (`revision`, and `added`, `changed`, `differ_kept`, and
#'   `kept_local`), `applied` (the parts applied), `failed` (a reason for
#'   each part that wasn't), `dry_run`, and `message`.
#' @seealso [push_all()], [pull_skills()], [pull_data_registry()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' pull_all(dry_run = TRUE)
#' pull_all()
#' }
#' }
pull_all <- function(project_path = ".", overwrite = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  connection <- .setup_connection(root)
  setup <- .setup_request("/api/v1/projects/setup", connection)
  if (identical(setup$language, "python")) {
    stop("This is a Python project on Framework Cloud. Use framework-py's pull_all() or fw pull.", call. = FALSE)
  }

  parts <- list(
    packages = .sync_plan("Packages", function() .setup_pull_plan(root, setup, overwrite, connection)),
    skills = .sync_plan("Skills", function() .skills_pull_plan(root, overwrite)),
    data_registry = .sync_plan("Data registry", function() {
      plan <- .data_registry_pull_plan(root, connection, overwrite, fn = "pull_all()")
      plan$title <- paste0("Data registry (revision ", plan$revision, ")")
      plan$quiet <- !length(plan$entries$added) && !length(c(plan$entries$changed, plan$entries$differ_kept))
      plan$apply <- function() .data_registry_pull_apply(root, plan, connection)
      plan
    })
  )
  lines <- .sync_lines(parts, "Changes from Framework Cloud:", "Project is up to date with Framework Cloud.", "not read")
  for (line in lines) message(line)

  result <- list(
    packages = c(list(revision = parts$packages$revision), parts$packages$packages),
    skills = parts$skills$plan,
    data_registry = c(list(revision = parts$data_registry$revision), parts$data_registry$entries),
    applied = character(),
    failed = Filter(Negate(is.null), lapply(parts, `[[`, "error")),
    dry_run = dry_run, message = paste(lines, collapse = "\n"))
  if (dry_run) return(invisible(result))
  if (any(vapply(parts, function(p) isTRUE(p$pending), logical(1))) &&
      !.fw_confirm(confirm, "Apply these changes?", "pull_all()", dry_run_hint = TRUE)) {
    message("Nothing changed.")
    return(invisible(result))
  }

  outcome <- .sync_apply(parts)
  if (!is.null(outcome$values$skills)) result$skills <- outcome$values$skills
  result$applied <- names(Filter(function(p) p$label %in% outcome$applied, parts))
  result$failed <- outcome$failed
  if (length(outcome$failed)) stop(.sync_partial("pull_all()", "Applied", outcome), call. = FALSE)
  invisible(result)
}

# --- Push ------------------------------------------------------------------

# Packages: what Cloud's dry run says pushing the package list would change
.setup_push_plan <- function(root, connection, setup, remove, force) {
  language <- setup$language %||% "r"
  none <- list(added = list(), changed = list(), removed = list(), kept = list())
  if (!identical(language, "r")) {
    return(list(title = "Packages", state = paste0("not managed for ", tools::toTitleCase(language), " projects"),
                quiet = TRUE, pending = FALSE, revision = setup$revision, changes = none, apply = function() NULL))
  }
  # The base revision for a project that never pulled its package list
  base <- .setup_lock_read(root)$revision %||% setup$revision
  local <- .setup_local_packages(root)
  send <- function(dry) {
    body <- list(base_revision = base, packages = unname(local), remove = remove, force = force, dry_run = dry)
    tryCatch(
      .setup_request("/api/v1/projects/setup/packages", connection, method = "POST", body = body),
      httr2_http_409 = function(e) {
        current <- tryCatch(httr2::resp_body_json(e$resp)$revision, error = function(err) NULL)
        stop("Framework Cloud's package list changed since this project last pulled it (revision ", current %||% "unknown",
             "). Pull first: pull_all(). push_all(force = TRUE) replaces Cloud's changes.", call. = FALSE)
      })
  }

  preview <- send(TRUE)
  changes <- preview$changes %||% list()
  added <- changes$added %||% list(); changed <- changes$changed %||% list()
  removed <- changes$removed %||% list(); kept <- changes$kept %||% list()

  lines <- character()
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
  warnings <- character()
  if (pending) {
    warnings <- paste0("This changes ", .setup_project_name(root), "'s package list on Framework Cloud. ",
                       "New setups, zips, and Update on GitHub will use it.")
    beyond <- setdiff(c(vapply(added, `[[`, "", "name"), vapply(changed, `[[`, "", "name")), names(local))
    if (length(beyond)) {
      warnings <- c(warnings, paste0("Pushing re-resolves the project from its blueprint's latest version, ",
                                     "which can update a project pinned to an older blueprint version."))
    }
    if (force && !identical(base, setup$revision)) {
      warnings <- c(warnings, "Cloud's newer package changes will be replaced by this project's packages.")
    }
  }
  list(lines = lines, warnings = warnings, quiet = !pending, pending = pending, revision = preview$revision,
       changes = list(added = added, changed = changed, removed = removed, kept = kept),
       apply = function() {
         if (!pending) return(NULL)
         reply <- send(FALSE)
         revision <- as.character(reply$revision %||% "")
         .setup_lock_write(root, revision, connection$server)
         done <- reply$changes %||% changes
         parts <- unlist(lapply(c("added", "changed", "removed"), function(k) {
           if (length(done[[k]])) paste(length(done[[k]]), k)
         }))
         message("\u2713 Packages pushed: revision ", revision, if (length(parts)) paste0(" (", paste(parts, collapse = ", "), ")"))
         list(applied = isTRUE(reply$applied), revision = revision)
       })
}

# Skills: the edited tracked skills push_skills() would send. Checking them
# against Cloud needs your login, so a project with edited skills and no
# login can't push them.
.skills_push_plan <- function(root, force) {
  edited <- .skill_push_edited(root)
  if (length(edited) && is.null(.fw_cloud_token(.fw_cloud_url()))) {
    names <- vapply(edited, function(e) basename(e$present[1]), "")
    stop("Not signed in, so edited skills (", paste(names, collapse = ", "), ") can't be pushed. ",
         .fw_login_hint(.fw_cloud_url()), call. = FALSE)
  }
  planned <- .skill_push_plan(root, force)
  plans <- planned$plans
  status <- function(ps, s) Filter(function(p) identical(p$status, s), ps)
  pushes <- status(plans, "push")
  refused <- status(plans, "refused")
  failed <- status(plans, "failed")

  lines <- character()
  if (length(pushes)) lines <- c(lines, paste0("  Skills to push: ", .sync_skill_names(pushes)))
  for (p in refused) {
    lines <- c(lines, paste0("  Pull first: ", p$name, " changed on Cloud since this project pulled it. ",
                             "push_all(force = TRUE) replaces it."))
  }
  for (p in failed) lines <- c(lines, paste0("  Not checked: ", p$name, ": ", p$reason))
  quiet <- !length(lines)
  for (p in planned$untracked) lines <- c(lines, paste0("  Not tracked: ", p$name, " \u2014 use skills_sync() to add it"))
  list(lines = lines, warnings = vapply(pushes, .skill_push_warning, ""), quiet = quiet,
       pending = length(pushes) > 0, plans = c(plans, planned$untracked),
       apply = function() {
         done <- .skill_push_apply(root, plans)
         pushed <- status(done, "pushed")
         if (length(pushed)) message("\u2713 Skills pushed: ", .sync_skill_names(pushed))
         bad <- c(status(done, "refused"), status(done, "failed"))
         if (length(bad)) {
           why <- vapply(bad, function(p) {
             if (identical(p$status, "refused")) paste0(p$name, " changed on Cloud since this project pulled it; push_all(force = TRUE) replaces it")
             else paste0(p$name, ": ", sub("\\.$", "", p$reason))
           }, "")
           stop(if (length(pushed)) paste0("pushed ", .sync_skill_names(pushed), "; "), "not pushed: ",
                paste(why, collapse = "; "), call. = FALSE)
         }
         done
       })
}

#' Push Everything to Framework Cloud
#'
#' Sends everything that syncs to the project on Framework Cloud, in one
#' call: its package list, its locally edited skills, and its data registry.
#' Cloud previews each part first (as a dry run), and the changes are listed
#' together, grouped by part (Packages, Skills, Data registry), with what
#' each push affects: new setups, zips, and Update on GitHub use the package
#' list and data registry, and a skill's new version is used wherever it's
#' attached. Then it asks `Push these changes? [y/n]` once.
#'
#' Packages and data entries only on Cloud stay there unless
#' `remove = TRUE`. When a part changed on Cloud since this project last
#' pulled it (the revisions in `.framework/setup.lock.json` and
#' `.framework/data.lock.json`, and each skill's in
#' `.framework/skills.lock.json`), that part is refused with "Pull first";
#' `force = TRUE` replaces Cloud's newer changes. Edited skills need
#' [cloud_login()]; packages and the data registry go with the project
#' token. Only data definitions are sent, never data files or hashes.
#'
#' When a part can't be pushed, the others still are, and the error names
#' which parts were pushed and which weren't. A push resolves the project
#' again from its blueprint's latest version.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param remove Remove packages and data entries from Cloud that this
#'   project doesn't have.
#' @param force Push even when a part changed on Cloud since the last pull.
#' @param confirm `TRUE` pushes without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run List the changes and send nothing.
#' @return Invisibly, a list: `packages` and `data_registry` (each with
#'   `revision` and Cloud's `changes`: `added`, `changed`, `removed`, and
#'   `kept`), `skills` (each skill's `name`, `status`, and `path`),
#'   `applied` (the parts pushed), `failed` (a reason for each part that
#'   wasn't), `dry_run`, and `message`.
#' @seealso [pull_all()], [push_skills()], [push_data_registry()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' push_all(dry_run = TRUE)
#' push_all()
#' }
#' }
push_all <- function(project_path = ".", remove = FALSE, force = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(remove)
  checkmate::assert_flag(force)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  connection <- .setup_connection(root)
  setup <- .setup_request("/api/v1/projects/setup", connection)
  if (identical(setup$language, "python")) {
    stop("This is a Python project on Framework Cloud. Use framework-py's push_all() or fw push.", call. = FALSE)
  }

  parts <- list(
    packages = .sync_plan("Packages", function() .setup_push_plan(root, connection, setup, remove, force)),
    skills = .sync_plan("Skills", function() .skills_push_plan(root, force)),
    data_registry = .sync_plan("Data registry", function() {
      plan <- .data_registry_push_plan(root, connection, remove, force, "pull_all()", "push_all(force = TRUE)")
      plan$apply <- function() if (plan$pending) .data_registry_push_apply(root, plan, connection)
      plan
    })
  )
  lines <- .sync_lines(parts, "Changes for Framework Cloud:", "Framework Cloud already matches this project.", "can't push")
  for (line in lines) message(line)

  result <- list(
    packages = list(revision = parts$packages$revision, changes = parts$packages$changes),
    skills = lapply(parts$skills$plans, function(p) list(name = p$name, status = p$status, path = p$path)),
    data_registry = list(revision = parts$data_registry$revision, changes = parts$data_registry$changes),
    applied = character(),
    failed = Filter(Negate(is.null), lapply(parts, `[[`, "error")),
    dry_run = dry_run, message = paste(lines, collapse = "\n"))
  if (dry_run) return(invisible(result))
  if (any(vapply(parts, function(p) isTRUE(p$pending), logical(1))) &&
      !.fw_confirm(confirm, "Push these changes?", "push_all()", dry_run_hint = TRUE)) {
    message("Nothing pushed.")
    return(invisible(result))
  }

  outcome <- .sync_apply(parts)
  for (name in c("packages", "data_registry")) {
    if (!is.null(outcome$values[[name]]$revision)) result[[name]]$revision <- outcome$values[[name]]$revision
  }
  if (!is.null(outcome$values$skills)) {
    result$skills <- lapply(outcome$values$skills, function(p) list(name = p$name, status = p$status, path = p$path))
  }
  result$applied <- names(Filter(function(p) p$label %in% outcome$applied, parts))
  result$failed <- outcome$failed
  if (length(outcome$failed)) stop(.sync_partial("push_all()", "Pushed", outcome), call. = FALSE)
  invisible(result)
}
