# Copy skills between assistant skills folders, so a skill edited in one
# folder (.claude/skills) matches its copies in the others (.agents/skills).
# framework-py: fw.skills_copy(); fw: fw skills copy.

.skill_copy_statuses <- c("copied", "current", "missing")

# Framework's state (sync lock, lock file, backups); no copy may write into
# or over it
.skill_copy_reserved <- ".framework"

# Assistant names and folder names, each mapped to its skills folder:
# claude -> .claude/skills; agents, codex, and copilot -> .agents/skills
.skill_copy_names <- function() {
  table <- .ai_assistant_table()
  dirs <- vapply(table, `[[`, "", "skills_dir")
  folders <- unique(dirs)
  names(folders) <- sub("^\\.([^/]+)/skills$", "\\1", folders)
  c(dirs, folders[setdiff(names(folders), names(dirs))])
}

# The folder name for an assistant skills folder ("claude", "agents"), or NULL
.skill_copy_folder_name <- function(dir) {
  folders <- unique(vapply(.ai_assistant_table(), `[[`, "", "skills_dir"))
  if (!dir %in% folders) return(NULL)
  sub("^\\.([^/]+)/skills$", "\\1", dir)
}

.skill_copy_name <- function(name, arg) {
  known <- .skill_copy_names()
  if (!is.character(name) || length(name) != 1 || !name %in% names(known)) {
    stop("`", arg, "` must be one of ", paste0("\"", names(known), "\"", collapse = ", "),
         ". Use `", arg, "_dir` for another folder.", call. = FALSE)
  }
  unname(known[[name]])
}

# A project-relative folder as supplied: no absolute or drive-qualified path,
# no ".." component, and no ":" in any component. Returns it with "/"
# separators and no "." parts.
.skill_copy_dir <- function(dir, arg) {
  checkmate::assert_string(dir, min.chars = 1, .var.name = arg)
  if (grepl("^[/\\\\~]|^[A-Za-z]:", dir)) stop("`", arg, "` must be a project-relative folder: ", dir, call. = FALSE)
  parts <- strsplit(dir, "[/\\\\]+")[[1]]
  if (".." %in% parts) stop("`", arg, "` cannot contain \"..\": ", dir, call. = FALSE)
  if (any(grepl(":", parts, fixed = TRUE))) stop("`", arg, "` cannot contain \":\": ", dir, call. = FALSE)
  parts <- parts[nzchar(parts) & parts != "."]
  if (!length(parts)) stop("`", arg, "` must name a folder inside the project: ", dir, call. = FALSE)
  paste(parts, collapse = "/")
}

# A path's device and inode, or NA when nothing is there
.skill_copy_id <- function(path) {
  force(path)
  info <- tryCatch(fs::file_info(path, follow = FALSE),
                   error = function(e) stop("Could not read ", path, ": ", conditionMessage(e), call. = FALSE))
  if (is.na(info$type)) NA_character_ else paste(info$device_id, info$inode)
}

# Whether the volume holding an existing folder ignores case: the folder, or
# its nearest ancestor with letters in its name, is the same file under its
# name with the case swapped. Without such a name, the platform default.
.skill_case_insensitive_at <- function(path) {
  lower <- paste(letters, collapse = ""); upper <- paste(LETTERS, collapse = "")
  repeat {
    name <- basename(path)
    swapped <- chartr(paste0(lower, upper), paste0(upper, lower), name)
    if (!identical(swapped, name)) {
      alias <- .skill_copy_id(file.path(dirname(path), swapped))
      return(!is.na(alias) && identical(alias, .skill_copy_id(path)))
    }
    parent <- dirname(path)
    if (identical(parent, path)) break
    path <- parent
  }
  .Platform$OS.type == "windows" || identical(Sys.info()[["sysname"]], "Darwin")
}

