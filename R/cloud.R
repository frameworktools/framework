# Cloud client for Framework Cloud (framework.pub, or a self-hosted server)
#
# Standalone-first: everything here is opt-in. With no token present, every
# cloud-aware code path falls back to local defaults and the package behaves
# exactly as it always has. HTTP is done via httr2, which is in Suggests --
# cloud functions error with installation guidance when it is missing.

# --- Server resolution ---------------------------------------------------
#
# Framework Cloud is self-hostable, so the server is resolved per call:
#   1. an explicit `url` argument
#   2. FW_CLOUD_URL in the project's .env  (project-scoped calls only)
#   3. the FW_CLOUD_URL environment variable
#   4. the default server saved by cloud_login()  (user-scoped calls only)
#   5. https://framework.pub
#
# Project-scoped calls (publish, the ledger) authenticate with the project's
# token, which is only valid on the server that issued it. They skip the
# login default so a project from framework.pub never sends its token to
# another server. User-scoped calls (login, settings, new()) skip the project
# .env so a user token never goes to a project's server by accident.

.fw_default_cloud_url <- "https://framework.pub"

# Validate and tidy a server URL. Plain http is allowed only for localhost
# (single-user mode on a laptop).
#' @keywords internal
.fw_normalize_cloud_url <- function(url) {
  url <- sub("/+$", "", trimws(url))
  if (!grepl("^[a-zA-Z][a-zA-Z0-9+.-]*://", url)) {
    url <- paste0("https://", url)
  }
  scheme <- tolower(sub("://.*$", "", url))
  host <- .fw_cloud_hostname(url)
  if (!nzchar(host)) {
    stop("Not a server URL: ", url, call. = FALSE)
  }
  if (identical(scheme, "http")) {
    if (!host %in% c("localhost", "127.0.0.1", "[::1]")) {
      stop(
        "Refusing plain http for ", host, ". Use https, or http only for ",
        "localhost and 127.0.0.1 (single-user mode).",
        call. = FALSE
      )
    }
  } else if (!identical(scheme, "https")) {
    stop("Server URLs must start with https:// (got ", scheme, "://).", call. = FALSE)
  }
  url
}

# Host without scheme, port, path, or user info.
#' @keywords internal
.fw_cloud_hostname <- function(url) {
  authority <- sub("^[a-zA-Z][a-zA-Z0-9+.-]*://", "", url)
  authority <- sub("[/?#].*$", "", authority)
  authority <- sub("^.*@", "", authority)
  if (startsWith(authority, "[")) {
    return(tolower(sub("\\].*$", "]", authority)))
  }
  tolower(sub(":.*$", "", authority))
}

# Host and port as people read it ("framework.example.edu", "localhost:8080").
# Names the server in messages and keys its stored token.
#' @keywords internal
.fw_cloud_host <- function(url = NULL) {
  url <- url %||% .fw_cloud_url()
  authority <- sub("^[a-zA-Z][a-zA-Z0-9+.-]*://", "", url)
  authority <- sub("[/?#].*$", "", authority)
  tolower(sub("^.*@", "", authority))
}

#' @keywords internal
.fw_is_default_cloud <- function(url) {
  identical(.fw_cloud_host(url), .fw_cloud_host(.fw_default_cloud_url))
}

#' @keywords internal
.fw_cloud_config_file <- function() {
  file.path(fw_config_dir(), "cloud.yml")
}

# The default server cloud_login() saved, or NULL.
#' @keywords internal
.fw_saved_cloud_url <- function() {
  path <- .fw_cloud_config_file()
  if (!file.exists(path)) {
    return(NULL)
  }
  url <- tryCatch(yaml::read_yaml(path)$server, error = function(e) NULL)
  if (is.character(url) && length(url) == 1 && nzchar(url)) url else NULL
}

#' @keywords internal
.fw_save_cloud_url <- function(url) {
  path <- .fw_cloud_config_file()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(list(server = url), path)
  invisible(path)
}

# A value from the project's .env file, or NULL.
#' @keywords internal
.fw_project_env_value <- function(key, project_dir = ".") {
  env_path <- file.path(project_dir, ".env")
  if (!file.exists(env_path)) {
    return(NULL)
  }
  lines <- readLines(env_path, warn = FALSE)
  hit <- grep(paste0("^", key, "="), lines, value = TRUE)
  if (length(hit) == 0) {
    return(NULL)
  }
  value <- sub(paste0("^", key, "="), "", hit[1])
  value <- gsub('^["\']|["\']$', "", trimws(value))
  if (nzchar(value)) value else NULL
}

# Which server to use, and where that setting came from.
#' @keywords internal
.fw_cloud_server <- function(url = NULL, scope = c("user", "project"), project_dir = ".") {
  scope <- match.arg(scope)
  candidates <- list(
    list(url = url, source = "the url argument"),
    if (identical(scope, "project")) {
      list(url = .fw_project_env_value("FW_CLOUD_URL", project_dir), source = "the project's .env")
    },
    list(url = Sys.getenv("FW_CLOUD_URL", ""), source = "the FW_CLOUD_URL environment variable"),
    if (identical(scope, "user")) {
      list(url = .fw_saved_cloud_url(), source = "your cloud_login() default")
    },
    list(url = .fw_default_cloud_url, source = "the built-in default")
  )
  for (candidate in candidates) {
    value <- candidate$url
    if (is.character(value) && length(value) == 1 && !is.na(value) && nzchar(value)) {
      return(list(url = .fw_normalize_cloud_url(value), source = candidate$source))
    }
  }
}

#' @keywords internal
.fw_cloud_url <- function(url = NULL, scope = c("user", "project")) {
  .fw_cloud_server(url, scope = scope)$url
}

# Token storage. Native-first: the OS credential store via the keyring
# package (macOS Keychain, Windows Credential Manager, Linux Secret
# Service), falling back to a 0600 file in the Framework config dir. Tokens
# are stored per server. Resolution order:
#   1. FW_CLOUD_TOKEN            (env; CI)
#   2. FW_TOKEN_FILE             (explicit file; authoritative when set --
#                                 tests and containers need isolation from
#                                 the developer's real keyring)
#   3. system keyring            (what cloud_login() writes; service
#                                 "framework-cloud:<host>", and the older
#                                 "framework.pub" service for framework.pub)
#   4. <config dir>/cloud-token  (keyring-less systems; cloud-token-<host>
#                                 for servers other than framework.pub)
#   5. ~/.secrets/framework/token (legacy installer location, read-only compat)

.fw_legacy_keyring_service <- "framework.pub"

#' @keywords internal
.fw_keyring_service <- function(url) {
  paste0("framework-cloud:", .fw_cloud_host(url))
}

