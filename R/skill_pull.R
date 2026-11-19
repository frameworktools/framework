# A project's skills, kept in step with its setup on Framework Cloud.
# pull_skills() installs and updates the skills the Cloud setup lists;
# push_skills() sends locally edited skills back. Both build on the
# per-skill machinery in skill_sync.R. framework-py: skill_pull.py; fw:
# fw skills pull / fw skills push. pull_all() and push_all() include them.

# The shared skill vocabulary (framework-py and fw use the same names)
.skill_pull_statuses <- c("added", "restored", "updated", "current", "edited", "replaced", "diverged", "missing",
                          "removed", "unavailable", "failed", "kept", "untracked")
# Which status names a skill when its copies in several folders differ
.skill_pull_precedence <- c("failed", "diverged", "missing", "unavailable", "kept", "untracked", "edited", "replaced",
                            "updated", "restored", "added", "current")

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
      # The setup's version stays "unedited": record its hash before the
      # newer version replaces it
      entry$setup_hash <- entry$setup_hash %||% source$hash
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

# The lock entry tracking a copy, or an empty list
.skill_pull_tracked <- function(state, relative) {
  keys <- names(Filter(function(e) relative %in% unlist(e$paths), state$skills))
  if (length(keys)) state$skills[[keys[1]]] else list()
}

# Whether a copy tracks a Cloud skill other than the one the setup names
# for it. Any Cloud identity counts, framework: IDs too, when the setup
# names a different Cloud skill; a personal ID counts against any setup
# content (the package or inline text).
.skill_pull_own <- function(root, relative, entry) {
  tracked <- .skill_pull_tracked(.skill_load(root), relative)
  id <- tracked$skill_id
  # One identity is server, skill ID, and variant together
  same <- !is.null(entry$sync) && .skill_same_cloud(tracked, entry$sync$skill_id, entry$sync$server, entry$sync$variant)
  !is.null(id) && !same && (!startsWith(id, "framework:") || !is.null(entry$sync))
}

# Whether the setup has a newer version of the Cloud skill a copy tracks
.skill_pull_newer <- function(state, relative, entry) {
  tracked <- .skill_pull_tracked(state, relative)
  !is.null(entry$sync) && .skill_same_cloud(tracked, entry$sync$skill_id, entry$sync$server, entry$sync$variant) &&
    isTRUE(as.integer(entry$sync$version %||% 0L) > as.integer(tracked$version %||% 0L))
}

# Whether a copy tracks your own (personal) Cloud skill
.skill_pull_personal <- function(state, relative) {
  id <- .skill_pull_tracked(state, relative)$skill_id
  !is.null(id) && !startsWith(id, "framework:")
}

# Whether a skill's tracked copies differ from each other or one is
# missing. Returns NULL, or the existing copy `a`, the other copy `b`, and
# whether `b` is missing.
# whether `b` is missing. When every tracked copy is missing, `restore` is TRUE.
.skill_pull_diverged <- function(root, state, keys) {
  # Per lock entry: only the paths inside one entry are compared. Skills
  # that share a name in separate entries are separate skills.
  if (!length(keys)) return(NULL)
  tracked <- character(); restore <- TRUE
  for (key in keys) {
    paths <- unlist(state$skills[[key]]$paths)
    if (!length(paths)) next
    hashes <- vapply(paths, function(p) .skill_pull_hash(root, p), "")
    tracked <- c(tracked, paths)
    present <- paths[nzchar(hashes)]
    if (!length(present)) next
    restore <- FALSE
    if (!all(nzchar(hashes))) return(list(a = present[1], b = paths[!nzchar(hashes)][1], missing = TRUE, paths = paths))
    if (length(unique(hashes)) > 1) return(list(a = paths[1], b = paths[hashes != hashes[1]][1], missing = FALSE, paths = paths))
  }
  if (restore && length(tracked)) list(restore = TRUE, paths = tracked) else NULL
}

# The lock entry a setup skill is tracked under, found by its identity even
# when no configured assistant path is tracked (after switching assistants):
# a Cloud skill by server, ID, and variant; a built-in by its origin and name
.skill_pull_identity_key <- function(state, name, entry) {
  keys <- if (!is.null(entry$sync)) {
    names(Filter(function(e) .skill_same_cloud(e, entry$sync$skill_id, entry$sync$server, entry$sync$variant), state$skills))
  } else if (isTRUE(entry$package)) {
    names(Filter(function(e) is.null(e$skill_id) && identical(e$origin$skill_id, paste0("framework:", name)) &&
                   name %in% basename(unlist(e$paths)), state$skills))
  }
  if (length(keys)) keys[1] else NULL
}