# A folder's identity: its deepest existing ancestor resolved on disk
# (links, case), then the rest as given. `given` counts the resolved parts;
# the rest compare without case when that ancestor's volume ignores case.
.skill_copy_key <- function(root, relative) {
  parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
  k <- length(parts)
  while (k > 0 && identical(.skill_kind(file.path(root, paste(parts[seq_len(k)], collapse = "/"))), "missing")) k <- k - 1L
  base <- if (k > 0) file.path(root, paste(parts[seq_len(k)], collapse = "/")) else root
  resolved <- normalizePath(base, winslash = "/", mustWork = TRUE)
  head <- strsplit(resolved, "/", fixed = TRUE)[[1]]
  head <- head[nzchar(head)]
  list(parts = c(head, parts[seq_along(parts) > k]), given = length(head), fold = .skill_case_insensitive_at(resolved))
}

# Whether two folders are the same or one is inside the other
.skill_copy_overlap <- function(a, b) {
  for (i in seq_len(min(length(a$parts), length(b$parts)))) {
    x <- a$parts[i]; y <- b$parts[i]
    if (identical(x, y)) next
    fold <- (i > a$given && a$fold) || (i > b$given && b$fold)
    if (!fold || !identical(tolower(x), tolower(y))) return(FALSE)
  }
  TRUE
}
.skill_copy_same <- function(a, b) length(a$parts) == length(b$parts) && .skill_copy_overlap(a, b)

# A target folder and each of its existing parents must be folders
.skill_copy_check_target <- function(root, target) {
  parts <- strsplit(target, "/", fixed = TRUE)[[1]]
  for (k in seq_along(parts)) {
    relative <- paste(parts[seq_len(k)], collapse = "/")
    kind <- .skill_kind(.skill_path(root, relative))
    if (identical(kind, "missing")) return(invisible())
    if (!identical(kind, "directory")) stop("Target is not a folder: ", relative, call. = FALSE)
  }
}

# The skills in a skills folder: its immediate folders that hold a regular
# SKILL.md. Other folders are ignored, as are names starting with "." (the
# installer stages copies in such folders). A symlinked or broken entry that
# isn't a link to a file is an error, as is a folder that can't be read.
.skill_copy_skills <- function(root, dir) {
  path <- .skill_path(root, dir)
  kind <- .skill_kind(path)
  if (identical(kind, "missing")) return(character())
  if (!identical(kind, "directory")) stop("Not a folder: ", dir, call. = FALSE)
  found <- character()
  # Dot names are skipped before any other check
  for (p in sort(.skill_list(path, ignore = function(name) startsWith(name, ".")), method = "radix")) {
    name <- basename(p)
    if (startsWith(name, ".")) next
    kind <- .skill_kind(p)
    if (identical(kind, "symlink")) {
      resolved <- tryCatch(as.character(fs::file_info(p, follow = TRUE)$type), error = function(e) NA_character_)
      if (!identical(resolved, "file")) stop("Skill symlinks are unsupported: ", file.path(dir, name), call. = FALSE)
      next
    }
    if (!identical(kind, "directory")) next
    skill_md <- .skill_kind(file.path(p, "SKILL.md"))
    if (identical(skill_md, "symlink")) stop("Skill symlinks are unsupported: ", file.path(dir, name, "SKILL.md"), call. = FALSE)
    if (identical(skill_md, "file")) found <- c(found, name)
  }
  found
}

# A project path as the filesystem spells it, relative to the root: its
# deepest existing part as on disk (case), then the rest as given
.skill_copy_spelling <- function(root, relative) {
  base <- normalizePath(root, winslash = "/", mustWork = TRUE)
  parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
  for (k in rev(seq_along(parts))) {
    head <- paste(parts[seq_len(k)], collapse = "/")
    full <- tryCatch(normalizePath(file.path(root, head), winslash = "/", mustWork = TRUE), error = function(e) NULL)
    if (!is.null(full) && startsWith(full, paste0(base, "/"))) {
      return(paste(c(substring(full, nchar(base) + 2L), parts[seq_along(parts) > k]), collapse = "/"))
    }
  }
  relative
}

