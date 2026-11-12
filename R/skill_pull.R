# A project's skills, kept in step with its setup on Framework Cloud.
# pull_skills() installs and updates the skills the Cloud setup lists;
# push_skills() sends locally edited skills back. Both build on the
# per-skill machinery in skill_sync.R. framework-py: skill_pull.py; fw:
# fw skills pull / fw skills push. pull_all() and push_all() include them.

.skill_pull_statuses <- c("added", "updated", "current", "edited", "replaced", "removed", "unavailable")
# Which status names a skill when its copies in several folders differ
.skill_pull_precedence <- c("edited", "replaced", "updated", "added", "unavailable", "current")

# Mockable console helpers
.fw_interactive <- function() rlang::is_interactive()
.fw_readline <- function(prompt) readline(prompt)

.skill_pull_root <- function(project_path) {
  checkmate::assert_string(project_path, min.chars = 1)
  # A mistyped path must not create a new folder full of skills
  if (!dir.exists(project_path) || !.has_settings_file(project_path)) {
    stop("Not a Framework project (no settings.yml): ", project_path, call. = FALSE)
  }
  normalizePath(project_path, mustWork = TRUE)
}

.skill_pull_settings <- function(root) {
  tryCatch(settings_read(file.path(root, "settings.yml")), error = function(e) list())
}

# The assistants' skills folders, then .agents/skills and .claude/skills if present
.skill_pull_dirs <- function(root, settings) {
  table <- .ai_assistant_table()
  chosen <- settings$ai$assistants
  chosen <- if (is.list(chosen) && !is.null(names(chosen)) && all(nzchar(names(chosen)))) {
    names(Filter(isTRUE, chosen))
  } else {
    unlist(chosen)
  }
  assistants <- intersect(chosen, names(table))
  dirs <- if (length(assistants) == 0) ".agents/skills" else unique(vapply(table[assistants], `[[`, "", "skills_dir"))
  for (dir in c(".agents/skills", ".claude/skills")) {
    if (dir.exists(file.path(root, dir))) dirs <- c(dirs, dir)
  }
  unique(dirs)
}

.skill_pull_folders <- function(root, dir) {
  path <- file.path(root, dir)
  if (!dir.exists(path)) return(character())
  names <- list.dirs(path, full.names = FALSE, recursive = FALSE)
  sort(names[!startsWith(names, ".")])
}

# The package skills for the project's type, for offline use
.skill_pull_package_skills <- function(settings) {
  type <- if (.fw_settings_sensitive(settings)) "project_sensitive" else settings$project_type %||% "project"
  skills <- list()
  for (name in .ai_skills_for_type(type)) skills[[name]] <- list(package = TRUE)
  skills
}

# The skills the project's current Cloud setup lists, merged over the
# package defaults. Errors when the setup can't be read.
.skill_pull_cloud_skills <- function(root, notes) {
  token <- .fw_project_token(root)
  if (is.null(token)) stop("no project token", call. = FALSE)
  server <- .fw_project_cloud_url(root)
  envelope <- .fw_api("/api/v1/projects/pull", token = token, url = server)
  if (!is.list(envelope) || !identical(as.integer(envelope$spec_version %||% NA), 1L)) {
    stop("the server sent a project setup this version of framework can't read", call. = FALSE)
  }
  spec <- spec_resolve(envelope$layers %||% list(), name = envelope$name %||% "project", check = FALSE)
  skills <- Filter(is.list, spec$skills %||% list())
  .skill_pull_latest(skills, server, notes)
}

# Newer Cloud versions of synced skills. Reading them needs your login; a
# project token can't. Without it, the versions in the setup are used.
.skill_pull_latest <- function(skills, server, notes) {
  synced <- names(Filter(function(e) !is.null(e$sync), skills))
  if (length(synced) == 0) return(list(skills = skills, notes = notes))
  token <- .fw_cloud_token(server)
  if (is.null(token)) {
    notes <- c(notes, paste0("Not signed in, so Cloud skills use the versions in the project's setup. ",
                             "framework::cloud_login() lets pull_skills() get their latest versions."))
    return(list(skills = skills, notes = notes))
  }
  for (name in synced) {
    entry <- skills[[name]]; source <- entry$sync
    remote <- tryCatch({
      r <- .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(source$skill_id, reserved = TRUE),
                          "?variant=", source$variant), token, url = server)
      if (!identical(.skill_hash(r$bundle), r$hash)) stop("Cloud skill verification failed", call. = FALSE)
      r
    }, error = function(e) {
      notes <<- c(notes, paste0("Latest version of ", name, " not checked (", conditionMessage(e), "); using the setup's."))
      NULL
    })
    if (!is.null(remote) && as.integer(remote$version) > as.integer(source$version)) {
      entry$bundle <- remote$bundle
      entry$sync$version <- remote$version; entry$sync$hash <- remote$hash
      skills[[name]] <- entry
    }
  }
  list(skills = skills, notes = notes)
}

