#' Register a Local Project on Framework Cloud and Link It
#'
#' Creates the Cloud project for a folder that is already a Framework project
#' (one you adopted with [adopt()] or brought up to date with [upgrade()])
#' and links the folder to it, in one step:
#'
#' 1. Sends `.framework/spec.json` as it is, with the name, slug, and
#'    description, in one request (`POST /api/v1/projects`). Framework Cloud
#'    stores the spec as the project's only layer and as its last-received
#'    spec, so the Cloud project has exactly this folder's name, type,
#'    language, folders, and tools, and none of your defaults. An adopted
#'    project is marked as adopted.
#' 2. Writes the project token and server to `.env` (`FW_PROJECT_TOKEN`,
#'    `FW_CLOUD_URL`), making sure git ignores `.env` first.
#'
#' It needs `.framework/spec.json` (run `upgrade(dry_run = FALSE)` first for
#' an older project), changes nothing in a project that already has a token
#' in `.env`, and refuses when git tracks `.env`. When you already have a
#' project with the slug, it offers to link this folder to that project
#' instead (in an interactive session) and creates nothing. A slug held by a
#' project in your Trash can't be reused. A self-hosted server from before
#' the spec API builds the project from your defaults; the spec is then sent
#' separately (`PUT /api/v1/project/spec`).
#'
#' @param path The project folder (default: the working directory).
#' @param name The Cloud project's name. Default: the spec's name, then the
#'   folder's name.
#' @param slug The project's slug. Default: made from the name (lowercase
#'   letters, digits, and hyphens).
#' @param description An optional description.
#' @param dry_run If TRUE, print the request without sending it.
#' @param include_private A project whose path has a folder named `private`
#'   asks before registering in an interactive session and stops otherwise;
#'   TRUE registers it anyway.
#'
#' @return Invisibly, a list with `slug`, `url`, `type`, `adopted`,
#'   `created`, `linked`, and `spec_changed`; with `dry_run = TRUE`, the
#'   request body.
#'
#' @seealso [adopt()], [upgrade()], [cloud_login()]
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' cloud_register("~/projects/old-study", dry_run = TRUE)
#' cloud_register("~/projects/old-study", slug = "old-study")
#' }
#' }
#'
#' @export
cloud_register <- function(path = ".", name = NULL, slug = NULL, description = NULL,
                           dry_run = FALSE, include_private = FALSE) {
  checkmate::assert_directory_exists(path)
  checkmate::assert_string(name, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(slug, min.chars = 1, null.ok = TRUE)
  checkmate::assert_string(description, null.ok = TRUE)
  checkmate::assert_flag(dry_run)
  checkmate::assert_flag(include_private)
  root <- normalizePath(path, winslash = "/", mustWork = TRUE)

  if (length(.fw_settings_files(root)) == 0) {
    stop("Not a Framework project: ", root, ". Run framework::adopt() first.", call. = FALSE)
  }

  # Already linked: say so and change nothing
  if (!is.null(.fw_project_env_value("FW_PROJECT_TOKEN", root))) {
    message("This project is already linked: .env has FW_PROJECT_TOKEN. Nothing changed. ",
            "To send its spec, run: fw project push-spec")
    return(invisible(list(slug = NULL, url = NULL, type = NULL, adopted = NULL, created = FALSE,
                          linked = TRUE, spec_changed = FALSE)))
  }

  spec_path <- file.path(root, ".framework", "spec.json")
  if (!file.exists(spec_path)) {
    stop("This project has no .framework/spec.json, which Framework Cloud is made from. Run ",
         "framework::upgrade(\"", path, "\", dry_run = FALSE) first, then cloud_register() again.",
         call. = FALSE)
  }
  # Sent as it is on disk, so empty maps stay {}
  spec_json <- paste(readLines(spec_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  spec <- tryCatch(jsonlite::fromJSON(spec_json, simplifyVector = FALSE), error = function(e) {
    stop(".framework/spec.json is not valid JSON: ", conditionMessage(e), call. = FALSE)
  })
  .fw_refuse_tracked_env(root)
  .cloud_register_private_check(root, include_private)

  name <- name %||% spec$name %||% basename(root)
  slug <- slug %||% .cloud_slugify(name)
  if (!grepl("^[a-z0-9]+(-[a-z0-9]+)*$", slug)) {
    stop(sprintf("\"%s\" cannot be a slug: use lowercase letters, digits, and hyphens, as in slug = \"old-study\".",
                 slug), call. = FALSE)
  }
  adopted <- isTRUE(spec$source$adopted)
  body <- .cloud_register_body(spec_json, name, slug, description, adopted)

  url <- .fw_cloud_url()
  host <- .fw_cloud_host(url)
  if (dry_run) {
    message("Framework Cloud request for ", name, " (dry run: nothing sent):")
    message("\nPOST ", url, "/api/v1/projects")
    shown <- jsonlite::fromJSON(body, simplifyVector = FALSE)
    shown$spec <- "<.framework/spec.json>"
    message(jsonlite::toJSON(shown, auto_unbox = TRUE, pretty = TRUE))
    message("\nThen FW_PROJECT_TOKEN and FW_CLOUD_URL go into .env.")
    return(invisible(jsonlite::fromJSON(body, simplifyVector = FALSE)))
  }

  # Create the project from its spec, at its slug, in one request
  token <- .fw_require_token(url)
  res <- .fw_api_request("/api/v1/projects", token, method = "POST", json = body, url = url)
  problem <- .cloud_field_problem(res, "slug")
  if (!is.null(problem)) {
    return(.cloud_slug_taken(root, slug, problem, token, url))
  }
  if (res$status >= 400) {
    stop(res$body$message %||% sprintf("Cloud request failed (HTTP %d)", res$status), call. = FALSE)
  }
  created <- res$body
  message("Created ", created$slug, " on ", host, ": ", created$url)

  # A server from before the spec API ignores the spec and slug, builds the
  # project from the user's defaults, and reports no type. The spec is then
  # sent separately.
  stored <- !is.null(created$type) && nzchar(created$type)
  if (!stored) {
    warning(host, " is older than the spec API, so it made the project from your defaults at ",
            created$slug, ". The spec is sent next; the project's layers stay your defaults until ",
            "the server is updated.", call. = FALSE)
  }

  tryCatch(
    .fw_write_project_token(root, created$token, url),
    error = function(e) {
      stop("Created ", created$slug, " on ", host, ", but linking this folder failed: ",
           conditionMessage(e), ". To finish, run: fw project link --from ", created$slug, call. = FALSE)
    }
  )

  if (!stored) {
    tryCatch({
      .fw_api("/api/v1/project/spec", token = created$token, method = "PUT", body = list(spec = spec), url = url)
      message("Sent .framework/spec.json.")
    }, error = function(e) {
      stop("Created ", created$slug, " on ", host, " and linked this folder, but sending the spec failed: ",
           conditionMessage(e), ". Run: fw project push-spec", call. = FALSE)
    })
  }

  invisible(list(slug = created$slug, url = created$url, type = created$type,
                 adopted = isTRUE(created$adopted), created = TRUE, linked = TRUE, spec_changed = TRUE))
}

# The JSON body of POST /api/v1/projects: the spec as it is on disk, then
# name, slug, description (when given), and adopted (when true)
#' @keywords internal
.cloud_register_body <- function(spec_json, name, slug, description = NULL, adopted = FALSE) {
  fields <- list(name = name, slug = slug)
  if (!is.null(description) && nzchar(description)) fields$description <- description
  if (adopted) fields$adopted <- TRUE
  rest <- as.character(jsonlite::toJSON(fields, auto_unbox = TRUE))
  paste0("{\"spec\":", spec_json, ",", substring(rest, 2))
}

# A slug from a name, as fw makes it: lowercase, each run of other
# characters a hyphen, no hyphen at either end
#' @keywords internal
.cloud_slugify <- function(name) {
  gsub("^-+|-+$", "", gsub("[^a-z0-9]+", "-", tolower(name)))
}

# A request that returns the status and parsed body instead of stopping on
# an error status, for the validation errors by field
#' @keywords internal
.fw_api_request <- function(path, token, method = "GET", json = NULL, url = .fw_cloud_url()) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Cloud features require the 'httr2' package. ",
         'Install it with install.packages("httr2").', call. = FALSE)
  }
  req <- httr2::request(paste0(url, path))
  req <- httr2::req_auth_bearer_token(req, token)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_user_agent(req, paste0("framework-r/", as.character(utils::packageVersion("framework"))))
  req <- httr2::req_method(req, method)
  if (!is.null(json)) req <- httr2::req_body_raw(req, json, type = "application/json")
  if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
    req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
  }
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- httr2::req_perform(req)
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
  list(status = httr2::resp_status(resp), body = body)
}

