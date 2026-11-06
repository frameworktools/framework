#' Setup Framework (First-Time Configuration or Cloud Project Setup)
#'
#' Two modes, dispatched on the first argument:
#'
#' - `setup("fw_...")` with a **project token** from Framework Cloud pulls
#'   that project's cloud definition and scaffolds it locally. The project's
#'   `.env` records the token and its server (`FW_CLOUD_URL`), so [publish()]
#'   and the ledger go back to the server the project came from.
#' - `setup()` (or with a port number) initializes Framework's global
#'   configuration and launches the legacy GUI for first-time setup.
#'
#' @param port A project token string (cloud mode), or a port number for the
#'   legacy GUI (default: 8080)
#' @param browse Automatically open browser/folder (default: TRUE)
#' @param location Cloud mode only: where to create the project (prompted
#'   interactively when NULL)
#' @param url Cloud mode only: the Framework Cloud server that issued the
#'   token. Defaults to `FW_CLOUD_URL`, then the server you last logged in to
#'   with [cloud_login()], then <https://framework.pub>.
#'
#' @return Cloud mode: invisibly, the project_create() result. GUI mode:
#'   invisibly returns the plumber server object.
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Set up a cloud-defined project by its token
#' framework::setup("1|fw_abc123...")
#'
#' # From a self-hosted server
#' framework::setup("1|fw_abc123...", url = "https://framework.example.edu")
#'
#' # First-time setup (legacy GUI)
#' framework::setup()
#' }
#' }
#'
#' @seealso [new()], [cloud_login()], [gui()]
#'
#' @export
setup <- function(port = 8080, browse = TRUE, location = NULL, url = NULL) {
  # A character first argument is a Framework Cloud project token
  if (is.character(port) && length(port) == 1) {
    checkmate::assert_string(url, min.chars = 1, null.ok = TRUE)
    return(.cloud_setup(token = port, location = location, browse = browse, url = url))
  }

  # Ensure global config exists
  init_global_config()

  # Launch GUI directly to settings page
  gui(port = port, browse = browse, route = "#/settings/basics")
}