.skill_copy_scan <- function(root, relative) {
  tryCatch(.skill_scan(.skill_path(root, relative)),
           error = function(e) stop(relative, ": ", conditionMessage(e), call. = FALSE))
}

# Stop after a failed copy: undo the copies already made. "No skills were
# changed" only when every undo worked; otherwise name each copy left
# replaced and where its old copy is, including the one being installed.
.skill_copy_fail <- function(done, cause, row) {
  installer <- inherits(cause, "fw_skill_install_error")
  reason <- if (installer) cause$reason else if (inherits(cause, "interrupt")) "interrupted" else sub("\\.$", "", conditionMessage(cause))
  lost <- c(.skill_rollback(done), if (installer) cause$lost)
  displaced <- .skill_displaced_lines(c(done, if (installer) cause$displaced))
  head <- paste0("Skill copy failed", if (!is.null(row)) paste0(" while copying ", row$from, " -> ", row$to), ": ", reason, ".")
  kept <- if (length(displaced)) c("What was copied is kept in the backups:", displaced)
  if (!length(lost)) stop(paste(c(paste(head, "No skills were changed."), kept), collapse = "\n"), call. = FALSE)
  stop(paste(c(paste(head, "These copies were replaced and could not be restored:"), .skill_lost_lines(lost), kept),
             collapse = "\n"), call. = FALSE)
}

