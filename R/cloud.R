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
#   4. the server saved by the last login (cloud_login(), fw login, or
#      framework-py). Project-scoped calls skip it when .env has
#      FW_PROJECT_TOKEN, and stop instead of guessing when the saved logins
#      name different servers.
#   5. cloud_login() only: https://framework.pub, named in the consent notice.
#      Every other call stops: using the public cloud is the user's choice.
#
# Project-scoped calls (publish, the ledger) authenticate with the project's
# token, which is only valid on the server that issued it, so the project's
# .env comes first. Linking a project writes FW_CLOUD_URL next to its token.
# User-scoped calls (settings, new()) skip the project .env
# so a user token never goes to a project's server by accident. fw and
# framework-py use the same order.

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

# fw's and Python's config folder: FW_CONFIG_HOME when set, else
# $XDG_CONFIG_HOME/framework, else ~/.config/framework.
#' @keywords internal
.fw_fw_config_dir <- function() {
  custom <- Sys.getenv("FW_CONFIG_HOME", "")
  if (nzchar(custom)) path.expand(custom) else .fw_shared_config_dir()
}

# The default server a login saved, or NULL. fw's cloud.yml and R's can both
# exist. The most recently written one wins, so the last login in any tool
# counts; on a tie fw's folder comes first. fw and Python use the same rule.
#' @keywords internal
.fw_saved_cloud_url <- function() {
  best <- NULL
  best_time <- -Inf
  for (dir in unique(c(.fw_fw_config_dir(), fw_config_dir()))) {
    path <- file.path(dir, "cloud.yml")
    if (!file.exists(path)) {
      next
    }
    url <- tryCatch(yaml::read_yaml(path)$server, error = function(e) NULL)
    if (!is.character(url) || length(url) != 1 || is.na(url) || !nzchar(url)) {
      next
    }
    time <- as.numeric(file.info(path)$mtime)
    if (time > best_time) {
      best <- url
      best_time <- time
    }
  }
  best
}

# Every server a login saved, most recent first, normalized and without
# duplicates. Logins in fw, R, and Python each keep one cloud.yml.
#' @keywords internal
.fw_saved_cloud_urls <- function() {
  found <- list()
  for (dir in unique(c(.fw_fw_config_dir(), fw_config_dir()))) {
    path <- file.path(dir, "cloud.yml")
    if (!file.exists(path)) {
      next
    }
    url <- tryCatch(yaml::read_yaml(path)$server, error = function(e) NULL)
    if (!is.character(url) || length(url) != 1 || is.na(url) || !nzchar(url)) {
      next
    }
    found[[length(found) + 1]] <- list(url = .fw_normalize_cloud_url(url), time = as.numeric(file.info(path)$mtime))
  }
  if (!length(found)) {
    return(character(0))
  }
  times <- vapply(found, function(f) f$time, numeric(1))
  urls <- vapply(found, function(f) f$url, character(1))[order(-times)]
  unique(urls)
}

# Writes R's cloud.yml, and nothing outside R's own folder. A newer file
# wins when the tools read it, so this login takes effect in fw and Python too.
#' @keywords internal
.fw_save_cloud_url <- function(url) {
  path <- .fw_cloud_config_file()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(list(server = url), path)
  invisible(path)
}

# The project's .env files, in the order a value is looked up: the file
# dotenv_location names, then <root>/.env, where Framework writes the
# project token.
#' @keywords internal
.fw_project_env_files <- function(project_dir) {
  settings_file <- tryCatch(.get_settings_file(project_dir), error = function(e) NULL)
  raw <- if (!is.null(settings_file)) tryCatch(yaml::read_yaml(settings_file), error = function(e) NULL)
  location <- if (is.list(raw)) {
    if (is.list(raw$default)) raw$default$dotenv_location %||% raw$dotenv_location else raw$dotenv_location
  }
  unique(c(.fw_dotenv_path(project_dir, location), file.path(project_dir, ".env")))
}

# A value from the project's .env files, or NULL. A file that can't be
# parsed stops with class fw_dotenv_unreadable, because a guess could pair
# the project's token with another server.
#' @keywords internal
.fw_project_env_value <- function(key, project_dir = ".") {
  # From a subfolder such as notebooks/, use the project root's .env, as
  # framework-py does
  if (identical(project_dir, ".") && !file.exists(".env") && !.has_settings_file(".")) {
    project_dir <- tryCatch(.find_project_root(getwd()), error = function(e) NULL) %||% "."
  }
  for (env_path in .fw_project_env_files(project_dir)) {
    if (!file.exists(env_path)) next
    values <- tryCatch(.fw_read_dotenv(env_path), error = function(e) {
      stop(errorCondition(sprintf(
        "Can't read %s (%s). Framework Cloud calls read the project's token and server from it. Fix the line and try again.",
        env_path, conditionMessage(e)
      ), class = "fw_dotenv_unreadable", call = NULL))
    })
    value <- unname(values[key])
    if (length(value) == 1 && !is.na(value) && nzchar(value)) {
      return(value)
    }
  }
  NULL
}

# An environment variable's value, or "" when it is unset or scaffold() set
# it from a project's .env, in this R process or a parent one
# (.fw_load_dotenv()).
#' @keywords internal
.fw_shell_env <- function(key) {
  if (.fw_dotenv_set(key)) "" else Sys.getenv(key, "")
}