# A group that can't be planned (a tracked copy without SKILL.md, a
# folder that can't be read) fails with its reason; the others proceed
.skill_pull_group_safe <- function(root, state, name, entry, key, paths, ...) {
  tryCatch(.skill_pull_group(root, state, name, entry, key, paths, ...), error = function(e) {
    found <- stats::setNames(rep("failed", length(paths)), paths)
    list(name = name, key = key, found = found, hashes = stats::setNames(rep("", length(paths)), paths),
         hint = sub("\\.$", "", conditionMessage(e)), own = FALSE, newer = FALSE)
  })
}

# Plan one lock entry's copies of a setup skill (key NULL: copies no entry
# tracks). Returns its name, statuses by path, hashes, hint, and flags.
.skill_pull_group <- function(root, state, name, entry, key, paths, configured, source, overwrite) {
  found <- character(); hashes <- character(); hint <- NULL; own_entry <- NULL
  tracked_entry <- if (is.null(key)) list() else state$skills[[key]]
  tracked <- unlist(tracked_entry$paths)
  split <- if (is.null(key)) NULL else .skill_pull_diverged(root, state, key)
  restore <- isTRUE(split$restore)
  left <- character()
  if (restore) {
    # Every copy this entry tracks is missing: each comes back where its
    # folder exists or is configured
    extra <- setdiff(paths, configured)
    left <- extra[!vapply(extra, function(p) identical(.skill_kind(.skill_path(root, dirname(p))), "directory"), logical(1))]
    paths <- setdiff(paths, left)
    split <- NULL
    # Your own skill comes back from its own Cloud identity, not from what
    # the setup names under its name
    id <- tracked_entry$skill_id
    if (!is.null(id) && !startsWith(id, "framework:") &&
        (!identical(entry$sync$skill_id, id) ||
         isTRUE(as.integer(entry$sync$version %||% 0L) < as.integer(tracked_entry$version %||% 0L)))) {
      fetched <- .skill_pull_fetch_own(tracked_entry)
      if (!is.null(fetched$entry)) {
        own_entry <- fetched$entry
      } else {
        found[paths] <- "missing"; hashes[paths] <- ""
        found[left] <- "missing"; hashes[left] <- ""
        hint <- if (identical(fetched$error, "login")) {
          paste0("Every tracked copy is gone. Sign in with cloud_login(), then run pull_skills() to restore it ",
                 "from Cloud skill ", id, ".")
        } else {
          paste0("Every tracked copy is gone, and Cloud skill ", id, " couldn't be read (", fetched$error,
                 "). Run pull_skills() again to restore it.")
        }
        return(list(name = name, key = key, found = found, hashes = hashes, hint = hint, loose = character(),
                    own = TRUE, newer = FALSE))
      }
    }
  }
  plan_entry <- own_entry %||% entry
  offline <- is.null(own_entry) && identical(source, "package") && !is.null(key) && !is.null(tracked_entry$skill_id)
  for (relative in paths) {
    hashes[[relative]] <- .skill_pull_hash(root, relative)
    found[[relative]] <- if (!is.null(split)) "diverged"
      else if (offline) "unavailable"
      else .skill_pull_plan(root, name, plan_entry, relative, overwrite)
    if (restore && identical(found[[relative]], "added")) found[[relative]] <- "restored"
  }
  # A copy no entry tracks, beside this entry's copies: pull never writes
  # it, gives it this entry's baseline, or adds it to the entry. It is kept,
  # never reported as current.
  loose <- if (is.null(key)) character() else setdiff(paths[nzchar(hashes[paths])], tracked)
  loose_hint <- NULL
  if (length(loose)) {
    found[loose] <- "untracked"
    # Put the copy back at the tracked path, then copy it to the loose path,
    # which joins this skill's entry. skills_sync() on the loose path would
    # make a new identity.
    adopt <- paste(.skill_copy_call(loose[1], tracked[1]), .skill_copy_call(tracked[1], loose[1]), sep = "; ")
    loose_hint <- paste0(loose[1], " isn't tracked, so pull left it alone. To track it with this skill: ", adopt)
  }
  # Tracked copies only in folders that are gone, and nothing else to pull
  if (length(left)) {
    if (!length(setdiff(names(found), loose))) {
      found[left] <- "missing"; hashes[left] <- ""
      id <- tracked_entry$skill_id
      hint <- paste0("Every tracked copy is gone. ", if (!is.null(id)) paste0("Its last pushed version is Cloud skill ", id, ". "),
                     "Its folders (", paste(dirname(left), collapse = ", "), ") are gone, so pull can't restore it.")
    } else {
      hint <- paste0("Restored where its folder exists. Not restored: ", paste(left, collapse = ", "),
                     ", because its folder is gone.")
    }
  }
  if (!is.null(split)) {
    # The hint copies within this entry only
    hint <- .skill_diverged_message(split$a, split$b, missing = split$missing, root = root,
                                    others = setdiff(split$paths, split$a))
  } else if (offline) {
    hint <- paste0("Framework Cloud wasn't reached, so ", name, " was left as it is.")
  } else if (!restore) {
    # A copy tracking a different Cloud skill than the setup names for this
    # name: kept, with the reason
    other <- Filter(function(r) .skill_pull_own(root, r, entry), setdiff(names(found), loose))
    if (length(other)) {
      found[other] <- "kept"
      mine <- .skill_pull_tracked(state, other[1])
      label <- if (identical(mine$skill_id, entry$sync$skill_id)) {
        paste0(mine$skill_id, ", ", mine$variant %||% "r", " variant on ", mine$server %||% "this server")
      } else mine$skill_id
      hint <- paste0(other[1], " belongs to a different skill (", label, "), so pull left it alone.")
    }
    # A new assistant folder: an edited copy, or one tracking your own or a
    # Cloud skill, is copied with skills_copy(), not pulled in an older form
    existing <- setdiff(paths[nzchar(hashes)], loose)
    keep <- Filter(function(r) identical(found[[r]], "edited") || .skill_pull_personal(state, r), existing)
    missing <- paths[!nzchar(hashes)]
    if (length(keep) && length(missing)) {
      hint <- .skill_diverged_message(keep[1], missing[1], missing = TRUE, root = root, others = missing)
      found[setdiff(names(found), loose)] <- "diverged"
    }
    # This entry's existing copies move together
    present <- intersect(tracked, existing)
    writes <- found[present] %in% c("updated", "replaced")
    if (!any(found == "diverged") && any(writes) && !all(writes)) {
      hint <- paste0(paste(present, collapse = " and "), " can't all be updated, so none was. ",
                     "Make them match, then pull again.")
      found[setdiff(names(found), loose)] <- "diverged"
    }
  }
  list(name = name, key = key, found = found, hashes = hashes, hint = hint, loose = loose, loose_hint = loose_hint,
       entry = own_entry, kind = if (!is.null(entry$sync)) "cloud" else if (isTRUE(entry$package)) "package" else "inline",
       own = any(vapply(names(found), function(r) .skill_pull_personal(state, r), logical(1))),
       newer = any(vapply(names(found), function(r) .skill_pull_newer(state, r, entry), logical(1))),
       same = !is.null(entry$sync) && any(vapply(names(found), function(r) {
         identical(.skill_pull_tracked(state, r)$skill_id, entry$sync$skill_id)
       }, logical(1))))
}

