# The skill planner: one pure function every skill command calls. It reads
# no files and makes no requests. The command gathers the disk, the lock,
# and what its sources offer, calls .skill_plan(), then shows or applies the
# steps and saves `lock_after`. The rules are docs/architecture/skills-lock-v2.md;
# the cases are inst/conformance/skills/. framework-py: skills_plan.py; fw:
# internal/skills/plan.go.
#
# Inputs:
# - disk: a list of functions. hash(path) gives a bundle hash, "ABSENT", or
#   "UNREADABLE"; folder_exists(dir); folders(dir) lists a skills folder's
#   folders; alias(path) gives a path's filesystem identity (its spelling on
#   disk), so a case alias matches its lock path.
# - lock: the lock as .skill_load() returns it (schema 2).
# - offer: source ("cloud" or "package"), skills (sources in setup order),
#   by_identity (key -> source), remote (push: key -> list(version, hash)).
#   A source has name, identity, channel, version, server, hash, known, and
#   bundle (NULL when the package doesn't ship the skill).
# - opt: command (pull, upgrade, create, copy, push, move), source, dirs,
#   overwrite, force, offline, scope (all, builtin, or listed).
#
# Steps are lists with path, entry (lock key or NULL), name, action (none,
# write, copy, record, move, push), status, reason_code, hint, and for some
# actions from, backup, and source (the source a write installs).

.skill_absent <- "ABSENT"
.skill_unreadable <- "UNREADABLE"

.skill_plan_new <- function(lock) {
  plan <- new.env(parent = emptyenv())
  plan$steps <- list(); plan$lock_after <- lock; plan$planned <- character(); plan$kept <- character()
  plan
}

.skill_step <- function(plan, path, key, action, status, reason = NULL, hint = NULL, name = NULL,
                        from = NULL, backup = FALSE, source = NULL) {
  step <- list(path = path, entry = key, name = name %||% basename(path), action = action, status = status,
               reason_code = reason, hint = hint, backup = isTRUE(backup))
  if (!is.null(from)) step$from <- from
  if (!is.null(source)) step$source <- source
  plan$steps[[length(plan$steps) + 1L]] <- step
  invisible(step)
}

# A hint: a key and its arguments. `from` may be NULL (the person picks).
.skill_hint <- function(key, ...) c(list(key = key), list(...))
.skill_hint_copy <- function(from, to) {
  list(key = "copy", from = from, to = sort(unique(to), method = "radix"), pick = is.null(from))
}

.skill_paths <- function(copies) vapply(copies, `[[`, "", "path")
.skill_sorted <- function(paths) sort(as.character(paths), method = "radix")

# Two identities name the same skill in different variants: same skill ID,
# and, for Cloud skills, the same server
.skill_other_variant <- function(a, b) {
  identical(a$skill_id, b$skill_id) && identical(a$kind, b$kind) && !identical(a$variant, b$variant) &&
    (!identical(a$kind, "cloud") || identical(a$server, b$server))
}

# A planning error: stops the command before any write
.skill_plan_error <- function(code, message, path = NULL) .skill_stop(code, message, path = path)

# --- Copy states -------------------------------------------------------------

# S is older than E: a lower Cloud version of the same identity, or a package
# whose history doesn't include the version the project holds
.skill_is_older <- function(S, E) {
  b <- E$base
  if (is.null(S) || is.null(b)) return(FALSE)
  # Cloud versions compare only when the same server delivered both
  if (identical(S$channel, "cloud") && identical(b$channel, "cloud")) {
    return(identical(S$server, b$server) && isTRUE(as.integer(S$version %||% 0L) < as.integer(b$version %||% 0L)))
  }
  if (identical(S$channel, "package") && identical(b$channel, "package")) return(!b$hash %in% S$known)
  FALSE
}

.skill_state_tracked <- function(p, E, S, disk) {
  h <- disk$hash(p)
  state <- if (identical(h, .skill_unreadable)) "unreadable"
    else if (identical(h, .skill_absent)) { if (disk$folder_exists(dirname(p))) "absent" else "gone" }
    else if (!is.null(S) && identical(h, S$hash) && !.skill_is_older(S, E)) "current"
    else if (identical(h, unname(E$copies[p]))) "clean"
    else "edited"
  list(path = p, state = state, disk = h, tracked = TRUE)
}