.skill_inline_bundle <- function(entry) {
  files <- c(list(SKILL.md = entry$content), entry$files %||% list())
  lapply(names(files), function(path) {
    list(path = path, content = jsonlite::base64_enc(charToRaw(enc2utf8(files[[path]]))), executable = FALSE)
  })
}

.skill_pull_shipped <- function(name) {
  path <- system.file("templates", "skills", name, package = "framework")
  if (nzchar(path) && file.exists(file.path(path, "SKILL.md"))) path else ""
}

# What pulling one skill into one folder does
.skill_pull_plan <- function(root, name, entry, relative, overwrite) {
  target <- .skill_path(root, relative)
  current <- if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL
  if (isTRUE(entry$package)) {
    source <- .skill_pull_shipped(name)
    if (!nzchar(source)) return("unavailable")
    status <- .skill_package_status(source, root, relative, name)
    status <- switch(status, create = "added", update = "updated", current = "current", "edited")
  } else {
    files <- .skill_validate(if (!is.null(entry$sync)) entry$bundle else .skill_inline_bundle(entry))
    fresh <- .skill_hash(files)
    if (!is.null(entry$sync) && !identical(fresh, entry$sync$hash)) {
      stop("Cloud skill verification failed: ", name, call. = FALSE)
    }
    state <- .skill_load(root)
    keys <- names(Filter(function(e) relative %in% unlist(e$paths), state$skills))
    tracked <- if (length(keys)) state$skills[[keys[1]]] else list()
    clean <- c(tracked$hash, entry$setup_hash)
    # The project already holds a newer version than the setup names, as after
    # push_skills(); without your login the setup's older one would replace it
    newer <- !is.null(entry$sync) && identical(tracked$skill_id, entry$sync$skill_id) &&
      identical(current, tracked$hash) && isTRUE(as.integer(tracked$version %||% 0L) > as.integer(entry$sync$version %||% 0L))
    status <- if (is.null(current)) "added"
      else if (identical(current, fresh) || newer) "current"
      else if (!is.null(entry$sync) && current %in% clean) "updated"
      else "edited"
  }
  if (identical(status, "edited") && isTRUE(overwrite)) "replaced" else status
}

.skill_pull_apply <- function(root, name, entry, relative, status) {
  force <- identical(status, "replaced")
  if (isTRUE(entry$package)) {
    .skill_package_install(.skill_pull_shipped(name), root, relative, name, force = force, lock = FALSE)
  } else if (!is.null(entry$sync)) {
    # Current with other files: a newer version than the setup's, kept as it is
    target <- .skill_path(root, relative)
    if (identical(status, "current") && !identical(.skill_hash(.skill_scan(target)), entry$sync$hash)) return(invisible(FALSE))
    .skill_cloud_install(root, relative, entry, force = force, clean = entry$setup_hash, lock = FALSE)
  } else if (!identical(status, "current")) {
    target <- .skill_path(root, relative)
    .skill_install(root, relative, .skill_inline_bundle(entry),
                   if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL)
  }
}

.skill_pull_summary <- function(counts, dry_run) {
  labels <- c(added = "added", updated = "updated", current = "up to date",
              edited = "locally edited (kept)", replaced = "replaced (backed up)",
              removed = "no longer in the project's setup",
              unavailable = "not in this version of framework")
  parts <- paste(counts[names(labels)], labels)[counts[names(labels)] > 0]
  prefix <- if (dry_run) "Skills (dry run, nothing written): " else "Skills: "
  paste0(prefix, if (length(parts)) paste(parts, collapse = ", ") else "none")
}

