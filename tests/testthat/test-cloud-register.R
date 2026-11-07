# cloud_register() creates the Cloud project for a local one, links it, and
# sends its spec. The Cloud API is mocked: nothing is created.

local_adopted <- function(folders = c("analysis", "data/raw", "archive"), env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  for (f in folders) dir.create(file.path(dir, f), recursive = TRUE)
  suppressMessages(adopt(dir, yes = TRUE, cloud = FALSE))
  dir
}

local_cloud <- function(env = parent.frame(), fail = NULL) {
  calls <- new.env()
  calls$log <- list()
  testthat::local_mocked_bindings(
    .fw_cloud_token = function(url = NULL) "fw_user",
    .fw_cloud_url = function(url = NULL, scope = "user") "https://cloud.test",
    .fw_api = function(path, token, method = "GET", body = NULL, url = NULL) {
      calls$log[[length(calls$log) + 1]] <- list(path = path, token = token, method = method, body = body)
      if (!is.null(fail) && identical(path, fail)) stop("server error")
      switch(path,
        "/api/v1/structures" = list(key = "ada/study-layout", name = body$name, url = "https://cloud.test/s"),
        "/api/v1/projects" = list(slug = "ada/study", url = "https://cloud.test/ada/study", token = "fwp_project"),
        "/api/v1/project/spec" = list(changed = TRUE),
        stop("unexpected ", path)
      )
    },
    .env = env
  )
  withr::local_options(rlang_interactive = FALSE, .local_envir = env)
  calls
}

test_that("cloud_register() saves the layout, creates, links, and sends the spec", {
  dir <- local_adopted()
  calls <- local_cloud()
  res <- suppressMessages(cloud_register(dir, name = "Study"))
  paths <- vapply(calls$log, `[[`, "", "path")
  expect_identical(paths, c("/api/v1/structures", "/api/v1/projects", "/api/v1/project/spec"))

  structure <- calls$log[[1]]$body
  expect_identical(structure$name, "Study layout")
  expect_identical(structure$directories$inputs_raw, "data/raw")
  expect_identical(structure$extra_directories$archive$path, "archive")

  project <- calls$log[[2]]$body
  expect_identical(project$structure, "ada/study-layout")
  expect_identical(project$language, "r")
  expect_true(project$adopted)
  expect_false(project$settings$sensitive)
  expect_identical(calls$log[[2]]$token, "fw_user")

  # The spec goes with the new project token
  expect_identical(calls$log[[3]]$method, "PUT")
  expect_identical(calls$log[[3]]$token, "fwp_project")
  expect_identical(calls$log[[3]]$body$spec$name, basename(dir))

  env <- readLines(file.path(dir, ".env"))
  expect_true("FW_PROJECT_TOKEN=fwp_project" %in% env)
  expect_true("FW_CLOUD_URL=https://cloud.test" %in% env)
  expect_true(".env" %in% readLines(file.path(dir, ".gitignore")))
  expect_identical(res$slug, "ada/study")
  expect_true(res$linked)
  expect_true(res$spec_pushed)

  expect_error(cloud_register(dir), "already linked")
})

test_that("a built-in layout needs no structure", {
  dir <- withr::local_tempdir()
  spec <- spec_resolve(list(list(type = "project_sensitive", git = list(use_git = FALSE))), name = "Built in")
  dir.create(file.path(dir, ".framework"))
  writeLines("default:\n  project_type: project_sensitive", file.path(dir, "settings.yml"))
  writeLines(jsonlite::toJSON(spec, auto_unbox = TRUE, null = "null"), file.path(dir, ".framework", "spec.json"))
  calls <- local_cloud()
  suppressMessages(cloud_register(dir))
  expect_identical(vapply(calls$log, `[[`, "", "path"), c("/api/v1/projects", "/api/v1/project/spec"))
  expect_identical(calls$log[[1]]$body$structure, "framework/project_sensitive")
  expect_true(calls$log[[1]]$body$settings$sensitive)
})

test_that("a dry run sends nothing and shows the requests", {
  dir <- local_adopted()
  calls <- local_cloud()
  out <- capture_messages(res <- cloud_register(dir, dry_run = TRUE))
  expect_length(calls$log, 0)
  expect_true(any(grepl("POST https://cloud.test/api/v1/structures", out, fixed = TRUE)))
  expect_true(any(grepl("PUT https://cloud.test/api/v1/project/spec", out, fixed = TRUE)))
  expect_identical(res$project$name, basename(dir))
  expect_false(file.exists(file.path(dir, ".env")))
})

test_that("cloud_register() needs a spec and names the commands that finish a failed link", {
  dir <- withr::local_tempdir()
  writeLines("default:\n  project_type: project", file.path(dir, "settings.yml"))
  local_cloud()
  expect_error(cloud_register(dir), "upgrade\\(")

  dir <- local_adopted()
  calls <- local_cloud(fail = "/api/v1/project/spec")
  out <- capture_messages(res <- cloud_register(dir))
  expect_true(res$linked)
  expect_false(res$spec_pushed)
  expect_true(any(grepl("fw project push-spec", out, fixed = TRUE)))
})

test_that("cloud_register() refuses a tracked .env and a private path", {
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
  expect_identical(vapply(calls$log, `[[`, "", "path"),
                   c("/api/v1/structures", "/api/v1/projects", "/api/v1/project/spec"))
  expect_true(any(grepl("^FW_PROJECT_TOKEN=", readLines(file.path(dir, ".env")))))
})