.skill_state_untracked <- function(p, E, S, disk) {
  h <- disk$hash(p)
  state <- if (identical(h, .skill_unreadable)) "unreadable"
    else if (identical(h, .skill_absent)) "new"
    else if (length(E$copies)) "loose"
    else if (identical(h, S$hash)) "current"
    else if (h %in% c(E$known, S$known)) "clean"
    else "edited"
  list(path = p, state = state, disk = h, tracked = FALSE)
}

.skill_states_in <- function(C, states) Filter(function(c) c$state %in% states, C)

# Tracked absent copies are restored; new folders are added
.skill_added_or_restored <- function(c) if (identical(c$state, "absent")) "restored" else "added"

# --- Pull, upgrade, and create ------------------------------------------------

.skill_plan_pull <- function(disk, lock, offer, opt) {
  plan <- .skill_plan_new(lock)
  accounted <- character()
  claimed <- character()
  for (S in offer$skills) {
    key <- .skill_key(S$identity)
    E <- lock$skills[[key]]
    extra <- character()
    for (d in opt$dirs) {
      p <- paste0(d, "/", S$name)
      # Two setup names for one folder (a case alias): stop, write nothing
      a <- disk$alias(p)
      if (a %in% names(claimed) && !identical(claimed[[a]], p)) {
        .skill_plan_error("paths_alias", paste0(
          claimed[[a]], " and ", p, " are the same folder on this volume. Give the skills names that differ ",
          "by more than letter case, then pull again."), p)
      }
      claimed[[a]] <- p
      owner <- .skill_owner(lock, p, disk$alias)
      if (identical(owner, key)) next
      if (!is.null(owner)) {
        accounted <- c(accounted, p)
        # An absent copy is planned through its owner's entry (restored or
        # reported missing), never claimed by this skill
        if (identical(disk$hash(p), .skill_absent)) next
        O <- lock$skills[[owner]]
        other_variant <- .skill_other_variant(O$identity, S$identity)
        # skills_move() switches the whole entry: offer it only when the entry
        # has just this copy and the setup's identity isn't tracked yet
        movable <- length(O$copies) == 1 && is.null(E)
        .skill_step(plan, p, owner, "none", "kept", if (other_variant) "other_variant" else "other_identity",
                    if (movable) .skill_hint("retarget", path = p, identity = S$identity), name = S$name)
        plan$kept <- c(plan$kept, p)
        next
      }
      extra <- c(extra, p)
    }
    plan$planned <- c(plan$planned, key)
    .skill_plan_entry(plan, key, E, S, extra, disk, opt)
    accounted <- c(accounted, names(E$copies), extra)
  }

  for (key in names(lock$skills)) {
    E <- lock$skills[[key]]
    if (key %in% plan$planned || identical(opt$scope, "listed")) next
    if (identical(opt$scope, "builtin") && !identical(E$identity$kind, "builtin")) next
    plan$planned <- c(plan$planned, key)
    .skill_plan_unlisted(plan, key, E, offer$by_identity[[key]], disk, opt)
    accounted <- c(accounted, names(E$copies))
  }

  if (identical(offer$source, "cloud") && identical(opt$command, "pull")) {
    seen <- unique(c(accounted, vapply(accounted, disk$alias, "")))
    for (d in opt$dirs) for (name in disk$folders(d)) {
      p <- paste0(d, "/", name)
      if (!p %in% seen && !disk$alias(p) %in% seen) .skill_step(plan, p, NULL, "none", "removed", "not_in_setup")
    }
  }
  plan
}

