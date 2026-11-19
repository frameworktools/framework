# Skills lock helpers for the skill tests (schema 2)

# The lock entry tracking a path, or an empty list
skill_lock_entry <- function(root, path) {
  state <- .skill_load(root)
  key <- .skill_owner(state, path)
  if (is.null(key)) list() else state$skills[[key]]
}
skill_lock_paths <- function(entry) names(entry$copies)

# A built-in installed from a package folder as the package delivers it,
# through the planner (as project creation does). TRUE when the copy holds
# the source's version afterwards.
skill_install_builtin <- function(source, root, relative, name = basename(relative)) {
  src <- .skill_source(name, .skill_identity("builtin", paste0("framework:", name)), "package", .skill_scan(source))
  status <- .skill_install_sources(root, list(src), dirname(relative))[[name]]
  isTRUE(status %in% c("added", "restored", "updated", "current"))
}