# Rewrite the context file's Skills section; only a file with a "## Skills"
# heading changes
.skill_pull_refresh_agents <- function(root, settings, skills, skills_dir) {
  file <- settings$ai$canonical_file %||% "AGENTS.md"
  path <- file.path(root, file)
  if (!file.exists(path)) return(invisible(FALSE))
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  match <- regexpr("(?sm)^## Skills[^\n]*\n.*?(?=\n+## |\n*\\z)", text, perl = TRUE)
  if (match == -1) return(invisible(FALSE))
  section <- paste0("## Skills\n\n", .generate_skills_section(skills = skills, skills_dir = skills_dir, project_dir = root))
  updated <- paste0(substring(text, 1, match - 1), section, substring(text, match + attr(match, "match.length")))
  if (identical(updated, text)) return(invisible(FALSE))
  writeLines(updated, path, useBytes = TRUE)
  invisible(TRUE)
}

#' Pull a Project's Skills from Framework Cloud
#'
#' Brings a project's skills up to date with its setup on Framework Cloud.
#' The project's current skill list comes from Framework Cloud with its
#' project token (`GET /api/v1/projects/pull`), as edited there with Edit
#' project. Missing skills are added. Unedited skills are updated to their
#' latest versions: Framework's from this package, and Cloud skills from
#' Cloud. Their latest Cloud versions need [cloud_login()]; without it, the
#' versions in the project's setup are used.
#'
#' Locally edited skills are kept and listed. `overwrite = TRUE` replaces
#' them too, backing the old copies up to `.framework/skills-backups/`.
#' Skills no longer in the setup are never deleted, only listed. The Skills
#' table in AGENTS.md is refreshed.
#'
#' Offline, or without a project token, the package skills for the project's
#' type are used instead, and the message says so.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param overwrite Replace locally edited skills too, after backing them up.
#' @param dry_run Report what would change and write nothing.
#' @return Invisibly, a list: `source` ("cloud" or "package"), `dry_run`,
#'   `skills` (each a list with `name`, `status`, and `paths`), `counts` by
#'   status (added, updated, current, edited, replaced, removed,
#'   unavailable), `message` (the summary line), and `notes`.
#' @seealso [push_skills()] sends edited skills back; [skills_sync()] syncs
#'   one skill.
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # See what would change, then pull
#' pull_skills(dry_run = TRUE)
#' pull_skills()
#' }
#' }
pull_skills <- function(project_path = ".", overwrite = FALSE, dry_run = FALSE) {
  checkmate::assert_flag(overwrite)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  settings <- .skill_pull_settings(root)
  dirs <- .skill_pull_dirs(root, settings)
  notes <- character()
  fetched <- tryCatch(.skill_pull_cloud_skills(root, notes), error = function(e) e)
  if (inherits(fetched, "error")) {
    reason <- sub("\\.$", "", conditionMessage(fetched))
    message("Framework Cloud not reached (", reason, "); using the package skills for this project type.")
    wanted <- .skill_pull_package_skills(settings)
    source <- "package"
  } else {
    wanted <- fetched$skills; notes <- fetched$notes
    source <- "cloud"
  }
  # A Cloud skill's version in the setup counts as unedited when a newer one replaces it
  for (name in names(wanted)) {
    if (!is.null(wanted[[name]]$sync)) wanted[[name]]$setup_hash <- wanted[[name]]$setup_hash %||% wanted[[name]]$sync$hash
  }

  if (!dry_run) {
    lock <- .skill_acquire(root)
    on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  }
  skills <- list()
  for (name in names(wanted)) {
    entry <- wanted[[name]]; found <- character()
    for (dir in dirs) {
      relative <- file.path(dir, name)
      status <- .skill_pull_plan(root, name, entry, relative, overwrite)
      if (!dry_run && status %in% c("added", "updated", "replaced", "current")) {
        # A current one is recorded in the lock
        .skill_pull_apply(root, name, entry, relative, status)
      }
      found[[relative]] <- status
    }
    status <- .skill_pull_precedence[min(match(found, .skill_pull_precedence))]
    skills[[length(skills) + 1L]] <- list(name = name, status = status, paths = names(found))
  }
  if (identical(source, "cloud")) {
    others <- list()
    for (dir in dirs) for (name in setdiff(.skill_pull_folders(root, dir), names(wanted))) {
      others[[name]] <- c(others[[name]], file.path(dir, name))
    }
    for (name in sort(names(others))) {
      skills[[length(skills) + 1L]] <- list(name = name, status = "removed", paths = others[[name]])
    }
  }

  if (!dry_run && length(dirs)) {
    present <- .skill_pull_folders(root, dirs[1])
    listed <- c(intersect(names(wanted), present), setdiff(present, names(wanted)))
    .skill_pull_refresh_agents(root, settings, listed, dirs[1])
  }

  statuses <- vapply(skills, `[[`, "", "status")
  counts <- vapply(.skill_pull_statuses, function(s) sum(statuses == s), integer(1))
  summary <- .skill_pull_summary(counts, dry_run)
  message(summary)
  for (skill in skills) {
    line <- switch(skill$status,
      edited = paste0("  Kept (locally edited): ", skill$name, " \u2014 pull_skills(overwrite = TRUE) replaces it"),
      replaced = paste0("  Replaced (old copy in .framework/skills-backups/): ", skill$name),
      removed = paste0("  No longer in the project's setup (kept): ", skill$name),
      unavailable = paste0("  Not in this version of framework: ", skill$name),
      NULL)
    if (!is.null(line)) message(line)
  }
  for (note in notes) message(note)
  invisible(list(source = source, dry_run = dry_run, skills = skills, counts = as.list(counts),
                 message = summary, notes = notes))
}