# Which server to use, and where that setting came from. Stops with class
# fw_no_server when nothing names one, except for scope "login", and with
# fw_project_server_missing for a project token with no server.
#
# For scope "project", the server matches the token .fw_project_token()
# picks, so a token goes only to the server that issued it.
#   * Token in the project's .env: url, FW_CLOUD_URL in that .env, then an
#     FW_CLOUD_URL the shell set. Values scaffold() loaded are ignored.
#   * Token only in the shell (CI): url, then the shell's FW_CLOUD_URL.
#     A token scaffold() loaded from another project's .env doesn't count.
#   * No token: url, the project's .env, an FW_CLOUD_URL the shell set,
#     then the cloud_login() server when exactly one is saved.
# Scopes "user" and "login" read the .env of the project at project_dir,
# when there is one, and also skip values scaffold() loaded, so a project
# never uses the server of the project scaffold() loaded before it.
#' @keywords internal
.fw_cloud_server <- function(url = NULL, scope = c("user", "project", "login"), project_dir = ".") {
  scope <- match.arg(scope)
  file_token <- NULL
  session_token <- FALSE
  if (identical(scope, "project")) {
    file_token <- .fw_project_env_value("FW_PROJECT_TOKEN", project_dir)
    session_token <- is.null(file_token) && nzchar(.fw_shell_env("FW_PROJECT_TOKEN"))
  }
  shell_candidate <- list(url = .fw_shell_env("FW_CLOUD_URL"), source = "the FW_CLOUD_URL environment variable")
  project_candidate <- function() {
    value <- if (identical(scope, "project")) {
      .fw_project_env_value("FW_CLOUD_URL", project_dir)
    } else {
      # Outside a project there's no .env to read, and an unreadable one
      # can't misdirect a user token
      root <- tryCatch(.find_project_root(project_dir), error = function(e) NULL)
      if (!is.null(root)) {
        tryCatch(.fw_project_env_value("FW_CLOUD_URL", root), fw_dotenv_unreadable = function(e) NULL)
      }
    }
    list(url = value, source = "the project's .env")
  }
  candidates <- if (session_token) {
    list(list(url = url, source = "the url argument"), shell_candidate)
  } else {
    list(list(url = url, source = "the url argument"), project_candidate(), shell_candidate)
  }
  for (candidate in candidates) {
    value <- candidate$url
    if (is.character(value) && length(value) == 1 && !is.na(value) && nzchar(value)) {
      return(list(url = .fw_normalize_cloud_url(value), source = candidate$source))
    }
  }

  # A project token is only valid on the server that issued it, and the
  # saved login may be another server's
  if (!is.null(file_token)) {
    stop(errorCondition(paste0(
      "This project's .env has FW_PROJECT_TOKEN but no FW_CLOUD_URL, so it does not say which ",
      "Framework Cloud server issued the token. Add FW_CLOUD_URL=<server> to the project's .env."
    ), class = "fw_project_server_missing", call = NULL))
  }
  if (session_token) {
    stop(errorCondition(paste0(
      "FW_PROJECT_TOKEN is set but FW_CLOUD_URL is not, so nothing says which ",
      "Framework Cloud server issued the token. Set FW_CLOUD_URL=<server> in the same environment as the token."
    ), class = "fw_project_server_missing", call = NULL))
  }

  saved <- .fw_saved_cloud_urls()
  if (length(saved) == 1 || (length(saved) > 1 && !identical(scope, "project"))) {
    return(list(url = saved[[1]], source = "your cloud_login() default"))
  }
  if (length(saved) > 1) {
    stop(errorCondition(paste0(
      "This project does not say which Framework Cloud server it uses: its .env has no FW_CLOUD_URL, ",
      "and you are logged in to ", paste(vapply(saved, .fw_cloud_host, ""), collapse = " and "),
      ". Add FW_CLOUD_URL=<server> to the project's .env, or set FW_CLOUD_URL."
    ), class = "fw_ambiguous_server", call = NULL))
  }
  if (identical(scope, "login")) {
    return(list(url = .fw_default_cloud_url, source = "the cloud_login() default"))
  }
  stop(errorCondition(paste0(
    "No Framework Cloud server is chosen. ",
    if (identical(scope, "project")) "This project's .env has no FW_CLOUD_URL and you have not logged in. Add FW_CLOUD_URL=<server> to .env, or log in " else "Log in ",
    'with framework::cloud_login() (framework.pub) or framework::cloud_login(url = "<server>"), ',
    "or set FW_CLOUD_URL."
  ), class = "fw_no_server", call = NULL))
}

#' @keywords internal
.fw_cloud_url <- function(url = NULL, scope = c("user", "project", "login"), project_dir = ".") {
  .fw_cloud_server(url, scope = scope, project_dir = project_dir)$url
}

# The user's server, or NULL when nothing names one.
#' @keywords internal
.fw_cloud_url_or_null <- function() {
  tryCatch(.fw_cloud_url(), fw_no_server = function(e) NULL)
}

