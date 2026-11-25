# flatten_versions(): POST /api/v1/artifacts/{slug}/flatten on Framework
# Cloud, after asking.

local_flatten_project <- function(env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  withr::local_envvar(FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA,
                      .local_envir = env)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE, .env = env)
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  dir
}

# Mock httr2 so a request records its URL, method, and token, and answers `answer`
local_flatten_server <- function(answer, env = parent.frame()) {
  sent <- new.env()
  sent$requests <- list()
  testthat::local_mocked_bindings(
    req_auth_bearer_token = function(req, token) {
      sent$token <- token
      req
    },
    req_perform = function(req, ...) {
      sent$requests[[length(sent$requests) + 1L]] <- list(url = req$url, method = req$method, auth = sent$token)
      req
    },
    resp_body_json = function(resp, ...) answer,
    .package = "httr2", .env = env
  )
  sent
}

answer <- list(artifact = "main-results", version = 1L, removed = 3L,
               artifact_url = "http://localhost:8080/artifacts/42")

test_that("flatten_versions() posts to the artifact's flatten route and reports what it removed", {
  skip_if_not_installed("httr2")
  local_flatten_project()
  sent <- local_flatten_server(answer)
  messages <- character()
  url <- withCallingHandlers(
    flatten_versions("main-results", confirm = TRUE),
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_length(sent$requests, 1L)
  expect_identical(sent$requests[[1]]$url, "http://localhost:8080/api/v1/artifacts/main-results/flatten")
  expect_identical(sent$requests[[1]]$method, "POST")
  expect_identical(sent$requests[[1]]$auth, "fw_project")
  expect_true("Flattened main-results to version 1; removed 3 older versions.\n" %in% messages)
  expect_true("Manage: http://localhost:8080/artifacts/42\n" %in% messages)
  expect_identical(as.character(url), "http://localhost:8080/artifacts/42")
  expect_identical(attr(url, "removed"), 3L)
})

test_that("project is sent as a query parameter, and one removed version reads singular", {
  skip_if_not_installed("httr2")
  local_flatten_project()
  sent <- local_flatten_server(modifyList(answer, list(removed = 1L)))
  expect_message(flatten_versions("main results", project = "thesis", confirm = TRUE),
                 "removed 1 older version.", fixed = TRUE)
  expect_identical(sent$requests[[1]]$url,
                   "http://localhost:8080/api/v1/artifacts/main%20results/flatten?project=thesis")
})

test_that("flatten_versions() asks in a console, defaulting to No", {
  skip_if_not_installed("httr2")
  local_flatten_project()
  sent <- local_flatten_server(answer)
  prompts <- character()
  testthat::local_mocked_bindings(
    .fw_interactive = function() TRUE,
    .fw_readline = function(prompt) {
      prompts <<- c(prompts, prompt)
      ""
    }
  )
  expect_message(result <- flatten_versions("main-results"), "Cancelled: nothing was changed.")
  expect_null(result)
  expect_identical(prompts, "Flatten main-results? [y/n] ")
  expect_length(sent$requests, 0L)

  testthat::local_mocked_bindings(.fw_interactive = function() TRUE, .fw_readline = function(prompt) "y")
  suppressMessages(flatten_versions("main-results"))
  expect_length(sent$requests, 1L)
})

test_that("without a console, flatten_versions() needs confirm = TRUE, and FALSE cancels", {
  skip_if_not_installed("httr2")
  local_flatten_project()
  sent <- local_flatten_server(answer)
  testthat::local_mocked_bindings(.fw_interactive = function() FALSE)
  expect_error(suppressMessages(flatten_versions("main-results")), "pass confirm = TRUE")
  expect_null(suppressMessages(flatten_versions("main-results", confirm = FALSE)))
  expect_length(sent$requests, 0L)
})

test_that("an account login is used when the project has no token", {
  skip_if_not_installed("httr2")
  local_flatten_project()
  writeLines("FW_CLOUD_URL=http://localhost:8080", ".env")
  withr::local_envvar(FW_CLOUD_TOKEN = "fw_account", FW_CLOUD_URL = "http://localhost:8080")
  sent <- local_flatten_server(answer)
  suppressMessages(flatten_versions("main-results", confirm = TRUE))
  expect_identical(sent$requests[[1]]$auth, "fw_account")
})

test_that("bad arguments stop before any request", {
  local_flatten_project()
  expect_error(flatten_versions(""))
  expect_error(flatten_versions(c("a", "b")))
  expect_error(flatten_versions("a", project = 1))
  expect_error(flatten_versions("a", confirm = "yes"))
})
