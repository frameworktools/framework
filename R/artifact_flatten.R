# Flattening an artifact's versions on Framework Cloud: the newest version
# becomes version 1, and older versions and their files are deleted for
# good. POST /api/v1/artifacts/{slug}/flatten; see framework-cloud's
# artifact API docs.

# The token and server for a Cloud call, resolved as publish() resolves
# them: the project's token on its server, else the account login.
#' @keywords internal
.fw_flatten_auth <- function() {
  token <- .fw_project_token()
  if (!is.null(token)) return(list(token = token, url = .fw_project_cloud_url()))
  url <- .fw_cloud_url()
  list(token = .fw_require_token(url), url = url)
}

#' Flatten an artifact's versions
#'
#' Keeps only an artifact's newest version on Framework Cloud, as version 1.
#' Older versions and their files are deleted for good, Trash included.
#' Links and embeds of an old version open the newest one, and collection
#' and report pins move to version 1. The next publish continues after the
#' highest old version number. Works for every artifact kind; an external
#' publication is refused.
#'
#' Flattening can't be undone, so `flatten_versions()` asks first in a
#' console (default No). In a script, pass `confirm = TRUE`.
#'
#' The project's token is used when the project has one, and it reaches only
#' artifacts in its own project. Otherwise the account login is used (see
#' [cloud_login()]).
#'
#' @param artifact Artifact slug, as given to [publish()].
#' @param project Project slug. Needed with an account login when several
#'   projects have an artifact with this slug. Default: none.
#' @param confirm `TRUE` flattens without asking; `FALSE` cancels. `NULL`
#'   (the default) asks in a console and stops otherwise.
#' @return The artifact's page on Framework Cloud (`artifact_url`),
#'   invisibly, with the number of versions removed in its `removed`
#'   attribute. `NULL` when cancelled.
#' @seealso [publish()]
#' @export
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' flatten_versions("main-results")
#' flatten_versions("main-results", project = "thesis", confirm = TRUE)
#' }
#' }
flatten_versions <- function(artifact, project = NULL, confirm = NULL) {
  checkmate::assert_string(artifact, min.chars = 1)
  checkmate::assert_string(project, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(confirm, null.ok = TRUE)
  auth <- .fw_flatten_auth()
  message("Flattening ", artifact, " keeps only its newest version, as version 1. ",
          "Older versions and their files are deleted for good, Trash included.")
  if (!.fw_confirm(confirm, paste0("Flatten ", artifact, "?"), "flatten_versions()")) {
    message("Cancelled: nothing was changed.")
    return(invisible(NULL))
  }
  path <- paste0("/api/v1/artifacts/", utils::URLencode(artifact, reserved = TRUE), "/flatten")
  if (!is.null(project)) path <- paste0(path, "?project=", utils::URLencode(project, reserved = TRUE))
  res <- .fw_api(path, auth$token, method = "POST", url = auth$url)
  removed <- as.integer(res$removed %||% 0L)
  message(sprintf("Flattened %s to version %s; removed %d older version%s.", res$artifact %||% artifact,
                  res$version %||% 1L, removed, if (removed == 1L) "" else "s"))
  url <- .fw_answer_link(res$artifact_url)
  if (!is.null(url)) message("Manage: ", url)
  if (is.null(url)) url <- NA_character_
  attr(url, "removed") <- removed
  invisible(url)
}