#' Copy Skills Between Assistant Skills Folders
#'
#' A project can keep the same skill in several assistant folders:
#' `.claude/skills/` for Claude Code and `.agents/skills/` for Codex and
#' Copilot. [pull_skills()] writes the same copy to each. After one copy is
#' edited, the copies differ and [skills_sync()] stops for that skill
#' ([push_skills()] reports it as failed and continues with the others).
#' `skills_copy()` copies the version to keep over the others.
#'
#' A skill is a folder in the source with a regular `SKILL.md` file.
#' Folders whose names start with `.` are skipped: they are where copies are
#' staged. Each skill's `SKILL.md` and its syncable companion files are
#' copied, with executable modes. Excluded files, such as `.env`, are not
#' copied and stay in the target. Other files that are only in a replaced
#' target copy are removed from it and kept in the backup. A target copy
#' that differs is backed up to `.framework/skills-backups/` before it is
#' replaced, and keeps its folder permissions. Identical copies are left as
#' they are. Skills that are only in a target folder are listed, left alone,
#' and not read. When the source skill is tracked in
#' `.framework/skills.lock.json`, a real run adds each copy to its entry,
#' with the source copy's record, so the copies sync as one skill. An edited
#' source makes an edited copy: [push_skills()] then pushes the edit, and
#' [pull_skills()] keeps both copies. A target that another skill tracks is
#' refused, in dry runs too. A dry run, or an untracked source, leaves the
#' lock alone. To move a copy instead, use [skills_move()].
#'
#' A real run takes the skill sync lock, then reads and checks every source
#' and target before anything is written. A dry run checks the same things.
#' If a copy fails or is interrupted, the copies already made are undone.
#' When one can't be undone, the error names it and its backup.
#'
#' @param from Assistant folder to copy from: `"claude"` (`.claude/skills`)
#'   or `"agents"` (`.agents/skills`). `"codex"` and `"copilot"` also name
#'   `.agents/skills`.
#' @param to Assistant folder to copy to, named as for `from`. By default,
#'   every other assistant skills folder in the project.
#' @param skills Names of the skills to copy. `NULL` copies every skill in
#'   the source folder.
#' @param from_dir,to_dir Project-relative skills folders, in place of `from`
#'   and `to`. Folder names and directories can't be mixed. The folders can't
#'   be the same or one inside the other, and neither can be in or contain
#'   `.framework/`.
#' @param project_path Path to the project directory (default: current directory).
#' @param dry_run Report what would be copied and write nothing.
#' @return Invisibly, a list: `dry_run`, `from` (the source folder), `to`
#'   (the target folders), `skills` (each a list with `name`, `status`,
#'   `from`, `to`, and `backup`; status is copied, current, or missing),
#'   `counts` by status, and `message` (the summary line). A missing skill is
#'   in a target folder but not in the source, and is kept; its `from` is
#'   `NULL`. `backup` is the backup folder of a replaced copy, else `NULL`.
#' @seealso [pull_skills()], [push_skills()], [skills_sync()], [skills_move()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Keep the Claude Code copies and copy them to .agents/skills
#' skills_copy(from = "claude", dry_run = TRUE)
#' skills_copy(from = "claude", to = "agents")
#' skills_copy(from = "claude", skills = "ggplot2-figures")
#' skills_copy(from_dir = ".claude/skills", to_dir = "some/other/skills")
#' }
#' }
skills_copy <- function(from = NULL, to = NULL, skills = NULL, from_dir = NULL, to_dir = NULL,
                        project_path = ".", dry_run = FALSE) {
  checkmate::assert_flag(dry_run)
  if (!is.null(skills)) {
    checkmate::assert_character(skills, any.missing = FALSE, min.chars = 1)
    if (!length(skills)) stop("`skills` is empty. Omit it to copy every skill.", call. = FALSE)
    skills <- unique(skills)
  }
  if (!is.null(from) && !is.null(from_dir)) stop("Pass `from` or `from_dir`, not both.", call. = FALSE)
  if (!is.null(to) && !is.null(to_dir)) stop("Pass `to` or `to_dir`, not both.", call. = FALSE)
  if (is.null(from) && is.null(from_dir)) stop("Pass `from` (an assistant folder name) or `from_dir`.", call. = FALSE)
  if ((!is.null(from) && !is.null(to_dir)) || (!is.null(from_dir) && !is.null(to))) {
    stop("Use folder names (`from`, `to`) or directories (`from_dir`, `to_dir`), not both kinds.", call. = FALSE)
  }
  source <- if (!is.null(from)) .skill_copy_name(from, "from") else .skill_copy_dir(from_dir, "from_dir")
  target <- if (!is.null(to)) .skill_copy_name(to, "to") else if (!is.null(to_dir)) .skill_copy_dir(to_dir, "to_dir")
  root <- .skill_pull_root(project_path)

  # A real run takes the sync lock before it looks at any skill folder
  if (!dry_run) {
    lock <- .skill_acquire(root)
    on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  }

  if (.skill_copy_overlap(.skill_copy_key(root, source), .skill_copy_key(root, .skill_copy_reserved))) {
    stop("Skills can't be copied from, into, or over Framework's .framework folder: ", source, call. = FALSE)
  }
  # The lock is read and checked before anything is written, so a lock that
  # can't be read never leaves a target overwritten
  lock_state <- tryCatch(.skill_load(root), error = function(e) {
    if (inherits(e, "fw_skill_error")) stop(e)
    stop("Could not read .framework/skills.lock.json (", conditionMessage(e), "). Nothing was copied.", call. = FALSE)
  })
  source_kind <- .skill_kind(.skill_path(root, source))
  if (identical(source_kind, "missing")) stop("Source skills folder not found: ", source, call. = FALSE)
  if (!identical(source_kind, "directory")) stop("Source is not a folder: ", source, call. = FALSE)
  available <- .skill_copy_skills(root, source)
  names <- skills %||% available
  unknown <- setdiff(names, available)
  if (length(unknown)) {
    # A folder without a valid SKILL.md is unreadable; no folder is missing
    there <- dir.exists(file.path(root, source, unknown))
    if (any(there)) {
      .skill_stop("copy_source_unreadable", paste0("Not a valid skill in ", source, " (no regular SKILL.md): ",
                                                    paste(unknown[there], collapse = ", "), ". Nothing was copied."))
    }
    .skill_stop("copy_source_missing", paste0("Not in ", source, ": ", paste(unknown, collapse = ", "), ". Nothing was copied."))
  }

  source_key <- .skill_copy_key(root, source)
  targets <- if (!is.null(target)) target else {
    dirs <- unique(vapply(.ai_assistant_table(), `[[`, "", "skills_dir"))
    dirs <- Filter(function(d) {
      !identical(.skill_kind(.skill_path(root, d)), "missing") && !.skill_copy_same(.skill_copy_key(root, d), source_key)
    }, dirs)
    if (!length(dirs)) stop("No other assistant skills folder in this project to copy to. Pass `to` or `to_dir`.", call. = FALSE)
    sort(unlist(dirs), method = "radix")
  }
  for (t in targets) {
    key <- .skill_copy_key(root, t)
    if (.skill_copy_same(key, source_key)) stop("The source and target are the same folder: ", source, " and ", t, call. = FALSE)
    if (.skill_copy_overlap(key, source_key)) {
      stop("The source and target folders overlap: ", source, " and ", t, ". Neither can be inside the other.", call. = FALSE)
    }
    if (.skill_copy_overlap(key, .skill_copy_key(root, .skill_copy_reserved))) {
      stop("Skills can't be copied from, into, or over Framework's .framework folder: ", t, call. = FALSE)
    }
    .skill_copy_check_target(root, t)
  }

  # Paths are reported and recorded as the filesystem spells them
  source <- .skill_copy_spelling(root, source)
  targets <- unname(vapply(targets, function(t) .skill_copy_spelling(root, t), ""))

  # Read and check every source and target before writing anything
  bundles <- lapply(stats::setNames(nm = names), function(name) .skill_copy_scan(root, file.path(source, name)))
  disk <- .skill_disk(root)
  # Skills only in a target: its folders with a regular SKILL.md
  disk$folders <- function(d) .skill_copy_skills(root, d)
  for (t in targets) for (name in names) {
    to_path <- file.path(t, name)
    kind <- .skill_kind(.skill_path(root, to_path))
    if (!kind %in% c("missing", "directory")) stop("Target is not a folder: ", to_path, call. = FALSE)
    if (identical(kind, "directory")) .skill_copy_scan(root, to_path)
  }
  # A target another skill's lock entry tracks is refused, in dry runs too.
  # An untracked source may be copied onto a tracked path: that is how a
  # hand-made copy is adopted (the lock is left as it is). A tracked
  # source's copies join its entry with its record.
  plan <- .skill_plan_copy(disk, lock_state, source, targets, names, all = is.null(skills))
  results <- lapply(plan$steps, function(s) {
    list(name = s$name, status = s$status, from = if (!identical(s$status, "missing")) s$from, to = s$path,
         backup = NULL, expected = if (identical(disk$hash(s$path), .skill_absent)) NULL else disk$hash(s$path))
  })

  if (!dry_run) {
    journal <- new.env(); journal$done <- list()
    row <- NULL
    # Interrupts too: the copies already made are undone
    outcome <- tryCatch({
      for (i in seq_along(results)) {
        if (!identical(results[[i]]$status, "copied")) next
        row <- results[[i]]
        swaps <- .skill_install(root, row$to, bundles[[row$name]], row$expected, journal = journal)
        results[[i]]["backup"] <- list(swaps[[1]]$backup)
      }
      NULL
    }, error = identity, interrupt = identity)
    if (!is.null(outcome)) .skill_copy_fail(journal$done, outcome, row)
    recorded <- tryCatch(.skill_save_changed(root, lock_state, plan$lock_after), error = identity)
    if (inherits(recorded, "error")) {
      stop("The skills were copied, but the copies could not be recorded in .framework/skills.lock.json: ",
           conditionMessage(recorded), call. = FALSE)
    }
  }
  results <- lapply(results, function(r) c(r[c("name", "status", "from", "to", "backup")], list(paths = r$to)))

  statuses <- vapply(results, `[[`, "", "status")
  counts <- vapply(.skill_copy_statuses, function(s) sum(statuses == s), integer(1))
  labels <- c(copied = if (dry_run) "to copy" else "copied", current = "up to date",
              missing = paste0("not in ", source, " (kept)"))
  parts <- paste(counts, labels[.skill_copy_statuses])[counts > 0]
  prefix <- if (dry_run) "Skills (dry run, nothing written) from " else "Skills from "
  summary <- paste0(prefix, source, ": ", if (length(parts)) paste(parts, collapse = ", ") else "none")
  message(summary)
  for (r in results) {
    if (identical(r$status, "copied")) {
      message("  ", if (dry_run) "Would copy" else "Copied", ": ", r$from, " -> ", r$to)
      if (!is.null(r$backup)) message("    Backup: ", r$backup)
    } else if (identical(r$status, "missing")) {
      message("  Not in ", source, " (kept): ", r$to)
    }
  }
  invisible(list(dry_run = dry_run, from = source, to = targets, skills = results,
                 counts = as.list(counts), message = summary, steps = plan$steps))
}

