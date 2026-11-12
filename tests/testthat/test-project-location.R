# A new project's location is always explicit: with no `location`, an
# interactive session confirms a folder in the current directory or takes
# another one, and a non-interactive session stops.

local_answers <- function(answers, env = parent.frame()) {
  prompts <- character()
  testthat::local_mocked_bindings(
    .fw_interactive = function() TRUE,
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
  withr::local_envvar(HOME = "/home/ada")

  local_answers(c("no", "~/work/"))
  expect_identical(.fw_ask_location("my-study"), "/home/ada/work/my-study")

  local_answers(c("n", "/srv/projects/my-study"))
  expect_identical(.fw_ask_location("my-study"), "/srv/projects/my-study")

  here <- getwd()
  local_answers(c("n", "sub"))
  expect_identical(.fw_ask_location("my-study"), file.path(here, "sub", "my-study"))
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

test_that("setup(token) without a location stops when not interactive", {
  withr::local_envvar(FW_CONFIG_HOME = withr::local_tempdir(), FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA)
  home <- withr::local_tempdir()
  withr::local_envvar(HOME = home)
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
