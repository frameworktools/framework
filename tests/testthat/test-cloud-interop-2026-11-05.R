# Cloud interop fixes from the 2026-11-05 audit: upload visibility, the
# handle hint, logout revocation, fw's saved server, the macOS keychain
# through /usr/bin/security, and a blank author email.

local_interop_env <- function(env = parent.frame()) {
  base <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(
    FW_CONFIG_HOME = NA, XDG_CONFIG_HOME = file.path(base, "xdg"),
    FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA,
    .local_envir = env
  )
  r_dir <- file.path(base, "r")
  dir.create(r_dir)
  testthat::local_mocked_bindings(R_user_dir = function(...) r_dir, .package = "tools", .env = env)
  withr::local_dir(withr::local_tempdir(.local_envir = env), .local_envir = env)
  list(r = r_dir, fw = file.path(base, "xdg", "framework"))
}

# ---- Contract 2: upload visibility --------------------------------------

test_that("a string slug sends no readable and no visibility", {
  skip_if_not_installed("httr2")
  local_interop_env()
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeLines("<p>hi</p>", "report.html")
  sent <- list()
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      sent[[length(sent) + 1L]] <<- rlang::list2(...)
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(id = 1L, version = 1L, url = "http://localhost:8080/d/x"),
    .package = "httr2"
  )

  suppressMessages(publish("report.html", slug = "estimates"))
  expect_null(sent[[1]]$readable)
  expect_null(sent[[1]]$visibility)

  suppressMessages(publish("report.html", slug = "estimates", visibility = "public"))
  expect_identical(sent[[2]]$visibility, "public")
  expect_null(sent[[2]]$readable)
})

test_that("the collection pre-check does not count a string slug as public", {
  skip_if_not_installed("httr2")
  local_interop_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeLines("<p>hi</p>", "report.html")
  collection_visibility <- "unlisted"
  uploads <- 0L
  testthat::local_mocked_bindings(
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "GET")) {
        return(list(collections = list(list(id = 7L, slug = "findings", title = "Findings",
                                            visibility = collection_visibility))))
      }
      list(id = 1L)
    }
  )
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      uploads <<- uploads + 1L
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(id = 3L, version = 1L, url = "http://localhost:8080/d/x"),
    .package = "httr2"
  )

  # A string slug predicts nothing, so the pre-check leaves it to the server
  suppressMessages(publish("report.html", slug = "x", collection = "findings"))
  expect_identical(uploads, 1L)

  # slug = FALSE asks for unlisted, which still needs consent
  expect_error(publish("report.html", slug = FALSE, collection = "findings"), "share_unlisted")

  collection_visibility <- "public"
  expect_error(publish("report.html", slug = FALSE, collection = "findings"),
               "Public collections require public artifacts")
  suppressMessages(publish("report.html", slug = "x", visibility = "public", collection = "findings"))
  expect_identical(uploads, 2L)
})

# ---- Contract 1: logout revokes the token ------------------------------

local_revoke_server <- function(status = 204L, env = parent.frame()) {
  seen <- new.env()
  seen$requests <- list()
  httr2::local_mocked_responses(function(req) {
    seen$requests[[length(seen$requests) + 1L]] <- list(
      url = req$url, method = req$method, auth = httr2::req_get_headers(req, "reveal")$Authorization
    )
    if (is.na(status)) stop("Could not resolve host")
    httr2::response(status_code = status)
  }, env = env)
  seen
}

test_that("cloud_logout() revokes the FW_TOKEN_FILE token, then removes it", {
  skip_if_not_installed("httr2")
  local_interop_env()
  token_file <- withr::local_tempfile()
  writeLines("fw_file_token", token_file)
  withr::local_envvar(FW_TOKEN_FILE = token_file)
  seen <- local_revoke_server(204L)

  expect_message(cloud_logout(url = "http://localhost:8080"), "Removed")
  expect_false(file.exists(token_file))
  expect_length(seen$requests, 1L)
  expect_identical(seen$requests[[1]]$url, "http://localhost:8080/api/v1/token")
  expect_identical(seen$requests[[1]]$method, "DELETE")
  expect_identical(seen$requests[[1]]$auth, "Bearer fw_file_token")
})

