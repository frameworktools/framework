# new() through Framework Cloud's resolver. When signed in, new_project()
# sends its choices to POST /api/v2/resolve and builds from the returned
# layers envelope. The person's default envelope is cached per server and
# language, so creation works offline without silently switching to a
# different configuration. The contract is shared with framework-py and fw;
# see inst/conformance/README.md ("Offline creation").

# <config folder>/cache/defaults/<host[_port]>/<language>.json. The port is
# joined with "_", which every platform allows in a folder name.
#' @keywords internal
.fw_defaults_cache_path <- function(url, language = "r") {
  host <- gsub(":", "_", .fw_cloud_host(url), fixed = TRUE)
  file.path(fw_config_dir(), "cache", "defaults", host, paste0(language, ".json"))
}

#' @keywords internal
.fw_defaults_cache_read <- function(url, language = "r") {
  path <- .fw_defaults_cache_path(url, language)
  if (!file.exists(path)) {
    return(NULL)
  }
  cached <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(cached$envelope) || !is.character(cached$fetched_at)) {
    return(NULL)
  }
  cached
}

#' @keywords internal
.fw_defaults_cache_write <- function(url, envelope, revision = NULL, language = "r") {
  path <- .fw_defaults_cache_path(url, language)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cached <- list(
    fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    defaults_revision = revision,
    envelope = envelope
  )
  writeLines(jsonlite::toJSON(cached, auto_unbox = TRUE, null = "null", pretty = TRUE), path)
  invisible(path)
}

# POST /api/v2/resolve. Returns list(status = "ok", envelope, revision,
# notices), or list(status = "offline", reason) for network errors,
# timeouts, and 5xx responses. Authentication errors (401, 403), conflicts
# with a blueprint (422), and other errors stop.
#' @keywords internal
.fw_resolve_request <- function(choices, token, url) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    return(list(status = "offline", reason = "the httr2 package is not installed"))
  }
  req <- httr2::request(paste0(url, "/api/v2/resolve"))
  req <- httr2::req_auth_bearer_token(req, token)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_user_agent(req, paste0("framework-r/", as.character(utils::packageVersion("framework"))))
  req <- httr2::req_body_json(req, choices, auto_unbox = TRUE, null = "null")
  req <- httr2::req_timeout(req, 20)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
    req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
  }

  resp <- tryCatch(httr2::req_perform(req), error = function(e) e)
  if (inherits(resp, "error")) {
    return(list(status = "offline", reason = conditionMessage(resp)))
  }

  code <- httr2::resp_status(resp)
  body <- tryCatch(httr2::resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)
  host <- .fw_cloud_host(url)
  if (code >= 500) {
    return(list(status = "offline", reason = paste0("HTTP ", code)))
  }
  if (code %in% c(401L, 403L)) {
    stop(
      host, " refused your token (HTTP ", code, "). Sign in again with framework::cloud_login(), ",
      "or pass offline = TRUE to create the project without Framework Cloud.",
      call. = FALSE
    )
  }
  if (code == 422L) {
    errors <- unlist(body$errors %||% body$message %||% "The choices conflict with the blueprint.")
    stop("Framework Cloud can't create a project with these choices:\n",
         paste0("  - ", errors, collapse = "\n"), call. = FALSE)
  }
  if (code >= 400) {
    stop("Framework Cloud request failed (HTTP ", code, ")",
         if (!is.null(body$message)) paste0(": ", body$message), call. = FALSE)
  }

  headers <- httr2::resp_headers(resp)
  header <- function(name) unlist(headers[tolower(names(headers)) == name], use.names = FALSE)
  list(
    status = "ok",
    envelope = body,
    revision = header("framework-defaults-revision")[1] %||% NULL,
    notices = header("framework-notice")
  )
}

# The envelope to build from, or NULL to build from the package's
# built-ins. Not signed in: NULL, without asking. Signed in: the cloud's
# envelope; offline, the cached defaults when the choices are the language
# alone; otherwise the built-ins only after saying so (asking in an
# interactive session, stopping in a non-interactive one unless
# offline = TRUE).
#' @keywords internal
.fw_new_envelope <- function(choices, offline = FALSE, language = "r") {
  token <- .fw_cloud_token()
  if (is.null(token)) {
    return(NULL)
  }
  url <- .fw_cloud_url()
  host <- .fw_cloud_host(url)
  defaults_only <- length(setdiff(names(choices), c("name", "language"))) == 0

  if (!isTRUE(offline)) {
    res <- .fw_resolve_request(choices, token, url)
    if (identical(res$status, "ok")) {
      for (notice in res$notices) message(notice)
      if (defaults_only) {
        .fw_defaults_cache_write(url, res$envelope, res$revision, language)
      } else {
        .fw_refresh_defaults_cache(token, url, language)
      }
      message("[ok] Resolved by ", host)
      return(res$envelope)
    }
    message(host, " can't be reached (", res$reason, ").")
  }

  cached <- if (defaults_only) .fw_defaults_cache_read(url, language)
  if (!is.null(cached)) {
    message("Using your Framework Cloud defaults from ", substr(cached$fetched_at, 1, 10))
    return(cached$envelope)
  }

  builtins <- "Creating the project from Framework's built-in defaults, not your Framework Cloud defaults."
  if (isTRUE(offline)) {
    message(builtins)
    return(NULL)
  }
  why <- if (defaults_only) {
    "There are no saved Framework Cloud defaults on this computer."
  } else {
    "Choices beyond the language need a connection to Framework Cloud."
  }
  if (rlang::is_interactive()) {
    message(why)
    if (!isTRUE(utils::askYesNo("Create the project from Framework's built-in defaults instead?", default = FALSE))) {
      stop("Cancelled: no project was created.", call. = FALSE)
    }
    message(builtins)
    return(NULL)
  }
  stop(why, " Pass offline = TRUE to create the project from Framework's built-in defaults.", call. = FALSE)
}

# After resolving a project with explicit choices, refresh the cached
# defaults with a second, language-only request. Never fails creation.
#' @keywords internal
.fw_refresh_defaults_cache <- function(token, url, language = "r") {
  tryCatch({
    res <- .fw_resolve_request(list(language = language), token, url)
    if (identical(res$status, "ok")) .fw_defaults_cache_write(url, res$envelope, res$revision, language)
  }, error = function(e) NULL)
  invisible(NULL)
}

# The choices new_project() sends: the language, the name, and only what the
# caller chose. Framework's structures are its system blueprints.
#' @keywords internal
.fw_new_choices <- function(name, type = NULL, workflow = NULL, tools = NULL,
                            package_sets = NULL, skill_sets = NULL) {
  choices <- list(language = "r", name = name)
  if (!is.null(type)) choices$blueprint <- paste0("framework/", type)
  if (!is.null(workflow)) choices$workflow <- workflow
  if (!is.null(tools)) {
    choices$tools <- if (is.character(tools)) {
      stats::setNames(as.list(rep(TRUE, length(tools))), tools)
    } else {
      as.list(tools)
    }
  }
  if (!is.null(package_sets)) choices$package_sets <- as.list(package_sets)
  if (!is.null(skill_sets)) choices$skill_sets <- as.list(skill_sets)
  choices
}