#' @keywords internal
.fw_token_file <- function(url = .fw_default_cloud_url) {
  if (.fw_is_default_cloud(url)) {
    return(file.path(fw_config_dir(), "cloud-token"))
  }
  file.path(fw_config_dir(), paste0("cloud-token-", gsub("[^a-z0-9.-]", "_", .fw_cloud_host(url))))
}

#' @keywords internal
.fw_legacy_token_file <- function() {
  path.expand(file.path("~", ".secrets", "framework", "token"))
}

#' @keywords internal
.fw_read_token_file <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  token <- trimws(readLines(path, n = 1L, warn = FALSE)[1])
  if (!is.na(token) && nzchar(token)) token else NULL
}

#' @keywords internal
.fw_keyring_get <- function(service) {
  tryCatch(
    {
      token <- keyring::key_get(service, "token")
      if (nzchar(token)) token else NULL
    },
    error = function(e) NULL
  )
}

#' @keywords internal
.fw_keyring_token <- function(url) {
  if (!requireNamespace("keyring", quietly = TRUE)) {
    return(NULL)
  }
  token <- .fw_keyring_get(.fw_keyring_service(url))
  if (is.null(token) && .fw_is_default_cloud(url)) {
    token <- .fw_keyring_get(.fw_legacy_keyring_service)
  }
  token
}

#' @keywords internal
.fw_cloud_token <- function(url = .fw_cloud_url()) {
  env_token <- Sys.getenv("FW_CLOUD_TOKEN", "")
  if (nzchar(env_token)) {
    return(env_token)
  }

  override <- Sys.getenv("FW_TOKEN_FILE", "")
  if (nzchar(override)) {
    # Authoritative when set: never fall through to the real keyring
    return(.fw_read_token_file(path.expand(override)))
  }

  token <- .fw_keyring_token(url) %||% .fw_read_token_file(.fw_token_file(url))
  if (is.null(token) && .fw_is_default_cloud(url)) {
    token <- .fw_read_token_file(.fw_legacy_token_file())
  }
  token
}

#' @keywords internal
.fw_api <- function(path, token, method = "GET", body = NULL, url = .fw_cloud_url()) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop(
      "Cloud features require the 'httr2' package. ",
      'Install it with install.packages("httr2").',
      call. = FALSE
    )
  }

  req <- httr2::request(paste0(url, path))
  req <- httr2::req_auth_bearer_token(req, token)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_user_agent(
    req,
    paste0("framework-r/", as.character(utils::packageVersion("framework")))
  )

  if (!identical(method, "GET")) {
    req <- httr2::req_method(req, method)
  }
  if (!is.null(body)) {
    req <- httr2::req_body_json(req, body)
  }

  # Local development against Herd's self-signed framework.test certificate
  if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
    req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
  }

  req <- httr2::req_error(req, body = function(resp) {
    msg <- tryCatch(
      httr2::resp_body_json(resp)$message,
      error = function(e) NULL
    )
    msg %||% paste0("Cloud request failed (HTTP ", httr2::resp_status(resp), ")")
  })

  httr2::resp_body_json(httr2::req_perform(req))
}

#' @keywords internal
.fw_require_token <- function(url = .fw_cloud_url()) {
  token <- .fw_cloud_token(url)
  if (is.null(token)) {
    login <- if (.fw_is_default_cloud(url)) {
      'framework::cloud_login("fw_...")'
    } else {
      sprintf('framework::cloud_login("fw_...", url = "%s")', url)
    }
    stop(
      "No cloud token found for ", .fw_cloud_host(url), ". Create one at ",
      url, "/tokens and run:\n  ", login,
      call. = FALSE
    )
  }
  token
}

# What connecting enables and transmits -- shown before consent, and the
# text CRAN's "obtaining confirmation from the user" clause is satisfied by.
#' @keywords internal
.fw_consent_notice <- function(url = .fw_cloud_url()) {
  paste0(
    "Connecting this machine to ", url, " enables cloud features\n",
    "that send data to that service when you use them:\n",
    "  - settings sync: your Framework settings document (cloud_sync())\n",
    "  - project registration: project name and type (new())\n",
    "  - integrity ledger: file digests, sizes, and this machine's hostname\n",
    "    (ledger_push(), or each data_save() if you set FW_LEDGER=live)\n",
    "  - publishing: documents you explicitly publish()\n",
    "Your data files themselves are never uploaded unless you publish them.\n",
    "Details: ", url, "/privacy\n"
  )
}

#' Log In to Framework Cloud
#'
#' Shows what connecting shares, asks for confirmation, then verifies the
#' token and stores it in the native credential store for your platform --
#' the macOS Keychain, Windows Credential Manager, or Linux Secret Service
#' (via the `keyring` package) -- falling back to a permission-restricted
#' file in the Framework config directory. This is the whole onboarding:
#'
#' ```r
#' framework::cloud_login("fw_...")
#'
#' # A self-hosted server, or single-user mode on this machine
#' framework::cloud_login("fw_...", url = "https://framework.example.edu")
#' framework::cloud_login("fw_...", url = "http://localhost:8080")
#' ```
#'
#' Tokens are stored per server, and the server you log in to becomes this
#' machine's default for [cloud_status()], [cloud_sync()], and [new()]. The
#' `FW_CLOUD_URL` environment variable overrides that default.
#'
#' @param token Your user token from Framework Cloud (Settings -> API tokens).
#' @param url The Framework Cloud server. Defaults to `FW_CLOUD_URL`, then the
#'   server you last logged in to, then <https://framework.pub>. Plain `http`
#'   is accepted only for `localhost` and `127.0.0.1`.
#' @param verify Check the token against the server before saving (default TRUE).
#' @param consent Set TRUE to confirm non-interactively (scripts, CI). In an
#'   interactive session you are prompted instead. What connecting shares is
#'   printed first and documented at the server's `/privacy` page.
#'
#' @return Invisibly, where the token was stored ("keyring" or the file path).
#'
#' @seealso [cloud_status()], [cloud_logout()], [cloud_settings()]
#' @export
cloud_login <- function(token, url = NULL, verify = TRUE, consent = NULL) {
  checkmate::assert_string(token, min.chars = 10)
  checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
  url <- .fw_cloud_url(url)
  host <- .fw_cloud_host(url)

  if (!isTRUE(consent)) {
    message(.fw_consent_notice(url))
    if (interactive()) {
      answer <- utils::askYesNo(paste0("Connect this machine to ", host, "?"), default = FALSE)
      if (!isTRUE(answer)) {
        stop("Cancelled - this machine was not connected.", call. = FALSE)
      }
    } else {
      stop(
        "cloud_login() needs confirmation. In a non-interactive session, ",
        'call cloud_login(token, consent = TRUE) after reviewing what ',
        "connecting shares (printed above; ", url, "/privacy).",
        call. = FALSE
      )
    }
  }

  if (verify) {
    me <- .fw_api("/api/v1/me", token = token, url = url)
    message("[ok] Token verified on ", host, ": ", me$email %||% me$project %||% "authenticated")
  }

  override <- Sys.getenv("FW_TOKEN_FILE", "")
  stored <- NULL
  service <- .fw_keyring_service(url)

  if (nzchar(override)) {
    # Explicit file mode (tests, containers): honor it exactly
    path <- path.expand(override)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(token, path)
    Sys.chmod(path, mode = "0600")
    stored <- path
    message("[ok] Token saved to ", path, " (FW_TOKEN_FILE)")
  } else if (requireNamespace("keyring", quietly = TRUE)) {
    stored <- tryCatch(
      {
        keyring::key_set_with_value(service, "token", token)
        message("[ok] Token stored in your system keyring (service: ", service, ")")
        "keyring"
      },
      error = function(e) NULL
    )
  }

  if (is.null(stored)) {
    path <- .fw_token_file(url)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(token, path)
    Sys.chmod(path, mode = "0600")
    stored <- path
    message("[ok] Token saved to ", path,
            ' (install.packages("keyring") to use the system credential store)')
  }

  .fw_save_cloud_url(url)
  message("[ok] Default server: ", url)

  # Retire the legacy installer file so only one copy of the secret exists
  legacy <- .fw_legacy_token_file()
  if (!nzchar(override) && .fw_is_default_cloud(url) && file.exists(legacy)) {
    file.remove(legacy)
    message("[ok] Removed legacy token file ", legacy)
  }

  invisible(stored)
}

