# Move a skill copy to another folder, record a move made by hand, or
# switch the skill a copy tracks. framework-py: skills_move(); fw: fw skills
# move.

# A `from` or `to` as given: an assistant folder name ("claude", "agents",
# "codex", "copilot") is that skills folder; anything else is a
# project-relative path
.skill_move_place <- function(x, arg) {
  known <- .skill_copy_names()
  if (x %in% names(known)) return(list(path = unname(known[[x]]), folder = TRUE))
  list(path = .skill_copy_dir(x, arg), folder = FALSE)
}

#' Move a Skill Copy or Switch Its Skill
#'
#' `.framework/skills.lock.json` tracks each copy of a skill by its folder.
#' `skills_move()` changes what the lock says about a copy, in three ways:
#'
#' - **Move a copy.** `skills_move(".claude/skills/survey-weights",
#'   ".agents/skills/survey-weights")` renames the folder and moves its lock
#'   record with it. Folder names move every tracked copy in a skills folder:
#'   `skills_move("claude", "agents")`.
#' - **Record a move made by hand.** When the folder was already moved (for
#'   example, `.claude` renamed to `.agents`), the same call moves only the
#'   lock record. [pull_skills()] and [push_skills()] print this call when
#'   they find a tracked copy whose folder is gone next to an untracked
#'   folder of the same name.
#' - **Switch the skill a copy tracks.** `skill_id`, `builtin`, or `variant`
#'   retarget the copy's lock entry to another identity: your own Cloud
#'   skill (`skill_id`, on the project's server), a Framework built-in
#'   (`builtin = "framework-data"`), or another language variant of the same
#'   skill (`variant`). [pull_skills()] prints this call when a folder tracks
#'   a different skill than the setup names. Unedited copies stay unedited,
#'   so the next pull updates them to the new skill's version. Edited copies
#'   stay edited, and [push_skills()] refuses them until `force = TRUE`,
#'   since the new skill has no pulled version to push over.
#'
#' Every check runs before anything is written: a target folder that
#' exists, a target the lock already tracks (even for the same skill), a copy
#' that isn't tracked, or an identity the project already tracks stops the
#' move with nothing changed.
#'
#' @param from The copy to move or switch, as a project-relative path, or
#'   an assistant folder name (`"claude"`, `"agents"`) to move every tracked
#'   copy in that skills folder.
#' @param to Where the copy goes: a project-relative path, or an assistant
#'   folder name, which keeps the skill's folder name. `NULL` when only
#'   switching the skill.
#' @param skill_id Your own Cloud skill's ID to switch the copy to. An ID
#'   starting with `framework:` names a built-in.
#' @param variant The language variant to switch to: `"r"`, `"python"`, or
#'   `"stata"`. By default, the copy's current variant.
#' @param builtin A Framework built-in's name to switch the copy to, such as
#'   `"framework-data"`.
#' @param project_path Path to the project directory (default: current directory).
#' @param dry_run Report what would change and write nothing.
#' @return Invisibly, a list: `dry_run`, `skills` (each a list with `name`,
#'   `status` "moved", `paths`, `from`, `reason`, and `reason_code`:
#'   path_moved, lock_moved, or retargeted), and `message`.
#' @seealso [skills_copy()] copies a skill instead; [pull_skills()],
#'   [push_skills()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # After switching from Claude Code to Codex
#' skills_move("claude", "agents", dry_run = TRUE)
#' skills_move("claude", "agents")
#'
#' # Track a copy as your own fork of a built-in
#' skills_move(".claude/skills/framework-data", skill_id = "5d0c2a7e-...")
#' }
#' }
skills_move <- function(from, to = NULL, skill_id = NULL, variant = NULL, builtin = NULL,
                        project_path = ".", dry_run = FALSE) {
  checkmate::assert_string(from, min.chars = 1)
  checkmate::assert_string(to, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(skill_id, min.chars = 1, null.ok = TRUE)
  checkmate::assert_choice(variant, c("r", "python", "stata"), null.ok = TRUE)
  checkmate::assert_string(builtin, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  if (!is.null(skill_id) && !is.null(builtin)) stop("Pass `skill_id` or `builtin`, not both.", call. = FALSE)
  retarget <- !is.null(skill_id) || !is.null(builtin) || !is.null(variant)
  if (is.null(to) && !retarget) stop("Pass `to`, or `skill_id`, `builtin`, or `variant` to switch the skill.", call. = FALSE)
  root <- .skill_pull_root(project_path)
  source <- .skill_move_place(from, "from")
  target <- if (!is.null(to)) .skill_move_place(to, "to")
  for (place in list(source, target)) {
    if (is.null(place)) next
    if (.skill_copy_overlap(.skill_copy_key(root, place$path), .skill_copy_key(root, .skill_copy_reserved))) {
      stop("Skills can't be moved from, into, or over Framework's .framework folder: ", place$path, call. = FALSE)
    }
    .skill_path(root, place$path)
  }

  if (!dry_run) {
    held <- .skill_acquire(root)
    on.exit(unlink(held, recursive = TRUE), add = TRUE)
  }
  lock <- .skill_load(root)
  disk <- .skill_disk(root)
  copies <- unlist(lapply(lock$skills, function(e) names(e$copies)), use.names = FALSE)
  # A path no entry tracks, with tracked copies directly in it, is a skills folder
  folder <- source$folder || (is.null(.skill_owner(lock, source$path, disk$alias)) &&
    any(vapply(dirname(copies), function(d) identical(disk$alias(d), disk$alias(source$path)), logical(1))))

  pairs <- list()
  if (!is.null(target)) {
    if (folder) {
      inside <- copies[vapply(dirname(copies), function(d) identical(disk$alias(d), disk$alias(source$path)), logical(1))]
      if (!length(inside)) {
        .skill_plan_error("move_nothing", paste0("No tracked skill copies in ", source$path, ", so there is nothing to move."),
                          source$path)
      }
      pairs <- lapply(sort(inside, method = "radix"), function(p) c(p, paste0(target$path, "/", basename(p))))
    } else {
      pairs <- list(c(source$path, if (target$folder) paste0(target$path, "/", basename(source$path)) else target$path))
    }
  }

  identity <- NULL
  if (retarget) {
    if (folder) stop("Switch one copy's skill at a time: pass the copy's path as `from`.", call. = FALSE)
    key <- .skill_owner(lock, source$path, disk$alias)
    if (is.null(key)) {
      .skill_plan_error("move_untracked", paste0(source$path, " isn't tracked in .framework/skills.lock.json, so there is nothing to switch."),
                        source$path)
    }
    current <- lock$skills[[key]]$identity
    v <- variant %||% current$variant
    identity <- if (!is.null(builtin)) .skill_identity("builtin", paste0("framework:", builtin), v)
      else if (!is.null(skill_id) && startsWith(skill_id, "framework:")) .skill_identity("builtin", skill_id, v)
      else if (!is.null(skill_id) && startsWith(skill_id, "inline:")) .skill_identity("inline", skill_id, v)
      else if (!is.null(skill_id)) .skill_identity("cloud", skill_id, v, .skill_server(root))
      else if (identical(current$kind, "local")) stop("A local skill has no other variant to switch to. Pass `skill_id` or `builtin`.", call. = FALSE)
      else { current$variant <- v; current }
  }

  plan <- .skill_plan_move(disk, lock, pairs, from = source$path, identity = identity)
  steps <- plan$steps
  if (!dry_run) {
    moved <- list()
    outcome <- tryCatch({
      for (s in steps[order(vapply(steps, `[[`, "", "path"), method = "radix")]) {
        if (!identical(s$action, "move")) next
        to_path <- .skill_path(root, s$path)
        dir.create(dirname(to_path), recursive = TRUE, showWarnings = FALSE)
        if (!isTRUE(.skill_rename(.skill_path(root, s$from), to_path))) stop("Could not move ", s$from, " to ", s$path, call. = FALSE)
        moved[[length(moved) + 1L]] <- s
      }
      .skill_save_changed(root, lock, plan$lock_after)
      NULL
    }, error = base::identity, interrupt = base::identity)
    if (!is.null(outcome)) {
      # Undo the renames already made, newest first; name any that can't be
      stuck <- character()
      for (s in rev(moved)) {
        back <- tryCatch(isTRUE(.skill_rename(.skill_path(root, s$path), .skill_path(root, s$from))), error = function(e) FALSE)
        if (!back) stuck <- c(stuck, paste0("  ", s$from, " is now at ", s$path))
      }
      reason <- if (inherits(outcome, "interrupt")) "interrupted" else sub("\\.$", "", conditionMessage(outcome))
      if (length(stuck)) {
        stop(paste(c(paste0("Skill move failed: ", reason, ". These moves could not be undone:"), stuck), collapse = "\n"),
             call. = FALSE)
      }
      stop("Skill move failed: ", reason, ". Nothing was moved.", call. = FALSE)
    }
  }
  rows <- .skill_rows(steps, "move")
  skills <- .skill_rows_out(rows, list(fn = "skills_move", lock = plan$lock_after, disk = disk))
  for (i in seq_along(skills)) skills[[i]]$from <- rows[[i]]$from
  summary <- paste0(if (dry_run) "Skills (dry run, nothing written): " else "Skills: ", length(skills), " moved")
  message(summary)
  for (skill in skills) message("  ", if (dry_run) "Would move" else "Moved", ": ", skill$paths[1], " \u2014 ", skill$reason)
  invisible(list(dry_run = dry_run, skills = skills, message = summary, steps = steps))
}