# Tracked skills whose files changed since the last pull, each with its paths.
# Reads only the project; checking them against Cloud needs your login.
.skill_push_edited <- function(root) {
  edited <- list()
  for (entry in .skill_load(root)$skills) {
    paths <- Filter(function(p) dir.exists(.skill_path(root, p)), unlist(entry$paths))
    if (!length(paths)) next
    hashes <- vapply(paths, function(p) .skill_hash(.skill_scan(.skill_path(root, p))), "")
    if (all(hashes == (entry$hash %||% ""))) next
    entry$present <- paths
    edited[[length(edited) + 1L]] <- entry
  }
  edited
}

# Locally edited tracked skills and what pushing each would do, and untracked folders
.skill_push_plan <- function(root, force) {
  state <- .skill_load(root)
  tracked <- unlist(lapply(state$skills, function(e) unlist(e$paths)))
  plans <- list()
  for (entry in .skill_push_edited(root)) {
    paths <- entry$present
    name <- basename(paths[1])
    builtin <- is.null(entry$skill_id) || startsWith(entry$skill_id, "framework:")
    action <- tryCatch(skills_sync(paths[1], root, direction = "status")$action, error = function(e) e)
    if (inherits(action, "error")) {
      plans[[length(plans) + 1L]] <- list(name = name, path = paths[1], status = "failed", reason = conditionMessage(action))
    } else if (identical(action, "push") || (identical(action, "conflict") && force)) {
      plans[[length(plans) + 1L]] <- list(name = name, path = paths[1], status = "push",
                                          builtin = builtin, forced = identical(action, "conflict"))
    } else if (identical(action, "conflict")) {
      plans[[length(plans) + 1L]] <- list(name = name, path = paths[1], status = "refused")
    }
  }
  untracked <- list()
  for (dir in .skill_pull_dirs(root, .skill_pull_settings(root))) {
    for (name in .skill_pull_folders(root, dir)) {
      if (!file.path(dir, name) %in% tracked) {
        untracked[[length(untracked) + 1L]] <- list(name = name, path = file.path(dir, name), status = "untracked")
      }
    }
  }
  list(plans = plans, untracked = untracked)
}

# Push each planned skill; each plan's status becomes pushed, refused, or failed
.skill_push_apply <- function(root, plans) {
  for (i in seq_along(plans)) {
    if (!identical(plans[[i]]$status, "push")) next
    result <- tryCatch(
      skills_sync(plans[[i]]$path, root, direction = "push", resolve = if (isTRUE(plans[[i]]$forced)) "local"),
      error = function(e) e)
    if (inherits(result, "error")) {
      plans[[i]]$status <- "failed"; plans[[i]]$reason <- conditionMessage(result)
    } else if (identical(result$action, "push")) {
      plans[[i]]$status <- "pushed"; plans[[i]]$version <- result$version
    } else {
      plans[[i]]$status <- "refused"
    }
  }
  plans
}

