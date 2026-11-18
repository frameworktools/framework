# A project's token goes only to the server that issued it, and project
# sync (packages, skills) reads the project's own settings and server

local_scope_env <- function(env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  withr::local_envvar(
    FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA,
    FW_TOKEN_FILE = NA, .local_envir = env
  )
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE, .env = env)
  # Whatever an earlier scaffold() loaded is undone afterwards
  loaded <- framework:::.fw_dotenv_loaded
  withr::defer({
    if (is.function(loaded$undo)) loaded$undo()
    loaded$undo <- NULL
    loaded$values <- NULL
  }, envir = env)
  withr::local_tempdir(.local_envir = env)
}

scope_project <- function(parent, name, env_lines = NULL) {
  dir <- file.path(parent, name)
  dir.create(dir, recursive = TRUE)
  writeLines(c("default:", "  project_type: project"), file.path(dir, "settings.yml"))
  if (!is.null(env_lines)) writeLines(env_lines, file.path(dir, ".env"))
  normalizePath(dir)
}

test_that("after scaffold() loads project A's .env, project B uses its own token and server", {
  parent <- local_scope_env()
  a <- scope_project(parent, "A", c("FW_PROJECT_TOKEN=tokA", "FW_CLOUD_URL=https://a.example"))
  b <- scope_project(parent, "B", c("FW_PROJECT_TOKEN=tokB", "FW_CLOUD_URL=https://b.example"))
  framework:::.fw_load_dotenv(file.path(a, ".env"))
  expect_identical(Sys.getenv("FW_PROJECT_TOKEN"), "tokA")

  expect_identical(framework:::.setup_connection(b), list(server = "https://b.example", token = "tokB"))
  expect_identical(framework:::.setup_connection(a), list(server = "https://a.example", token = "tokA"))

  # B has a token but no server: A's server (loaded into the session) is not B's
  c_dir <- scope_project(parent, "C", "FW_PROJECT_TOKEN=tokC")
  expect_identical(framework:::.fw_project_token(c_dir), "tokC")
  expect_error(framework:::.setup_connection(c_dir), class = "fw_project_server_missing")

  # A project with no token of its own never borrows A's, which scaffold() loaded
  d <- scope_project(parent, "D")
  expect_null(framework:::.fw_project_token(d))
  expect_error(framework:::.setup_connection(d), "no project token")
})

test_that("a shell FW_CLOUD_URL still names the server for a .env token without one", {
  parent <- local_scope_env()
  dir <- scope_project(parent, "P", "FW_PROJECT_TOKEN=tokP")
  withr::local_envvar(FW_CLOUD_URL = "https://shell.example")
  expect_identical(framework:::.setup_connection(dir), list(server = "https://shell.example", token = "tokP"))
})

test_that("a token only in the environment with no FW_CLOUD_URL stops instead of using the login server", {
  parent <- local_scope_env()
  framework:::.fw_save_cloud_url("https://login.example")
  dir <- scope_project(parent, "CI")
  withr::local_envvar(FW_PROJECT_TOKEN = "ci-token")
  expect_error(framework:::.setup_connection(dir), class = "fw_project_server_missing")
  expect_error(framework:::.fw_project_cloud_url(dir), "FW_PROJECT_TOKEN is set but FW_CLOUD_URL is not")

  # The url argument or FW_CLOUD_URL names it
  expect_identical(framework:::.fw_cloud_server("https://arg.example", scope = "project", project_dir = dir)$url,
                   "https://arg.example")
  withr::local_envvar(FW_CLOUD_URL = "https://ci.example")
  expect_identical(framework:::.setup_connection(dir), list(server = "https://ci.example", token = "ci-token"))
})