# Your own skill's latest version from Cloud, by its own identity, as a
# setup entry. Reading it needs your login.
.skill_pull_fetch_own <- function(tracked) {
  server <- tracked$server
  token <- if (!is.null(server)) tryCatch(.fw_cloud_token(server), error = function(e) NULL)
  if (is.null(token)) return(list(error = "login"))
  variant <- tracked$variant %||% "r"
  remote <- tryCatch({
    r <- .fw_api(paste0("/api/v1/skills/sync/", utils::URLencode(tracked$skill_id, reserved = TRUE), "?variant=", variant),
                 token, url = server)
    if (!identical(.skill_hash(r$bundle), r$hash)) stop("Cloud skill verification failed", call. = FALSE)
    r
  }, error = function(e) e)
  if (inherits(remote, "error")) return(list(error = sub("\\.$", "", conditionMessage(remote))))
  list(entry = list(bundle = remote$bundle,
                    sync = list(skill_id = remote$skill_id %||% tracked$skill_id, version = remote$version,
                                hash = remote$hash, variant = variant, server = server)))
}

# What pulling one skill into one folder does
.skill_pull_plan <- function(root, name, entry, relative, overwrite) {
  target <- .skill_path(root, relative)
  current <- if (dir.exists(target)) .skill_hash(.skill_scan(target)) else NULL
  # A copy tracking your own or another Cloud skill keeps that identity:
  # kept, even with overwrite
  if (.skill_pull_own(root, relative, entry)) return("edited")
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
  # overwrite resets an edited copy of your own Cloud skill to that same
  # skill's Cloud version (same or newer), after a backup. A different
  # identity never replaces it (see .skill_pull_own() above).
  if (identical(status, "edited") && isTRUE(overwrite)) "replaced" else status
}