# Token storage. Native-first: the OS credential store (macOS Keychain via
# /usr/bin/security; elsewhere the keyring
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
  file.path(.fw_home(), ".secrets", "framework", "token")
}

#' @keywords internal
.fw_read_token_file <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  token <- trimws(readLines(path, n = 1L, warn = FALSE)[1])
  if (!is.na(token) && nzchar(token)) token else NULL
}

# On macOS the token lives in the login keychain and is read, written, and
# deleted through /usr/bin/security, as fw does. fw's items trust only that
# tool, so reading them from R's own process would raise an access dialog
# (and hang a headless session). Other systems use the keyring package.
#' @keywords internal
.fw_use_macos_security <- function() {
  identical(Sys.info()[["sysname"]], "Darwin") && file.exists("/usr/bin/security")
}

#' @keywords internal
.fw_security <- function(args) {
  out <- suppressWarnings(system2("/usr/bin/security", args, stdout = TRUE, stderr = FALSE))
  list(status = attr(out, "status") %||% 0L, output = out)
}

# Runs `security -i` with one command on stdin, through a pipe, so the
# command never appears in argv or a temp file. Returns the exit status.
#' @keywords internal
.fw_security_stdin <- function(command) {
  con <- pipe("/usr/bin/security -i >/dev/null 2>&1", open = "w")
  writeLines(command, con)
  status <- close(con)
  if (is.null(status)) 0L else as.integer(status)
}

#' @keywords internal
.fw_keychain_available <- function() {
  .fw_use_macos_security() || requireNamespace("keyring", quietly = TRUE)
}

#' @keywords internal
.fw_keyring_get <- function(service) {
  if (.fw_use_macos_security()) {
    res <- .fw_security(c("find-generic-password", "-s", shQuote(service), "-a", "token", "-w"))
    if (!identical(as.integer(res$status), 0L) || length(res$output) == 0) {
      return(NULL)
    }
    token <- sub("[\r\n]+$", "", paste(res$output, collapse = "\n"))
    if (startsWith(token, "go-keyring-base64:")) {
      token <- rawToChar(jsonlite::base64_dec(sub("^go-keyring-base64:", "", token)))
    }
    return(if (nzchar(token)) token else NULL)
  }
  tryCatch(
    {
      token <- keyring::key_get(service, "token")
      if (nzchar(token)) token else NULL
    },
    error = function(e) NULL
  )
}

# Stores a token. Errors when it cannot.
#' @keywords internal
.fw_keyring_set <- function(service, token) {
  if (.fw_use_macos_security()) {
    unsafe <- function(x) grepl("['\\\\]|[[:cntrl:]]", x)
    if (unsafe(token) || unsafe(service)) {
      stop("The token contains a quote, backslash, or control character the keychain command cannot take.",
           call. = FALSE)
    }
    cmd <- sprintf("add-generic-password -U -s '%s' -a 'token' -w '%s'", service, token)
    if (!identical(.fw_security_stdin(cmd), 0L)) {
      stop("security add-generic-password failed.", call. = FALSE)
    }
    return(invisible(TRUE))
  }
  keyring::key_set_with_value(service, "token", token)
  invisible(TRUE)
}

# Deletes a stored token. TRUE when one was removed.
#' @keywords internal
.fw_keyring_delete <- function(service) {
  if (.fw_use_macos_security()) {
    res <- .fw_security(c("delete-generic-password", "-s", shQuote(service), "-a", "token"))
    return(identical(as.integer(res$status), 0L))
  }
  tryCatch(
    {
      keyring::key_delete(service, "token")
      TRUE
    },
    error = function(e) FALSE
  )
}

#' @keywords internal
.fw_keyring_token <- function(url) {
  if (!.fw_keychain_available()) {
    return(NULL)
  }
  token <- .fw_keyring_get(.fw_keyring_service(url))
  if (is.null(token) && .fw_is_default_cloud(url)) {
    token <- .fw_keyring_get(.fw_legacy_keyring_service)
  }
  token
}

#' @keywords internal
.fw_cloud_token <- function(url = .fw_cloud_url_or_null()) {
  env_token <- Sys.getenv("FW_CLOUD_TOKEN", "")
  if (nzchar(env_token)) {
    return(env_token)
  }

  override <- Sys.getenv("FW_TOKEN_FILE", "")
  if (nzchar(override)) {
    # Authoritative when set: never fall through to the real keyring
    return(.fw_read_token_file(path.expand(override)))
  }

  if (is.null(url)) {
    return(NULL)
  }
  token <- .fw_keyring_token(url) %||% .fw_read_token_file(.fw_token_file(url))
  if (is.null(token) && .fw_is_default_cloud(url)) {
    token <- .fw_read_token_file(.fw_legacy_token_file())
  }
  token
}