#' Launch Framework GUI
#'
#' Opens a beautiful web-based interface for Framework with documentation,
#' project management, and settings configuration.
#'
#' The GUI requires the optional 'plumber' package, which in turn depends on
#' 'sodium' (and the system libsodium library). Everything else in Framework
#' works without it.
#'
#' The GUI's API can change settings and `.env` files, so the server
#' accepts API calls only from the GUI page it served. It rejects requests
#' from other websites (by their `Origin` header), and requests that change
#' things must carry a session cookie that only the GUI page gets. When bound
#' to a loopback address, it answers only to `localhost` and `127.0.0.1`.
#' Set `FW_GUI_ALLOWED_ORIGINS` (comma-separated) to allow another origin,
#' such as a development server.
#'
#' @param port Port number to use (default: 8080)
#' @param host Host address to bind to. Default "127.0.0.1" for local access only.
#'   Use "0.0.0.0" to allow connections from other machines (requires appropriate
#'   network security).
#' @param browse Automatically open browser (default: TRUE)
#' @param route Initial route to open (default: NULL for home page)
#'
#' @return Invisibly returns the plumber server object
#'
#' @examples
#' \donttest{
#' if (FALSE) {
#' # Launch the GUI
#' framework::gui()
#'
#' # Launch on specific port
#' framework::gui(port = 8888)
#'
#' # Open directly to settings
#' framework::gui(route = "#/settings/basics")
#'
#' # Run as standalone server (no browser, accessible from network)
#' framework::gui(port = 8080, host = "0.0.0.0", browse = FALSE)
#' }
#' }
#'
#' @seealso [setup()] for first-time configuration
#'
#' @export
gui <- function(port = 8080, host = "127.0.0.1", browse = TRUE, route = NULL) {
  if (!requireNamespace("plumber", quietly = TRUE)) {
    stop(
      "The Framework GUI requires the 'plumber' package. ",
      'Install it with install.packages("plumber").',
      call. = FALSE
    )
  }

  # Check if we're in development mode (loaded via devtools::load_all)
  # Dev mode has inst/ directory; installed packages flatten inst/ contents to root
  is_dev_mode <- FALSE
  pkg_path <- find.package("framework")
  if (dir.exists(file.path(pkg_path, "inst"))) {
    # We're in a development directory structure (inst/ only exists in source)
    is_dev_mode <- TRUE
    dev_root <- pkg_path
  }

  # Find GUI assets directory
  if (is_dev_mode) {
    gui_path <- file.path(dev_root, "inst", "gui")
  } else {
    gui_path <- system.file("gui", package = "framework")
  }
  if (gui_path == "" || !dir.exists(gui_path)) {
    stop("GUI assets not found. Please rebuild the package with `npm run deploy`.")
  }

  # Find plumber API file
  if (is_dev_mode) {
    plumber_file <- file.path(dev_root, "inst", "plumber.R")
  } else {
    plumber_file <- system.file("plumber.R", package = "framework")
  }
  if (plumber_file == "" || !file.exists(plumber_file)) {
    stop("Plumber API file not found.")
  }

  # Create plumber API
  pr <- plumber::pr(plumber_file)

  # The API can change settings and .env files, so only the GUI page this
  # server sent may call it. See .gui_check_request().
  session_token <- .gui_new_token()
  loopback <- .gui_is_loopback(host)
  allowed_origins <- .gui_allowed_origins(dev = is_dev_mode)

  pr$filter("guard", function(req, res) {
    problem <- .gui_check_request(req, session_token, loopback, allowed_origins)
    if (!is.null(problem)) {
      res$status <- problem$status
      res$setHeader("Content-Type", "application/json")
      res$body <- jsonlite::toJSON(list(error = problem$message), auto_unbox = TRUE)
      return(res)
    }
    origin <- req$HTTP_ORIGIN %||% ""
    if (nzchar(origin) && origin %in% allowed_origins) {
      # The Vite dev server (gui-dev) runs on another port
      res$setHeader("Access-Control-Allow-Origin", origin)
      res$setHeader("Vary", "Origin")
      res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
      res$setHeader("Access-Control-Allow-Headers", "Content-Type")
      res$setHeader("Access-Control-Allow-Credentials", "true")
    }
    if (identical(req$REQUEST_METHOD, "OPTIONS")) {
      res$status <- 204
      res$body <- ""
      return(res)
    }
    plumber::forward()
  })

  # Add static file serving filter for GUI assets
  pr$filter("static", function(req, res) {
    # Only handle non-API requests
    if (!grepl("^/api/", req$PATH_INFO)) {
      # Determine file path
      path <- req$PATH_INFO
      if (path == "/" || path == "") {
        path <- "/index.html"
      }
      # Stay inside the GUI folder
      if (grepl("(^|/)\\.\\.(/|$)", path) || grepl("\\\\", path)) {
        res$status <- 404
        return(res)
      }

      file_path <- file.path(gui_path, gsub("^/", "", path))

      if (file.exists(file_path)) {
        # Determine content type
        ext <- tools::file_ext(file_path)
        content_type <- switch(ext,
          html = "text/html",
          css = "text/css",
          js = "application/javascript",
          json = "application/json",
          png = "image/png",
          jpg = "image/jpeg",
          jpeg = "image/jpeg",
          gif = "image/gif",
          svg = "image/svg+xml",
          ico = "image/x-icon",
          "application/octet-stream"
        )

        # Read file
        is_binary <- grepl("^image/", content_type) || ext == "ico"
        if (is_binary) {
          body <- readBin(file_path, "raw", file.info(file_path)$size)
        } else {
          body <- paste(readLines(file_path, warn = FALSE), collapse = "\n")
        }

        res$status <- 200
        res$setHeader("Content-Type", content_type)
        if (identical(content_type, "text/html")) {
          # The page's own requests carry this cookie; other sites' do not
          res$setHeader("Set-Cookie", .gui_cookie(session_token))
        }
        res$body <- body
        return(res)
      }
    }

    plumber::forward()
  })

  # Print startup message
  message("\n================================================================")
  message("Framework GUI")
  message("================================================================")
  display_host <- if (host == "0.0.0.0") "localhost" else host
  message("Running at: http://", display_host, ":", port)
  if (host == "0.0.0.0") {
    message("Listening on all interfaces (0.0.0.0)")
  }
  message("Press Ctrl+C to stop")
  message("================================================================\n")

  # Open browser if requested
  if (browse) {
    # Always open localhost in browser, even if binding to 0.0.0.0
    browser_host <- if (host == "0.0.0.0") "127.0.0.1" else host
    url <- paste0("http://", browser_host, ":", port)
    if (!is.null(route)) {
      url <- paste0(url, "/", gsub("^/", "", route))
    }
    browser_opt <- getOption("browser")
    if (is.null(browser_opt) || !nzchar(browser_opt)) {
      message("Note: No browser configured. Open manually: ", url)
    } else {
      tryCatch(
        utils::browseURL(url),
        error = function(e) {
          message("Could not open browser. Open manually: ", url)
        }
      )
    }
  }

  # Run the server (blocking until Ctrl+C)
  pr$run(port = port, host = host)
}