# A copy's hash, or "" when there is none
.skill_pull_hash <- function(root, relative) {
  target <- .skill_path(root, relative)
  if (identical(.skill_kind(target), "missing")) "" else .skill_hash(.skill_scan(target))
}

# Applies a planned status. `planned` is the copy's hash when it was
# planned. The copy is re-hashed just before installing; a copy edited since
# is left alone, and "edited" returned. Otherwise "applied". Updated was
# planned as unedited, so it is forced: an earlier folder's update has
# already moved the lock's hash to the new version.
.skill_pull_apply <- function(root, name, entry, relative, status, planned, prior = NULL) {
  force <- status %in% c("replaced", "updated")
  # A current copy whose install is declined (an older or other version's
  # metadata) is left as it is, not reported as edited
  declined <- if (identical(status, "current")) "applied" else "edited"
  if (isTRUE(entry$package)) {
    ok <- .skill_package_install(.skill_pull_shipped(name), root, relative, name, force = force, lock = FALSE,
                                 planned = planned, prior = prior)
    return(if (isTRUE(ok)) "applied" else declined)
  }
  if (!identical(.skill_pull_hash(root, relative), planned)) return("edited")
  if (!is.null(entry$sync)) {
    # Current with other files: a newer version than the setup's, kept as it is
    if (identical(status, "current") && !identical(planned, entry$sync$hash)) return("applied")
    ok <- .skill_cloud_install(root, relative, entry, force = force, clean = entry$setup_hash, lock = FALSE,
                               planned = planned, prior = prior)
    return(if (isTRUE(ok)) "applied" else declined)
  }
  if (!identical(status, "current")) {
    .skill_install(root, relative, .skill_inline_bundle(entry), if (nzchar(planned)) planned else NULL)
  }
  "applied"
}

# The detail line for one pulled skill, or NULL. `fn` names the command
# that replaces an edited copy (pull_skills or pull_all).
.skill_pull_line <- function(skill, fn) {
  labels <- c(edited = "Edited", kept = "Kept", untracked = "Untracked", replaced = "Replaced", restored = "Restored",
              diverged = "Diverged", missing = "Missing", removed = "Removed", unavailable = "Unavailable",
              failed = "Failed")
  if (!skill$status %in% names(labels) || is.null(skill$reason)) return(NULL)
  reason <- gsub("pull_skills(", paste0(fn, "("), skill$reason, fixed = TRUE)
  paste0("  ", labels[[skill$status]], ": ", skill$name, " \u2014 ", reason)
}