#' Log Out of Framework Cloud
#'
#' Removes this machine's stored token for a server from the system keyring
#' and any token files. Tokens can also be revoked on the server under API
#' tokens.
#'
#' @param url The server to log out of. Defaults to the server
#'   [cloud_login()] would use.
#'
#' @return Invisibly, TRUE.
#'
#' @export
cloud_logout <- function(url = NULL) {
  checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
  url <- .fw_cloud_url(url)
  removed <- character(0)

  if (requireNamespace("keyring", quietly = TRUE)) {
    services <- .fw_keyring_service(url)
    if (.fw_is_default_cloud(url)) {
      services <- c(services, .fw_legacy_keyring_service)
    }
    for (service in services) {
      tryCatch(
        {
          keyring::key_delete(service, "token")
          removed <- c(removed, paste0("keyring (", service, ")"))
        },
        error = function(e) NULL
      )
    }
  }

  paths <- .fw_token_file(url)
  if (.fw_is_default_cloud(url)) {
    paths <- c(paths, .fw_legacy_token_file())
  }
  for (path in paths) {
    if (file.exists(path)) {
      file.remove(path)
      removed <- c(removed, path)
    }
  }

  if (length(removed) == 0) {
    message("No stored token found for ", .fw_cloud_host(url), ".")
  } else {
    message("[ok] Removed: ", paste(removed, collapse = ", "))
  }

  invisible(TRUE)
}