.skill_plan_entry <- function(plan, key, E, S, extra, disk, opt) {
  E <- E %||% .skill_entry_new(S$identity)
  C <- c(lapply(.skill_sorted(names(E$copies)), .skill_state_tracked, E = E, S = S, disk = disk),
         lapply(.skill_sorted(extra), .skill_state_untracked, E = E, S = S, disk = disk))
  C <- C[order(.skill_paths(C), method = "radix")]
  step <- function(c, action, status, reason = NULL, hint = NULL, ...) {
    .skill_step(plan, c$path, key, action, status, reason, hint, name = S$name, ...)
  }
  all_rows <- function(cs, status, reason = NULL, hint = NULL) for (c in cs) step(c, "none", status, reason, hint)
  states <- vapply(C, `[[`, "", "state")

  if (any(states == "unreadable")) return(all_rows(C, "failed", "unreadable"))
  if (is.null(S$bundle)) return(all_rows(C, "unavailable", "not_shipped"))
  # The package's copy (offline, or upgrade) never writes over a built-in
  # tracked on Cloud. A Cloud setup that names the package copy may.
  if (identical(opt$source, "package") && identical(E$base$channel, "cloud")) {
    if (isTRUE(opt$offline)) return(all_rows(C, "unavailable", "offline"))
    return(all_rows(C, "kept", "cloud_tracked"))
  }

  older <- .skill_is_older(S, E)
  present <- .skill_states_in(C, c("current", "clean", "edited"))
  edited <- .skill_states_in(present, "edited")
  holes <- .skill_states_in(C, c("absent", "new"))
  gone <- .skill_states_in(C, "gone")
  loose <- .skill_states_in(C, "loose")
  for (c in loose) {
    hint <- if (length(present)) .skill_hint_copy(present[[1]]$path, c$path)
      else if (length(gone)) .skill_hint("move", from = gone[[1]]$path, to = c$path)
    step(c, "none", "untracked", "untracked", hint)
  }
  for (c in gone) {
    twin <- Filter(function(l) identical(basename(l$path), basename(c$path)), loose)
    step(c, "none", "missing", "folder_gone",
         if (length(twin)) .skill_hint("move", from = c$path, to = twin[[1]]$path))
  }

  if (length(edited)) {
    if (length(unique(vapply(present, `[[`, "", "disk"))) > 1) {
      src <- if (length(edited) == 1) edited[[1]]$path
      targets <- setdiff(.skill_paths(c(present, holes)), src)
      return(all_rows(c(present, holes), "diverged", "copies_differ", .skill_hint_copy(src, targets)))
    }
    if (length(holes) && (older || !isTRUE(opt$overwrite))) {
      return(all_rows(c(present, holes), "diverged", "copy_absent", .skill_hint_copy(edited[[1]]$path, .skill_paths(holes))))
    }
    # Overwrite never moves to an older version
    if (older) return(for (c in present) step(c, "none", "edited", "newer_in_project"))
    if (!isTRUE(opt$overwrite)) return(for (c in present) step(c, "none", "edited", "local_edits", .skill_hint("overwrite")))
    for (c in present) {
      if (identical(c$state, "current")) step(c, "record", "current")
      else step(c, "write", "replaced", "replaced_edits", backup = TRUE, source = S)
    }
    for (c in holes) step(c, "write", .skill_added_or_restored(c), source = S)
    return(.skill_plan_finish(plan, key, E, S))
  }

  # Unedited copies at different versions (a pull that wrote only some of
  # them) update only to a source that knows every version they hold;
  # otherwise the person picks
  disks <- unique(vapply(present, `[[`, "", "disk"))
  if (length(disks) > 1 && (older || !all(disks %in% c(S$known, S$hash)))) {
    return(all_rows(c(present, holes), "diverged", "copies_differ", .skill_hint_copy(NULL, .skill_paths(c(present, holes)))))
  }

  if (older) {
    # A new copy comes from the copy holding the version the project tracks
    from <- Filter(function(c) identical(c$disk, E$base$hash), present)
    from <- if (length(from)) from[[1]] else if (length(present)) present[[1]]
    for (c in present) step(c, "none", "current", "newer_in_project")
    for (c in holes) {
      if (!is.null(from)) step(c, "copy", .skill_added_or_restored(c), from = from$path)
      else step(c, "none", "unavailable", "setup_older", .skill_hint("login"))
    }
    return(.skill_plan_finish(plan, key, E, NULL))   # copies recorded; base unchanged
  }

  for (c in present) {
    if (identical(c$state, "current")) {
      stale <- !identical(unname(E$copies[c$path]), S$hash) || !.skill_same_base(E$base, .skill_base_of(S))
      step(c, if (stale) "record" else "none", "current")
    } else {
      step(c, "write", "updated", backup = TRUE, source = S)
    }
  }
  for (c in holes) step(c, "write", .skill_added_or_restored(c), source = S)
  .skill_plan_finish(plan, key, E, S)
}

