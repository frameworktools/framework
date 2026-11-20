# A project's skills, kept in step with its setup on Framework Cloud.
# pull_skills() installs and updates the skills the Cloud setup lists;
# push_skills() sends locally edited skills back. Both gather their inputs,
# call the planner (skill_plan.R), and apply its steps (skill_engine.R).
# framework-py: skill_pull.py; fw: fw skills pull / fw skills push.
# pull_all() and push_all() include them.

# The shared skill vocabulary (framework-py and fw use the same names)
.skill_pull_statuses <- c("added", "restored", "updated", "current", "edited", "replaced", "diverged", "missing",
                          "removed", "unavailable", "failed", "kept", "untracked")

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
  tryCatch(settings_read(.setup_settings_file(root)), error = function(e) list())
}

# The enabled assistants' skills folders (.agents/skills when none is set)
.skill_pull_dirs <- function(root, settings) {
  table <- .ai_assistant_table()
  chosen <- settings$ai$assistants
  chosen <- if (is.list(chosen) && !is.null(names(chosen)) && all(nzchar(names(chosen)))) {
    names(Filter(isTRUE, chosen))
  } else {
    unlist(chosen)
  }
  assistants <- intersect(chosen, names(table))
  # Only the enabled assistants' folders. Copies the lock tracks elsewhere
  # are planned through their entries; anything else at a disabled
  # assistant's path is never probed.
  if (length(assistants) == 0) ".agents/skills" else unique(vapply(table[assistants], `[[`, "", "skills_dir"))
}

# The package skill names for the project's type, for offline use
.skill_pull_package_names <- function(settings) {
  type <- if (.fw_settings_sensitive(settings)) "project_sensitive" else settings$project_type %||% "project"
  .ai_skills_for_type(type)
}

# The skills the project's current Cloud setup lists, merged over the
# package defaults. Errors when the setup can't be read.
.skill_pull_cloud_skills <- function(root, notes) {
  token <- .fw_project_token(root)
  if (is.null(token)) stop(errorCondition("no project token", class = "fw_no_project_token", call = NULL))
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
      # The setup's version stays known: an unedited copy of it is updated
      entry$setup_hash <- entry$setup_hash %||% source$hash
      entry$bundle <- remote$bundle
      entry$sync$version <- remote$version; entry$sync$hash <- remote$hash
      skills[[name]] <- entry
    }
  }
  list(skills = skills, notes = notes)
}

# What a pull offers: the Cloud setup's skills, or, when Cloud can't be
# reached or the project has no token, the package skills for the project's
# type. A refused token, an unknown server, or a setup this version can't
# read stops with an error, so package defaults never hide the failure.
.skill_pull_offer <- function(root, settings) {
  fetched <- tryCatch(
    .skill_pull_cloud_skills(root, character()),
    fw_no_project_token = function(e) e,
    httr2_failure = function(e) e,
    curl_error = function(e) e,
    httr2_http_401 = function(e) .setup_refused(e),
    httr2_http_403 = function(e) .setup_refused(e)
  )
  if (inherits(fetched, "error")) {
    reason <- sub("\\.$", "", conditionMessage(fetched))
    message("Framework Cloud not reached (", reason, "); using the package skills for this project type.")
    names <- .skill_pull_package_names(settings)
    return(list(source = "package", offline = TRUE, notes = character(),
                skills = lapply(names, .skill_source_package)))
  }
  skills <- lapply(names(fetched$skills), function(n) .skill_source_setup(n, fetched$skills[[n]]))
  list(source = "cloud", offline = FALSE, notes = fetched$notes, skills = skills)
}

# Your own skill's latest version from Cloud, by its own identity, as a
# source, or NULL. Reading it needs your login.
.skill_fetch_identity <- function(key, entry, name) {
  server <- entry$identity$server
  token <- tryCatch(.fw_cloud_token(server), error = function(e) NULL)
  if (is.null(token)) return(NULL)
  tryCatch({
    r <- .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(entry$identity$skill_id, reserved = TRUE),
                        "?variant=", entry$identity$variant), token, url = server)
    if (!identical(.skill_hash(r$bundle), r$hash)) stop("Cloud skill verification failed", call. = FALSE)
    .skill_source(name, entry$identity, "cloud", .skill_validate(r$bundle), known = r$hash,
                  version = r$version, server = server)
  }, error = function(e) NULL)
}

