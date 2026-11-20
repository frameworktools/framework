# What skill commands share around the planner (skill_plan.R): reading the
# disk, building sources, applying a plan, and wording result rows.

# --- Disk ----------------------------------------------------------------------

# A copy's bundle hash now, "ABSENT", or "UNREADABLE". `errors` collects why
# a copy can't be read.
.skill_disk_hash <- function(root, path, errors = NULL) {
  tryCatch({
    target <- .skill_path(root, path)
    kind <- .skill_kind(target)
    if (identical(kind, "missing")) .skill_absent
    else if (!identical(kind, "directory")) stop("Not a skill folder", call. = FALSE)
    else .skill_hash(.skill_scan(target))
  }, error = function(e) {
    if (!is.null(errors)) assign(path, sub("\\.$", "", conditionMessage(e)), envir = errors)
    .skill_unreadable
  })
}

# The planner's view of a project's skill folders. Each path is read once.
.skill_disk <- function(root) {
  hashes <- new.env(parent = emptyenv()); errors <- new.env(parent = emptyenv())
  aliases <- new.env(parent = emptyenv())
  list(
    root = root,
    hash = function(p) {
      h <- get0(p, envir = hashes, inherits = FALSE)
      if (is.null(h)) { h <- .skill_disk_hash(root, p, errors); assign(p, h, envir = hashes) }
      h
    },
    error = function(p) get0(p, envir = errors, inherits = FALSE),
    folder_exists = function(d) {
      identical(tryCatch(.skill_kind(file.path(root, d)), error = function(e) "unreadable"), "directory")
    },
    folders = function(d) .skill_pull_folders(root, d),
    spell = function(p) .skill_copy_spelling(root, p),
    # A path's filesystem identity: its device and inode when it exists.
    # Otherwise its nearest existing parent as resolved on disk, then the
    # rest, folded to lower case when that parent's volume ignores case. A
    # case alias of a tracked path is that path.
    alias = function(p) {
      a <- get0(p, envir = aliases, inherits = FALSE)
      if (is.null(a)) {
        id <- tryCatch(.skill_copy_id(file.path(root, p)), error = function(e) NA_character_)
        a <- if (!is.na(id)) paste0("id:", id) else {
          k <- tryCatch(.skill_copy_key(root, p), error = function(e) NULL)
          if (is.null(k)) paste0("path:", p) else {
            tail <- k$parts[seq_along(k$parts) > k$given]
            if (isTRUE(k$fold)) tail <- tolower(tail)
            paste0("path:", paste(c(k$parts[seq_len(k$given)], tail), collapse = "/"))
          }
        }
        assign(p, a, envir = aliases)
      }
      a
    }
  )
}

.skill_pull_folders <- function(root, dir) {
  path <- file.path(root, dir)
  if (!dir.exists(path)) return(character())
  names <- list.dirs(path, full.names = FALSE, recursive = FALSE)
  sort(names[!startsWith(names, ".")], method = "radix")
}

# --- Sources ---------------------------------------------------------------------

.skill_source <- function(name, identity, channel, bundle, known = character(), version = NULL, server = NULL) {
  hash <- if (!is.null(bundle)) .skill_hash(bundle)
  list(name = name, identity = identity, channel = channel,
       version = if (identical(channel, "cloud")) as.integer(version) else NULL,
       server = if (identical(channel, "cloud")) sub("/$", "", server %||% "") else NULL,
       hash = hash, known = .skill_known(known, hash), bundle = bundle)
}

.skill_pull_shipped <- function(name) {
  path <- system.file("templates", "skills", name, package = "framework")
  if (nzchar(path) && file.exists(file.path(path, "SKILL.md"))) path else ""
}

# A built-in as this package ships it. Its known hashes are every version
# the package has shipped (skill-history.json).
.skill_source_package <- function(name, variant = "r") {
  path <- .skill_pull_shipped(name)
  bundle <- if (nzchar(path)) .skill_scan(path)
  .skill_source(name, .skill_identity("builtin", paste0("framework:", name), variant), "package", bundle,
                known = .skill_history(name, variant))
}

.skill_inline_bundle <- function(entry) {
  files <- c(list(SKILL.md = entry$content), entry$files %||% list())
  lapply(names(files), function(path) {
    list(path = path, content = jsonlite::base64_enc(charToRaw(enc2utf8(files[[path]]))), executable = FALSE)
  })
}