# The skills_sync() error for a skill whose copies differ, with the
# skills_copy() call that reconciles it. `a` exists. With missing = TRUE, `b`
# is missing and `a` is the only copy to copy from.
# A command is given only when it copies this skill: never when the copies
# have different names (skills_copy() keeps a skill's name), or when the
# missing copy's name is taken by another folder there (with `root`, as a
# different case on a volume that ignores case).
# `others`: every other copy in the entry. With more than one, the hint
# names a call for each, so running them once reconciles the whole entry.
.skill_diverged_message <- function(a, b, missing = FALSE, root = NULL, others = NULL) {
  if (length(others) > 1) return(.skill_diverged_many(a, others, missing, root))
  name <- basename(a); dir_b <- dirname(b)
  if (!identical(name, basename(b))) {
    return(paste0(a, " and ", b, " are tracked as one skill under different names. Copying keeps a skill's name, ",
                  "so copy the version to keep into the other folder yourself."))
  }
  if (missing && !is.null(root)) {
    taken <- tryCatch(list.files(file.path(root, dir_b), all.files = TRUE, no.. = TRUE), error = function(e) character())
    taken <- taken[tolower(taken) == tolower(name) & taken != name]
    if (length(taken)) {
      return(paste0(b, " is missing, and ", file.path(dir_b, taken[1]), " is a different folder whose name differs ",
                    "only in case. Rename or remove it, then copy ", a, " there."))
    }
  }
  if (missing) return(paste0(b, " is missing. Copy ", a, " over it: ", .skill_copy_call(a, b)))
  paste0(a, " and ", b, " differ. Pick one and copy it over the other: ", .skill_copy_call(a, b),
         " (to keep ", b, ", swap from and to)")
}

