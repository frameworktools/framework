# new_project() through Framework Cloud's resolver, the cached defaults, and
# the offline rules shared with framework-py and fw

local_signed_in <- function(env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  testthat::local_mocked_bindings(
    .fw_cloud_token = function(url = NULL) "fw_test",
    .fw_cloud_url = function(url = NULL, scope = "user") "https://cloud.test:8443",
    .fw_api = function(...) stop("Cloud registration unavailable in this test"),
    .env = env
  )
  withr::local_options(rlang_interactive = FALSE, .local_envir = env)
}

scripts_envelope <- function() {
  list(
    spec_version = 1,
    name = "Untitled project",
    author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""),
    layers = list(
      list(kind = "base", key = "project", layer = list(type = "project")),
      list(kind = "facet", key = "framework/workflow-scripts", layer = list(
        tools = list(quarto = FALSE, jupyter = FALSE),
        scaffold = list(workflow = "scripts", notebook_format = "script")
      )),
      list(kind = "project", key = "untitled-project", layer = list(language = "r", git = list(use_git = FALSE)))
    )
  )
}

create <- function(..., env = parent.frame()) {
  location <- file.path(withr::local_tempdir(.local_envir = env), "study")
  suppressMessages(new_project("Study", location, browse = FALSE, ...))
  location
}

test_that("signed in, new_project() builds the envelope the cloud resolves and caches the defaults", {
  local_signed_in()
  sent <- NULL
  local_mocked_bindings(.fw_resolve_request = function(choices, token, url) {
    sent <<- choices
    list(status = "ok", envelope = scripts_envelope(), revision = "rev-7", notices = "Your default blueprint is Standard.")
  })

  location <- file.path(withr::local_tempdir(), "study")
  expect_message(new_project("Study", location, browse = FALSE), "Your default blueprint is Standard.")
  expect_identical(sent, list(language = "r", name = "Study"))
  expect_false(file.exists(file.path(location, "_quarto.yml")))
  expect_identical(yaml::read_yaml(file.path(location, "settings", "scaffold.yml"))$scaffold$workflow, "scripts")

  cached <- framework:::.fw_defaults_cache_read("https://cloud.test:8443")
  expect_identical(cached$defaults_revision, "rev-7")
  expect_identical(cached$envelope$layers[[2]]$key, "framework/workflow-scripts")
  expect_true(file.exists(file.path(fw_config_dir(), "cache", "defaults", "cloud.test_8443", "r.json")))
})

test_that("explicit choices go to the cloud, and the defaults are refreshed separately", {
  local_signed_in()
  calls <- list()
  local_mocked_bindings(.fw_resolve_request = function(choices, token, url) {
    calls[[length(calls) + 1]] <<- choices
    list(status = "ok", envelope = scripts_envelope(), revision = "rev-8", notices = character())
  })
  create(type = "project_sensitive", workflow = "jupyter", tools = c(targets = TRUE, quarto = FALSE))
  expect_identical(calls[[1]], list(
    language = "r", name = "Study", blueprint = "framework/project_sensitive", workflow = "jupyter",
    tools = list(targets = TRUE, quarto = FALSE)
  ))
  expect_identical(calls[[2]], list(language = "r"))
  expect_identical(framework:::.fw_defaults_cache_read("https://cloud.test:8443")$defaults_revision, "rev-8")
})

test_that("offline with saved defaults, new_project() uses them and says so", {
  local_signed_in()
  framework:::.fw_defaults_cache_write("https://cloud.test:8443", scripts_envelope(), "rev-7")
  local_mocked_bindings(.fw_resolve_request = function(...) list(status = "offline", reason = "timeout"))

  location <- file.path(withr::local_tempdir(), "study")
  expect_message(new_project("Study", location, browse = FALSE),
                 paste0("Using your Framework Cloud defaults from ", format(Sys.time(), "%Y-%m-%d", tz = "UTC")))
  expect_identical(yaml::read_yaml(file.path(location, "settings", "scaffold.yml"))$scaffold$workflow, "scripts")
})

test_that("offline with no usable defaults stops in scripts unless offline = TRUE", {
  local_signed_in()
  local_mocked_bindings(.fw_resolve_request = function(...) list(status = "offline", reason = "timeout"))

  expect_error(create(), "no saved Framework Cloud defaults.*offline = TRUE")
  framework:::.fw_defaults_cache_write("https://cloud.test:8443", scripts_envelope(), "rev-7")
  expect_error(create(workflow = "jupyter"), "beyond the language need a connection")

  location <- create(workflow = "jupyter", offline = TRUE)
  expect_identical(yaml::read_yaml(file.path(location, "settings", "scaffold.yml"))$scaffold$workflow, "jupyter")
})

