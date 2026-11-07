# Private data read in this session, and the warning on public saves after it.
# framework-py: _private.note_private_read(), warn_public_save().

# Whether a folder name marks it private: "private" or "..._private", in any
# case. framework-py: _private.is_private_folder_name().
#' @keywords internal
.fw_is_private_folder_name <- function(name) {
  lowered <- tolower(name)
  lowered == "private" | endsWith(lowered, "_private")
}

# macOS keeps /tmp, /var, and /etc under /private; that prefix isn't a
# private folder. Matched as a string, so it reads the same on Windows, where
# normalizePath() adds a drive letter.
#' @keywords internal
.fw_strip_system_private <- function(path) {
  sub("^([A-Za-z]:)?/private/(?=(tmp|var|etc)/)", "\\1/", path, perl = TRUE)
}

#' @keywords internal
.fw_full_path <- function(path) {
  .fw_strip_system_private(normalizePath(path.expand(path), winslash = "/", mustWork = FALSE))
}

# Whether `path` (the folder `under` or a path below it) is `under`
#' @keywords internal
.fw_path_under <- function(path, under) {
  path <- tolower(sub("/+$", "", path))
  under <- tolower(sub("/+$", "", under))
  path == under | startsWith(path, paste0(under, "/"))
}

# The settings folders marked private by key: a directories entry whose key
# contains "private" and not "public" (outputs_private_tables), as full
# paths. framework-py: _private.private_directories().
#' @keywords internal
.fw_private_directories <- function(root = NULL) {
  if (is.null(root)) root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (is.null(root)) return(character())
  settings <- tryCatch(suppressWarnings(settings_read()), error = function(e) NULL)
  dirs <- .configured_directories(settings %||% list())
  keys <- tolower(names(dirs))
  dirs <- dirs[grepl("private", keys, fixed = TRUE) & !grepl("public", keys, fixed = TRUE)]
  if (length(dirs) == 0) return(character())
  unique(vapply(dirs, function(folder) .fw_full_path(.fw_folder_abs(root, folder)),
                character(1), USE.NAMES = FALSE))
}

# The private-path rule for files to upload, shared with framework-py
# (_private.is_private_path()): a path is private when one of its folders
# (not the file name; a folder's own name counts when the path is a folder)
# is named "private" or ends in "_private", in any case, or when it is a
# settings folder marked private or under one. macOS's /private/ system
# prefix doesn't count.
#' @keywords internal
.fw_path_is_private <- function(path, private_dirs = NULL) {
  if (is.null(private_dirs)) private_dirs <- .fw_private_directories()
  vapply(path, function(one) {
    full <- .fw_full_path(one)
    parts <- strsplit(full, "/", fixed = TRUE)[[1]]
    folders <- if (dir.exists(one)) parts else parts[-length(parts)]
    any(.fw_is_private_folder_name(folders)) || any(.fw_path_under(full, private_dirs))
  }, logical(1), USE.NAMES = FALSE)
}

# Whether a quoted string in a notebook is a path with a private folder part,
# or a settings folder marked private or a path under one. The last part
# counts as a folder only when it has no ".", so a file named
# "01-private-notes.qmd" doesn't count. framework-py:
# _private._private_path_string().
#' @keywords internal
.fw_private_path_string <- function(value, root, private_dirs) {
  if (!grepl("[/\\\\]", value)) return(FALSE)
  parts <- strsplit(value, "[/\\\\]")[[1]]
  if (grepl("[/\\\\]$", value)) parts <- c(parts, "")
  last <- parts[length(parts)]
  folders <- if (grepl(".", last, fixed = TRUE)) parts[-length(parts)] else parts
  if (any(.fw_is_private_folder_name(folders))) return(TRUE)
  if (length(private_dirs) == 0 || is.null(root)) return(FALSE)
  candidate <- if (grepl("^(/|[A-Za-z]:[/\\\\]|~)", value)) value else file.path(root, value)
  any(.fw_path_under(.fw_full_path(candidate), private_dirs))
}