.skill_push_warning <- function(plan) {
  if (isTRUE(plan$builtin)) {
    paste0("This saves ", plan$name, " as your own skill; the built-in Framework skill stays as it is.")
  } else if (isTRUE(plan$forced)) {
    paste0("Cloud has a newer version of ", plan$name, " than this project pulled. Pushing replaces it ",
           "as the latest version; the Cloud changes stay in its history.")
  } else {
    paste0("This replaces the current version of ", plan$name, ", used wherever it's attached.")
  }
}

# Whether to go ahead: TRUE/FALSE as given, else ask in a console
.fw_confirm <- function(confirm, question, fn, dry_run_hint = FALSE) {
  if (!is.null(confirm)) return(isTRUE(confirm))
  if (!.fw_interactive()) {
    stop(fn, " asks before changing anything. Without a console, pass confirm = TRUE",
         if (dry_run_hint) ", or dry_run = TRUE to only see the changes", ".", call. = FALSE)
  }
  tolower(trimws(.fw_readline(paste0(question, " [y/n] ")))) %in% c("y", "yes")
}

#' Push Locally Edited Skills to Framework Cloud
#'
#' Sends locally edited skills to Framework Cloud as new versions of your
#' own skills. Each skill tracked in `.framework/skills.lock.json` whose files
#' changed since the last pull goes up through [skills_sync()]. A skill that
#' changed on Cloud since then is refused with "Pull first"; `force = TRUE`
#' pushes it anyway, as the latest version. A built-in Framework skill is
#' never changed: an edited one is saved as your own copy. Skills not
#' tracked are listed; [skills_sync()] adds one. Needs [cloud_login()].
#'
#' Before pushing, a warning names what each new version affects, then asks
#' to continue. Without a console, pass `confirm = TRUE`.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param force Push skills that changed on Cloud since the last pull.
#' @param confirm `TRUE` pushes without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run Report what would be pushed and send nothing.
#' @return Invisibly, a list: `dry_run`, `skills` (each with `name`,
#'   `status`, and `paths`; status is pushed, refused, untracked, cancelled,
#'   or failed), `counts` by status, and `message` (the summary line).
#' @seealso [pull_skills()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' push_skills(dry_run = TRUE)
#' push_skills()
#' }
#' }
push_skills <- function(project_path = ".", force = FALSE, confirm = NULL, dry_run = FALSE) {
  checkmate::assert_flag(force)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  root <- .skill_pull_root(project_path)
  .fw_require_token(.fw_cloud_url())
  planned <- .skill_push_plan(root, force)
  plans <- planned$plans
  pushes <- which(vapply(plans, function(p) identical(p$status, "push"), logical(1)))

  for (i in pushes) message(.skill_push_warning(plans[[i]]))
  if (length(pushes) && !dry_run) {
    if (!.fw_confirm(confirm, "Continue?", "push_skills()")) {
      for (i in pushes) plans[[i]]$status <- "cancelled"
    } else {
      plans <- .skill_push_apply(root, plans)
    }
  }

  skills <- lapply(c(plans, planned$untracked), function(p) {
    status <- if (dry_run && identical(p$status, "push")) "pushed" else p$status
    c(list(name = p$name, status = status, paths = p$path), if (!is.null(p$reason)) list(reason = p$reason))
  })
  keys <- c("pushed", "refused", "untracked", "cancelled", "failed")
  statuses <- vapply(skills, `[[`, "", "status")
  counts <- vapply(keys, function(k) sum(statuses == k), integer(1))
  labels <- c(pushed = if (dry_run) "to push" else "pushed", refused = "refused (pull first)",
              untracked = "not tracked", cancelled = "cancelled", failed = "failed")
  parts <- paste(counts, labels[keys])[counts > 0]
  prefix <- if (dry_run) "Skills (dry run, nothing sent): " else "Skills pushed: "
  summary <- paste0(prefix, if (length(parts)) paste(parts, collapse = ", ") else "nothing to push")
  message(summary)
  for (skill in skills) {
    line <- switch(skill$status,
      refused = paste0("  Pull first: ", skill$name, " changed on Cloud since this project pulled it. ",
                       "push_skills(force = TRUE) replaces it."),
      untracked = paste0("  Not tracked: ", skill$name, " \u2014 use skills_sync() to add it"),
      failed = paste0("  Failed: ", skill$name, ": ", skill$reason),
      NULL)
    if (!is.null(line)) message(line)
  }
  invisible(list(dry_run = dry_run, skills = skills, counts = as.list(counts), message = summary))
}