# lock_after for one entry, when any of its steps writes, copies, or records
.skill_plan_finish <- function(plan, key, E, S) {
  steps <- Filter(function(s) identical(s$entry, key), plan$steps)
  if (!any(vapply(steps, function(s) s$action %in% c("write", "copy", "record"), logical(1)))) return(invisible())
  F <- E
  for (s in steps) {
    if (s$action %in% c("write", "record")) F$copies[s$path] <- S$hash
    if (identical(s$action, "copy")) F$copies[s$path] <- unname(E$copies[s$from])
  }
  if (!is.null(S)) {
    F$base <- .skill_base_of(S)
    F$known <- .skill_known(E$known, S$known, S$hash)
    F$pending <- NULL
  }
  plan$lock_after$skills[[key]] <- F
  invisible()
}

# A lock entry the setup doesn't name
.skill_plan_unlisted <- function(plan, key, E, S, disk, opt) {
  C <- lapply(.skill_sorted(names(E$copies)), .skill_state_tracked, E = E, S = S, disk = disk)
  step <- function(c, action, status, reason = NULL, hint = NULL, ...) {
    .skill_step(plan, c$path, key, action, status, reason, hint, ...)
  }
  all_rows <- function(cs, status, reason = NULL, hint = NULL) for (c in cs) step(c, "none", status, reason, hint)
  if (any(vapply(C, function(c) identical(c$state, "unreadable"), logical(1)))) return(all_rows(C, "failed", "unreadable"))
  if (isTRUE(opt$offline)) return(all_rows(C, "unavailable", "offline"))
  present <- .skill_states_in(C, c("current", "clean", "edited"))
  holes <- .skill_states_in(C, "absent")
  if (!length(present)) {
    if (!is.null(S) && length(holes)) {               # fetched by its own identity
      for (c in C) {
        if (identical(c$state, "absent")) step(c, "write", "restored", source = S)
        else step(c, "none", "missing", "folder_gone")
      }
      return(.skill_plan_finish(plan, key, E, S))
    }
    return(all_rows(C, "missing", "all_gone", if (identical(E$identity$kind, "cloud")) .skill_hint("login")))
  }
  edited <- .skill_states_in(present, "edited")
  differ <- length(unique(vapply(present, `[[`, "", "disk"))) > 1
  if (length(edited) && (differ || length(holes))) {
    src <- if (length(edited) == 1) edited[[1]]$path
    return(all_rows(c(present, holes), "diverged", if (differ) "copies_differ" else "copy_absent",
                    .skill_hint_copy(src, setdiff(.skill_paths(c(present, holes)), src))))
  }
  # A folder a setup skill reported as kept is not also removed
  kept <- vapply(plan$kept, disk$alias, "")
  for (c in C) {
    if (dirname(c$path) %in% opt$dirs && !c$path %in% plan$kept && !disk$alias(c$path) %in% kept) {
      step(c, "none", "removed", "not_in_setup")
    }
  }
}

# --- Copy ----------------------------------------------------------------------

