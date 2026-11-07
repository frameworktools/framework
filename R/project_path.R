#' A path from the project root
#'
#' Joins its arguments under the project root and returns an absolute path,
#' like `here::here()`. The same call gives the same path from any folder in
#' the project, so code in `notebooks/` and a script in the root find the same
#' file. The file need not exist. framework-py calls it `fw.path()`.
#'
#' @param ... Path parts relative to the project root, joined in order. A part
#'   may hold slashes (`"outputs/tables"`). No parts gives the root itself. An
#'   absolute or rooted part (`"/etc"`, `"C:/data"`, `"\\data"`, `"~/x"`) is an
#'   error.
#' @return The absolute path, a character string. The root is written with
#'   forward slashes on every system.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' project_path()                            # The project root
#' project_path("outputs/tables", "incidence.csv")  # From any folder in the project
#' file.exists(project_path("outputs", "tables", "incidence.csv"))
#' }
#' }
#' @export
project_path <- function(...) {
  parts <- list(...)
  for (part in parts) {
    if (!is.character(part) || length(part) != 1 || is.na(part)) {
      stop("project_path() parts must be single character strings", call. = FALSE)
    }
    # Rooted on either system: "/etc", "C:\\data", "C:data", "\\data", or "~"
    if (grepl("^([/\\\\]|~|[A-Za-z]:)", part)) {
      stop(sprintf(
        "project_path() parts are relative to the project root, but '%s' is absolute",
        part
      ), call. = FALSE)
    }
  }

  start <- getwd()
  root <- .find_project_root(start)
  if (is.null(root)) {
    stop(sprintf(
      paste0(
        "No Framework project found at or above %s. ",
        "A project has settings.yml (or config.yml) in its root folder."
      ),
      normalizePath(start, winslash = "/", mustWork = FALSE)
    ), call. = FALSE)
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  parts <- Filter(nzchar, unlist(parts))
  if (length(parts) == 0) {
    return(root)
  }
  do.call(file.path, c(list(sub("/+$", "", root)), as.list(parts)))
}