#' Check Cloud Connection Status
#'
#' Reports which Framework Cloud server is in use and where that setting came
#' from, whether a token is stored for it, and who the token authenticates
#' as. Inside a project set up from a different server, the project's server
#' is reported too.
#'
#' @param url Check this server instead of the default.
#'
#' @return Invisibly, TRUE if connected, FALSE otherwise.
#'
#' @export
cloud_status <- function(url = NULL) {
  checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
  server <- .fw_cloud_server(url)
  message("Server: ", server$url, " (from ", server$source, ")")

  project <- tryCatch(.fw_cloud_server(scope = "project"), error = function(e) NULL)
  if (!is.null(project) && !is.null(.fw_project_token()) &&
      !identical(project$url, server$url)) {
    message("This project publishes to ", project$url, " (from ", project$source, ")")
  }

  token <- .fw_cloud_token(server$url)

  if (is.null(token)) {
    login <- if (.fw_is_default_cloud(server$url)) {
      "cloud_login()"
    } else {
      sprintf('cloud_login(token, url = "%s")', server$url)
    }
    message("Not connected. Run ", login, " to connect.")
    return(invisible(FALSE))
  }

  me <- tryCatch(
    .fw_api("/api/v1/me", token = token, url = server$url),
    error = function(e) {
      message("Token found but ", .fw_cloud_host(server$url),
              " is unreachable or the token is invalid: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(me)) {
    return(invisible(FALSE))
  }

  message("Connected to ", .fw_cloud_host(server$url), " as ", me$email %||% me$project)
  invisible(TRUE)
}

#' Fetch Your Cloud Settings
#'
#' Retrieves your settings document from Framework Cloud. These settings are
#' overlaid on local defaults when creating projects with [new()].
#'
#' @return A list with `revision`, `schema_version`, and `document`.
#'
#' @export
cloud_settings <- function() {
  .fw_api("/api/v1/settings", token = .fw_require_token())
}

# Fetch cloud settings without failing: falls back to the locally cached
# mirror (written by cloud_sync()) when offline, then to NULL -- callers fall
# back to local defaults (the standalone guarantee).
#' @keywords internal
.fw_cloud_settings_quietly <- function() {
  token <- .fw_cloud_token()
  if (is.null(token)) {
    return(NULL)
  }

  tryCatch(
    {
      res <- .fw_api("/api/v1/settings", token = token)
      message("[ok] Using your settings from ", .fw_cloud_host(), " (revision ", res$revision, ")")
      res$document
    },
    error = function(e) {
      cached <- .fw_sync_paths()$document
      if (file.exists(cached)) {
        message("Cloud unreachable (", conditionMessage(e), "). Using cached cloud settings.")
        return(yaml::read_yaml(cached))
      }
      message("Cloud unreachable (", conditionMessage(e), "). Using local defaults.")
      NULL
    }
  )
}

# --- Cloud project registration ------------------------------------------

# Write the project's token and its server into the project's .env
# (gitignored) so publish(), the ledger, and collaborators' setup() go to the
# server the project came from. Never touches settings.yml -- the token is a
# secret. FW_CLOUD_URL is written for every server, framework.pub included:
# a project token is only valid on the server that issued it.
#' @keywords internal
.fw_write_project_token <- function(project_dir, token, url = .fw_default_cloud_url) {
  env_path <- file.path(project_dir, ".env")
  lines <- if (file.exists(env_path)) readLines(env_path, warn = FALSE) else character(0)
  added <- character(0)
  new_lines <- character(0)
  if (!any(grepl("^FW_PROJECT_TOKEN=", lines))) {
    new_lines <- c(new_lines, paste0("FW_PROJECT_TOKEN=", token))
    added <- c(added, "FW_PROJECT_TOKEN")
  }
  if (!any(grepl("^FW_CLOUD_URL=", lines))) {
    new_lines <- c(new_lines, paste0("FW_CLOUD_URL=", url))
    added <- c(added, "FW_CLOUD_URL")
  }
  if (length(new_lines) == 0) {
    return(invisible(FALSE))
  }
  .fw_refuse_tracked_env(project_dir)
  .fw_ensure_env_ignored(project_dir)
  header <- "# Framework Cloud project key and server (created by framework::new or setup)"
  if (length(lines) > 0) {
    lines <- c(lines, "")
  }
  writeLines(c(lines, header, new_lines), env_path)
  message("  Added: ", paste(added, collapse = " and "), " to .env")
  invisible(TRUE)
}

# A .env git already tracks would carry the token into the next commit.
#' @keywords internal
.fw_refuse_tracked_env <- function(project_dir) {
  if (!.git_available() || !file.exists(file.path(project_dir, ".env"))) {
    return(invisible(FALSE))
  }
  status <- suppressWarnings(system2(
    "git", c("-C", shQuote(project_dir), "ls-files", "--error-unmatch", ".env"),
    stdout = FALSE, stderr = FALSE
  ))
  if (identical(as.integer(status), 0L)) {
    stop(
      "Git tracks this project's .env, so a project token written there would be committed. ",
      "Stop tracking it first:\n  git rm --cached .env\n  git commit -m \"Stop tracking .env\"\n",
      "Then run this again.",
      call. = FALSE
    )
  }
  invisible(FALSE)
}

# Make sure git ignores .env before a project token goes into it. In a git
# repository git decides (git check-ignore); otherwise .gitignore's own
# rules do. Either way a missing rule is appended to the project's
# .gitignore. Shared with framework-py.
#' @keywords internal
.fw_ensure_env_ignored <- function(project_dir) {
  git <- function(...) suppressWarnings(system2("git", c("-C", shQuote(project_dir), ...), stdout = FALSE, stderr = FALSE))
  in_repo <- .git_available() && identical(as.integer(git("rev-parse", "--is-inside-work-tree")), 0L)
  if (!in_repo) {
    added <- suppressMessages(.ensure_secrets_ignored(project_dir))
  } else {
    added <- !identical(as.integer(git("check-ignore", "-q", ".env")), 0L)
    if (added) {
      path <- file.path(project_dir, ".gitignore")
      lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character(0)
      writeLines(c(lines, "", "# Secrets (added by Framework)", ".env"), path)
    }
  }
  if (isTRUE(added)) message("  Added .env to .gitignore so the project token stays out of git")
  invisible(isTRUE(added))
}

# Register a locally created project on Framework Cloud and store its key.
# Quiet by design: offline or name-taken just means no cloud registration.
#' @keywords internal
.fw_cloud_register_project <- function(project_dir, name, type) {
  url <- .fw_cloud_url()
  token <- .fw_cloud_token(url)
  if (is.null(token)) {
    return(invisible(NULL))
  }

  res <- tryCatch(
    .fw_api(
      "/api/v1/projects", token = token, method = "POST",
      body = list(name = name, project_type = type, language = "r"), url = url
    ),
    error = function(e) {
      message("Cloud project registration skipped: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(res)) {
    return(invisible(NULL))
  }

  message("[ok] Registered on ", .fw_cloud_host(url), ": ", res$project$slug)
  .fw_write_project_token(project_dir, res$pull_token, url)
  invisible(res)
}

# --- Cloud publishing ----------------------------------------------------

# The project's cloud key: env var (set by dotenv on scaffold()) first, then
# a direct read of ./.env for pre-scaffold sessions.
#' @keywords internal
.fw_project_token <- function(project_dir = ".") {
  env_token <- Sys.getenv("FW_PROJECT_TOKEN", "")
  if (nzchar(env_token)) {
    return(env_token)
  }
  .fw_project_env_value("FW_PROJECT_TOKEN", project_dir)
}

# The server a project's token belongs to.
#' @keywords internal
.fw_project_cloud_url <- function(project_dir = ".") {
  .fw_cloud_server(scope = "project", project_dir = project_dir)$url
}

# Does this project have any storage bucket configured? Errors (no project,
# no settings) mean no.
#' @keywords internal
.fw_has_storage_buckets <- function() {
  tryCatch(
    {
      config <- settings_read()
      length(.collect_all_s3_connections(config)$connections %||% list()) > 0
    },
    error = function(e) FALSE
  )
}

# Zip a directory's contents (relative paths) for bundle upload
#' @keywords internal
.fw_zip_dir <- function(dir) {
  zipfile <- tempfile("fw_bundle_", fileext = ".zip")
  old_wd <- setwd(dir)
  on.exit(setwd(old_wd), add = TRUE)
  files <- list.files(".", recursive = TRUE)
  if (length(files) == 0) {
    stop("Nothing to bundle in ", dir, call. = FALSE)
  }
  utils::zip(zipfile, files, flags = "-q9X")
  if (!file.exists(zipfile)) {
    stop("Failed to create bundle zip (is the 'zip' tool installed?)", call. = FALSE)
  }
  zipfile
}

# Publish a rendered document to the project's Framework Cloud server. Accepts:
#   - self-contained .html (single upload)
#   - .html with a sibling <name>_files/ directory (bundled automatically)
#   - a render output directory (bundled; entry = index.html or the one HTML)
#   - .qmd (rendered: embedded by default, full bundle when self_contained = FALSE)
#   - .Rmd (rendered self-contained)
# Each publish adds a version. `slug` is publish()'s argument: a string names
# the document and turns on its readable URL, TRUE turns it on with the
# derived name, FALSE turns it off, and NULL leaves the setting alone.
#' @keywords internal
.fw_cloud_publish <- function(source, dest = NULL, title = NULL, self_contained = TRUE,
                              slug = NULL, description = NULL, kind = NULL,
                              password = NULL, visibility = NULL, collection = NULL,
                              share_unlisted = FALSE) {
  token <- .fw_project_token()
  selected <- NULL
  if (!is.null(collection)) {
    if (length(collection) != 1L || is.na(collection) ||
        !(is.character(collection) || is.numeric(collection))) {
      stop("collection must be a collection ID or slug.", call. = FALSE)
    }
    rows <- .fw_api("/api/v2/collections", token, url = .fw_project_cloud_url())$collections
    matches <- Filter(function(x) identical(as.character(x$id), as.character(collection)) ||
                        identical(x$slug, as.character(collection)), rows)
    if (length(matches) != 1L) stop("Collection is missing or ambiguous in this project.", call. = FALSE)
    selected <- matches[[1]]
    public <- if (!is.null(slug)) !isFALSE(slug) else if (!is.null(visibility)) visibility == "public" else NULL
    if (identical(selected$visibility, "public") && isFALSE(public)) {
      stop('Public collections require public artifacts. Set visibility = "public".', call. = FALSE)
    }
    if (identical(selected$visibility, "unlisted") && isFALSE(public) && !share_unlisted) {
      stop("Set share_unlisted = TRUE to share an unlisted artifact with collection readers.", call. = FALSE)
    }
  }
  ext <- tolower(tools::file_ext(source))
  html_path <- NULL
  bundle_dir <- NULL
  entrypoint <- NULL

  if (dir.exists(source)) {
    # A render output directory
    bundle_dir <- normalizePath(source)
    htmls <- list.files(bundle_dir, pattern = "\\.html?$")
    entrypoint <- if ("index.html" %in% htmls) "index.html" else htmls[1]
    if (is.na(entrypoint) || is.null(entrypoint)) {
      stop("No HTML file found at the top of ", source, call. = FALSE)
    }
  } else if (ext %in% c("qmd")) {
    quarto <- Sys.which("quarto")
    if (!nzchar(quarto)) {
      stop("Rendering requires the quarto CLI on your PATH.", call. = FALSE)
    }
    out_dir <- tempfile("fw_publish_")
    dir.create(out_dir)
    args <- c("render", shQuote(source), "--output-dir", shQuote(out_dir), "--to", "html")
    if (self_contained) {
      args <- c(args, "--embed-resources")
    }
    status <- system2(quarto, args)
    if (!identical(status, 0L)) {
      stop("Quarto render failed.", call. = FALSE)
    }
    htmls <- list.files(out_dir, pattern = "\\.html$")
    if (length(htmls) == 0) {
      stop("Quarto render produced no HTML output.", call. = FALSE)
    }
    if (self_contained) {
      html_path <- file.path(out_dir, htmls[1])
    } else {
      bundle_dir <- out_dir
      entrypoint <- htmls[1]
    }
  } else if (ext %in% c("rmd")) {
    if (!requireNamespace("rmarkdown", quietly = TRUE)) {
      stop("Rendering .Rmd requires the rmarkdown package.", call. = FALSE)
    }
    html_path <- rmarkdown::render(source, output_format = "html_document",
                                   output_dir = tempfile("fw_publish_"), quiet = TRUE)
  } else if (ext %in% c("html", "htm")) {
    # Quarto's default (non-embedded) output leaves assets in <name>_files/
    files_dir <- paste0(tools::file_path_sans_ext(source), "_files")
    if (dir.exists(files_dir)) {
      stage <- tempfile("fw_publish_")
      dir.create(stage)
      file.copy(source, file.path(stage, basename(source)))
      file.copy(files_dir, stage, recursive = TRUE)
      bundle_dir <- stage
      entrypoint <- basename(source)
    } else {
      html_path <- source
    }
  } else {
    html_path <- source
  }

  readable <- if (is.null(slug)) NULL else !isFALSE(slug)
  if (!is.character(slug)) {
    slug <- dest %||% tools::file_path_sans_ext(basename(source))
  }
  slug <- sub("\\.html?$", "", slug)

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop('Cloud publishing requires httr2. install.packages("httr2")', call. = FALSE)
  }

  req <- httr2::request(paste0(.fw_project_cloud_url(), "/api/v1/documents"))
  req <- httr2::req_auth_bearer_token(req, token)
  req <- httr2::req_headers(req, Accept = "application/json")

  if (!is.null(bundle_dir)) {
    zipfile <- .fw_zip_dir(bundle_dir)
    on.exit(unlink(zipfile), add = TRUE)
    message("Publishing bundle (", length(list.files(bundle_dir, recursive = TRUE)), " files)")
    body <- list(
      bundle = curl::form_file(zipfile, type = "application/zip"),
      entrypoint = entrypoint,
      slug = slug
    )
  } else {
    body <- list(
      file = curl::form_file(html_path),
      slug = slug
    )
  }
  if (!is.null(readable)) {
    # Multipart fields are strings; the API's boolean rule takes "1" and "0"
    body$readable <- if (readable) "1" else "0"
  }
  if (!is.null(title)) {
    body$title <- title
  }
  for (field in c("description", "kind", "password", "visibility")) {
    value <- get(field)
    if (!is.null(value)) body[[field]] <- value
  }
  req <- httr2::req_body_multipart(req, !!!body)
  if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
    req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
  }
  req <- httr2::req_error(req, body = function(resp) {
    tryCatch(httr2::resp_body_json(resp)$message, error = function(e) NULL) %||%
      paste0("Publish failed (HTTP ", httr2::resp_status(resp), ")")
  })

  res <- httr2::resp_body_json(httr2::req_perform(req))

  if (!is.null(res$version)) {
    message("Published version ", res$version, ": ", res$url)
  } else {
    message("Published: ", res$url)
  }
  if (!is.null(res$notice) && nzchar(res$notice)) {
    message(res$notice)
  }
  if (!is.null(selected)) {
    tryCatch({
      if (is.null(res$id)) stop("The server did not return an artifact ID.")
      .fw_api(paste0("/api/v2/collections/", selected$id, "/items"), token,
              method = "POST", url = .fw_project_cloud_url(),
              body = list(document_id = res$id, share_unlisted = share_unlisted))
      message("Added to collection: ", selected$title)
    }, error = function(e) {
      warning("Artifact published at ", res$url, ", but collection attachment failed: ",
              conditionMessage(e), ". Attach it from the project Outputs page; publishing again creates another version.", call. = FALSE)
    })
  }
  invisible(res$url)
}

# --- Data integrity ledger -----------------------------------------------

# Whether per-save live streaming to the cloud ledger is enabled. OFF by
# default: the local framework.db is the ledger of record and ledger_push()
# imports it to the cloud on demand. Live mode ("live"/"on"/"true" via the
# FW_LEDGER env var, or `options: cloud_ledger: live` in settings.yml) makes
# every data_save() stream its digest immediately -- tamper-evident, since
# the entry lands before the file could be altered -- at the cost of a
# network call per save.
#' @keywords internal
.fw_ledger_live <- function() {
  mode <- Sys.getenv("FW_LEDGER", "")
  if (!nzchar(mode)) {
    mode <- tryCatch(
      as.character(settings_read()$options$cloud_ledger %||% ""),
      error = function(e) ""
    )
  }
  tolower(mode) %in% c("live", "on", "true")
}

# Push a digest to the project's cloud ledger after data_save(). Runs only
# in live mode (see .fw_ledger_live). Quiet by design: no project token or
# an unreachable cloud mean "local only", never a failed save. The local
# framework.db stays canonical either way.
#' @keywords internal
.fw_ledger_push_quietly <- function(name, hash, size_bytes = NULL, file_path = NULL) {
  if (!.fw_ledger_live()) {
    return(invisible(NULL))
  }

  # openssl hash objects carry an S3 class jsonlite won't serialize
  hash <- paste0(as.character(hash))
  if (!is.null(size_bytes)) {
    size_bytes <- as.numeric(size_bytes)
  }

  token <- .fw_project_token()
  if (is.null(token)) {
    return(invisible(NULL))
  }

  url <- tryCatch(.fw_project_cloud_url(), error = function(e) NULL)
  if (is.null(url)) {
    return(invisible(NULL))
  }

  if (is.null(size_bytes) && !is.null(file_path) && file.exists(file_path)) {
    size_bytes <- file.size(file_path)
  }

  res <- tryCatch(
    .fw_api(
      "/api/v1/ledger", token = token, method = "POST",
      body = list(
        name = name,
        algo = "sha256",
        hash = hash,
        size_bytes = size_bytes,
        recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
        client = list(
          device = Sys.info()[["nodename"]],
          package_version = as.character(utils::packageVersion("framework"))
        )
      ),
      url = url
    ),
    error = function(e) {
      message("Ledger push skipped: ", conditionMessage(e))
      NULL
    }
  )

  if (!is.null(res)) {
    message("[ok] Ledger entry #", res$sequence, " recorded on ", .fw_cloud_host(url))
  }

  invisible(res)
}

#' Verify a Dataset Against the Integrity Ledger
#'
#' Hashes the file behind a catalog name and compares it against the local
#' framework.db record and the project's cloud ledger on Framework Cloud.
#' Proves "the data I have is bit-identical to what was recorded" without the
#' data ever leaving the machine.
#'
#' @param name Data catalog name (e.g. "inputs.raw.enrollment"), as used with
#'   [data_read()] / [data_save()].
#'
#' @return Invisibly, TRUE when every available record matches.
#'
#' @export
data_verify <- function(name) {
  checkmate::assert_string(name, min.chars = 1)

  config <- settings_read()

  # Catalog names use dot notation but are stored nested (data$inputs$raw$x);
  # accept a flat key too
  entry <- config$data[[name]]
  if (is.null(entry)) {
    node <- config$data
    for (part in strsplit(name, ".", fixed = TRUE)[[1]]) {
      node <- node[[part]]
      if (is.null(node)) break
    }
    entry <- node
  }
  if (is.null(entry) || is.null(entry$path)) {
    stop("No data catalog entry named '", name, "'.", call. = FALSE)
  }
  if (!file.exists(entry$path)) {
    stop("File missing: ", entry$path, call. = FALSE)
  }

  # paste0 strips openssl's "hash" class, which would defeat identical()
  file_hash <- paste0(as.character(.calculate_file_hash(entry$path)))
  all_match <- TRUE
  message("Verifying ", name, " (", entry$path, ")")
  message("  file sha256: ", substr(file_hash, 1, 16), "...")

  # Local framework.db record
  record <- tryCatch(.get_data_record(name), error = function(e) NULL)
  if (!is.null(record)) {
    if (identical(record$hash[1], file_hash)) {
      message("  [ok] matches local framework.db record")
    } else {
      message("  [MISMATCH] local framework.db has ", substr(record$hash[1], 1, 16), "...")
      all_match <- FALSE
    }
  }

  # Cloud ledger head
  token <- .fw_project_token()
  if (!is.null(token)) {
    entries <- tryCatch(
      .fw_api(paste0("/api/v1/ledger?name=", utils::URLencode(name, reserved = TRUE)),
              token = token, url = .fw_project_cloud_url())$entries,
      error = function(e) {
        message("  (cloud ledger unreachable: ", conditionMessage(e), ")")
        NULL
      }
    )
    if (length(entries) > 0) {
      head_entry <- entries[[1]]
      if (identical(head_entry$hash, file_hash)) {
        message("  [ok] matches cloud ledger entry #", head_entry$sequence,
                " (recorded ", head_entry$recorded_at %||% "?", ")")
      } else {
        message("  [MISMATCH] cloud ledger head #", head_entry$sequence,
                " has ", substr(head_entry$hash, 1, 16), "...")
        all_match <- FALSE
      }
    } else if (!is.null(entries)) {
      message("  (no cloud ledger entries for this name yet)")
    }
  }

  if (all_match) {
    message("[ok] Verified")
  } else {
    warning("Integrity mismatch for '", name, "'", call. = FALSE)
  }

  invisible(all_match)
}

#' Import the Local Ledger into the Cloud
#'
#' Reads the project's local `framework.db` (the SQLite ledger of record that
#' `data_save()` always maintains) and appends any digests the cloud ledger
#' does not yet have. This is the default way project history reaches
#' Framework Cloud: an explicit, reviewable action rather than a network call
#' on every save.
#'
#' For per-save streaming instead -- tamper-evident, since each entry lands
#' before the file could be altered -- set `FW_LEDGER=live` or
#' `options: cloud_ledger: live` in the project's `settings.yml`.
#'
#' @return Invisibly, a list with `pushed` and `up_to_date` counts.
#'
#' @seealso [data_verify()], [ledger_list()]
#' @export
ledger_push <- function() {
  token <- .fw_project_token()
  if (is.null(token)) {
    stop("No project token found (FW_PROJECT_TOKEN / .env). ",
         "Create the project with framework::new() while logged in.", call. = FALSE)
  }

  con <- .get_db_connection()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  local_rows <- DBI::dbGetQuery(
    con,
    "SELECT name, hash, updated_at FROM data WHERE hash IS NOT NULL AND hash != ''"
  )

  if (nrow(local_rows) == 0) {
    message("Local ledger is empty - nothing to push.")
    return(invisible(list(pushed = 0L, up_to_date = 0L)))
  }

  # Cloud head per dataset name (entries arrive newest first)
  url <- .fw_project_cloud_url()
  cloud_entries <- .fw_api("/api/v1/ledger", token = token, url = url)$entries
  cloud_head <- list()
  for (entry in cloud_entries) {
    if (is.null(cloud_head[[entry$name]])) {
      cloud_head[[entry$name]] <- entry$hash
    }
  }

  pushed <- 0L
  up_to_date <- 0L

  for (i in seq_len(nrow(local_rows))) {
    name <- local_rows$name[i]
    hash <- paste0(as.character(local_rows$hash[i]))

    if (identical(cloud_head[[name]], hash)) {
      up_to_date <- up_to_date + 1L
      next
    }

    # framework.db stores timestamps as Unix epochs; the API wants a date.
    # Legacy rows may carry NA -- omit recorded_at rather than send junk.
    recorded_at <- paste0(local_rows$updated_at[i])
    if (grepl("^[0-9]+(\\.[0-9]+)?$", recorded_at)) {
      recorded_at <- format(
        as.POSIXct(as.numeric(recorded_at), origin = "1970-01-01", tz = "UTC"),
        "%Y-%m-%dT%H:%M:%SZ"
      )
    } else if (!grepl("^[0-9]{4}-", recorded_at)) {
      recorded_at <- NULL
    }

    body <- list(
      name = name,
      algo = "sha256",
      hash = hash,
      client = list(
        device = Sys.info()[["nodename"]],
        package_version = as.character(utils::packageVersion("framework")),
        source = "ledger_push"
      )
    )
    if (!is.null(recorded_at)) {
      body$recorded_at <- recorded_at
    }

    result <- tryCatch(
      { .fw_api("/api/v1/ledger", token = token, method = "POST", body = body, url = url); TRUE },
      error = function(e) {
        message("  [skip] ", name, ": ", conditionMessage(e))
        FALSE
      }
    )
    if (result) {
      message("  [ok] pushed ", name)
      pushed <- pushed + 1L
    }
  }

  message("[ok] Ledger push complete: ", pushed, " pushed, ", up_to_date, " already current.")
  invisible(list(pushed = pushed, up_to_date = up_to_date))
}

#' List the Project's Cloud Ledger
#'
#' @param name Optional data catalog name to filter by.
#'
#' @return A data.frame of ledger entries, newest first.
#'
#' @export
ledger_list <- function(name = NULL) {
  token <- .fw_project_token()
  if (is.null(token)) {
    stop("No project token found (FW_PROJECT_TOKEN / .env). ",
         "Create the project with framework::new() while logged in.", call. = FALSE)
  }

  path <- "/api/v1/ledger"
  if (!is.null(name)) {
    path <- paste0(path, "?name=", utils::URLencode(name, reserved = TRUE))
  }

  entries <- .fw_api(path, token = token, url = .fw_project_cloud_url())$entries
  if (length(entries) == 0) {
    message("No ledger entries yet.")
    return(invisible(data.frame()))
  }

  do.call(rbind, lapply(entries, function(e) {
    data.frame(
      sequence = e$sequence,
      name = e$name,
      hash = e$hash,
      size_bytes = e$size_bytes %||% NA,
      recorded_at = e$recorded_at %||% NA,
      stringsAsFactors = FALSE
    )
  }))
}

# --- Settings sync -------------------------------------------------------

#' @keywords internal
.fw_sync_paths <- function() {
  dir <- fw_config_dir()
  list(
    document = file.path(dir, "cloud-settings.yml"),
    state = file.path(dir, "sync-state.yml")
  )
}

#' @keywords internal
.fw_document_hash <- function(document) {
  json <- jsonlite::toJSON(document, auto_unbox = TRUE, null = "null")
  as.character(openssl::sha256(as.character(json)))
}

#' Sync Your Settings with Framework Cloud
#'
#' Your cloud settings document is mirrored to `cloud-settings.yml` in the
#' Framework config directory. Edit it there (or on the website) and sync.
#' Your main `settings.yml` is never touched.
#'
#' - `pull` fetches the cloud document (backing up local edits first).
#' - `push` sends your local mirror to the cloud.
#' - `auto` (default) chooses: pull when the cloud is ahead, push when only
#'   your local mirror changed, and stops with instructions when both changed.
#'
#' @param direction One of "auto", "pull", "push".
#'
#' @return Invisibly, the current revision number.
#'
#' @seealso [cloud_login()], [cloud_settings()]
#' @export
cloud_sync <- function(direction = c("auto", "pull", "push")) {
  direction <- match.arg(direction)
  token <- .fw_require_token()
  paths <- .fw_sync_paths()

  remote <- .fw_api("/api/v1/settings", token = token)
  remote_revision <- remote$revision

  state <- if (file.exists(paths$state)) yaml::read_yaml(paths$state) else NULL
  local_doc <- if (file.exists(paths$document)) yaml::read_yaml(paths$document) else NULL
  local_changed <- !is.null(local_doc) && !is.null(state) &&
    !identical(.fw_document_hash(local_doc), state$hash)
  remote_ahead <- is.null(state) || remote_revision > (state$revision %||% -1)

  if (direction == "auto") {
    direction <- if (is.null(local_doc) || is.null(state)) {
      "pull"
    } else if (local_changed && remote_ahead) {
      stop(
        "Both your local mirror and the cloud changed since the last sync.\n",
        "  cloud_sync(\"pull\") to take the cloud version (your file is backed up), or\n",
        "  cloud_sync(\"push\") to overwrite the cloud with your local mirror.",
        call. = FALSE
      )
    } else if (local_changed) {
      "push"
    } else if (remote_ahead) {
      "pull"
    } else {
      message("[ok] Already in sync (revision ", remote_revision, ")")
      return(invisible(remote_revision))
    }
  }

  if (direction == "pull") {
    if (!is.null(local_doc) && local_changed) {
      backup <- paste0(paths$document, ".backup-", format(Sys.time(), "%Y%m%d-%H%M%S"))
      file.copy(paths$document, backup)
      message("Local edits backed up to ", backup)
    }
    dir.create(dirname(paths$document), recursive = TRUE, showWarnings = FALSE)
    yaml::write_yaml(remote$document, paths$document)
    yaml::write_yaml(
      list(revision = remote_revision, hash = .fw_document_hash(remote$document)),
      paths$state
    )
    message("[ok] Pulled cloud settings (revision ", remote_revision, ") -> ", paths$document)
    return(invisible(remote_revision))
  }

  # push
  if (is.null(local_doc)) {
    stop("Nothing to push: no local mirror. Run cloud_sync(\"pull\") first.", call. = FALSE)
  }
  if (is.null(state)) {
    stop("No sync state. Run cloud_sync(\"pull\") first so pushes can detect conflicts.", call. = FALSE)
  }

  res <- tryCatch(
    .fw_api(
      "/api/v1/settings", token = token, method = "PUT",
      body = list(
        document = local_doc,
        base_revision = state$revision,
        client = list(
          device = Sys.info()[["nodename"]],
          app = "framework-r",
          version = as.character(utils::packageVersion("framework"))
        )
      )
    ),
    error = function(e) {
      stop(
        "Push rejected: ", conditionMessage(e), "\n",
        "The cloud likely changed since your last sync. cloud_sync(\"pull\") first.",
        call. = FALSE
      )
    }
  )

  yaml::write_yaml(
    list(revision = res$revision, hash = .fw_document_hash(local_doc)),
    paths$state
  )
  message("[ok] Pushed settings (revision ", res$revision, ")")
  invisible(res$revision)
}

# Overlay a cloud settings document onto the local default config used by
# new_project(). Only keys the creation path consumes are mapped.
#' @keywords internal
.fw_overlay_cloud_settings <- function(config, doc) {
  if (is.null(doc)) {
    return(config)
  }

  if (!is.null(doc$author)) {
    config$author <- .author_merge(config$author, doc$author)
  }

  d <- doc$defaults %||% list()
  config$defaults <- config$defaults %||% list()
  for (key in c("use_renv", "use_git", "seed_on_scaffold")) {
    if (!is.null(d[[key]])) config$defaults[[key]] <- isTRUE(d[[key]])
  }
  for (key in c("seed", "ide", "notebook_format")) {
    if (!is.null(d[[key]])) config$defaults[[key]] <- d[[key]]
  }

  if (!is.null(doc$ai$enabled)) {
    config$defaults$ai_support <- isTRUE(doc$ai$enabled)
  }
  if (length(doc$ai$assistants %||% list()) > 0) {
    config$defaults$ai_assistants <- doc$ai$assistants
  }

  # Per-type directory structure overrides
  for (t in names(doc$project_types %||% list())) {
    dirs <- doc$project_types[[t]]$directories
    if (!is.null(dirs)) {
      config$project_types[[t]] <- config$project_types[[t]] %||% list()
      config$project_types[[t]]$directories <- dirs
    }
  }

  config
}

# --- Cloud blueprint plumbing -------------------------------------------
#
# During project creation, the fetched blueprint (structure + AGENTS.md
# master + skill contents) is stashed here so the deeper creation helpers
# (.create_ai_files, .ai_install_skills) can consult it without threading a
# new argument through every call. Cleared via on.exit by the stasher.

.fw_cloud_state <- new.env(parent = emptyenv())

#' @keywords internal
.fw_blueprint_stash <- function(bp) assign("blueprint", bp, envir = .fw_cloud_state)

#' @keywords internal
.fw_blueprint_get <- function() {
  if (exists("blueprint", envir = .fw_cloud_state)) {
    get("blueprint", envir = .fw_cloud_state)
  } else {
    NULL
  }
}

#' @keywords internal
.fw_blueprint_clear <- function() {
  if (exists("blueprint", envir = .fw_cloud_state)) {
    rm("blueprint", envir = .fw_cloud_state)
  }
}

# Fetch the cloud blueprint for a project type; NULL when no token, offline,
# or the type is unknown to the cloud. Never errors.
#' @keywords internal
.fw_cloud_blueprint_quietly <- function(type) {
  token <- .fw_cloud_token()
  if (is.null(token)) {
    return(NULL)
  }

  tryCatch(
    {
      res <- .fw_api(paste0("/api/v1/blueprints?key=", utils::URLencode(type)), token = token)
      bp <- res$blueprints[[1]] %||% NULL
      if (!is.null(bp)) {
        message("[ok] Using cloud blueprint: ", bp$name %||% type)
      }
      bp
    },
    error = function(e) {
      message("Cloud blueprint unavailable (", conditionMessage(e), "). Using local templates.")
      NULL
    }
  )
}

# The AGENTS.md master overrides generated content ONLY when an admin has
# actually customized it -- an unedited master is identical to the packaged
# template, and creation output must stay byte-stable for those users.
#' @keywords internal
.fw_cloud_agents_override <- function(type, project_name) {
  bp <- .fw_blueprint_get()
  master <- bp$agents_md %||% ""
  if (!nzchar(master)) {
    return(NULL)
  }

  template_dir <- system.file("templates", package = "framework")
  template_file <- file.path(template_dir, sprintf("ai-context.%s.md", type))
  if (!file.exists(template_file)) {
    template_file <- file.path(template_dir, "ai-context.project.md")
  }
  packaged <- if (file.exists(template_file)) {
    paste(readLines(template_file, warn = FALSE), collapse = "\n")
  } else {
    ""
  }

  if (identical(trimws(master), trimws(packaged))) {
    return(NULL)
  }

  gsub("\\{ProjectName\\}", project_name, master)
}

# framework::setup("fw_...") and new(key = ...) land here: pull the project's
# layers envelope (pull v2) by its project token, resolve it, and create the
# project from the spec. The envelope carries the owner's author block and
# every layer, so the project comes out configured their way. The server is
# user-scoped: setup() run inside another project must not send this token to
# that project's server.
#' @keywords internal
.cloud_setup <- function(token, location = NULL, browse = interactive(), url = NULL) {
  url <- .fw_cloud_url(url)
  message(
    "Fetching this project's definition from ", url,
    " (what is shared: ", url, "/privacy)"
  )
  envelope <- .fw_api("/api/v2/projects/pull", token = token, url = url)
  if (!is.list(envelope) || !identical(as.integer(envelope$spec_version %||% NA), 1L)) {
    stop("The server returned a project definition this version of framework cannot read.", call. = FALSE)
  }
  name <- envelope$name %||% ""
  if (!nzchar(name)) {
    stop("The cloud project has no name.", call. = FALSE)
  }
  layers <- envelope$layers %||% list()

  # spec_resolve() refuses other languages; say where to go instead
  language <- .fw_envelope_language(layers)
  if (!identical(language, "r")) {
    stop(.spec_language_message(language), call. = FALSE)
  }

  spec <- spec_resolve(layers, name = name, author = envelope$author)
  spec$source <- envelope$source %||% list(origin = "cloud")
  message("Setting up cloud project: ", name, " (", spec$type, ")")

  if (is.null(location)) {
    slug <- .fw_envelope_slug(layers) %||% .slugify(name)
    suggested <- file.path("~", "projects", slug)
    if (interactive()) {
      answer <- readline(paste0("Location [", suggested, "]: "))
      location <- if (nzchar(trimws(answer))) trimws(answer) else suggested
    } else {
      location <- suggested
    }
  }

  result <- .project_create_from_spec(spec, location)

  if (isTRUE(result$success)) {
    # The setup token IS this project's key; store it for publish() et al.
    if (!identical(spec$type, "bare")) {
      .fw_write_project_token(result$path, token, url)
    }

    message("\nProject ready at ", result$path)
    if (browse && Sys.info()[["sysname"]] == "Darwin") {
      system2("open", result$path)
    }
  }

  invisible(c(result, list(spec = spec)))
}

# The language set by the topmost layer that sets one (r when none does)
#' @keywords internal
.fw_envelope_language <- function(layers) {
  language <- "r"
  for (entry in layers) {
    value <- entry$layer$language
    if (is.character(value) && length(value) == 1) language <- value
  }
  language
}

# The cloud's project layer carries the project's slug as its key
#' @keywords internal
.fw_envelope_slug <- function(layers) {
  for (entry in rev(layers)) {
    if (identical(entry$kind, "project") && is.character(entry$key) && nzchar(entry$key)) {
      return(entry$key)
    }
  }
  NULL
}
