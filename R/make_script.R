#' Create an R Script from Stub Template
#'
#' Convenience wrapper for `make_notebook()` that creates R scripts (.R files).
#' This is identical to calling `make_notebook("name.R")`.
#'
#' @param name Character. The script name (with or without .R extension).
#'   Examples: "process-data", "process-data.R"
#' @param dir Character. Directory to create the script in. Uses your project's
#'   configured `directories$scripts` setting. Default: "scripts/". A relative path
#'   starts at the project root, not the working directory.
#' @param stub Character. Name of the stub template to use. Defaults to
#'   "default", the only script stub Framework ships. Create custom stubs in
#'   `stubs/script-{stub}.R`, or save your default with
#'   `write_framework_template("script", ...)`.
#' @param overwrite Logical. Whether to overwrite existing file. Default FALSE.
#'
#' @return Invisible path to created script
#'
#' @details
#' This function is a convenience wrapper that:
#' 1. Ensures the name ends with .R extension
#' 2. Uses `script_dir` config option instead of `notebook_dir`
#' 3. Calls `make_notebook()` with `type = "script"`
#'
#' ## Default Output
#'
#' Scripts are created in the `scripts/` directory by default:
#' ```
#' scripts/
#'   process-data.R
#'   build-features.R
#'   run-model.R
#' ```
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Create script (extension optional)
#' make_script("process-data")
#' make_script("process-data.R")
#'
#' # Use a custom stub: save it as stubs/script-etl.R first
#' make_script("etl-pipeline", stub = "etl")
#'
#' # Create in specific directory
#' make_script("analysis", dir = "analysis/")
#' }
#' }
#'
#' @seealso [make_notebook()] for creating Quarto/RMarkdown notebooks
#' @export
make_script <- function(name, dir = NULL, stub = "default", overwrite = FALSE) {
  # Validate arguments
  checkmate::assert_string(name, min.chars = 1)
  checkmate::assert_string(dir, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(stub, min.chars = 1)
  checkmate::assert_flag(overwrite)

  # Normalize name to include .R extension
  if (!grepl("\\.R$", name, ignore.case = TRUE)) {
    name <- paste0(name, ".R")
  }

  # Get script directory from config if not specified
  if (is.null(dir)) {
    dir <- .get_script_dir_from_config()
  }

  # Call make_notebook with type = "script"
  make_notebook(
    name = name,
    type = "script",
    dir = dir,
    stub = stub,
    overwrite = overwrite
  )
}


# Where scripts go: directories$scripts, the legacy options$script_dir, an
# existing scripts/ folder, or the project root
#' @keywords internal
.get_script_dir_from_config <- function() {
  config <- tryCatch(settings_read(), error = function(e) NULL)
  config$directories$scripts %||% config$options$script_dir %||%
    if (dir.exists("scripts")) "scripts" else "."
}