# from_dir and to_dirs: skills folders. `all`: names is every skill in
# from_dir, so skills only in a target are listed as missing.
.skill_plan_copy <- function(disk, lock, from_dir, to_dirs, names, all = FALSE) {
  plan <- .skill_plan_new(lock)
  for (t in to_dirs) {
    planned <- character()
    for (n in names) {
      src <- paste0(from_dir, "/", n); dst <- paste0(t, "/", n)
      # The source must be a readable skill; the target, when present, too
      if (identical(disk$hash(src), .skill_absent)) {
        .skill_plan_error("copy_source_missing", paste0(src, " doesn't exist, so there is nothing to copy."), src)
      }
      if (identical(disk$hash(src), .skill_unreadable)) {
        .skill_plan_error("copy_source_unreadable", paste0(src, " isn't a valid skill (", disk$error(src) %||% "no SKILL.md",
                                                           "). Nothing was copied."), src)
      }
      if (identical(disk$hash(dst), .skill_unreadable)) {
        .skill_plan_error("copy_target_unreadable", paste0(dst, " isn't a valid skill (", disk$error(dst) %||% "no SKILL.md",
                                                           "). Move it aside, then copy again. Nothing was copied."), dst)
      }
      E <- .skill_owner(lock, src, disk$alias); D <- .skill_owner(lock, dst, disk$alias)
      if (!is.null(D) && !is.null(E) && !identical(D, E)) {
        .skill_plan_error("copy_target_owned", paste0(
          "Target ", dst, " belongs to another skill (tracked separately in .framework/skills.lock.json). ",
          "Nothing was copied."), dst)
      }
      same <- identical(disk$hash(dst), disk$hash(src))
      # A copy left as it is keeps its folder's spelling on disk
      if (same && !is.null(disk$spell)) dst <- disk$spell(dst)
      .skill_step(plan, dst, E, if (same) "none" else "copy", if (same) "current" else "copied",
                  name = n, from = src, backup = !same && !identical(disk$hash(dst), .skill_absent))
      planned <- c(planned, disk$alias(dst))
      # A tracked source: the target joins its entry with the source's record
      if (!is.null(E)) {
        target <- .skill_owner(plan$lock_after, dst, disk$alias)
        spelled <- if (identical(target, E)) {
          names(plan$lock_after$skills[[E]]$copies)[vapply(names(plan$lock_after$skills[[E]]$copies), function(p) {
            identical(disk$alias(p), disk$alias(dst))
          }, logical(1))][1]
        } else dst
        source_path <- .skill_lock_path(lock$skills[[E]], src, disk$alias)
        plan$lock_after$skills[[E]]$copies[spelled] <- unname(lock$skills[[E]]$copies[source_path])
      }
    }
    if (all) {
      for (n in disk$folders(t)) {
        p <- paste0(t, "/", n)
        if (!disk$alias(p) %in% planned) .skill_step(plan, p, NULL, "none", "missing", name = n)
      }
    }
  }
  plan
}

# An entry's copy path for `path`, by spelling or filesystem identity
.skill_lock_path <- function(E, path, alias = identity) {
  if (path %in% names(E$copies)) return(path)
  target <- alias(path)
  for (p in names(E$copies)) if (identical(alias(p), target)) return(p)
  path
}

# --- Push ------------------------------------------------------------------------