# A skill as a resolved setup names it: a package built-in, a Cloud version
# (a built-in when its ID is framework:<name>), or inline text
.skill_source_setup <- function(name, entry, variant = "r") {
  if (isTRUE(entry$package)) return(.skill_source_package(name, variant))
  if (!is.null(entry$sync) && !is.null(entry$bundle)) {
    sync <- entry$sync
    files <- .skill_validate(entry$bundle)
    if (!identical(.skill_hash(files), sync$hash)) stop("Cloud skill verification failed: ", name, call. = FALSE)
    v <- sync$variant %||% variant
    server <- sub("/$", "", sync$server %||% "")
    identity <- if (startsWith(sync$skill_id, "framework:")) .skill_identity("builtin", sync$skill_id, v)
      else .skill_identity("cloud", sync$skill_id, v, server)
    return(.skill_source(name, identity, "cloud", files, known = c(unlist(sync$known_hashes), entry$setup_hash),
                         version = sync$version, server = server))
  }
  files <- .skill_validate(.skill_inline_bundle(entry))
  .skill_source(name, .skill_identity("inline", paste0("inline:", name), variant), "inline", files)
}

# --- Apply ------------------------------------------------------------------------

# Undo the lock changes of declined steps: a declined copy keeps its old
# record, and its entry keeps its old base while known still gains the
# source's hashes. A new entry with no copy left is dropped.
.skill_lock_decline <- function(after, before, declined) {
  for (s in declined) {
    key <- s$entry
    F <- after$skills[[key]]; E <- before$skills[[key]]
    if (is.null(F)) next
    if (!is.null(E) && s$path %in% names(E$copies)) F$copies[s$path] <- unname(E$copies[s$path])
    else F$copies <- F$copies[names(F$copies) != s$path]
    if (!is.null(E)) {
      F$base <- E$base
      F$pending <- E$pending
    }
    after$skills[[key]] <- if (is.null(E) && !length(F$copies)) NULL else F
  }
  after
}

# Apply a pull plan's writes and copies in path order under the sync lock,
# then save the lock. A copy that changed since planning is left alone and
# its step becomes edited (changed_during_pull). Returns the steps as
# applied. `fn` names the command in errors.
.skill_apply <- function(root, plan, disk, before, fn = "pull_skills()") {
  steps <- plan$steps
  order <- order(vapply(steps, `[[`, "", "path"), method = "radix")
  declined <- list(); written <- character(); current <- NULL
  decline <- function(i) {
    steps[[i]]$action <<- "none"; steps[[i]]$status <<- "edited"; steps[[i]]$reason_code <<- "changed_during_pull"
    steps[[i]]$hint <<- NULL; steps[[i]]$backup <<- FALSE
    declined[[length(declined) + 1L]] <<- steps[[i]]
  }
  failure <- tryCatch({
    for (i in order) {
      s <- steps[[i]]
      if (!s$action %in% c("write", "copy")) next
      current <- s$path
      planned <- disk$hash(s$path)
      if (!identical(.skill_disk_hash(root, s$path), planned)) { decline(i); next }
      files <- if (identical(s$action, "write")) s$source$bundle else {
        b <- .skill_scan(.skill_path(root, s$from))
        if (!identical(.skill_hash(b), disk$hash(s$from))) NULL else b
      }
      if (is.null(files)) { decline(i); next }
      .skill_install(root, s$path, files, if (identical(planned, .skill_absent)) NULL else planned)
      written <- c(written, s$path)
    }
    NULL
  }, error = identity, interrupt = identity)
  after <- plan$lock_after
  if (!is.null(failure)) {
    # Steps not written keep the lock as it was for their copies
    rest <- Filter(function(s) s$action %in% c("write", "copy") && !s$path %in% written, steps)
    after <- .skill_lock_decline(after, before, c(declined, rest))
    tryCatch(.skill_save_changed(root, before, after), error = function(e) NULL)
    reason <- if (inherits(failure, "interrupt")) "interrupted" else sub("\\.$", "", conditionMessage(failure))
    stop(fn, " stopped at ", current, ": ", reason, ". ",
         if (length(written)) paste0("Already written: ", paste(written, collapse = ", "), ".") else "No skills were written.",
         call. = FALSE)
  }
  after <- .skill_lock_decline(after, before, declined)
  saved <- tryCatch(.skill_save_changed(root, before, after), error = identity)
  if (inherits(saved, "error")) {
    stop(fn, " could not save .framework/skills.lock.json: ", sub("\\.$", "", conditionMessage(saved)), ". ",
         if (length(written)) paste0("Already written: ", paste(written, collapse = ", "), ".") else "No skills were written.",
         call. = FALSE)
  }
  list(steps = steps, written = written, lock = after)
}

