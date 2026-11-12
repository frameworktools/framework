# A new project's location is always explicit: with no `location`, an
# interactive session confirms a folder in the current directory or takes
# another one, and a non-interactive session stops.

local_answers <- function(answers, projects_dir = NULL, env = parent.frame()) {
  prompts <- character()
  testthat::local_mocked_bindings(
    .fw_interactive = function() TRUE,
    .fw_projects_dir = function() projects_dir,
    .fw_readline = function(prompt) {
      prompts <<- c(prompts, prompt)
      if (length(answers) == 0) stop("No more answers for: ", prompt)
      out <- answers[[1]]
      answers <<- answers[-1]
      out
    },
    .env = env
  )
  function() prompts
}

local_cwd <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  getwd()
}

cloud_envelope <- function() {
  list(
    spec_version = 1L,
    name = "My Study",
    author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""),
    layers = list(
      list(kind = "base", key = "project", version = 1L, layer = list(type = "project")),
      list(kind = "project", key = "my-study", layer = list(language = "r"))
    ),
    source = list(origin = "cloud")
  )
}

test_that("Enter or y creates the project in the current directory", {
  here <- local_cwd()
  prompts <- local_answers(c(""))
  expect_identical(.fw_ask_location("my-study"), file.path(here, "my-study"))
  expect_identical(
    prompts(),
    paste0("Create the project here (", file.path(here, "my-study"), ")? [y/n] ")
  )

  local_answers(c("Y"))
  expect_identical(.fw_ask_location("my-study"), file.path(here, "my-study"))
})

test_that("n asks for a parent folder, and blank uses the current directory", {
  here <- local_cwd()
  prompts <- local_answers(c("n", ""))
  expect_identical(.fw_ask_location("my-study"), file.path(here, "my-study"))
  expect_identical(
    prompts()[[2]],
    paste0("Where should the project go? Leave blank to use the current directory (", here, "): ")
  )
})

test_that("a typed folder is the parent, unless it already ends in the project name", {
  local_cwd()
  withr::local_envvar(HOME = "/home/ada", USERPROFILE = "/home/ada")

  local_answers(c("no", "~/work/"))
  expect_identical(.fw_ask_location("my-study"), "/home/ada/work/my-study")

  local_answers(c("n", "/srv/projects/my-study"))
  expect_identical(.fw_ask_location("my-study"), "/srv/projects/my-study")

  here <- getwd()
  local_answers(c("n", "sub"))
  expect_identical(.fw_ask_location("my-study"), file.path(here, "sub", "my-study"))
})

test_that("a Projects folder from Framework Cloud is offered instead of the current directory", {
  here <- local_cwd()
  withr::local_envvar(HOME = "/home/ada", USERPROFILE = "/home/ada")
  prompts <- local_answers(c(""), projects_dir = "~/research")
  expect_identical(.fw_ask_location("my-study"), "/home/ada/research/my-study")
  expect_identical(prompts(), "Create the project in /home/ada/research/my-study? [y/n] ")
})

test_that("declining the Projects folder asks for a parent folder", {
  here <- local_cwd()
  prompts <- local_answers(c("n", ""), projects_dir = "/srv/research")
  expect_identical(.fw_ask_location("my-study"), file.path(here, "my-study"))
  expect_identical(
    prompts(),
    c(
      "Create the project in /srv/research/my-study? [y/n] ",
      paste0("Where should the project go? Leave blank to use the current directory (", here, "): ")
    )
  )

  local_answers(c("n", "/elsewhere"), projects_dir = "/srv/research")
  expect_identical(.fw_ask_location("my-study"), "/elsewhere/my-study")
})

test_that("a non-interactive session ignores the Projects folder and stops", {
  local_cwd()
  called <- FALSE
  testthat::local_mocked_bindings(
    .fw_interactive = function() FALSE,
    .fw_projects_dir = function() {
      called <<- TRUE
      "/srv/research"
    }
  )
  expect_error(.fw_ask_location("my-study"), "Pass `location =`")
  expect_false(called)
})