.skill_plan_push <- function(disk, lock, offer, opt) {
  plan <- .skill_plan_new(lock)
  tracked <- unlist(lapply(lock$skills, function(e) names(e$copies)), use.names = FALSE)
  tracked <- unique(c(tracked, vapply(tracked, disk$alias, "")))
  untracked <- character()
  for (d in opt$dirs) for (n in disk$folders(d)) {
    p <- paste0(d, "/", n)
    if (!p %in% tracked && !disk$alias(p) %in% tracked) untracked <- c(untracked, p)
  }
  absent_all <- function(E) length(E$copies) && all(vapply(names(E$copies), function(p) identical(disk$hash(p), .skill_absent), logical(1)))
  # Twin rule: an untracked folder is a hand-moved copy of an absent copy of
  # any entry when it has that copy's name (in another folder) or holds its
  # recorded bytes (a rename). A match counts only when it is the copy's
  # only match and the folder's only match (and, for an entry with no copy
  # left, the entry's only match).
  twins <- list()
  for (key in names(lock$skills)) {
    E <- lock$skills[[key]]
    absent <- Filter(function(p) identical(disk$hash(p), .skill_absent), .skill_sorted(names(E$copies)))
    for (cp in absent) for (u in untracked) {
      if (identical(basename(u), basename(cp)) || identical(disk$hash(u), unname(E$copies[cp]))) {
        twins[[length(twins) + 1L]] <- list(key = key, from = cp, to = u)
      }
    }
  }
  twin_froms <- vapply(twins, `[[`, "", "from"); twin_tos <- vapply(twins, `[[`, "", "to")
  unique_twin <- function(t) sum(twin_froms == t$from) == 1 && sum(twin_tos == t$to) == 1

  for (key in names(lock$skills)) {
    E <- lock$skills[[key]]
    C <- lapply(.skill_sorted(names(E$copies)), .skill_state_tracked, E = E, S = NULL, disk = disk)
    step_all <- function(action, status, reason = NULL, hint = NULL) {
      for (c in C) .skill_step(plan, c$path, key, action, status, reason, hint)
    }
    if (any(vapply(C, function(c) identical(c$state, "unreadable"), logical(1)))) { step_all("none", "failed", "unreadable"); next }
    present <- .skill_states_in(C, c("clean", "edited"))
    if (!length(present)) {
      mine <- Filter(function(t) identical(t$key, key), twins)
      if (length(mine) == 1 && unique_twin(mine[[1]])) {
        step_all("none", "missing", "folder_gone", .skill_hint("move", from = mine[[1]]$from, to = mine[[1]]$to))
      } else if (length(mine)) {
        step_all("none", "missing", "folder_gone")     # more than one match: no hint
      } else {
        step_all("none", "missing", "all_gone")
      }
      next
    }
    edited <- .skill_states_in(present, "edited")
    if (!length(edited)) next                        # nothing to push
    holes <- .skill_states_in(C, "absent")
    differ <- length(unique(vapply(present, `[[`, "", "disk"))) > 1
    if (differ || length(holes)) {
      # One absent copy with a unique twin was moved by hand: move it back
      # into the lock rather than copy over it
      moved <- if (!differ && length(holes) == 1) Filter(function(t) identical(t$from, holes[[1]]$path) && unique_twin(t), twins)
      if (length(moved)) {
        step_all("none", "failed", "copy_absent", .skill_hint("move", from = moved[[1]]$from, to = moved[[1]]$to))
        next
      }
      src <- if (length(edited) == 1) edited[[1]]$path
      step_all("none", "failed", if (differ) "copies_differ" else "copy_absent",
               .skill_hint_copy(src, setdiff(.skill_paths(c(present, holes)), src)))
      next
    }
    local <- present[[1]]$disk
    R <- offer$remote[[key]]
    if (!is.null(R) && identical(R$hash, local)) {
      step_all("record", "current")                  # Cloud already has it: adopt its version
    } else if (identical(E$identity$kind, "builtin")) {
      step_all("push", "pushed")                     # becomes your own skill
    } else if (is.null(E$base) && !is.null(E$pending) && !isTRUE(opt$force)) {
      # A first push that stopped before its reply: it may have reached Cloud
      step_all("none", "refused", "first_push_pending", .skill_hint("force"))
    } else if (is.null(E$base)) {
      if (isTRUE(opt$force)) step_all("push", "pushed") else step_all("none", "refused", "no_base", .skill_hint("force"))
    } else if (is.null(R) || identical(as.integer(R$version), as.integer(E$base$version))) {
      step_all("push", "pushed")
    } else {
      if (isTRUE(opt$force)) step_all("push", "pushed") else step_all("none", "refused", "cloud_changed", .skill_hint("force"))
    }
  }
  for (p in untracked) {
    mine <- Filter(function(t) identical(t$to, p), twins)
    hint <- if (length(mine) == 1 && unique_twin(mine[[1]])) .skill_hint("move", from = mine[[1]]$from, to = p)
      else if (!length(mine)) .skill_hint("sync", path = p)
    .skill_step(plan, p, NULL, "none", "untracked", "untracked", hint)
  }
  plan
}

# --- Move ------------------------------------------------------------------------

