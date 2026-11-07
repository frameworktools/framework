# Backups of files Framework rewrites, for upgrade() and quarto_regenerate().
# They go to .framework/backups/<timestamp>/<path from the project root>.
# .framework/.gitignore ignores backups/, so they never reach git whatever
# the project's .gitignore says. framework-py: _backups.backup_files().

# A new backup folder's path from the root: .framework/backups/<timestamp>
#' @keywords internal
.fw_backup_dir <- function(root) {
  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  rel <- file.path(".framework", "backups", stamp)
  i <- 2
  while (dir.exists(file.path(root, rel))) {
    rel <- file.path(".framework", "backups", paste0(stamp, "-", i))
    i <- i + 1
  }
  rel
}

# Copy the existing files among `paths` (from the root) into the backup
# folder `rel` (from .fw_backup_dir()), keeping their paths. Returns the
# paths copied.
#' @keywords internal
.fw_backup_files <- function(root, paths, rel) {
  paths <- unique(paths[file.exists(file.path(root, paths)) & !dir.exists(file.path(root, paths))])
  if (length(paths) == 0) return(character())
  .fw_ignore_in_framework_dir(root, "backups/")
  copied <- character()
  for (path in paths) {
    target <- file.path(root, rel, path)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (file.copy(file.path(root, path), target, overwrite = TRUE, copy.date = TRUE)) {
      copied <- c(copied, path)
    }
  }
  copied
}

# Add entries to .framework/.gitignore (created if missing), once each
#' @keywords internal
.fw_ignore_in_framework_dir <- function(root, entries) {
  path <- file.path(root, ".framework", ".gitignore")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  missing <- setdiff(entries, trimws(lines))
  if (length(missing) > 0) writeLines(c(lines, missing), path)
  invisible(missing)
}
