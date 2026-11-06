device_start <- function(req) {
  httr2::response_json(body = list(
    device_code = "dev-123", user_code = "ABCD-EFGH",
    verification_url = "http://localhost:8080/device",
    verification_url_complete = "http://localhost:8080/device?code=ABCD-EFGH",
    interval = 2, expires_in = 10
  ))
}

mock_device <- function(replies) {
  seen <- character()
  pending <- replies
  handler <- function(req) {
    path <- sub("^https?://[^/]+", "", req$url)
    seen <<- c(seen, path)
    if (identical(path, "/api/v1/cli/device")) return(device_start(req))
    if (identical(path, "/api/v1/cli/device/token")) {
      expect_null(req$headers$Authorization)
      status <- if (length(pending)) pending[[1]] else 200L
      pending <<- pending[-1]
      if (status == 200L) {
        return(httr2::response_json(body = list(token = "fw_browser_0123456789")))
      }
      return(httr2::response_json(status_code = status, body = list(error = "pending")))
    }
    if (identical(path, "/api/v1/me")) {
      return(httr2::response_json(body = list(email = "ada@example.org")))
    }
    httr2::response(status_code = 404)
  }
  list(handler = handler, seen = function() seen)
}

test_that("cloud_login() without a token approves this computer in the browser", {
  skip_if_not_installed("httr2")
  withr::local_envvar(FW_TOKEN_FILE = withr::local_tempfile(), FW_CONFIG_HOME = withr::local_tempdir(),
                      R_USER_CONFIG_DIR = withr::local_tempdir())
  mock <- mock_device(c(428L, 429L))
  waits <- numeric()
  local_mocked_bindings(.fw_sleep = function(seconds) waits <<- c(waits, seconds))
  httr2::local_mocked_responses(mock$handler)
  stored <- suppressMessages(cloud_login(url = "http://localhost:8080", browser = FALSE))
  expect_identical(stored, Sys.getenv("FW_TOKEN_FILE"))
  expect_identical(readLines(stored), "fw_browser_0123456789")
  expect_identical(waits, c(2, 2, 7))
  expect_identical(mock$seen(), c(
    "/api/v1/cli/device", "/api/v1/cli/device/token", "/api/v1/cli/device/token",
    "/api/v1/cli/device/token", "/api/v1/me"
  ))
})

test_that("cloud_login() reports a denied or expired browser login", {
  skip_if_not_installed("httr2")
  withr::local_envvar(FW_TOKEN_FILE = withr::local_tempfile(), FW_CONFIG_HOME = withr::local_tempdir())
  local_mocked_bindings(.fw_sleep = function(seconds) NULL)
  httr2::local_mocked_responses(mock_device(403L)$handler)
  expect_error(suppressMessages(cloud_login(url = "http://localhost:8080", browser = FALSE)),
               "denied in the browser")
  httr2::local_mocked_responses(mock_device(410L)$handler)
  expect_error(suppressMessages(cloud_login(url = "http://localhost:8080", browser = FALSE)),
               "code expired")
  expect_false(file.exists(Sys.getenv("FW_TOKEN_FILE")))
})
