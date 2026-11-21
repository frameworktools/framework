# Display settings: what an embedded artifact shows on other sites. Framework
# Cloud stores them per artifact and applies them to every version; a
# publish names only the settings it changes. The keys are in framework-cloud
# docs/plans/2026-11-21-artifact-display.md, and Cloud refuses others.

.fw_display_keys <- c(
  "title", "description", "author", "credit", "details", "variable_tips", "column_summaries",
  "output", "links", "legend", "analysis", "dagitty", "code", "interactive"
)

# `display` as a named list of TRUE/FALSE, or NULL when not given. Takes a
# named list or a named logical vector, and stops before anything uploads
# when a name isn't a setting or a value isn't a single TRUE or FALSE.
#' @keywords internal
.fw_display_settings <- function(display) {
  if (is.null(display)) return(NULL)
  keys <- paste(.fw_display_keys, collapse = ", ")
  if (!(is.list(display) || is.logical(display)) || is.data.frame(display)) {
    stop("display takes a named list or a named logical vector, ",
         "such as list(analysis = FALSE). Settings: ", keys, ".", call. = FALSE)
  }
  if (!length(display)) return(NULL)
  names <- names(display)
  if (is.null(names) || anyNA(names) || any(!nzchar(names))) {
    stop("Name every display setting, as in list(analysis = FALSE). Settings: ", keys, ".", call. = FALSE)
  }
  unknown <- setdiff(names, .fw_display_keys)
  if (length(unknown)) {
    stop("Unknown display setting", if (length(unknown) > 1L) "s", ": ", paste(unknown, collapse = ", "),
         ". Settings: ", keys, ".", call. = FALSE)
  }
  if (anyDuplicated(names)) {
    stop("Display setting named twice: ", paste(unique(names[duplicated(names)]), collapse = ", "), ".",
         call. = FALSE)
  }
  values <- as.list(display)
  flags <- vapply(values, function(value) is.logical(value) && length(value) == 1L && !is.na(value), logical(1))
  if (!all(flags)) {
    stop("Display settings take TRUE or FALSE: ", paste(names[!flags], collapse = ", "), ".", call. = FALSE)
  }
  stats::setNames(lapply(values, isTRUE), names)
}

# The display form field: a JSON object of settings to booleans.
#' @keywords internal
.fw_display_json <- function(display) {
  as.character(jsonlite::toJSON(display, auto_unbox = TRUE))
}

# Destinations other than Framework Cloud have no display settings.
#' @keywords internal
.fw_display_ignored <- function(display, where) {
  if (!is.null(display)) {
    message("display applies to Framework Cloud only; ignored for ", where, ".")
  }
  invisible(NULL)
}