# Sources for lock entries the setup doesn't name, fetched by their own
# identity: Cloud skills none of whose copies is on disk
.skill_pull_by_identity <- function(lock, disk, offer) {
  named <- vapply(offer$skills, function(s) .skill_key(s$identity), "")
  out <- list()
  if (isTRUE(offer$offline)) return(out)
  for (key in setdiff(names(lock$skills), named)) {
    E <- lock$skills[[key]]
    paths <- names(E$copies)
    if (!identical(E$identity$kind, "cloud") || !length(paths)) next
    hashes <- vapply(paths, disk$hash, "")
    if (!all(hashes == .skill_absent) || !any(vapply(dirname(paths), disk$folder_exists, logical(1)))) next
    source <- .skill_fetch_identity(key, E, basename(paths[1]))
    if (!is.null(source)) out[[key]] <- source
  }
  out
}

# Plan and, unless dry_run, apply a pull: the same machinery for
# pull_skills(), pull_all(), upgrade(), and project creation.
# opt: command, dirs, overwrite, dry_run, scope. Returns the plan's steps as
# applied, the rows, the lock, and the disk.
.skill_sync_run <- function(root, offer, opt, fn = "pull_skills()") {
  if (!isTRUE(opt$dry_run)) {
    held <- .skill_acquire(root)
    on.exit(unlink(held, recursive = TRUE), add = TRUE)
  }
  lock <- .skill_load(root)
  disk <- .skill_disk(root)
  opt$source <- offer$source
  opt$offline <- isTRUE(offer$offline)
  if (is.null(offer$by_identity)) offer$by_identity <- .skill_pull_by_identity(lock, disk, offer)
  plan <- .skill_plan_pull(disk, lock, offer, opt)
  steps <- if (isTRUE(opt$dry_run)) plan$steps else .skill_apply(root, plan, disk, lock, fn)$steps
  sources <- list()
  for (s in offer$skills) sources[[.skill_key(s$identity)]] <- s
  list(steps = steps, rows = .skill_rows(steps, opt$command), lock = lock, disk = disk, sources = sources)
}

# The detail line for one pulled skill, or NULL
.skill_pull_line <- function(skill) {
  labels <- c(edited = "Edited", kept = "Kept", untracked = "Untracked", replaced = "Replaced", restored = "Restored",
              diverged = "Diverged", missing = "Missing", removed = "Removed", unavailable = "Unavailable",
              failed = "Failed", current = "Current")
  if (!skill$status %in% names(labels) || is.null(skill$reason)) return(NULL)
  paste0("  ", labels[[skill$status]], ": ", skill$name, " — ", skill$reason)
}