test_that("cloud_logout() revokes the keychain token before deleting it", {
  skip_if_not_installed("httr2")
  local_interop_env()
  order <- character()
  testthat::local_mocked_bindings(
    .fw_keychain_available = function() TRUE,
    .fw_keyring_get = function(service) {
      if (identical(service, "framework-cloud:localhost:8080")) "fw_keychain_token" else NULL
    },
    .fw_keyring_delete = function(service) {
      order <<- c(order, paste("delete", service))
      identical(service, "framework-cloud:localhost:8080")
    }
  )
  httr2::local_mocked_responses(function(req) {
    order <<- c(order, paste("revoke", httr2::req_get_headers(req, "reveal")$Authorization))
    httr2::response(status_code = 204L)
  })

  expect_message(cloud_logout(url = "http://localhost:8080"), "keyring (framework-cloud:localhost:8080)",
                 fixed = TRUE)
  expect_identical(order, c("revoke Bearer fw_keychain_token", "delete framework-cloud:localhost:8080"))
})

test_that("cloud_logout() treats 401 as already revoked", {
  skip_if_not_installed("httr2")
  local_interop_env()
  token_file <- withr::local_tempfile()
  writeLines("fw_old", token_file)
  withr::local_envvar(FW_TOKEN_FILE = token_file)
  local_revoke_server(401L)

  msgs <- testthat::capture_messages(cloud_logout(url = "http://localhost:8080"))
  expect_false(any(grepl("Could not revoke", msgs)))
  expect_false(file.exists(token_file))
})

test_that("cloud_logout() still removes the local token when the server is unreachable", {
  skip_if_not_installed("httr2")
  local_interop_env()
  token_file <- withr::local_tempfile()
  writeLines("fw_offline", token_file)
  withr::local_envvar(FW_TOKEN_FILE = token_file)
  local_revoke_server(NA)

  msgs <- testthat::capture_messages(cloud_logout(url = "http://localhost:8080"))
  expect_true(any(grepl("Could not revoke the token on localhost:8080. Revoke it at http://localhost:8080/tokens.",
                        msgs, fixed = TRUE)))
  expect_false(file.exists(token_file))
})

test_that("cloud_logout() leaves an FW_CLOUD_TOKEN token alone", {
  skip_if_not_installed("httr2")
  local_interop_env()
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  withr::local_envvar(FW_CLOUD_TOKEN = "fw_env_token")
  seen <- local_revoke_server(204L)

  expect_message(cloud_logout(url = "http://localhost:8080"), "No stored token")
  expect_length(seen$requests, 0L)
})

# ---- Default server: fw's cloud.yml ------------------------------------

test_that("the saved server reads fw's cloud.yml first, then R's", {
  dirs <- local_interop_env()
  server <- framework:::.fw_cloud_server

  expect_identical(server()$url, "https://framework.pub")

  writeLines("server: http://localhost:8080", file.path(dirs$r, "cloud.yml"))
  expect_identical(server()$url, "http://localhost:8080")

  # After `fw login`: fw's file wins, as in fw and Python
  dir.create(dirs$fw, recursive = TRUE)
  writeLines("server: https://fw.example.edu", file.path(dirs$fw, "cloud.yml"))
  expect_identical(server()$url, "https://fw.example.edu")
  expect_identical(server()$source, "your cloud_login() default")

  # An empty or broken fw file falls through to R's
  writeLines("server: ''", file.path(dirs$fw, "cloud.yml"))
  expect_identical(server()$url, "http://localhost:8080")

  withr::local_envvar(FW_CLOUD_URL = "https://env.example.edu")
  expect_identical(server()$url, "https://env.example.edu")
})

test_that("FW_CONFIG_HOME is fw's folder and R's at once", {
  local_interop_env()
  home <- withr::local_tempdir()
  withr::local_envvar(FW_CONFIG_HOME = home)
  writeLines("server: https://shared.example.edu", file.path(home, "cloud.yml"))
  expect_identical(framework:::.fw_cloud_server()$url, "https://shared.example.edu")
})

test_that("saving the server writes R's file, and fw's only when it exists", {
  dirs <- local_interop_env()
  framework:::.fw_save_cloud_url("http://localhost:8080")
  expect_identical(yaml::read_yaml(file.path(dirs$r, "cloud.yml"))$server, "http://localhost:8080")
  expect_false(dir.exists(dirs$fw))

  dir.create(dirs$fw, recursive = TRUE)
  writeLines("server: https://fw.example.edu", file.path(dirs$fw, "cloud.yml"))
  framework:::.fw_save_cloud_url("https://r.example.edu")
  expect_identical(yaml::read_yaml(file.path(dirs$fw, "cloud.yml"))$server, "https://r.example.edu")
  expect_identical(framework:::.fw_cloud_server()$url, "https://r.example.edu")
})