# pairs: list of c(from, to) copy paths. identity: the new identity for the
# entry tracking `from` (retarget), or NULL.
.skill_plan_move <- function(disk, lock, pairs, from = NULL, identity = NULL) {
  plan <- .skill_plan_new(lock)
  for (pair in pairs) {
    src <- pair[[1]]; dst <- pair[[2]]
    E <- .skill_owner(lock, src, disk$alias)
    if (is.null(E)) .skill_plan_error("move_untracked", paste0(src, " isn't tracked in .framework/skills.lock.json, so there is nothing to move."), src)
    src <- .skill_lock_path(lock$skills[[E]], src, disk$alias)
    owner <- .skill_owner(lock, dst, disk$alias)
    # A destination with a record of its own, even in the same entry, is
    # never overwritten
    if (!is.null(owner) && !identical(disk$alias(src), disk$alias(dst))) {
      .skill_plan_error("move_target_owned", paste0(
        dst, " is already tracked in .framework/skills.lock.json", if (!identical(owner, E)) " by another skill",
        ". Pick the copy to keep with skills_copy(), or move to another folder. Nothing was moved."), dst)
    }
    there <- !identical(disk$hash(src), .skill_absent); here <- !identical(disk$hash(dst), .skill_absent)
    if (there && here && !identical(disk$alias(src), disk$alias(dst))) {
      .skill_plan_error("move_target_exists", paste0(dst, " already exists. Remove it or pick another folder; nothing was moved."), dst)
    }
    if (!there && !here) .skill_plan_error("move_nothing", paste0("Neither ", src, " nor ", dst, " exists, so there is nothing to move."), src)
    action <- if (there) "move" else "record"
    .skill_step(plan, dst, E, action, "moved", if (identical(action, "move")) "path_moved" else "lock_moved", from = src)
    copies <- plan$lock_after$skills[[E]]$copies
    record <- unname(copies[src])
    copies <- copies[names(copies) != src]
    copies[dst] <- record
    plan$lock_after$skills[[E]]$copies <- copies
  }
  if (!is.null(identity)) {
    key <- .skill_owner(lock, from, disk$alias)
    if (is.null(key)) .skill_plan_error("move_untracked", paste0(from, " isn't tracked in .framework/skills.lock.json, so there is nothing to switch."), from)
    new_key <- .skill_key(identity, from)
    if (new_key %in% names(lock$skills)) {
      .skill_plan_error("move_identity_exists", paste0(
        "This project already tracks ", new_key, ". Move or remove its copies first."), from)
    }
    E <- plan$lock_after$skills[[key]]
    # A copy's bytes: at its path, or, when this move hasn't renamed it yet,
    # at the path it moves from
    sources <- stats::setNames(vapply(plan$steps, function(s) s$from %||% s$path, ""), vapply(plan$steps, `[[`, "", "path"))
    bytes <- function(p) {
      h <- disk$hash(p)
      if (identical(h, .skill_absent) && p %in% names(sources)) disk$hash(sources[[p]]) else h
    }
    # Unedited copies stay unedited: their records become known hashes
    clean <- names(E$copies)[vapply(names(E$copies), function(p) identical(bytes(p), unname(E$copies[p])), logical(1))]
    F <- .skill_entry_new(identity)
    F$known <- .skill_known(E$copies[clean])
    F$copies <- E$copies
    plan$lock_after$skills[[key]] <- NULL
    plan$lock_after$skills[[new_key]] <- F
    # A moved copy has two steps: the move under the old key, then the
    # retarget under the new one
    for (p in .skill_sorted(names(E$copies))) .skill_step(plan, p, new_key, "record", "moved", "retargeted")
  }
  plan
}

# --- Rows ---------------------------------------------------------------------------

# The order a row takes its status from its steps
.skill_row_precedence <- c("failed", "diverged", "missing", "unavailable", "kept", "untracked", "edited", "replaced",
                           "updated", "restored", "added", "current", "refused", "cancelled", "pushed", "removed",
                           "moved", "copied")

# Steps become result rows. Pull, upgrade, and push: one row per lock entry,
# plus one per untracked, kept, or removed step. Copy and move: one per step.
.skill_rows <- function(steps, command) {
  steps <- Filter(function(s) !is.null(s$status), steps)
  if (!length(steps)) return(list())
  steps <- steps[order(vapply(steps, `[[`, "", "path"), method = "radix")]
  own <- command %in% c("copy", "move")
  groups <- list(); index <- character()
  for (s in steps) {
    alone <- own || is.null(s$entry) || s$status %in% c("untracked", "kept", "removed")
    id <- if (alone) paste0("\r", length(groups)) else s$entry
    if (!alone && id %in% index) {
      g <- match(id, index); groups[[g]] <- c(groups[[g]], list(s))
    } else {
      groups[[length(groups) + 1L]] <- list(s); index <- c(index, id)
    }
  }
  lapply(groups, function(g) {
    statuses <- vapply(g, `[[`, "", "status")
    status <- .skill_row_precedence[min(match(statuses, .skill_row_precedence))]
    first <- g[[which(statuses == status)[1]]]
    list(name = g[[1]]$name, status = status, paths = sort(vapply(g, `[[`, "", "path"), method = "radix"),
         entry = g[[1]]$entry, reason_code = first$reason_code, hint = first$hint, first = first$path,
         from = first$from, detail = first$detail)
  })
}