.skill_pull_summary <- function(counts, dry_run) {
  labels <- c(added = "added", restored = "restored", updated = "updated", current = "up to date",
              edited = "locally edited (kept)", replaced = "replaced (backed up)",
              diverged = "copies differ (not pulled)", kept = "kept (a different skill)",
              untracked = "untracked (left alone)", removed = "no longer in the project's setup",
              missing = "missing (every copy gone)", unavailable = "not pulled (unavailable)", failed = "failed")
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
#' `.framework/skills.lock.json` records what each copy held when a sync
#' last wrote it. A copy that still matches its record is unedited and is
#' updated. Any other copy is locally edited, including one reverted by hand
#' to an older version, and is kept and listed. `overwrite = TRUE` replaces
#' edited copies too, backing the old copies up to
#' `.framework/skills-backups/`. Skills no longer in the setup are never
#' deleted, only listed. The Skills table in AGENTS.md is refreshed.
#'
#' A skill is judged by its identity (a Framework built-in, a Cloud skill
#' and its variant, or setup text), never by its folder name. A folder that
#' tracks another identity is kept, and the row gives the [skills_move()]
#' call that switches it. A skill's copies (in `.claude/skills/` and
#' `.agents/skills/`) are judged together: when an edited copy differs from
#' another copy, or is missing beside it, the skill is diverged, nothing is
#' written, and the row gives the [skills_copy()] call that reconciles it.
#' `overwrite` never chooses between two edits. A missing copy next to
#' unedited ones is restored. No skill moves to an older version: when the
#' project holds a newer version than the setup names (after
#' [push_skills()]), its copies are kept, and a new assistant folder gets
#' the project's copy.
#'
#' Pull uses the enabled assistants' skills folders (`.agents/skills` when
#' none is set) and the paths `.framework/skills.lock.json` tracks. Other
#' folders, such as a disabled assistant's, are not read.
#'
#' Offline, or without a project token, the package skills for the project's
#' type are used instead, and the message says so. Skills tracked on Cloud
#' are then left as they are and listed as unavailable.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param overwrite Replace locally edited skills too, after backing them up.
#' @param dry_run Report what would change and write nothing.
#' @return Invisibly, a list: `source` ("cloud" or "package"), `dry_run`,
#'   `skills` (each a list with `name`, `status`, and `paths`), `counts` by
#'   status, `message` (the summary line), `notes`, and `steps` (one per
#'   copy, with its `action`). Statuses: added, restored (a deleted tracked
#'   copy put back), updated, current, edited (local edits kept), replaced
#'   (local edits backed up and overwritten), diverged (copies differ, or
#'   one is missing beside an edited one; nothing written), missing (every
#'   tracked copy gone and not restorable, or a copy's folder gone), removed
#'   (no longer in the setup), unavailable (Cloud not reached; left alone),
#'   failed (a copy couldn't be read), kept (a folder tracking a different
#'   skill), and untracked (a copy not in the lock, left alone). Every row
#'   that isn't a plain success has a `reason`, one plain sentence, a
#'   `reason_code`, and, when there is one, a `hint` with the exact command
#'   to run and its `hint_key` and `hint_args`.
#' @seealso [push_skills()] sends edited skills back; [skills_sync()] syncs
#'   one skill; [skills_copy()] copies an edited skill to the other
#'   assistant folders; [skills_move()] moves a copy or switches its skill.
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
  .skill_pull_command(project_path, overwrite, dry_run, fn = "pull_skills")
}

.skill_pull_command <- function(project_path, overwrite, dry_run, fn) {
  root <- .skill_pull_root(project_path)
  settings <- .skill_pull_settings(root)
  dirs <- .skill_pull_dirs(root, settings)
  # A lock this version can't read stops the pull before any request
  .skill_load(root)
  offer <- .skill_pull_offer(root, settings)
  run <- .skill_sync_run(root, offer, list(command = "pull", dirs = dirs, overwrite = overwrite, dry_run = dry_run,
                                           scope = "all"), fn = paste0(fn, "()"))
  skills <- .skill_rows_out(run$rows, list(fn = fn, lock = run$lock, disk = run$disk, sources = run$sources))

  if (!dry_run && length(dirs)) {
    present <- .skill_pull_folders(root, dirs[1])
    wanted <- vapply(offer$skills, `[[`, "", "name")
    listed <- c(intersect(wanted, present), setdiff(present, wanted))
    .skill_pull_refresh_agents(root, settings, listed, dirs[1])
  }

  statuses <- vapply(skills, `[[`, "", "status")
  counts <- vapply(.skill_pull_statuses, function(s) sum(statuses == s), integer(1))
  summary <- .skill_pull_summary(counts, dry_run)
  message(summary)
  for (skill in skills) {
    line <- .skill_pull_line(skill)
    if (!is.null(line)) message(line)
  }
  for (note in offer$notes) message(note)
  invisible(list(source = offer$source, dry_run = dry_run, skills = skills, counts = as.list(counts),
                 message = summary, notes = offer$notes, steps = run$steps))
}

# --- Push ---------------------------------------------------------------------------

# Cloud's head of a lock entry's skill (`version`, `hash`, `skill_id`,
# `system`), or NULL when Cloud has no such skill (a built-in it never
# published)
.skill_push_remote <- function(key, entry, server, token) {
  id <- entry$identity
  if (!id$kind %in% c("cloud", "builtin")) return(NULL)
  path <- paste0("/api/v1/skills/sync/", utils::URLencode(id$skill_id, reserved = TRUE), "?variant=", id$variant)
  # A built-in from the package: Cloud's copy of the version the project
  # holds, or 409 when Cloud never published it
  if (identical(id$kind, "builtin") && identical(entry$base$channel, "package")) path <- paste0(path, "&hash=", entry$base$hash)
  remote <- tryCatch(.fw_api(path, token, url = server), httr2_http_404 = function(e) NULL,
                     httr2_http_409 = function(e) NULL)
  if (is.null(remote)) return(NULL)
  list(version = remote$version, hash = remote$hash, skill_id = remote$skill_id %||% id$skill_id,
       system = isTRUE(remote$system))
}