# The skills_copy() call that copies the skill at `from` to `to`: folder
# names when both are assistant folders, else directories
.skill_copy_call <- function(from, to) {
  q <- function(x) paste0("\"", x, "\"")
  folder_from <- .skill_copy_folder_name(dirname(from)); folder_to <- .skill_copy_folder_name(dirname(to))
  if (!is.null(folder_from) && !is.null(folder_to)) {
    paste0("skills_copy(from = ", q(folder_from), ", to = ", q(folder_to), ", skills = ", q(basename(from)), ")")
  } else {
    paste0("skills_copy(from_dir = ", q(dirname(from)), ", to_dir = ", q(dirname(to)), ", skills = ", q(basename(from)), ")")
  }
}

# The divergence message for an entry with three or more copies: copy `a`
# over every other copy, one skills_copy() call per target
.skill_diverged_many <- function(a, others, missing, root) {
  for (o in others) {
    single <- .skill_diverged_message(a, o, missing = missing, root = root)
    if (!grepl("skills_copy(", single, fixed = TRUE)) return(single)
  }
  calls <- vapply(others, function(o) .skill_copy_call(a, o), "")
  copies <- c(a, others)
  listed <- paste0(paste(copies[-length(copies)], collapse = ", "), ", and ", copies[length(copies)])
  paste0(listed, if (missing) " don't all exist and match" else " differ",
         ". Pick one and copy it over the others: ", paste(calls, collapse = "; "),
         " (to keep another copy, copy that one over the rest)")
}