test_that("offline = TRUE never contacts the cloud", {
  local_signed_in()
  local_mocked_bindings(
    .fw_resolve_request = function(...) stop("contacted the cloud"),
    .fw_api = function(...) testthat::fail("offline creation attempted registration")
  )
  location <- create(offline = TRUE)
  expect_true(file.exists(file.path(location, "_quarto.yml")))
})

test_that("not signed in, new_project() uses the built-ins without asking", {
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  local_mocked_bindings(.fw_resolve_request = function(...) stop("contacted the cloud"))
  location <- create()
  expect_true(file.exists(file.path(location, "_quarto.yml")))
})

test_that("the resolve request sorts offline, auth, and conflict responses", {
  skip_if_not_installed("httr2")
  request <- function(response) {
    httr2::local_mocked_responses(function(req) response)
    framework:::.fw_resolve_request(list(language = "r"), "fw_test", "https://cloud.test")
  }

  ok <- request(httr2::response(
    status_code = 200,
    headers = c("Content-Type: application/json", "Framework-Defaults-Revision: rev-9",
                "Framework-Notice: First notice", "Framework-Notice: Second notice"),
    body = charToRaw(jsonlite::toJSON(scripts_envelope(), auto_unbox = TRUE))
  ))
  expect_identical(ok$status, "ok")
  expect_identical(ok$revision, "rev-9")
  expect_identical(ok$notices, c("First notice", "Second notice"))
  expect_identical(ok$envelope$name, "Untitled project")

  expect_identical(request(httr2::response(status_code = 503))$status, "offline")
  expect_error(request(httr2::response(status_code = 401)), "refused your token")
  expect_error(request(httr2::response(status_code = 403)), "refused your token")
  expect_error(request(httr2::response(
    status_code = 422, headers = "Content-Type: application/json",
    body = charToRaw('{"message":"Invalid","errors":{"tools.quarto":["The Course blueprint requires Quarto."]}}')
  )), "requires Quarto")
})


test_that("new_project registers its resolved choices and saves an ignored project token", {
  local_signed_in()
  sent <- NULL
  local_mocked_bindings(
    .fw_resolve_request = function(choices, token, url) {
      list(status = "ok", envelope = scripts_envelope(), revision = "rev-9", notices = character())
    },
    .fw_api = function(path, token, method = "GET", body = NULL, url = NULL) {
      sent <<- list(path = path, body = body, method = method)
      list(slug = "study", token = "1|project-token")
    }
  )
  location <- create(type = "project", tools = c(targets = TRUE), skill_sets = "framework")
  expect_identical(sent$path, "/api/v2/projects")
  expect_identical(sent$method, "POST")
  expect_identical(sent$body, list(
    language = "r", name = "Study", blueprint = "framework/project",
    tools = list(targets = TRUE), skill_sets = list("framework")
  ))
  expect_true("FW_PROJECT_TOKEN=1|project-token" %in% readLines(file.path(location, ".env")))
  expect_true("FW_CLOUD_URL=https://cloud.test:8443" %in% readLines(file.path(location, ".env")))
  expect_true(".env" %in% readLines(file.path(location, ".gitignore")))
})

test_that("failed Cloud registration leaves a usable local project", {
  local_signed_in()
  local_mocked_bindings(
    .fw_resolve_request = function(...) {
      list(status = "ok", envelope = scripts_envelope(), revision = "rev-9", notices = character())
    },
    .fw_api = function(...) stop("server unavailable")
  )
  location <- file.path(withr::local_tempdir(), "study")
  expect_message(new_project("Study", location, browse = FALSE), "Cloud project registration skipped: server unavailable")
  expect_true(file.exists(file.path(location, "settings.yml")))
  expect_false(any(grepl("^FW_PROJECT_TOKEN=", readLines(file.path(location, ".env")))))
})


test_that("bare project registration does not create a token file", {
  local_signed_in()
  location <- withr::local_tempdir()
  local_mocked_bindings(.fw_api = function(...) list(slug = "bare", token = "1|bare-token"))
  expect_message(framework:::.fw_cloud_register_project(location, "Bare", "bare", list(language = "r", name = "Bare")), "Registered on")
  expect_false(file.exists(file.path(location, ".env")))
})
