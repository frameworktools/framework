# cloud_register() creates the Cloud project for a local one from its spec,
# in one request, and links it. The Cloud API is mocked: nothing is created.

local_adopted <- function(folders = c("analysis", "data/raw", "archive"), env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  for (f in folders) dir.create(file.path(dir, f), recursive = TRUE)
  suppressMessages(adopt(dir, yes = TRUE, cloud = FALSE))
  dir
}

# The server: POST /api/v1/projects answers with `create` (a function of the
# parsed body returning list(status, body)); other calls are recorded
local_cloud <- function(env = parent.frame(), create = NULL, interactive = FALSE, answer = FALSE) {
  calls <- new.env()
  calls$log <- list()
  create <- create %||% function(body) list(status = 201L, body = list(
    slug = body$slug, name = body$name, language = "r", type = body$spec$type,
    adopted = isTRUE(body$adopted), url = paste0("https://cloud.test/", body$slug),
    token = "fwp_project", github = NULL
  ))
  testthat::local_mocked_bindings(
    .fw_cloud_token = function(url = NULL) "fw_user",
    .fw_cloud_url = function(url = NULL, scope = "user") "https://cloud.test",
    .fw_api_request = function(path, token, method = "GET", json = NULL, url = NULL) {
      body <- jsonlite::fromJSON(json, simplifyVector = FALSE)
      calls$log[[length(calls$log) + 1]] <- list(path = path, token = token, method = method, json = json, body = body)
      create(body)
    },
    .fw_api = function(path, token, method = "GET", body = NULL, url = NULL) {
      calls$log[[length(calls$log) + 1]] <- list(path = path, token = token, method = method, body = body)
      if (grepl("pull-tokens$", path)) return(list(token = "fwp_existing", url = "https://cloud.test"))
      list(changed = TRUE)
    },
    .adopt_ask = function(msg, default = FALSE) {
      calls$asked <- c(calls$asked, msg)
      answer
    },
    .env = env
  )
  withr::local_options(rlang_interactive = interactive, .local_envir = env)
  calls
}

test_that("cloud_register() sends the spec in one request and links the folder", {
  dir <- local_adopted()
  calls <- local_cloud()
  res <- suppressMessages(cloud_register(dir, name = "Study One"))
  expect_length(calls$log, 1)
  call <- calls$log[[1]]
  expect_identical(call$path, "/api/v1/projects")
  expect_identical(call$method, "POST")
  expect_identical(call$token, "fw_user")

  body <- call$body
  expect_identical(body$name, "Study One")
  expect_identical(body$slug, "study-one")
  expect_true(body$adopted)
  expect_null(body$project_type)
  expect_identical(body$spec$directories$inputs_raw, "data/raw")
  # The spec goes as it is on disk: empty maps stay {}
  spec_text <- paste(readLines(file.path(dir, ".framework", "spec.json")), collapse = "\n")
  expect_true(startsWith(call$json, paste0("{\"spec\":", spec_text, ",")))
  expect_match(call$json, "\"skills\": {}", fixed = TRUE)

  env <- readLines(file.path(dir, ".env"))
  expect_true("FW_PROJECT_TOKEN=fwp_project" %in% env)
  expect_true("FW_CLOUD_URL=https://cloud.test" %in% env)
  expect_true(".env" %in% readLines(file.path(dir, ".gitignore")))
  expect_identical(res$slug, "study-one")
  expect_identical(res$type, "project")
  expect_true(res$adopted)
  expect_true(res$linked)

  # Already linked: nothing changes
  expect_message(again <- cloud_register(dir), "already linked")
  expect_length(calls$log, 1)
  expect_false(again$created)
})

test_that("a project made by Framework isn't marked adopted", {
  dir <- withr::local_tempdir()
  spec <- spec_resolve(list(list(type = "project_sensitive", git = list(use_git = FALSE))), name = "Built In")
  suppressMessages(project_create(spec, file.path(dir, "p")))
  calls <- local_cloud()
  expect_error(cloud_register(file.path(dir, "p"), slug = "Not A Slug"), "cannot be a slug")
  suppressMessages(cloud_register(file.path(dir, "p"), slug = "built-in"))
  expect_null(calls$log[[1]]$body$adopted)
  expect_identical(calls$log[[1]]$body$spec$type, "project_sensitive")
})