test_that("the Projects folder comes from the cloud settings document", {
  withr::local_envvar(FW_CONFIG_HOME = withr::local_tempdir(), FW_CLOUD_TOKEN = "1|fw_user")
  testthat::local_mocked_bindings(.fw_api = function(path, ...) {
    expect_identical(path, "/api/v1/settings")
    list(revision = 3L, document = list(defaults = list(ide = "positron", projects_dir = "~/research")))
  })
  expect_identical(.fw_projects_dir(), "~/research")

  testthat::local_mocked_bindings(.fw_api = function(path, ...) {
    list(revision = 3L, document = list(defaults = list(projects_dir = NULL)))
  })
  expect_null(.fw_projects_dir())

  testthat::local_mocked_bindings(.fw_api = function(path, ...) {
    list(revision = 3L, document = list(defaults = list(projects_dir = "  ")))
  })
  expect_null(.fw_projects_dir())
})

test_that("offline or signed out, the Projects folder comes from the synced mirror", {
  withr::local_envvar(FW_CONFIG_HOME = withr::local_tempdir(), FW_CLOUD_TOKEN = "1|fw_user")
  testthat::local_mocked_bindings(.fw_api = function(...) stop("Could not resolve host"))
  expect_null(.fw_projects_dir())

  writeLines("defaults:\n  projects_dir: ~/cached\n", .fw_sync_paths()$document)
  expect_identical(.fw_projects_dir(), "~/cached")

  withr::local_envvar(FW_CLOUD_TOKEN = NA, FW_TOKEN_FILE = file.path(tempdir(), "no-token"))
  expect_identical(.fw_projects_dir(), "~/cached")
})

test_that("an unrecognized answer asks again", {
  here <- local_cwd()
  prompts <- local_answers(c("maybe", "y"))
  expect_message(location <- .fw_ask_location("my-study"), "Answer y or n")
  expect_identical(location, file.path(here, "my-study"))
  expect_length(prompts(), 2)
})

test_that("without a location, a non-interactive session stops", {
  local_cwd()
  testthat::local_mocked_bindings(.fw_interactive = function() FALSE)
  expect_error(.fw_ask_location("my-study"), "Pass `location =`")
})