# A result row: `reason` is one plain sentence saying why; `hint` is the
# exact command to run (the commands the reason names), or absent. Every
# row that isn't a plain success has a reason.
.skill_pull_row <- function(name, status, paths, reason = NULL, first = paths[1], kind = NULL) {
  reason <- reason %||% switch(status,
    edited = paste0(first, " has local edits, which were kept. pull_skills(overwrite = TRUE) replaces them with the ",
                    switch(kind %||% "cloud", package = "built-in version.", inline = "setup's version.", "Cloud version.")),
    replaced = paste0(first, " had local edits, which were backed up to .framework/skills-backups/ and replaced."),
    removed = "It's no longer in the project's setup, so it was left in place.",
    restored = "Every tracked copy was missing, so it was installed again.",
    unavailable = paste0(name, " isn't in this version of framework, so it was left as it is."),
    NULL)
  calls <- if (is.null(reason)) character() else regmatches(reason, gregexpr("(pull_skills|skills_copy)\\([^)]*\\)", reason))[[1]]
  c(list(name = name, status = status, paths = paths),
    if (!is.null(reason)) list(reason = reason),
    if (length(calls)) list(hint = paste(calls, collapse = "; ")))
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
#' Locally edited skills are kept and listed. `overwrite = TRUE` replaces
#' them too, backing the old copies up to `.framework/skills-backups/`.
#' Skills no longer in the setup are never deleted, only listed. The Skills
#' table in AGENTS.md is refreshed.
#'
#' A skill whose tracked copies (in `.claude/skills/` and `.agents/skills/`)
#' differ, or with a tracked copy missing, is diverged: no copy of it is
#' written, its entry in `.framework/skills.lock.json` is left as it is, and
#' the message gives the [skills_copy()] call that reconciles it. The same
#' applies to a new assistant folder when the existing copy is locally
#' edited or tracks your own or a Cloud skill. No skill moves to an older
#' version.
#'
#' An edited copy of your own Cloud skill is kept. With `overwrite = TRUE`
#' it is reset, after a backup, to that same skill's Cloud version (the same
#' version or a newer one), which discards your local edits. A different
#' identity (another Cloud skill, a built-in, or setup content) never
#' replaces your own skill.
#'
#' Pull uses the enabled assistants' skills folders (`.agents/skills` when
#' none is set) and the paths `.framework/skills.lock.json` tracks. Other
#' folders, such as a disabled assistant's, are not read.
#'
#' Offline, or without a project token, the package skills for the project's
#' type are used instead, and the message says so.
#'
#' @param project_path Path to the project directory (default: current directory).
#' @param overwrite Replace locally edited skills too, after backing them up.
#' @param dry_run Report what would change and write nothing.
#' @return Invisibly, a list: `source` ("cloud" or "package"), `dry_run`,
#'   `skills` (each a list with `name`, `status`, and `paths`), `counts` by
#'   status, `message` (the summary line), and `notes`. Statuses: added,
#'   restored (a deleted tracked copy put back), updated, current, edited
#'   (local edits kept), replaced (local edits backed up and overwritten),
#'   diverged (tracked copies differ or one is missing; nothing written),
#'   missing (every tracked copy gone and not restorable), removed (no longer
#'   in the setup), unavailable (Cloud not reached; left alone), failed (the
#'   entry couldn't be read), kept (belongs to a different skill, or the
#'   setup names a different identity), and untracked (a copy not in the
#'   lock, left alone). Every row that isn't a plain success has a `reason`,
#'   one plain sentence, and a `hint` with the exact command to run when
#'   there is one.
#' @seealso [push_skills()] sends edited skills back; [skills_sync()] syncs
#'   one skill; [skills_copy()] copies an edited skill to the other
#'   assistant folders.
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
  # Package skills stand in only when Cloud can't be reached or the project
  # has no token. A refused token, an unknown server, or a setup this version
  # can't read stops with an error, so package defaults never hide the failure.
  fetched <- tryCatch(
    .skill_pull_cloud_skills(root, notes),
    fw_no_project_token = function(e) e,
    httr2_failure = function(e) e,
    curl_error = function(e) e,
    httr2_http_401 = function(e) .setup_refused(e),
    httr2_http_403 = function(e) .setup_refused(e)
  )
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
  # Plan every skill in every folder before writing anything, so a copy in
  # a second folder is judged as it was, not after the first was updated
  # Each step keeps the copy's hash as planned
  # Planned per lock entry: each entry tracking a copy of the skill is its
  # own group, with its own status and hint. Configured paths no entry
  # tracks join the entry the setup names (else the only one). A diverged
  # entry never changes another entry's plan.
  groups <- list(); steps <- list()
  state <- .skill_load(root)
  for (name in names(wanted)) {
    entry <- wanted[[name]]
    # As the lock spells them: a folder tracked through a case alias is that entry's
    configured <- unique(unname(vapply(file.path(dirs, name), function(r) .skill_lock_spelling(root, state, r), "")))
    tracked_keys <- unique(unlist(lapply(configured, function(r) .skill_entry_key(state, r))))
    identity <- .skill_pull_identity_key(state, name, entry)
    keys <- unique(c(tracked_keys, identity))
    untracked <- configured[vapply(configured, function(r) is.null(.skill_entry_key(state, r)), logical(1))]
    home <- if (!is.null(identity)) identity else if (length(keys) == 1) keys else NULL
    plan_keys <- if (length(keys)) keys else NA_character_
    for (key in plan_keys) {
      paths <- if (is.na(key)) character() else unlist(state$skills[[key]]$paths)
      if (identical(key, home) || (is.na(key))) paths <- unique(c(paths, untracked))
      if (!length(paths)) next
      groups[[length(groups) + 1L]] <- .skill_pull_group_safe(root, state, name, entry, if (is.na(key)) NULL else key,
                                                              paths, configured, source, overwrite)
    }
    # Untracked configured paths when the skill's entries are someone else's
    if (length(keys) && is.null(home) && length(untracked)) {
      groups[[length(groups) + 1L]] <- .skill_pull_group_safe(root, state, name, entry, NULL, untracked, configured,
                                                              source, overwrite)
    }
  }
  # Untracked copies beside an entry are their own row, kept as they are
  split_groups <- list()
  for (g in groups) {
    loose <- intersect(g$loose %||% character(), names(g$found))
    row <- list(name = g$name, key = NULL, found = g$found[loose], hashes = g$hashes[loose],
                hint = g$loose_hint, loose = loose)
    g$found <- g$found[setdiff(names(g$found), loose)]; g$loose <- character()
    if (length(g$found)) split_groups[[length(split_groups) + 1L]] <- g
    if (length(loose)) split_groups[[length(split_groups) + 1L]] <- row
  }
  groups <- split_groups
  for (g in seq_along(groups)) {
    for (relative in names(groups[[g]]$found)) {
      # Untracked copies beside an entry are never written or joined
      if (relative %in% groups[[g]]$loose) next
      steps[[length(steps) + 1L]] <- list(group = g, name = groups[[g]]$name, relative = relative,
                                          status = groups[[g]]$found[[relative]], hash = groups[[g]]$hashes[[relative]],
                                          entry = groups[[g]]$entry)
    }
  }
  if (!dry_run) {
    written <- character()
    for (step in steps) {
      if (!step$status %in% c("added", "restored", "updated", "replaced", "current")) next
      # A current one is recorded in the lock
      # Every write is judged against the lock as it was before the pull
      applied <- tryCatch(.skill_pull_apply(root, step$name, step$entry %||% wanted[[step$name]], step$relative,
                                            step$status, step$hash,
                                            prior = state),
                          error = function(e) e)
      if (inherits(applied, "error")) {
        # The failed step may have written its copy before failing (as when
        # saving the lock file)
        now <- tryCatch(.skill_pull_hash(root, step$relative), error = function(e) NA_character_)
        if (!identical(now, step$hash)) written <- c(written, step$relative)
        stop("pull_skills() stopped at ", step$relative, ": ", sub("\\.$", "", conditionMessage(applied)), ". ",
             if (length(written)) paste0("Already written: ", paste(written, collapse = ", "), ".") else "No skills were written.",
             call. = FALSE)
      }
      if (identical(applied, "edited")) {
        # Edited since it was planned, or declined by the installer (an older
        # version or another identity): kept. A copy that was missing stays
        # missing and is reported as not pulled.
        groups[[step$group]]$found[[step$relative]] <- if (nzchar(step$hash)) "edited" else "unavailable"
      } else if (!identical(step$status, "current")) {
        written <- c(written, step$relative)
      }
    }
  }
  skills <- lapply(groups, function(g) {
    status <- .skill_pull_precedence[min(match(g$found, .skill_pull_precedence))]
    first <- names(g$found)[g$found == status][1]
    .skill_pull_row(g$name, status, names(g$found), g$hint, first = first, kind = g$kind)
  })
  # A tracked skill the setup doesn't list, with every copy gone: pull can't
  # restore it, and says so
  planned_keys <- unlist(lapply(groups, `[[`, "key"))
  for (key in setdiff(names(state$skills), planned_keys)) {
    tracked <- unlist(state$skills[[key]]$paths)
    if (!length(tracked) || any(nzchar(vapply(tracked, function(p) .skill_pull_hash(root, p), "")))) next
    id <- state$skills[[key]]$skill_id
    skills[[length(skills) + 1L]] <- .skill_pull_row(
      basename(tracked[1]), "missing", tracked,
      paste0("Every tracked copy is gone. ", if (!is.null(id)) paste0("Its last pushed version is Cloud skill ", id, ". "),
             "The project's setup doesn't list it, so pull can't restore it."))
  }
  if (identical(source, "cloud")) {
    others <- list()
    # A folder pulled under another spelling (Foo for foo) is the same
    # folder: matched by filesystem identity, never also reported removed
    planned <- unlist(lapply(groups, function(g) names(g$found)))
    planned_ids <- unique(stats::na.omit(vapply(planned, function(p) .skill_copy_id(file.path(root, p)), "")))
    for (dir in dirs) for (name in setdiff(.skill_pull_folders(root, dir), names(wanted))) {
      if (.skill_copy_id(file.path(root, dir, name)) %in% planned_ids) next
      others[[name]] <- c(others[[name]], file.path(dir, name))
    }
    for (name in sort(names(others))) {
      skills[[length(skills) + 1L]] <- .skill_pull_row(name, "removed", others[[name]])
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
    line <- .skill_pull_line(skill, "pull_skills")
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
    # A copy that can't be read fails only its own skill
    hashes <- tryCatch(vapply(unlist(entry$paths), function(p) .skill_pull_hash(root, p), ""), error = function(e) e)
    if (inherits(hashes, "error")) {
      entry$present <- unlist(entry$paths)[1]; entry$error <- conditionMessage(hashes)
      edited[[length(edited) + 1L]] <- entry
      next
    }
    paths <- names(hashes)[nzchar(hashes)]
    # Every tracked copy is gone: reported as missing, never pushed
    if (!length(paths)) {
      if (length(hashes)) { entry$present <- names(hashes)[1]; entry$missing <- TRUE; edited[[length(edited) + 1L]] <- entry }
      next
    }
    # A missing tracked copy is a divergence too, reported by skills_sync()
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
    if (isTRUE(entry$missing)) {
      plans[[length(plans) + 1L]] <- list(name = name, path = paths[1], status = "missing")
      next
    }
    action <- if (!is.null(entry$error)) simpleError(entry$error)
      else tryCatch(skills_sync(paths[1], root, direction = "status")$action, error = function(e) e)
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
#'   `status`, and `paths`; status is pushed, refused, missing, untracked,
#'   cancelled, or failed), `counts` by status, and `message` (the summary
#'   line). A skill whose tracked copies are all missing is reported as
#'   missing and not pushed.
#' @seealso [pull_skills()], [skills_copy()]
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
  .fw_require_token(.skill_server(root))
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

  skills <- lapply(c(plans, planned$untracked), .skill_push_row, fn = "push_skills")
  keys <- c("pushed", "refused", "missing", "untracked", "cancelled", "failed")
  statuses <- vapply(skills, `[[`, "", "status")
  counts <- vapply(keys, function(k) sum(statuses == k), integer(1))
  labels <- c(pushed = if (dry_run) "to push" else "pushed", refused = "refused (pull first)",
              missing = "missing (every copy gone)", untracked = "not tracked", cancelled = "cancelled",
              failed = "failed")
  parts <- paste(counts, labels[keys])[counts > 0]
  prefix <- if (dry_run) "Skills (dry run, nothing sent): " else "Skills pushed: "
  summary <- paste0(prefix, if (length(parts)) paste(parts, collapse = ", ") else "nothing to push")
  message(summary)
  labels <- c(refused = "Refused", missing = "Missing", untracked = "Untracked", cancelled = "Cancelled", failed = "Failed")
  for (skill in skills) {
    if (skill$status %in% names(labels)) message("  ", labels[[skill$status]], ": ", skill$name, " \u2014 ", skill$reason)
  }
  invisible(list(dry_run = dry_run, skills = skills, counts = as.list(counts), message = summary))
}

# A push result row in the shared vocabulary: pushed, refused, missing,
# untracked, cancelled, or failed (a planned push is reported as pushed in a
# dry run). Every row but pushed has a `reason`; `hint` is the command to
# run, when there is one.
.skill_push_row <- function(p, fn = "push_skills") {
  status <- if (identical(p$status, "push")) "pushed" else p$status
  reason <- switch(status,
    refused = paste0(p$name, " changed on Cloud since this project pulled it. ", fn, "(force = TRUE) replaces it."),
    missing = "Every tracked copy is gone, so there is nothing to push.",
    untracked = paste0(p$path[1], " isn't tracked. skills_sync(\"", p$path[1], "\") pushes it as a new skill."),
    cancelled = "The push was cancelled, so nothing was sent.",
    failed = p$reason,
    NULL)
  calls <- if (is.null(reason)) character() else
    regmatches(reason, gregexpr("(push_skills|push_all|skills_sync|skills_copy)\\([^)]*\\)", reason))[[1]]
  c(list(name = p$name, status = status, paths = p$path),
    if (!is.null(reason)) list(reason = reason),
    if (length(calls)) list(hint = calls[1]))
}