# GUI request guard -------------------------------------------------------
#
# The GUI API has no login and can change settings and .env files. It runs
# on this machine, so it trusts only:
#   - a Host header that names this machine, when bound to a loopback
#     address (stops DNS rebinding);
#   - no Origin header, or an Origin equal to the server's own (or the
#     gui-dev Vite server in development);
#   - for requests that change things (POST, PUT, DELETE), the session
#     cookie set when this server sent the GUI page. The cookie is
#     SameSite=Strict, so another site's requests never carry it.

#' @keywords internal
.gui_new_token <- function() {
  paste(as.character(openssl::rand_bytes(24)), collapse = "")
}

#' @keywords internal
.gui_cookie <- function(token) {
  sprintf("fw_gui_session=%s; Path=/; HttpOnly; SameSite=Strict", token)
}

#' @keywords internal
.gui_is_loopback <- function(host) {
  host %in% c("127.0.0.1", "localhost", "::1", "[::1]")
}

# Origins besides the server's own that may call the API: the gui-dev Vite
# server in development, plus FW_GUI_ALLOWED_ORIGINS (comma-separated).
#' @keywords internal
.gui_allowed_origins <- function(dev = FALSE) {
  extra <- trimws(strsplit(Sys.getenv("FW_GUI_ALLOWED_ORIGINS", ""), ",", fixed = TRUE)[[1]])
  dev_origins <- if (dev) c("http://localhost:5175", "http://127.0.0.1:5175", "http://framework.test:5175") else character()
  unique(c(dev_origins, extra[nzchar(extra)]))
}

#' @keywords internal
.gui_cookie_value <- function(cookie_header, name = "fw_gui_session") {
  if (is.null(cookie_header) || !nzchar(cookie_header)) {
    return(NULL)
  }
  parts <- trimws(strsplit(cookie_header, ";", fixed = TRUE)[[1]])
  hit <- parts[startsWith(parts, paste0(name, "="))]
  if (length(hit) == 0) NULL else substring(hit[1], nchar(name) + 2)
}

# NULL when the request may go on, otherwise list(status, message)
#' @keywords internal
.gui_check_request <- function(req, token, loopback = TRUE, allowed_origins = character()) {
  host_header <- req$HTTP_HOST %||% ""
  host_name <- tolower(sub(":[0-9]+$", "", host_header))
  if (loopback && !.gui_is_loopback(host_name)) {
    return(list(status = 403L, message = "The Framework GUI answers only to localhost."))
  }

  origin <- req$HTTP_ORIGIN %||% ""
  same_origin <- nzchar(host_header) && identical(origin, paste0("http://", host_header))
  dev_origin <- nzchar(origin) && origin %in% allowed_origins
  if (nzchar(origin) && !same_origin && !dev_origin) {
    return(list(status = 403L, message = "Requests from other websites are not allowed."))
  }

  method <- toupper(req$REQUEST_METHOD %||% "GET")
  is_api <- grepl("^/api/", req$PATH_INFO %||% "")
  if (is_api && !method %in% c("GET", "HEAD", "OPTIONS") && !dev_origin) {
    cookie <- .gui_cookie_value(req$HTTP_COOKIE)
    if (is.null(cookie) || !identical(cookie, token)) {
      return(list(status = 403L, message = "Reload the Framework GUI page, then try again."))
    }
  }
  NULL
}
