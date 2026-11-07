#' Load a model saved with save_model()
#'
#' Reads `<name>.rds` from the models folder with [readRDS()]. framework-py
#' saves models as `<name>.pkl`, which R cannot read.
#'
#' @param name The name it was saved under, without extension.
#' @param public Which models folder to read in a project with private and
#'   public output folders: the public one (`TRUE`) or the private one
#'   (`FALSE`). Default (`NULL`): the private folder, then the public one. In
#'   other projects both are the one models folder.
#'
#' @return The model.
#'
#' @details A file that no longer matches the hash [save_model()] recorded
#'   in framework.db loads with a warning.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' model <- lm(mpg ~ hp + wt, data = mtcars, model = FALSE)
#' save_model(model, "mpg_regression")
#' model <- load_model("mpg_regression")
#' }
#' }
#'
#' @seealso [save_model()]
#' @export
load_model <- function(name, public = NULL) {
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_flag(public, null.ok = TRUE)

  sides <- if (is.null(public)) c(FALSE, TRUE) else public
  folders <- unique(vapply(sides, function(side) .output_dir("models", side), character(1)))
  models <- file.path(folders, paste0(name, ".rds"))
  found <- models[file.exists(models) & !dir.exists(models)]
  if (length(found) == 0) {
    python <- file.path(folders, paste0(name, ".pkl"))
    python <- python[file.exists(python)]
    if (length(python) > 0) {
      stop(sprintf("%s is a model Python saved (.pkl), which R cannot read.", python[1]), call. = FALSE)
    }
    stop(sprintf(
      "No saved model named '%s'. Looked for: %s", name, paste(models, collapse = ", ")
    ), call. = FALSE)
  }
  path <- found[1]
  .fw_check_recorded_model(path)
  model <- readRDS(path)
  message(sprintf("Loaded model from %s", path))
  model
}

# Warn when a model file differs from the hash save_model() recorded
#' @keywords internal
.fw_check_recorded_model <- function(path) {
  con <- tryCatch(.fw_results_connection(create = FALSE), error = function(e) NULL)
  if (is.null(con)) {
    return(invisible(NULL))
  }
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  recorded <- tryCatch(
    DBI::dbGetQuery(con, "SELECT hash FROM results WHERE name = ?", list(.fw_result_name(path)))$hash,
    error = function(e) NULL
  )
  if (length(recorded) == 0 || is.na(recorded[1]) || !nzchar(recorded[1])) {
    return(invisible(NULL))
  }
  if (!identical(as.character(recorded[1]), .fw_hex(.calculate_file_hash(path)))) {
    warning(sprintf("%s changed since save_model() recorded it.", basename(path)), call. = FALSE)
  }
  invisible(NULL)
}

# How many data rows a model carries: the largest nrow() among its data
# frame components (lm's model, glm's data, lme4's frame slot, any list
# element), the length of a kept y, or the rows of a kept x matrix
#' @keywords internal
.fw_model_data_rows <- function(model) {
  if (is.data.frame(model)) {
    return(nrow(model))
  }
  rows <- 0L
  frame <- tryCatch(attr(model, "frame", exact = TRUE), error = function(e) NULL)
  if (is.data.frame(frame)) {
    rows <- max(rows, nrow(frame))
  }
  if (is.list(model)) {
    for (element in model) {
      if (is.data.frame(element)) rows <- max(rows, nrow(element))
    }
    y <- model[["y"]]
    if (is.atomic(y) && length(y) > 1) rows <- max(rows, length(y))
    x <- model[["x"]]
    if (is.matrix(x)) rows <- max(rows, nrow(x))
  }
  as.integer(rows)
}

# save_model(public = TRUE) warns, before saving, when the model holds data
# rows. `note` names the private data the session read (see
# .fw_private_read_note()), so one save gives one warning. TRUE when it warned.
#' @keywords internal
.fw_warn_model_rows <- function(model, name, public, note = "") {
  if (!isTRUE(public)) {
    return(FALSE)
  }
  rows <- .fw_model_data_rows(model)
  if (rows == 0) {
    return(FALSE)
  }
  hint <- if (is.data.frame(model)) {
    "Remove them from the object first."
  } else {
    paste0(
      "Refit with model = FALSE (and without y = TRUE or x = TRUE), or save the estimates ",
      "with save_table() instead."
    )
  }
  if (nzchar(note)) {
    hint <- sprintf("%s This session also read private data (%s).", hint, note)
  }
  warning(sprintf(
    "save_model(public = TRUE): '%s' holds %d data rows, which would be saved to the public models folder with it. %s",
    name, rows, hint
  ), call. = FALSE)
  TRUE
}