# POST one push; returns Cloud's reply (skill_id, version, hash, server)
.skill_push_post <- function(body, server, token) {
  .fw_api("/api/v1/skills/sync", token, method = "POST", url = server, body = body)
}

# Whether any copy of an entry differs from its record (a push candidate)
.skill_push_changed <- function(entry, disk) {
  any(vapply(names(entry$copies), function(p) {
    h <- disk$hash(p)
    !identical(h, .skill_absent) && !identical(h, unname(entry$copies[p]))
  }, logical(1)))
}

# The skills with a copy that differs from its record: what a push would
# check against Cloud
.skill_push_edited_names <- function(root) {
  lock <- .skill_load(root)
  disk <- .skill_disk(root)
  unname(vapply(Filter(function(e) .skill_push_changed(e, disk), lock$skills), function(e) basename(names(e$copies)[1]), ""))
}

# Plan a push: read the lock and disk, ask Cloud for the head of each
# changed entry, and plan. A request that fails fails its skill.
.skill_push_prepare <- function(root, force, server, token) {
  lock <- .skill_load(root)
  disk <- .skill_disk(root)
  dirs <- .skill_pull_dirs(root, .skill_pull_settings(root))
  remote <- list(); errors <- list()
  for (key in names(lock$skills)) {
    E <- lock$skills[[key]]
    if (!.skill_push_changed(E, disk)) next
    if (identical(E$identity$kind, "cloud") && !identical(E$identity$server, server)) {
      errors[[key]] <- paste0("It tracks a skill on another server (", E$identity$server, ").")
      next
    }
    got <- tryCatch(.skill_push_remote(key, E, server, token), error = identity)
    if (inherits(got, "error")) errors[[key]] <- sub("\\.$", "", conditionMessage(got))
    else if (!is.null(got)) remote[[key]] <- got
  }
  plan <- .skill_plan_push(disk, lock, list(remote = remote), list(command = "push", dirs = dirs, force = force))
  for (i in seq_along(plan$steps)) {
    s <- plan$steps[[i]]
    if (!is.null(s$entry) && !is.null(errors[[s$entry]]) && identical(s$action, "push")) {
      plan$steps[[i]]$action <- "none"; plan$steps[[i]]$status <- "failed"
      plan$steps[[i]]$detail <- paste0(errors[[s$entry]], ".")
    }
  }
  list(plan = plan, lock = lock, disk = disk, remote = remote, server = server, token = token, force = force)
}

# The warning shown before an entry is pushed
.skill_push_warning <- function(prepared, key) {
  E <- prepared$lock$skills[[key]]
  name <- basename(names(E$copies)[1])
  R <- prepared$remote[[key]]
  if (identical(E$identity$kind, "builtin")) {
    paste0("This saves ", name, " as your own skill; the built-in Framework skill stays as it is.")
  } else if (!is.null(R) && (is.null(E$base) || !identical(as.integer(R$version), as.integer(E$base$version)))) {
    paste0("Cloud has a newer version of ", name, " than this project pulled. Pushing replaces it ",
           "as the latest version; the Cloud changes stay in its history.")
  } else {
    paste0("This replaces the current version of ", name, ", used wherever it's attached.")
  }
}

.skill_push_keys <- function(steps) unique(unlist(lapply(Filter(function(s) identical(s$action, "push"), steps), `[[`, "entry")))

