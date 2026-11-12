#' Set up a Framework Cloud project, or Framework's global settings
#'
#' - `setup("fw_...")` with a **project token** from Framework Cloud pulls
#'   that project's definition and creates it locally. The project's `.env`
#'   records the token and its server (`FW_CLOUD_URL`), so [publish()] and the
#'   ledger go back to the server the project came from.
#' - `setup()` with no token creates Framework's global settings file if it is
#'   missing. Manage your defaults at <https://framework.pub> after
#'   [cloud_login()].
#'
#' @param token A project token from Framework Cloud. NULL (default) sets up
#'   the global settings only.
#' @param browse Open the new project's folder (default: TRUE)
#' @param location The project folder to create. If NULL (default), an
#'   interactive session asks `Create the project here (<path>)? [y/n]` for
#'   a folder named for the project in the current directory, or
#'   `Create the project in <path>? [y/n]` for one in a Projects folder: the
#'   project owner's, sent by Framework Cloud with the project, else yours
#'   from Framework Cloud Settings. On n it asks which folder to put it in
#'   (blank for the current directory). A non-interactive session stops and
#'   asks for `location`.
#' @param url The Framework Cloud server that issued the token. Defaults to
#'   `FW_CLOUD_URL`, then the server you last logged in to with
#'   [cloud_login()], then <https://framework.pub>.
#'
#' @return With a token, invisibly, the project_create() result. Without one,
#'   invisibly NULL.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Set up a cloud-defined project by its token
#' framework::setup("1|fw_abc123...")
#'
#' # From a self-hosted server
#' framework::setup("1|fw_abc123...", url = "https://framework.example.edu")
#' }
#' }
#'
#' @seealso [new()], [cloud_login()]
#'
#' @export
setup <- function(token = NULL, browse = TRUE, location = NULL, url = NULL) {
  if (is.character(token) && length(token) == 1) {
    checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
    return(.cloud_setup(token = token, location = location, browse = browse, url = url))
  }

  init_global_config()
  message("Framework's global settings are ready. Manage your defaults at https://framework.pub after cloud_login().")
  invisible(NULL)
}

#' Framework GUI (deprecated)
#'
#' The local GUI is retired. Framework Cloud at <https://framework.pub> manages
#' projects, defaults, and settings.
#'
#' @param ... Ignored.
#'
#' @return Invisibly NULL, with a deprecation warning.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' gui()
#' }
#' }
#'
#' @export
gui <- function(...) {
  .Deprecated(msg = "gui() is deprecated. Visit https://framework.pub for an alternative.")
  invisible(NULL)
}