# --- Wording -----------------------------------------------------------------------

# The command a hint names, or NULL. `fn` is the command's own name, for
# the overwrite and force hints.
.skill_hint_text <- function(hint, fn = "pull_skills") {
  if (is.null(hint)) return(NULL)
  q <- function(x) paste0("\"", x, "\"")
  switch(hint$key,
    overwrite = paste0(fn, "(overwrite = TRUE)"),
    force = paste0(fn, "(force = TRUE)"),
    copy = {
      if (is.null(hint$from) || !all(basename(unlist(hint$to)) == basename(hint$from))) NULL
      else paste(vapply(unlist(hint$to), function(t) .skill_copy_call(hint$from, t), ""), collapse = "; ")
    },
    move = paste0("skills_move(", q(hint$from), ", ", q(hint$to), ")"),
    retarget = {
      id <- hint$identity
      if (identical(id$kind, "builtin")) {
        paste0("skills_move(", q(hint$path), ", builtin = ", q(sub("^framework:", "", id$skill_id)), ", variant = ", q(id$variant), ")")
      } else {
        paste0("skills_move(", q(hint$path), ", skill_id = ", q(id$skill_id), ", variant = ", q(id$variant), ")")
      }
    },
    sync = paste0("skills_sync(", q(hint$path), ")"),
    login = "cloud_login()",
    NULL)
}

# How a person reads an identity in a reason
.skill_identity_label <- function(identity, versus = NULL) {
  if (!is.null(versus) && identical(identity$skill_id, versus$skill_id)) {
    return(paste0(identity$skill_id, ", ", identity$variant, " variant",
                  if (identical(identity$kind, "cloud")) paste0(" on ", identity$server)))
  }
  identity$skill_id %||% "a local skill"
}

.skill_list_and <- function(x) {
  if (length(x) < 2) return(paste(x, collapse = ""))
  paste0(paste(x[-length(x)], collapse = ", "), " and ", x[length(x)])
}