test_that("push_skills() and push_all()'s skills use the project's server, not the login server", {
  parent <- local_scope_env()
  framework:::.fw_save_cloud_url("https://login.example")
  dir <- scope_project(parent, "S", c("FW_PROJECT_TOKEN=tokS", "FW_CLOUD_URL=https://project.example"))
  expect_identical(framework:::.skill_server(dir), "https://project.example")

  asked <- character()
  local_mocked_bindings(
    .fw_cloud_token = function(url = NULL) { asked <<- c(asked, url); NULL },
    .skill_push_edited = function(root) list(list(present = ".claude/skills/lab-style"))
  )
  expect_error(push_skills(dir), "project.example")
  expect_error(framework:::.skills_push_plan(dir, FALSE), "project.example")
  expect_identical(unique(asked), "https://project.example")

  # A project not linked to Cloud uses your login
  plain <- scope_project(parent, "plain")
  expect_identical(framework:::.skill_server(plain), "https://login.example")
})

skill_scope_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude]"),
             file.path(root, "settings.yml"))
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token", .local_envir = env)
  root
}

skill_scope_mock <- function(pull, env = parent.frame(), user_token = NULL, remote = NULL) {
  local_mocked_bindings(
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_cloud_token = function(...) user_token,
    .fw_api = function(path, token, ...) {
      if (identical(path, "/api/v1/projects/pull")) return(pull())
      if (startsWith(path, "/api/v1/skills/sync/")) return(remote)
      stop("unexpected request: ", path)
    },
    .env = env
  )
}

test_that("pull_skills() falls back to package skills only offline", {
  root <- skill_scope_project()
  http_error <- function(status) {
    resp <- httr2::response(status_code = status, headers = list(`Content-Type` = "application/json"),
                            body = charToRaw('{"message":"Invalid token"}'))
    rlang::abort("Invalid token", class = c(paste0("httr2_http_", status), "httr2_http", "httr2_error"), resp = resp)
  }

  skill_scope_mock(function() http_error(401))
  expect_error(suppressMessages(pull_skills(root, dry_run = TRUE)), "refused the project token")

  skill_scope_mock(function() list(spec_version = 99L))
  expect_error(suppressMessages(pull_skills(root, dry_run = TRUE)), "can't read")

  skill_scope_mock(function() stop(errorCondition("no server", class = "fw_project_server_missing")))
  expect_error(suppressMessages(pull_skills(root, dry_run = TRUE)), class = "fw_project_server_missing")

  skill_scope_mock(function() stop(errorCondition("ambiguous", class = "fw_ambiguous_server")))
  expect_error(suppressMessages(pull_skills(root, dry_run = TRUE)), class = "fw_ambiguous_server")

  skill_scope_mock(function() stop(errorCondition("Could not connect", class = c("httr2_failure", "httr2_error"))))
  expect_identical(suppressMessages(pull_skills(root, dry_run = TRUE))$source, "package")

  # No project token: the package skills, as documented
  withr::local_envvar(FW_PROJECT_TOKEN = NA)
  expect_identical(suppressMessages(pull_skills(root, dry_run = TRUE))$source, "package")
})

test_that("a copy at the setup's version updates to a newer Cloud version instead of counting as edited", {
  root <- skill_scope_project()
  bundle <- function(text) {
    content <- paste0("---\nname: lab-style\ndescription: Our lab's figure style\n---\n", text, "\n")
    list(list(path = "SKILL.md", content = jsonlite::base64_enc(charToRaw(content)), executable = FALSE))
  }
  entry <- function(text, version) {
    b <- bundle(text)
    list(content = rawToChar(jsonlite::base64_dec(b[[1]]$content)), bundle = b,
         sync = list(skill_id = "lab-id", version = version, hash = .skill_hash(b), variant = "r"))
  }
  envelope <- function() {
    list(spec_version = 1L, name = "Test",
         layers = list(list(kind = "project", key = "test", layer = list(skills = list(`lab-style` = entry("Version one", 1L))))))
  }
  skill_scope_mock(envelope)
  suppressMessages(pull_skills(root))

  # Another project's copy at the setup's version, without this lock entry
  unlink(file.path(root, ".framework"), recursive = TRUE)

  latest <- entry("Version five", 5L)
  skill_scope_mock(envelope, user_token = "user-token",
                   remote = list(skill_id = "lab-id", version = 5L, hash = latest$sync$hash, bundle = latest$bundle))
  result <- suppressMessages(pull_skills(root))
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["lab-style"]], "updated")
  skill <- readLines(file.path(root, ".claude/skills/lab-style/SKILL.md"))
  expect_identical(tail(skill, 1), "Version five")
})