# Send each planned push and adopt each Cloud match, under the sync lock.
# Each push saves its pending request first, so a retry after a lost reply
# reuses it. Returns the steps as applied.
.skill_push_apply <- function(root, prepared) {
  held <- .skill_acquire(root)
  on.exit(unlink(held, recursive = TRUE), add = TRUE)
  steps <- prepared$plan$steps
  before <- prepared$lock
  state <- .skill_load(root)
  disk <- prepared$disk; server <- prepared$server
  set_steps <- function(key, ...) {
    changes <- list(...)
    for (i in seq_along(steps)) if (identical(steps[[i]]$entry, key)) for (n in names(changes)) steps[[i]][n] <<- list(changes[[n]])
  }
  adopt <- function(state, key, E, identity, hash, version, server, fresh = FALSE) {
    F <- E
    F$identity <- identity
    F$base <- list(channel = "cloud", hash = hash, version = as.integer(version), server = sub("/$", "", server))
    # Only copies seen holding the pushed files take its record; a copy whose
    # folder is gone keeps its own
    seen <- vapply(names(F$copies), function(p) identical(disk$hash(p), hash), logical(1))
    F$copies[seen] <- hash
    F$known <- if (fresh) .skill_known(hash) else .skill_known(E$known, hash)
    F$pending <- NULL
    new_key <- .skill_key(identity, names(E$copies)[1])
    state$skills[[key]] <- NULL
    state$skills[[new_key]] <- if (!is.null(state$skills[[new_key]])) .skill_entry_merge(F, state$skills[[new_key]]) else F
    state
  }
  records <- unique(unlist(lapply(Filter(function(s) identical(s$action, "record"), steps), `[[`, "entry")))
  for (key in records) {
    E <- state$skills[[key]]; R <- prepared$remote[[key]]
    if (is.null(E) || is.null(R)) next
    state <- adopt(state, key, E, E$identity, R$hash, R$version, server)
  }
  for (key in .skill_push_keys(steps)) {
    E <- state$skills[[key]]
    R <- prepared$remote[[key]]
    present <- Filter(function(p) !identical(disk$hash(p), .skill_absent), names(E$copies))
    outcome <- tryCatch({
      files <- .skill_scan(.skill_path(root, present[1]))
      local <- .skill_hash(files)
      if (!identical(local, disk$hash(present[1]))) stop("Local skill changed during sync", call. = FALSE)
      id <- E$identity
      builtin <- identical(id$kind, "builtin")
      forced <- !builtin && (is.null(E$base) || (!is.null(R) && !identical(as.integer(R$version), as.integer(E$base$version))))
      skill_id <- if (builtin) R$skill_id else if (identical(id$kind, "cloud")) id$skill_id
      expected <- if (builtin) R$version %||% 0L
        else if (forced) R$version %||% 0L
        else E$base$version %||% R$version %||% 0L
      basis <- paste0(expected, ":", skill_id %||% "", ":", id$variant)
      pending <- E$pending
      if (is.null(pending) || !identical(pending$hash, local) || !identical(pending$basis, basis)) {
        pending <- list(request_id = .skill_uuid(), hash = local, basis = basis)
      }
      E$pending <- pending; state$skills[[key]] <- E
      .skill_save(root, state)
      body <- list(request_id = pending$request_id, skill_id = skill_id, expected_version = as.integer(expected),
                   variant = id$variant, bundle = files, client = list(app = "framework-r"))
      body$project_token <- .skill_project_token(root, server)
      reply <- .skill_push_post(body, server, prepared$token)
      if (!is.null(reply$bundle) && !identical(.skill_hash(reply$bundle), reply$hash)) {
        stop("Cloud skill verification failed", call. = FALSE)
      }
      reply
    }, error = identity)
    if (inherits(outcome, "error")) {
      set_steps(key, action = "none", status = "failed", reason_code = NULL, hint = NULL,
                detail = conditionMessage(outcome))
      next
    }
    reply_server <- sub("/$", "", outcome$server %||% server)
    identity <- if (identical(E$identity$kind, "builtin") || !identical(outcome$skill_id, E$identity$skill_id)) {
      if (startsWith(outcome$skill_id, "framework:")) .skill_identity("builtin", outcome$skill_id, E$identity$variant)
      else .skill_identity("cloud", outcome$skill_id, E$identity$variant, reply_server)
    } else E$identity
    fresh <- !.skill_same_identity(identity, E$identity)
    state <- adopt(state, key, E, identity, outcome$hash, outcome$version, reply_server, fresh = fresh)
    set_steps(key, version = outcome$version)
  }
  .skill_save_changed(root, before, state)
  steps
}

.skill_push_counts <- c("pushed", "current", "refused", "missing", "untracked", "cancelled", "failed")