test_that("a dry run sends nothing and shows the request", {
  dir <- local_adopted()
  calls <- local_cloud()
  out <- capture_messages(res <- cloud_register(dir, dry_run = TRUE))
  expect_length(calls$log, 0)
  expect_true(any(grepl("POST https://cloud.test/api/v1/projects", out, fixed = TRUE)))
  expect_identical(res$slug, framework:::.cloud_slugify(basename(dir)))
  expect_false(file.exists(file.path(dir, ".env")))
})

test_that("a taken slug offers to link to the existing project", {
  dir <- local_adopted()
  taken <- function(body) list(status = 422L, body = list(
    message = "The slug has already been taken.",
    errors = list(slug = list("You already have a project with this slug."))
  ))
  local_cloud(create = taken)
  expect_error(cloud_register(dir, slug = "study"), "fw project link --from study")
  expect_false(file.exists(file.path(dir, ".env")))

  calls <- local_cloud(create = taken, interactive = TRUE, answer = TRUE)
  res <- suppressMessages(cloud_register(dir, slug = "study"))
  expect_identical(calls$asked, "You already have a project study on cloud.test. Link this folder to it instead?")
  expect_identical(calls$log[[2]]$path, "/api/v1/projects/study/pull-tokens")
  expect_true("FW_PROJECT_TOKEN=fwp_existing" %in% readLines(file.path(dir, ".env")))
  expect_false(res$created)
})

test_that("a slug held by a project in the Trash is reported as such", {
  dir <- local_adopted()
  local_cloud(create = function(body) list(status = 422L, body = list(
    errors = list(slug = list("A deleted project in your Trash has this slug."))
  )))
  expect_error(cloud_register(dir, slug = "old"), "in your Trash")
  local_cloud(create = function(body) list(status = 422L, body = list(errors = list(slug = list("is reserved")))))
  expect_error(cloud_register(dir, slug = "admin"), "refused the slug admin: is reserved")
})

test_that("an older server gets the spec sent separately", {
  dir <- local_adopted()
  calls <- local_cloud(create = function(body) list(status = 201L, body = list(
    slug = "study", url = "https://cloud.test/study", token = "fwp_old"
  )))
  expect_warning(suppressMessages(cloud_register(dir)), "older than the spec API")
  expect_identical(calls$log[[2]]$path, "/api/v1/project/spec")
  expect_identical(calls$log[[2]]$method, "PUT")
  expect_identical(calls$log[[2]]$token, "fwp_old")
})

test_that("cloud_register() needs a spec and refuses a tracked .env and a private path", {
  dir <- withr::local_tempdir()
  writeLines("default:\n  project_type: project", file.path(dir, "settings.yml"))
  local_cloud()
  expect_error(cloud_register(dir), "upgrade\\(")

  skip_if(!nzchar(Sys.which("git")))
  dir <- local_adopted()
  writeLines("A=1", file.path(dir, ".env"))
  system2("git", c("-C", shQuote(dir), "init", "-q"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", shQuote(dir), "add", "-f", ".env"), stdout = FALSE, stderr = FALSE)
  calls <- local_cloud()
  expect_error(cloud_register(dir), "tracks this project's .env")
  expect_length(calls$log, 0)

  parent <- file.path(withr::local_tempdir(), "private")
  dir.create(parent)
  dir <- file.path(parent, "study")
  dir.create(file.path(dir, "analysis"), recursive = TRUE)
  suppressMessages(adopt(dir, yes = TRUE, cloud = FALSE))
  expect_error(cloud_register(dir), "private folder")
  expect_silent(suppressMessages(cloud_register(dir, include_private = TRUE)))
})

test_that("adopt(cloud = TRUE) registers without asking", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "analysis"))
  calls <- local_cloud()
  suppressMessages(adopt(dir, yes = TRUE, cloud = TRUE))
  expect_length(calls$log, 1)
  expect_true(calls$log[[1]]$body$adopted)
  expect_true(any(grepl("^FW_PROJECT_TOKEN=", readLines(file.path(dir, ".env")))))
})