# Whether a data file is private by its path: a folder between the project
# root and the file named like private, confidential, or sensitive (the
# security audit's segment rule), or, for a file outside the project, the
# private-path rule (.fw_path_is_private()). framework-py:
# _private.is_private_data().
#' @keywords internal
.fw_is_private_data <- function(path) {
  full <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (!is.null(root)) {
    base <- sub("/+$", "", normalizePath(root, winslash = "/", mustWork = FALSE))
    if (startsWith(full, paste0(base, "/"))) {
      folder <- dirname(substring(full, nchar(base) + 2L))
      return(grepl("(^|/)[^/]*(private|confidential|sensitive)[^/]*(/|$)", folder, ignore.case = TRUE))
    }
  }
  .fw_path_is_private(path)
}

# Remember that data_read() read private data, named as the caller gave it
#' @keywords internal
.fw_note_private_read <- function(name, spec) {
  private <- isTRUE(spec$private) || (!is.null(spec$path) && .fw_is_private_data(spec$path))
  reads <- .framework_env$private_reads %||% character()
  if (private && !name %in% reads) {
    .framework_env$private_reads <- c(reads, name)
  }
  invisible(NULL)
}

#' @keywords internal
.fw_project_is_sensitive <- function() {
  root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL)
  if (is.null(root)) {
    return(FALSE)
  }
  settings <- tryCatch(settings_read(), error = function(e) NULL)
  .fw_settings_sensitive(settings)
}

# Whether settings describe a project that holds sensitive data.
# `project_type: project_sensitive` always counts: projects of that type made
# before Framework 2 have no `security:` block. Otherwise
# `security: sensitive:` decides when it is set, and without it the
# privacy-sensitive layout (an inputs_private_* or outputs_private_* folder)
# counts. framework-py: _private.settings_sensitive().
#' @keywords internal
.fw_settings_sensitive <- function(settings) {
  if (!is.list(settings)) return(FALSE)
  if (identical(settings$project_type, "project_sensitive")) return(TRUE)
  flag <- if (is.list(settings$security)) settings$security$sensitive else NULL
  if (!is.null(flag)) return(isTRUE(flag))
  keys <- names(.configured_directories(settings))
  any(grepl("^(inputs|outputs)_private_", keys))
}

# Why settings and the project type disagree about sensitive data, or NULL:
# a project_sensitive project with `security: sensitive: false`, or one with
# no `security:` block at all, which framework::upgrade() adds.
#' @keywords internal
.fw_sensitive_mismatch <- function(settings) {
  if (!is.list(settings) || !identical(settings$project_type, "project_sensitive")) return(NULL)
  flag <- if (is.list(settings$security)) settings$security$sensitive else NULL
  if (isTRUE(flag)) return(NULL)
  if (is.null(flag)) {
    return(paste0("project_type is project_sensitive but settings have no security: block. ",
                  "Framework treats the project as sensitive; run framework::upgrade() to add ",
                  "security: sensitive: true."))
  }
  paste0("project_type is project_sensitive but security: sensitive: is false. ",
         "Framework treats the project as sensitive because of its type.")
}

# In a sensitive project that read private data this session, the names
# read, as "inputs.x, inputs/y.csv, inputs.z, and 2 more"; otherwise ""
#' @keywords internal
.fw_private_read_note <- function() {
  reads <- .framework_env$private_reads %||% character()
  if (length(reads) == 0 || !.fw_project_is_sensitive()) {
    return("")
  }
  shown <- paste(utils::head(reads, 3), collapse = ", ")
  if (length(reads) > 3) {
    shown <- sprintf("%s, and %d more", shown, length(reads) - 3)
  }
  shown
}

# After a public save in a sensitive project that read private data this
# session: the output may have been made from it
#' @keywords internal
.fw_warn_public_save <- function(path, public) {
  shown <- if (isTRUE(public)) .fw_private_read_note() else ""
  if (!nzchar(shown)) {
    return(invisible(FALSE))
  }
  warning(sprintf(paste0(
    "Saved %s as public, and this session read private data (%s). Check that it holds only ",
    "aggregated or de-identified results before sharing it."
  ), basename(path), shown), call. = FALSE)
  invisible(TRUE)
}