#' Push Locally Edited Skills to Framework Cloud
#'
#' Sends locally edited skills to Framework Cloud as new versions of your
#' own skills. A skill tracked in `.framework/skills.lock.json` is edited
#' when a copy differs from what the last sync wrote there. A skill that
#' changed on Cloud since then is refused with "Pull first"; `force = TRUE`
#' pushes it anyway, as the latest version. A built-in Framework skill is
#' never changed: an edited one is saved as your own copy. A skill switched
#' to another identity with [skills_move()] has no pulled version and is
#' refused until `force = TRUE`. Skills not tracked are listed; [skills_sync()]
#' adds one, and [skills_move()] records one that was moved by hand. Needs
#' [cloud_login()].
#'
#' Before pushing, a warning names what each new version affects, then asks
#' to continue. Without a console, pass `confirm = TRUE`.
#'
#' A skill whose copies in `.claude/skills/` and `.agents/skills/` differ is
#' reported as failed, and the other skills are still pushed. [skills_copy()]
#' makes the copies match.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param force Push skills that changed on Cloud since the last pull.
#' @param confirm `TRUE` pushes without asking; `FALSE` cancels. `NULL` asks
#'   in a console and stops otherwise.
#' @param dry_run Report what would be pushed and send nothing.
#' @return Invisibly, a list: `dry_run`, `skills` (each with `name`,
#'   `status`, `paths`, and, unless pushed, `reason`, `reason_code`, and
#'   `hint`; status is pushed, current (Cloud already has these files, so
#'   nothing was sent and the lock records Cloud's version), refused,
#'   missing, untracked, cancelled, or failed), `counts` by status, and `message` (the summary line). A skill
#'   whose tracked copies are all missing is reported as missing and not
#'   pushed.
#' @seealso [pull_skills()], [skills_copy()], [skills_move()]
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
  .skill_load(root)
  server <- .skill_server(root)
  token <- .fw_require_token(server)
  prepared <- .skill_push_prepare(root, force, server, token)
  steps <- prepared$plan$steps
  pushes <- .skill_push_keys(steps)

  for (key in pushes) message(.skill_push_warning(prepared, key))
  if (length(pushes) && !dry_run) {
    if (!.fw_confirm(confirm, "Continue?", "push_skills()")) {
      steps <- .skill_push_cancel(steps)
    } else {
      steps <- .skill_push_apply(root, prepared)
    }
  } else if (!dry_run && any(vapply(steps, function(s) identical(s$action, "record"), logical(1)))) {
    steps <- .skill_push_apply(root, prepared)
  }
  .skill_push_result(steps, prepared, dry_run, "push_skills")
}

# Every push step becomes cancelled
.skill_push_cancel <- function(steps) {
  lapply(steps, function(s) {
    if (identical(s$action, "push")) { s$action <- "none"; s$status <- "cancelled"; s$reason_code <- "cancelled" }
    s
  })
}

.skill_push_result <- function(steps, prepared, dry_run, fn) {
  skills <- .skill_rows_out(.skill_rows(steps, "push"), list(fn = fn, lock = prepared$lock, disk = prepared$disk))
  statuses <- vapply(skills, `[[`, "", "status")
  counts <- vapply(.skill_push_counts, function(k) sum(statuses == k), integer(1))
  labels <- c(pushed = if (dry_run) "to push" else "pushed", current = "already on Cloud", refused = "refused (pull first)",
              missing = "missing (every copy gone)", untracked = "not tracked", cancelled = "cancelled",
              failed = "failed")
  parts <- paste(counts, labels[.skill_push_counts])[counts > 0]
  prefix <- if (dry_run) "Skills (dry run, nothing sent): " else "Skills pushed: "
  summary <- paste0(prefix, if (length(parts)) paste(parts, collapse = ", ") else "nothing to push")
  message(summary)
  labels <- c(refused = "Refused", missing = "Missing", untracked = "Untracked", cancelled = "Cancelled", failed = "Failed")
  for (skill in skills) {
    if (skill$status %in% names(labels)) message("  ", labels[[skill$status]], ": ", skill$name, " — ", skill$reason)
  }
  invisible(list(dry_run = dry_run, skills = skills, counts = as.list(counts), message = summary, steps = steps))
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