# The server's first validation error for `field`, or NULL when the
# response isn't a 422 about it
#' @keywords internal
.cloud_field_problem <- function(res, field) {
  if (!identical(as.integer(res$status), 422L)) return(NULL)
  problems <- unlist(res$body$errors[[field]])
  if (length(problems) == 0) NULL else problems[1]
}

# A slug the server refused. One of the user's own projects gets the offer
# to link to it instead (as fw project link --from does); one held by a
# project in the Trash, or a slug refused for another reason, is an error.
#' @keywords internal
.cloud_slug_taken <- function(root, slug, problem, token, url) {
  host <- .fw_cloud_host(url)
  if (grepl("deleted", problem, fixed = TRUE)) {
    stop(slug, " is the slug of a project in your Trash on ", host, ", so it can't be used again. ",
         "Restore that project and run fw project link --from ", slug,
         ", or pass slug = with another name.", call. = FALSE)
  }
  if (!grepl("already have", problem, fixed = TRUE)) {
    stop(host, " refused the slug ", slug, ": ", problem, call. = FALSE)
  }
  if (rlang::is_interactive() &&
      isTRUE(.adopt_ask(sprintf("You already have a project %s on %s. Link this folder to it instead?", slug, host),
                        default = FALSE))) {
    minted <- .fw_api(paste0("/api/v1/projects/", utils::URLencode(slug, reserved = TRUE), "/pull-tokens"),
                      token = token, method = "POST",
                      body = list(name = paste("framework (R) on", Sys.info()[["nodename"]])), url = url)
    .fw_write_project_token(root, minted$token, minted$url %||% url)
    message("To send this folder's spec to it, run: fw project push-spec")
    return(invisible(list(slug = slug, url = NULL, type = NULL, adopted = NULL, created = FALSE,
                          linked = TRUE, spec_changed = FALSE)))
  }
  stop("You already have a project ", slug, " on ", host, ". To link this folder to it, run ",
       "fw project link --from ", slug, ". To create a new project, pass slug = with another name.",
       call. = FALSE)
}

# A project path with a folder named private (or ..._private): ask in an
# interactive session, stop otherwise, unless include_private = TRUE
#' @keywords internal
.cloud_register_private_check <- function(root, include_private) {
  parts <- strsplit(.fw_strip_system_private(root), "/", fixed = TRUE)[[1]]
  if (include_private || !any(.fw_is_private_folder_name(parts))) return(invisible(TRUE))
  if (rlang::is_interactive() &&
      isTRUE(.adopt_ask(paste0(root, " is inside a private folder. Register it on Framework Cloud anyway?"),
                        default = FALSE))) {
    return(invisible(TRUE))
  }
  stop("This project is inside a private folder, so it was not registered. ",
       "Pass include_private = TRUE to register it anyway.", call. = FALSE)
}