# One plain sentence (or two) saying why a row has its status. `ctx`: fn
# (pull_skills, pull_all, push_skills, push_all), lock, disk, and sources
# (key -> source).
.skill_reason_text <- function(row, ctx) {
  fn <- ctx$fn %||% "pull_skills"
  first <- row$first %||% row$paths[1]
  hint <- row$hint; command <- .skill_hint_text(hint, fn)
  entry <- if (!is.null(row$entry)) ctx$lock$skills[[row$entry]]
  source <- if (!is.null(row$entry)) ctx$sources[[row$entry]]
  push <- startsWith(fn, "push")
  code <- row$reason_code %||% ""
  switch(paste(row$status, code, sep = "/"),
    "failed/unreadable" = paste0(first, ": ", (if (!is.null(ctx$disk)) ctx$disk$error(first)) %||% "not a valid skill folder", "."),
    "unavailable/not_shipped" = paste0(row$name, " isn't in this version of framework, so it was left as it is."),
    "unavailable/offline" = paste0("Framework Cloud wasn't reached, so ", row$name, " was left as it is."),
    "unavailable/setup_older" = paste0("Every copy is gone, and the setup names an older version than this project had. ",
                                       "Sign in with cloud_login() so pull can get the latest version."),
    "kept/cloud_tracked" = paste0(row$name, " was last updated from Framework Cloud, so the package version doesn't replace it."),
    "kept/other_identity" = , "kept/other_variant" = {
      label <- .skill_identity_label(entry$identity, if (identical(code, "other_variant")) hint$identity)
      paste0(first, " belongs to a different skill (", label, "), so pull left it alone.",
             if (!is.null(command)) paste0(" To switch it to the setup's skill: ", command))
    },
    "untracked/untracked" = {
      lead <- paste0(first, " isn't tracked", if (push) "." else ", so pull left it alone.")
      if (identical(hint$key, "sync")) paste0(lead, " ", command, " pushes it as a new skill.")
      else if (identical(hint$key, "move")) paste0(lead, " If it is ", hint$from, ", moved by hand: ", command)
      else if (!is.null(command)) paste0(lead, " To track it with this skill: ", command)
      else lead
    },
    "edited/local_edits" = paste0(first, " has local edits, which were kept. ", fn, "(overwrite = TRUE) replaces them with the ",
                                  switch(source$channel %||% "cloud", package = "built-in version.",
                                         inline = "setup's version.", "Cloud version.")),
    "edited/newer_in_project" = paste0(first, " has local edits on a newer version than the setup's, so it was kept."),
    "edited/changed_during_pull" = paste0(first, " changed during the pull, so it was left as it is."),
    "replaced/replaced_edits" = paste0(first, " had local edits, which were backed up to .framework/skills-backups/ and replaced."),
    "current/newer_in_project" = "This project holds a newer version than the setup names, so it was left as it is.",
    "current/" = if (push) "Cloud already has these files, so nothing was sent; the lock now records Cloud's version." else NULL,
    "restored/" = "A tracked copy was missing, so it was installed again.",
    "diverged/copies_differ" = , "failed/copies_differ" = {
      if (isTRUE(hint$pick)) {
        copies <- unlist(hint$to)
        keep <- vapply(copies, function(k) {
          calls <- .skill_hint_text(.skill_hint_copy(k, setdiff(copies, k)), fn)
          if (is.null(calls)) "" else paste0(" To keep ", k, ": ", calls, ".")
        }, "")
        paste0(.skill_list_and(copies), " differ. Pick the copy to keep.", paste(keep, collapse = ""))
      } else {
        paste0(.skill_list_and(c(hint$from, unlist(hint$to))), " differ, and only ", hint$from, " is edited.",
               if (!is.null(command)) paste0(" Copy it over the other", if (length(hint$to) > 1) "s", ": ", command)
               else " Copy it over the others yourself; skills_copy() keeps a skill's name.")
      }
    },
    "diverged/copy_absent" = , "failed/copy_absent" = paste0(
      .skill_list_and(unlist(hint$to)), if (length(hint$to) > 1) " are" else " is", " missing beside the edited copy ", hint$from, ".",
      if (!is.null(command)) paste0(" Copy it there: ", command) else ""),
    "missing/folder_gone" = paste0(
      if (!is.null(ctx$disk) && ctx$disk$folder_exists(dirname(first))) paste0(first, " is gone") else paste0(first, "'s folder is gone"),
      ", so ", if (push) "it can't be pushed." else "it can't be restored.",
                                   if (identical(hint$key, "move")) paste0(" If the skill moved to ", hint$to, ": ", command) else ""),
    "missing/all_gone" = {
      if (push) "Every tracked copy is gone, so there is nothing to push."
      else if (identical(hint$key, "login")) paste0("Every tracked copy is gone. Sign in with cloud_login(), then pull again ",
                                                   "to restore it from Cloud skill ", entry$identity$skill_id, ".")
      else "Every tracked copy is gone, and pull can't restore it."
    },
    "removed/not_in_setup" = "It's no longer in the project's setup, so it was left in place.",
    "refused/cloud_changed" = paste0(row$name, " changed on Cloud since this project pulled it. ", command, " replaces it."),
    "refused/first_push_pending" = paste0(
      row$name, "'s first push stopped before Cloud replied, so it may already be on Cloud. Check your skills on ",
      "Framework Cloud: if it's there, run skills_sync(\"", first, "\", skill_id = \"<its ID>\"); if not, ", command,
      " pushes it as a new skill."),
    "refused/no_base" = paste0(row$name, " has no pulled version to push over, since it was switched to another skill. ",
                               command, " pushes it as the latest version."),
    "cancelled/cancelled" = "The push was cancelled, so nothing was sent.",
    "moved/path_moved" = paste0("Moved from ", row$from, "."),
    "moved/lock_moved" = paste0("Recorded the move from ", row$from, "."),
    "moved/retargeted" = paste0("Now tracked as ", row$entry, "."),
    "missing/" = paste0("Not in the source folder, so it was kept."),
    if (!is.null(row$detail)) row$detail else NULL)
}

# Rows as commands return them: name, status, paths, and, for every row
# that isn't a plain success, reason (prose), reason_code, hint (the
# command), hint_key, and hint_args
.skill_rows_out <- function(rows, ctx) {
  lapply(rows, function(row) {
    reason <- .skill_reason_text(row, ctx)
    hint <- .skill_hint_text(row$hint, ctx$fn %||% "pull_skills")
    out <- list(name = row$name, status = row$status, paths = row$paths)
    if (!is.null(reason)) out$reason <- reason
    if (!is.null(hint)) out$hint <- hint
    out$reason_code <- row$reason_code
    if (!is.null(row$hint)) {
      out$hint_key <- row$hint$key
      out$hint_args <- row$hint[setdiff(names(row$hint), "key")]
    }
    out
  })
}