# ---- Contract 3: macOS keychain through /usr/bin/security --------------

test_that("keychain reads parse security's output and go-keyring's base64", {
  testthat::local_mocked_bindings(.fw_use_macos_security = function() TRUE)
  calls <- list()
  reply <- list(status = 0L, output = "fw_plain_token")
  testthat::local_mocked_bindings(.fw_security = function(args) {
    calls[[length(calls) + 1L]] <<- args
    reply
  })
  expect_identical(framework:::.fw_keyring_get("framework-cloud:keychain-test.invalid"), "fw_plain_token")
  expect_identical(calls[[1]], c("find-generic-password", "-s", shQuote("framework-cloud:keychain-test.invalid"),
                                 "-a", "token", "-w"))

  reply <- list(status = 0L, output = paste0("go-keyring-base64:", jsonlite::base64_enc("fw_encoded")))
  expect_identical(framework:::.fw_keyring_get("framework-cloud:keychain-test.invalid"), "fw_encoded")

  reply <- structure(list(status = 44L, output = character()))
  expect_null(framework:::.fw_keyring_get("framework-cloud:keychain-test.invalid"))
})

test_that("keychain writes go through security -i on stdin and refuse quotes", {
  testthat::local_mocked_bindings(.fw_use_macos_security = function() TRUE)
  sent <- NULL
  testthat::local_mocked_bindings(.fw_security_stdin = function(command) {
    sent <<- command
    0L
  })
  framework:::.fw_keyring_set("framework-cloud:keychain-test.invalid", "fw_abc")
  expect_identical(sent, "add-generic-password -U -s 'framework-cloud:keychain-test.invalid' -a 'token' -w 'fw_abc'")
  expect_error(framework:::.fw_keyring_set("framework-cloud:keychain-test.invalid", "fw_a'b"), "quote")
  expect_error(framework:::.fw_keyring_set("framework-cloud:keychain-test.invalid", "fw_a\\b"), "backslash")
})

test_that("the real macOS keychain round-trips a throwaway item", {
  skip_on_cran()
  skip_if_not(framework:::.fw_use_macos_security(), "macOS only")
  skip_if(nzchar(Sys.getenv("CI")), "no login keychain on CI")
  service <- "framework-cloud:keychain-test.invalid"
  withr::defer(framework:::.fw_keyring_delete(service))
  framework:::.fw_keyring_delete(service)

  expect_null(framework:::.fw_keyring_get(service))
  framework:::.fw_keyring_set(service, "fw_keychain_roundtrip")
  expect_identical(framework:::.fw_keyring_get(service), "fw_keychain_roundtrip")
  framework:::.fw_keyring_set(service, "fw_keychain_updated")
  expect_identical(framework:::.fw_keyring_get(service), "fw_keychain_updated")

  # An item as go-keyring writes it
  encoded <- paste0("go-keyring-base64:", jsonlite::base64_enc("fw_from_go"))
  framework:::.fw_security_stdin(sprintf("add-generic-password -U -s '%s' -a 'token' -w '%s'", service, encoded))
  expect_identical(framework:::.fw_keyring_get(service), "fw_from_go")

  expect_true(framework:::.fw_keyring_delete(service))
  expect_null(framework:::.fw_keyring_get(service))
  expect_false(framework:::.fw_keyring_delete(service))
})

# ---- Blank author email -------------------------------------------------

test_that("a blank author email is left out of author.yml", {
  skip_if_not_installed("yaml")
  skip_on_cran()
  project_dir <- tempfile("framework_test_")
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  result <- suppressMessages(project_create(
    name = "blank_email",
    location = project_dir,
    type = "project",
    author = list(name = "Ada Lovelace", email = "", affiliation = ""),
    directories = list(notebooks = "notebooks"),
    git = list(use_git = FALSE, hooks = list(), gitignore_content = "")
  ))
  author <- yaml::read_yaml(file.path(result$path, "settings", "author.yml"))$author
  expect_identical(author$name, "Ada Lovelace")
  expect_false("email" %in% names(author))
  expect_false(any(grepl("email", readLines(file.path(result$path, "settings", "author.yml")))))
})