test_that("setup() writes the project token for bare projects too", {
  parent <- local_scope_env()
  location <- file.path(parent, "bare-project")
  local_mocked_bindings(
    .fw_cloud_url = function(...) "https://cloud.example",
    .fw_api = function(...) list(spec_version = 1L, name = "Bare",
                                 layers = list(list(kind = "base", key = "bare", layer = list(type = "bare")))),
    .project_create_from_spec = function(spec, location) {
      dir.create(location, recursive = TRUE)
      list(success = TRUE, path = location)
    }
  )
  result <- suppressMessages(framework:::.cloud_setup("fw_setup_token", location = location, browse = FALSE))
  expect_identical(result$spec$type, "bare")
  env <- readLines(file.path(location, ".env"))
  expect_true("FW_PROJECT_TOKEN=fw_setup_token" %in% env)
  expect_true("FW_CLOUD_URL=https://cloud.example" %in% env)
})

test_that("a 1.x project's config.yml is its package list, and push stops on unreadable settings", {
  root <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  packages:", "    - dplyr", "    - name: here"),
             file.path(root, "config.yml"))
  expect_true(framework:::.has_settings_file(root))
  expect_setequal(names(framework:::.setup_local_packages(root)), c("dplyr", "here"))
  expect_setequal(names(framework:::.setup_local_packages(root, strict = TRUE)), c("dplyr", "here"))
  expect_true(framework:::.skill_pull_settings(root)$project_type == "project")

  broken <- withr::local_tempdir()
  writeLines(c("default:", "  packages: [unclosed"), file.path(broken, "settings.yml"))
  expect_length(framework:::.setup_local_packages(broken), 0L)
  expect_error(framework:::.setup_local_packages(broken, strict = TRUE), "Could not read the project's packages")

  # push_all(remove = TRUE) never sends an empty package list for unreadable settings
  sent <- list()
  local_mocked_bindings(.setup_request = function(path, connection, method = "GET", body = NULL) {
    sent[[length(sent) + 1L]] <<- body
    list(revision = "r1", changes = list())
  })
  plan <- framework:::.sync_plan("Packages", function() {
    framework:::.setup_push_plan(broken, list(server = "https://cloud.example", token = "t"),
                                 list(language = "r", revision = "r1"), remove = TRUE, force = FALSE)
  })
  expect_match(plan$error, "Could not read the project's packages")
  expect_length(sent, 0L)
})

test_that("the .env reader trims keys and values and drops inline comments, like the writer", {
  path <- withr::local_tempfile()
  writeLines(c(
    "FW_PROJECT_TOKEN = tok # issued by Cloud",
    " export FW_CLOUD_URL=https://cloud.example   ",
    "QUOTED=\"a # b\" # comment",
    "SINGLE='x'",
    "HASH=a#b",
    "EMPTY= # nothing yet",
    "  # indented comment"
  ), path)
  values <- framework:::.fw_read_dotenv(path)
  expect_identical(values[["FW_PROJECT_TOKEN"]], "tok")
  expect_identical(values[["FW_CLOUD_URL"]], "https://cloud.example")
  expect_identical(values[["QUOTED"]], "a # b")
  expect_identical(values[["SINGLE"]], "x")
  expect_identical(values[["HASH"]], "a#b")
  expect_identical(values[["EMPTY"]], "")
  expect_length(values, 6L)

  # The writer sees the spaced key as a token already set, and the reader agrees
  dir <- withr::local_tempdir()
  writeLines("FW_PROJECT_TOKEN = tok", file.path(dir, ".env"))
  expect_false(framework:::.fw_write_project_token(dir, "other", "https://cloud.example"))
  expect_identical(framework:::.fw_project_env_value("FW_PROJECT_TOKEN", dir), "tok")
})
