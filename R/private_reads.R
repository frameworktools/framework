# Private data read in this session, and the warning on public saves after it.
# framework-py: _private.note_private_read(), warn_public_save().

# Whether a data file is private by its path: a folder between the project
# root and the file named like private, confidential, or sensitive (the
# security audit's segment rule), or, for a file outside the project,
# "private" anywhere in its full path (macOS's /private/ prefix aside)
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
  if (startsWith(full, "/private/")) {
    full <- substring(full, nchar("/private"))
  }
  grepl("private", full, ignore.case = TRUE)
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
  isTRUE(settings$security$sensitive)
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