#' @keywords internal
.fw_api <- function(path, token, method = "GET", body = NULL, url = .fw_cloud_url(), timeout = NULL,
                    headers = FALSE) {
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
  if (!is.null(timeout)) {
    req <- httr2::req_timeout(req, timeout)
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

  resp <- httr2::req_perform(req)
  out <- httr2::resp_body_json(resp)
  # headers = TRUE keeps the response headers as the "headers" attribute
  if (isTRUE(headers)) {
    attr(out, "headers") <- httr2::resp_headers(resp)
  }
  out
}

# How to connect to a server: browser login first, a pasted token for
# scripts, with url = for servers other than framework.pub. cloud_status()
# and every call that needs a token give the same advice, as framework-py
# does.
#' @keywords internal
.fw_login_hint <- function(url) {
  where <- if (.fw_is_default_cloud(url)) "" else sprintf('url = "%s"', url)
  browser <- sprintf("framework::cloud_login(%s)", where)
  token <- if (nzchar(where)) {
    sprintf('framework::cloud_login("fw_...", %s)', where)
  } else {
    'framework::cloud_login("fw_...")'
  }
  paste0("Run ", browser, " to approve this computer in your browser, or create a token at ",
         url, "/tokens and run ", token, ".")
}

#' @keywords internal
.fw_require_token <- function(url = .fw_cloud_url()) {
  token <- .fw_cloud_token(url)
  if (is.null(token)) {
    stop(
      "No cloud token found for ", .fw_cloud_host(url), ". ", .fw_login_hint(url),
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
#' the macOS Keychain (through `/usr/bin/security`, as `fw` does), or Windows
#' Credential Manager or Linux Secret Service (through the `keyring` package),
#' falling back to a permission-restricted
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
#' `FW_CLOUD_URL` environment variable overrides that default. A project
#' with `FW_PROJECT_TOKEN` in its `.env` uses the `FW_CLOUD_URL` there,
#' never this default.
#'
#' Without a token, `cloud_login()` opens the server's approval page in your
#' browser. Sign in, or create a free account, and approve this computer; the
#' token comes back to R. With a token from the server's token page,
#' `cloud_login(token)` stores that token instead.
#'
#' @param token Your user token from Framework Cloud (Settings -> API tokens).
#'   Omit it to approve this computer in the browser.
#' @param url The Framework Cloud server. Defaults to `FW_CLOUD_URL`, then the
#'   server you last logged in to, then <https://framework.pub>, which the
#'   consent notice names before connecting. Plain `http` is accepted only for
#'   `localhost` and `127.0.0.1`.
#' @param verify Check the token against the server before saving (default TRUE).
#' @param consent Set TRUE to confirm non-interactively (scripts, CI). In an
#'   interactive session you are prompted instead. What connecting shares is
#'   printed first and documented at the server's `/privacy` page.
#'
#' @param browser Open the approval page when no token is given. FALSE prints
#'   the link only.
#'
#' @return Invisibly, where the token was stored ("keyring" or the file path).
#'
#' @seealso [cloud_status()], [cloud_logout()], [cloud_settings()]
#' @export
cloud_login <- function(token = NULL, url = NULL, verify = TRUE, consent = NULL,
                        browser = TRUE) {
  checkmate::assert_string(token, min.chars = 10, null.ok = TRUE)
  checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
  checkmate::assert_flag(browser)
  url <- .fw_cloud_url(url, scope = "login")
  host <- .fw_cloud_host(url)

  if (is.null(token)) {
    # Approving in the browser is the confirmation.
    message(.fw_consent_notice(url))
    token <- .fw_device_login(url, browser)
    consent <- TRUE
  }

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
  } else if (.fw_keychain_available()) {
    stored <- tryCatch(
      {
        .fw_keyring_set(service, token)
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

# Tests replace the pause between approval checks.
.fw_sleep <- function(seconds) Sys.sleep(seconds)

.fw_browse <- function(url) utils::browseURL(url)

.fw_device_request <- function(url, path, body) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop(
      "Cloud features require the 'httr2' package. ",
      'Install it with install.packages("httr2").',
      call. = FALSE
    )
  }
  req <- httr2::request(paste0(url, path))
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- httr2::req_user_agent(
    req,
    paste0("framework-r/", as.character(utils::packageVersion("framework")))
  )
  req <- httr2::req_body_json(req, body)
  if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
    req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
  }
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  httr2::req_perform(req)
}

# Approve this machine in the browser and return the new token: the same
# flow as fw login and Stata's fw_login.
.fw_device_login <- function(url, browser = TRUE) {
  host <- .fw_cloud_host(url)
  resp <- .fw_device_request(
    url, "/api/v1/cli/device",
    list(client_name = paste("R on", Sys.info()[["nodename"]]))
  )
  status <- httr2::resp_status(resp)
  if (status %in% c(404L, 405L)) {
    stop(host, " does not offer browser login. Create a token at ", url,
         "/tokens, then call cloud_login(token).", call. = FALSE)
  }
  if (status >= 400L) {
    stop("Browser login failed (HTTP ", status, ").", call. = FALSE)
  }
  start <- httr2::resp_body_json(resp)
  page <- start$verification_url_complete %||% start$verification_url
  interval <- as.numeric(start$interval %||% 5)
  expires <- as.numeric(start$expires_in %||% 600)
  message(
    "Approve this computer in your browser.\n  Code: ", start$user_code %||% "",
    "\n  Page: ", page, "\nWaiting for approval. Press Esc or Ctrl+C to stop."
  )
  if (isTRUE(browser) && interactive()) {
    try(.fw_browse(page), silent = TRUE)
  }
  waited <- 0
  while (waited < expires) {
    .fw_sleep(interval)
    waited <- waited + interval
    poll <- .fw_device_request(
      url, "/api/v1/cli/device/token", list(device_code = start$device_code)
    )
    status <- httr2::resp_status(poll)
    if (status == 428L) next
    if (status == 429L) {
      interval <- interval + 5
      next
    }
    if (status == 403L) stop("The login request was denied in the browser.", call. = FALSE)
    if (status == 410L) break
    if (status >= 400L) stop("Browser login failed (HTTP ", status, ").", call. = FALSE)
    token <- httr2::resp_body_json(poll)$token
    if (!is.character(token) || !nzchar(token)) {
      stop(host, " approved the login but returned no token.", call. = FALSE)
    }
    return(token)
  }
  stop("The login code expired. Run cloud_login() again.", call. = FALSE)
}

#' Log Out of Framework Cloud
#'
#' Revokes this machine's stored token for a server on that server, then
#' removes it from the system keyring and any token files. When
#' `FW_TOKEN_FILE` is set, only that file is used, because it is the only
#' place [cloud_login()] wrote. A token in `FW_CLOUD_TOKEN` is neither
#' revoked nor removed. When the server can't be reached, the local copy is
#' still removed and the token can be revoked on the server's tokens page.
#' The default server saved by [cloud_login()] is kept.
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

  # FW_TOKEN_FILE is authoritative when set: cloud_login() writes only
  # there and every lookup reads only there, so logout removes only it
  override <- Sys.getenv("FW_TOKEN_FILE", "")
  if (nzchar(override)) {
    path <- path.expand(override)
    if (file.exists(path)) {
      .fw_revoke_tokens(.fw_read_token_file(path), url)
      file.remove(path)
      message("[ok] Removed: ", path, " (FW_TOKEN_FILE)")
    } else {
      message("No stored token found in FW_TOKEN_FILE (", path, ").")
    }
    return(invisible(TRUE))
  }

  services <- character(0)
  if (.fw_keychain_available()) {
    services <- .fw_keyring_service(url)
    if (.fw_is_default_cloud(url)) {
      services <- c(services, .fw_legacy_keyring_service)
    }
  }
  paths <- .fw_token_file(url)
  if (.fw_is_default_cloud(url)) {
    paths <- c(paths, .fw_legacy_token_file())
  }

  # Revoke every stored copy on the server first, then remove them here
  tokens <- c(
    unlist(lapply(services, .fw_keyring_get)),
    unlist(lapply(paths, .fw_read_token_file))
  )
  .fw_revoke_tokens(tokens, url)

  for (service in services) {
    if (.fw_keyring_delete(service)) {
      removed <- c(removed, paste0("keyring (", service, ")"))
    }
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

# Revokes tokens on the server with DELETE /api/v1/token. A 401 means a
# token was already invalid. Any other failure prints one line and lets
# logout go on.
#' @keywords internal
.fw_revoke_tokens <- function(tokens, url) {
  tokens <- unique(tokens[!is.na(tokens) & nzchar(tokens)])
  if (length(tokens) == 0 || !requireNamespace("httr2", quietly = TRUE)) {
    return(invisible(FALSE))
  }
  failed <- FALSE
  for (token in tokens) {
    status <- tryCatch(
      {
        req <- httr2::request(paste0(url, "/api/v1/token"))
        req <- httr2::req_auth_bearer_token(req, token)
        req <- httr2::req_method(req, "DELETE")
        req <- httr2::req_headers(req, Accept = "application/json")
        req <- httr2::req_error(req, is_error = function(resp) FALSE)
        req <- httr2::req_timeout(req, 15)
        if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
          req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
        }
        httr2::resp_status(httr2::req_perform(req))
      },
      error = function(e) NA_integer_
    )
    if (is.na(status) || !(status < 300 || status == 401)) {
      failed <- TRUE
    }
  }
  if (failed) {
    message("Could not revoke the token on ", .fw_cloud_host(url),
            ". Revoke it at ", url, "/tokens.")
  }
  invisible(!failed)
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
  server <- tryCatch(.fw_cloud_server(url), fw_no_server = function(e) {
    message(conditionMessage(e))
    NULL
  })
  if (is.null(server)) {
    return(invisible(FALSE))
  }
  message("Server: ", server$url, " (from ", server$source, ")")

  project <- tryCatch(.fw_cloud_server(scope = "project"), fw_project_server_missing = function(e) {
    message(conditionMessage(e))
    NULL
  }, error = function(e) NULL)
  if (!is.null(project) && !is.null(.fw_project_token()) &&
      !identical(project$url, server$url)) {
    message("This project publishes to ", project$url, " (from ", project$source, ")")
  }

  token <- .fw_cloud_token(server$url)

  if (is.null(token)) {
    message("Not connected. ", .fw_login_hint(server$url))
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
# secret. A project token is only valid on the server that issued it, so a
# new token always comes with FW_CLOUD_URL, framework.pub included: an empty
# or different FW_CLOUD_URL line is replaced, a commented placeholder is
# filled, or the line goes next to the token. A project that already has a
# token keeps it and its FW_CLOUD_URL. fw and framework-py write .env the
# same way.
#' @keywords internal
.fw_write_project_token <- function(project_dir, token, url) {
  url <- .fw_normalize_cloud_url(url)
  env_path <- file.path(project_dir, ".env")
  lines <- if (file.exists(env_path)) readLines(env_path, warn = FALSE) else character(0)
  set_at <- function(key) grep(paste0("^\\s*(export\\s+)?", key, "\\s*="), lines)
  placeholder_at <- function(key) grep(paste0("^\\s*#\\s*(export\\s+)?", key, "\\s*="), lines)
  value_at <- function(i) gsub("^[\"']|[\"']$", "", trimws(sub("^[^=]*=", "", lines[i])))

  token_at <- set_at("FW_PROJECT_TOKEN")
  if (length(token_at) > 0 && nzchar(value_at(token_at[1]))) {
    return(invisible(FALSE))
  }
  .fw_refuse_tracked_env(project_dir)
  .fw_ensure_env_ignored(project_dir)

  token_line <- paste0("FW_PROJECT_TOKEN=", token)
  url_line <- paste0("FW_CLOUD_URL=", url)
  appended <- character(0)
  token_slot <- c(token_at, placeholder_at("FW_PROJECT_TOKEN"))[1]
  if (is.na(token_slot)) {
    appended <- token_line
  } else {
    lines[token_slot] <- token_line
  }

  url_at <- set_at("FW_CLOUD_URL")
  previous <- if (length(url_at) > 0) value_at(url_at[1]) else ""
  if (length(url_at) == 0) url_at <- placeholder_at("FW_CLOUD_URL")[1]
  if (length(url_at) > 0 && !anyNA(url_at)) {
    lines[url_at] <- url_line
  } else if (length(appended) > 0) {
    appended <- c(appended, url_line)
  } else {
    lines <- append(lines, url_line, after = token_slot)
  }

  if (length(appended) > 0) {
    header <- "# Framework Cloud project key and server (created by framework::new or setup)"
    lines <- c(lines, if (length(lines) > 0) "", header, appended)
  }
  writeLines(lines, env_path)
  message("  Added: FW_PROJECT_TOKEN and FW_CLOUD_URL to .env")
  if (nzchar(previous) && !identical(previous, url)) {
    message("  FW_CLOUD_URL was ", previous, "; the token is from ", url)
  }
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
.fw_cloud_register_project <- function(project_dir, name, type, choices = NULL) {
  url <- .fw_cloud_url_or_null()
  token <- if (!is.null(url)) .fw_cloud_token(url)
  if (is.null(token)) {
    return(invisible(NULL))
  }

  res <- tryCatch(
    {
      if (is.null(choices)) {
        .fw_api(
          "/api/v1/projects", token = token, method = "POST",
          body = list(name = name, project_type = type, language = "r"), url = url
        )
      } else {
        # Register the same choices used to resolve the local project, rather
        # than a name-only v1 record that cannot recreate its configuration.
        .fw_api("/api/v1/projects", token = token, method = "POST", body = choices, url = url)
      }
    },
    error = function(e) {
      message("Cloud project registration skipped: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(res)) {
    return(invisible(NULL))
  }

  slug <- res$slug %||% res$project$slug
  project_token <- res$token %||% res$pull_token
  message("[ok] Registered on ", .fw_cloud_host(url), ": ", slug)
  # Every registered project needs its token, bare ones included: without
  # it the folder can't link to the Cloud project it just created
  .fw_write_project_token(project_dir, project_token, url)
  invisible(res)
}

# --- Cloud publishing ----------------------------------------------------

# The project's cloud key comes from its own .env first, then from an
# FW_PROJECT_TOKEN the shell set (CI). Reading .env first means that after
# scaffold() of one project, calls for another project use that project's
# token. .fw_cloud_server() picks the matching server.
#' @keywords internal
.fw_project_token <- function(project_dir = ".") {
  file_token <- .fw_project_env_value("FW_PROJECT_TOKEN", project_dir)
  if (!is.null(file_token)) {
    return(file_token)
  }
  # A token scaffold() loaded from another project's .env never stands in
  # for this project's
  env_token <- .fw_shell_env("FW_PROJECT_TOKEN")
  if (nzchar(env_token)) env_token else NULL
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
# Each publish adds a version, except a code snippet that matches its newest
# version. `slug` is publish()'s argument: a string names
# the document only. TRUE makes it public with the derived name, FALSE makes
# it unlisted, and NULL or a string leaves the visibility alone (a new
# artifact is unlisted). `plot_description` is a ggplot's figure.phiz.json,
# sent beside its image as the plot_description field.
#' @keywords internal
.fw_cloud_publish <- function(source, dest = NULL, title = NULL, self_contained = TRUE,
                              slug = NULL, description = NULL, kind = NULL,
                              password = NULL, visibility = NULL, collection = NULL,
                              share_unlisted = FALSE, plot_description = NULL, display = NULL) {
  display <- .fw_display_settings(display)
  token <- .fw_project_token()
  selected <- NULL
  if (!is.null(collection)) {
    if (length(collection) != 1L || is.na(collection) ||
        !(is.character(collection) || is.numeric(collection))) {
      stop("collection must be a collection ID or slug.", call. = FALSE)
    }
    rows <- .fw_api("/api/v1/collections", token, url = .fw_project_cloud_url())$collections
    matches <- Filter(function(x) identical(as.character(x$id), as.character(collection)) ||
                        identical(x$slug, as.character(collection)), rows)
    if (length(matches) != 1L) stop("Collection is missing or ambiguous in this project.", call. = FALSE)
    selected <- matches[[1]]
    # As on the server: an explicit visibility wins over the TRUE/FALSE
    # switch. A string slug only names the artifact, so it predicts nothing.
    public <- if (!is.null(visibility)) visibility == "public" else if (is.logical(slug)) isTRUE(slug) else NULL
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

  # An explicit visibility wins. `readable` is the older switch between
  # public and unlisted, sent only for slug = TRUE or FALSE. A string slug
  # never sets it.
  readable <- if (is.logical(slug) && is.null(visibility)) isTRUE(slug) else NULL
  if (!is.character(slug)) {
    slug <- dest %||% tools::file_path_sans_ext(basename(source))
  }
  slug <- sub("\\.html?$", "", slug)

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop('Cloud publishing requires httr2. install.packages("httr2")', call. = FALSE)
  }

  # Resolve the server first, so a missing FW_CLOUD_URL errors here, not inside httr2
  server <- .fw_project_cloud_url()
  req <- httr2::request(paste0(server, "/api/v1/documents"))
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
    # A ggplot figure's phiz plot description, which Cloud compiles to a live
    # chart; the uploaded image stays as its static fallback.
    if (!is.null(plot_description)) {
      body$plot_description <- curl::form_file(plot_description, type = "application/json")
    }
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
  # Display settings, as a JSON object of the settings to change
  if (!is.null(display)) body$display <- .fw_display_json(display)
  req <- httr2::req_body_multipart(req, !!!body)
  if (nzchar(Sys.getenv("FW_CLOUD_INSECURE", ""))) {
    req <- httr2::req_options(req, ssl_verifypeer = 0, ssl_verifyhost = 0)
  }
  req <- httr2::req_error(req, body = function(resp) {
    tryCatch(httr2::resp_body_json(resp)$message, error = function(e) NULL) %||%
      paste0("Publish failed (HTTP ", httr2::resp_status(resp), ")")
  })

  res <- httr2::resp_body_json(httr2::req_perform(req))

  if (isTRUE(res$unchanged)) {
    # A code snippet that matches its newest version adds none
    message("Unchanged, still version ", res$version, ": ", res$url)
  } else if (!is.null(res$version)) {
    message("Published version ", res$version, ": ", res$url)
  } else {
    message("Published: ", res$url)
  }
  # The link to paste into a site that takes Framework embeds: a public
  # artifact's short link or an unlisted one's own link. Null when the
  # artifact can't be embedded (private or with a password), and missing
  # from older servers.
  embed_link <- .fw_embed_link(res)
  if (!is.null(embed_link)) message("Embed: ", embed_link)
  # The server's notice assumes an unlisted link. Say it plainly for a
  # public artifact whose owner has no handle yet.
  public <- identical(res$visibility, "public") ||
    (is.null(res$visibility) && !is.null(res$notice) && grepl("handle", res$notice, fixed = TRUE))
  if (public && is.null(res$readable_url)) {
    message("Public. Set a handle in Account > Account details to get a readable URL.")
  } else if (!is.null(res$notice) && nzchar(res$notice) && !grepl("handle", res$notice, fixed = TRUE)) {
    message(res$notice)
  }
  if (!is.null(selected)) {
    tryCatch({
      if (is.null(res$id)) stop("The server did not return an artifact ID.")
      .fw_api(paste0("/api/v1/collections/", selected$id, "/items"), token,
              method = "POST", url = .fw_project_cloud_url(),
              body = list(document_id = res$id, share_unlisted = share_unlisted))
      message("Added to collection: ", selected$title)
    }, error = function(e) {
      warning("Artifact published at ", res$url, ", but collection attachment failed: ",
              conditionMessage(e), ". Attach it from the project Outputs page; publishing again creates another version.", call. = FALSE)
    })
  }
  url <- res$url
  if (!is.null(embed_link)) attr(url, "embed_link") <- embed_link
  invisible(url)
}

# The embed_link of a publish answer, or NULL when it is null, missing, or
# not a link.
#' @keywords internal
.fw_embed_link <- function(res) {
  link <- res$embed_link
  if (is.character(link) && length(link) == 1L && !is.na(link) && nzchar(link)) link else NULL
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

  url <- tryCatch(.fw_project_cloud_url(), fw_project_server_missing = function(e) {
    message("Ledger push skipped: ", conditionMessage(e))
    NULL
  }, error = function(e) NULL)
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
        # UTC with a Z, as ledger_push() and framework-py send
        recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
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
#' Hashes the file behind a catalog name (or a file path) and compares it
#' against the local
#' framework.db record and the project's cloud ledger on Framework Cloud.
#' Proves "the data I have is bit-identical to what was recorded" without the
#' data ever leaving the machine.
#'
#' @param name Data catalog name (e.g. "inputs.raw.enrollment") or a file
#'   path (e.g. "outputs/public/summary.csv"), as used with [data_read()] /
#'   [data_save()]. A path is relative to the project root.
#'
#' @return Invisibly, TRUE when no available record disagrees with the file.
#'   It prints which records were compared. With no framework.db record and
#'   no cloud ledger entry, nothing is compared: it says "Not verified" and
#'   still returns TRUE, as framework-py does.
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
  key <- name
  if (is.null(entry) || is.null(entry$path)) {
    # data_save() to a plain path records its hash under that path, in its
    # clean project-relative form ("./x.csv" is "x.csv")
    path <- .fw_project_path(name)
    if (!file.exists(path) || dir.exists(path)) {
      stop("No data catalog entry or file named '", name, "'.", call. = FALSE)
    }
    entry <- list(path = name)
    key <- .fw_clean_data_path(name)
  }
  # Catalog paths are relative to the project root
  entry$path <- .fw_project_path(entry$path)
  if (!file.exists(entry$path)) {
    stop("File missing: ", .fw_project_relative_path(entry$path), call. = FALSE)
  }

  # paste0 strips openssl's "hash" class, which would defeat identical()
  file_hash <- paste0(as.character(.calculate_file_hash(entry$path)))
  all_match <- TRUE
  compared <- character()
  message("Verifying ", name, " (", .fw_project_relative_path(entry$path), ")")
  message("  file sha256: ", substr(file_hash, 1, 16), "...")

  # Local framework.db record
  # The clean name first, then the name as given (a record made before
  # names were cleaned), then the file's path from the project root
  record <- NULL
  for (candidate in unique(c(key, name, .fw_project_relative_path(entry$path)))) {
    record <- tryCatch(.get_data_record(candidate), error = function(e) NULL)
    if (!is.null(record) && NROW(record) > 0) break
  }
  if (!is.null(record) && NROW(record) > 0 && !is.na(record$hash[1])) {
    compared <- c(compared, "framework.db")
    if (identical(record$hash[1], file_hash)) {
      message("  [ok] matches local framework.db record")
    } else {
      message("  [MISMATCH] local framework.db has ", substr(record$hash[1], 1, 16), "...")
      all_match <- FALSE
    }
  } else {
    message("  (no framework.db record for this name yet)")
  }

  # Cloud ledger head
  token <- .fw_project_token()
  if (!is.null(token)) {
    entries <- tryCatch(
      .fw_api(paste0("/api/v1/ledger?name=", utils::URLencode(key, reserved = TRUE)),
              token = token, url = .fw_project_cloud_url())$entries,
      error = function(e) {
        message("  (cloud ledger unreachable: ", conditionMessage(e), ")")
        NULL
      }
    )
    if (length(entries) > 0) {
      head_entry <- entries[[1]]
      compared <- c(compared, "the cloud ledger")
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

  if (!all_match) {
    warning("Integrity mismatch for '", name, "'", call. = FALSE)
  } else if (length(compared) == 0) {
    message("[!] Not verified: no record to compare with. ",
            "data_save() and data_add() record one.")
  } else {
    message("[ok] Verified against ", paste(compared, collapse = " and "))
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
    stop(.fw_unlinked_message(), call. = FALSE)
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
    stop(.fw_unlinked_message(), call. = FALSE)
  }

  path <- "/api/v1/ledger"
  if (!is.null(name)) {
    path <- paste0(path, "?name=", utils::URLencode(name, reserved = TRUE))
  }

  entries <- .fw_api(path, token = token, url = .fw_project_cloud_url())$entries
  if (length(entries) == 0) {
    message("No ledger entries yet.")
    # Same columns as a non-empty result, so code that selects them works
    return(invisible(data.frame(
      sequence = integer(), name = character(), hash = character(),
      size_bytes = numeric(), recorded_at = character(), stringsAsFactors = FALSE
    )))
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
        "  cloud_sync(\"pull\") takes the cloud version and backs up your file.\n",
        "  Then copy your edits from the backup and run cloud_sync(\"push\").",
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

# The Projects folder the cloud sends with a project's definition: the
# Framework-Projects-Dir header, percent-encoded UTF-8, or NULL when absent.
#' @keywords internal
.fw_header_projects_dir <- function(headers) {
  if (length(headers) == 0) {
    return(NULL)
  }
  value <- unlist(headers[tolower(names(headers)) == "framework-projects-dir"], use.names = FALSE)[1]
  if (!is.character(value) || is.na(value)) {
    return(NULL)
  }
  value <- tryCatch(utils::URLdecode(value), error = function(e) NA_character_)
  Encoding(value) <- "UTF-8"
  value <- trimws(value)
  if (is.na(value) || !nzchar(value)) NULL else value
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
  envelope <- .fw_api("/api/v1/projects/pull", token = token, url = url, headers = TRUE)
  owner_projects_dir <- .fw_header_projects_dir(attr(envelope, "headers"))
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
    location <- .fw_ask_location(
      .fw_envelope_slug(layers) %||% .slugify(name),
      projects_dir = owner_projects_dir
    )
  }
  location <- .fw_abs_path(location)
  message("Creating the project at ", location)

  result <- .project_create_from_spec(spec, location)

  if (isTRUE(result$success)) {
    # The setup token IS this project's key; store it for publish() et al.
    # Bare projects record the token too, as registration does, so the folder
    # stays linked to its Cloud project
    .fw_write_project_token(result$path, token, url)

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