test_that("setup(token) asks where to create the project and says where it is", {
  withr::local_envvar(FW_CONFIG_HOME = withr::local_tempdir(), FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA)
  testthat::local_mocked_bindings(.fw_api = function(...) cloud_envelope())
  local_cwd()
  parent <- withr::local_tempdir()
  local_answers(c("n", parent))

  messages <- character()
  result <- withCallingHandlers(
    setup("1|fw_pull", browse = FALSE, url = "https://cloud.example.edu"),
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_true(result$success)
  expect_true(file.exists(file.path(parent, "my-study", "settings.yml")))
  expect_true(any(grepl(paste0("Creating the project at ", file.path(parent, "my-study")), messages, fixed = TRUE)))
  expect_true(any(grepl("Project ready at", messages, fixed = TRUE)))
})

test_that("the Framework-Projects-Dir header is decoded", {
  expect_null(.fw_header_projects_dir(NULL))
  expect_null(.fw_header_projects_dir(list(`Content-Type` = "application/json")))
  expect_null(.fw_header_projects_dir(list(`Framework-Projects-Dir` = "")))
  expect_identical(.fw_header_projects_dir(list(`framework-projects-dir` = "~/research")), "~/research")
  decoded <- .fw_header_projects_dir(list(`Framework-Projects-Dir` = "~/My%20Projects/%C3%A9tudes"))
  expect_identical(decoded, "~/My Projects/\u00e9tudes")
})

setup_with_header <- function(headers, projects_dir, answers, env = parent.frame()) {
  withr::local_envvar(
    FW_CONFIG_HOME = withr::local_tempdir(.local_envir = env), FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA,
    .local_envir = env
  )
  testthat::local_mocked_bindings(
    .fw_api = function(path, ..., headers = FALSE) {
      envelope <- cloud_envelope()
      attr(envelope, "headers") <- headers_value
      envelope
    },
    .env = env
  )
  headers_value <- headers
  local_answers(answers, projects_dir = projects_dir, env = env)
}

test_that("setup(token) offers the owner's Projects folder from the pull header first", {
  local_cwd()
  projects <- file.path(withr::local_tempdir(), "My Projects")
  encoded <- utils::URLencode(projects)
  prompts <- setup_with_header(list(`Framework-Projects-Dir` = encoded), "/from/settings", c("y"))

  result <- suppressMessages(setup("1|fw_pull", browse = FALSE, url = "https://cloud.example.edu"))
  expect_true(result$success)
  expect_true(file.exists(file.path(projects, "my-study", "settings.yml")))
  expect_identical(prompts(), paste0("Create the project in ", file.path(projects, "my-study"), "? [y/n] "))
})

test_that("setup(token) without the header falls back to the synced Projects folder", {
  local_cwd()
  projects <- withr::local_tempdir()
  prompts <- setup_with_header(list(), projects, c("y"))

  result <- suppressMessages(setup("1|fw_pull", browse = FALSE, url = "https://cloud.example.edu"))
  expect_true(result$success)
  expect_identical(prompts(), paste0("Create the project in ", file.path(projects, "my-study"), "? [y/n] "))
})

test_that("setup(token) with neither asks about the current directory", {
  here <- local_cwd()
  prompts <- setup_with_header(NULL, NULL, c("y"))

  result <- suppressMessages(setup("1|fw_pull", browse = FALSE, url = "https://cloud.example.edu"))
  expect_true(result$success)
  expect_identical(prompts(), paste0("Create the project here (", file.path(here, "my-study"), ")? [y/n] "))
})

test_that("setup(token) without a location stops when not interactive", {
  withr::local_envvar(FW_CONFIG_HOME = withr::local_tempdir(), FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA)
  home <- withr::local_tempdir()
  withr::local_envvar(HOME = home, USERPROFILE = home)
  testthat::local_mocked_bindings(
    .fw_api = function(...) cloud_envelope(),
    .fw_interactive = function() FALSE
  )
  here <- local_cwd()

  expect_error(
    suppressMessages(setup("1|fw_pull", browse = FALSE, url = "https://cloud.example.edu")),
    "Pass `location =`"
  )
  expect_false(dir.exists(file.path(home, "projects")))
  expect_false(dir.exists(file.path(here, "my-study")))
})

test_that("new_project() offers a folder in the current directory", {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup())
  here <- local_cwd()
  local_answers(c("y"))

  result <- suppressMessages(new_project("My Study", browse = FALSE, offline = TRUE))
  expect_true(result$success)
  expect_true(file.exists(file.path(here, "my-study", "settings.yml")))
})

test_that("new_project() creates a missing Projects folder with the project", {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup())
  local_cwd()
  projects <- file.path(withr::local_tempdir(), "not", "yet", "here")
  local_answers(c("y"), projects_dir = projects)

  result <- suppressMessages(new_project("My Study", browse = FALSE, offline = TRUE))
  expect_true(result$success)
  expect_true(file.exists(file.path(projects, "my-study", "settings.yml")))
})

test_that("new_project() makes a relative location absolute", {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup())
  here <- local_cwd()

  messages <- testthat::capture_messages(
    new_project("Study", "nested/study", browse = FALSE, offline = TRUE)
  )
  expect_true(any(startsWith(messages, paste0("Location: ", file.path(here, "nested", "study")))))
  expect_true(file.exists(file.path(here, "nested", "study", "settings.yml")))
})

test_that(".fw_api(headers = TRUE) keeps the response headers", {
  skip_if_not_installed("httr2")
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 200,
      headers = c("Content-Type: application/json", "Framework-Projects-Dir: ~/My%20Projects"),
      body = charToRaw('{"name": "My Study"}')
    )
  })
  res <- .fw_api("/api/v1/projects/pull", token = "1|fw_pull", url = "https://cloud.example.edu", headers = TRUE)
  expect_identical(res$name, "My Study")
  expect_identical(.fw_header_projects_dir(attr(res, "headers")), "~/My Projects")

  plain <- .fw_api("/api/v1/projects/pull", token = "1|fw_pull", url = "https://cloud.example.edu")
  expect_null(attr(plain, "headers"))
})
