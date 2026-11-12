# pull_setup() and push_setup() against a mocked Framework Cloud

setup_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  writeLines(c(
    "default:",
    "  project_name: Test Project",
    "  project_type: project",
    "  ai:",
    "    assistants: [claude]",
    "  packages:",
    "    use_renv: false",
    "    default_packages:",
    "      - name: dplyr",
    "        source: cran",
    "        auto_attach: true",
    "      - name: janitor",
    "        source: cran",
    "        version: 2.2.0",
    "      - name: here",
    "        source: cran"
  ), file.path(root, "settings.yml"))
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token", .local_envir = env)
  root
}

setup_cloud_packages <- function() {
  list(
    list(name = "dplyr", source = "cran", version = NULL, auto_attach = TRUE, repo = NULL),
    list(name = "janitor", source = "cran", version = "2.1.0", auto_attach = FALSE, repo = NULL),
    list(name = "tidyr", source = "cran", version = NULL, auto_attach = FALSE, repo = NULL)
  )
}

setup_http_error <- function(status, body = list(message = "x")) {
  resp <- httr2::response(status_code = status, headers = list(`Content-Type` = "application/json"),
                          body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE)))
  rlang::abort(body$message, class = c(paste0("httr2_http_", status), "httr2_http", "httr2_error"), resp = resp)
}

# A mocked Cloud: the setup, the layers pull_skills() reads, and the
# package push. Records POST bodies and installs.
setup_mock <- function(cloud, env = parent.frame()) {
  local_mocked_bindings(
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_cloud_token = function(...) NULL,
    .fw_interactive = function() FALSE,
    .install_package = function(spec) { cloud$installed <- c(cloud$installed, .parse_package_spec(spec)$name); TRUE },
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (!is.null(cloud$offline)) stop(structure(class = c("httr2_failure", "httr2_error", "error", "condition"),
                                                  list(message = cloud$offline, call = NULL)))
      if (identical(path, "/api/v1/projects/setup")) {
        if (isTRUE(cloud$missing)) setup_http_error(404, list(message = "Not found"))
        return(list(revision = cloud$revision, language = cloud$language %||% "r",
                    packages = cloud$packages, skills = list()))
      }
      if (identical(path, "/api/v1/projects/pull")) {
        return(list(spec_version = 1L, name = "Test Project", layers = list()))
      }
      if (identical(path, "/api/v1/projects/setup/packages")) {
        cloud$posts <- c(cloud$posts, list(body))
        if (!isTRUE(body$force) && !identical(body$base_revision, cloud$revision)) {
          setup_http_error(409, list(message = "Pull first", revision = cloud$revision))
        }
        return(cloud$reply(body))
      }
      stop("unexpected request: ", path)
    },
    .env = env
  )
}

test_that("pull_setup() lists the changes, then adds packages and skills", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- setup_cloud_packages()
  setup_mock(cloud)

  out <- capture.output(result <- pull_setup(root, dry_run = TRUE), type = "message")
  expect_identical(out[1], "Setup changes from Framework Cloud (revision rev-1):")
  expect_true("  Packages to add: tidyr" %in% out)
  expect_true(paste0("  Packages that differ: janitor (local 2.2.0, Cloud 2.1.0) \u2014 kept; ",
                     "pull_setup(overwrite = TRUE) uses Cloud's") %in% out)
  expect_true("  Only in this project (kept): here" %in% out)
  expect_true(any(grepl("^  Skills: \\d+ to add$", out)))
  expect_false(result$applied)
  expect_false(file.exists(file.path(root, ".framework/setup.lock.json")))
  expect_false(dir.exists(file.path(root, ".claude")))

  expect_error(suppressMessages(pull_setup(root)), "pass confirm = TRUE, or dry_run = TRUE")
  result <- suppressMessages(pull_setup(root, confirm = FALSE))
  expect_false(result$applied)

  result <- suppressMessages(pull_setup(root, confirm = TRUE))
  expect_true(result$applied)
  expect_identical(cloud$installed, "tidyr")
  packages <- .setup_local_packages(root)
  expect_identical(names(packages), c("dplyr", "janitor", "here", "tidyr"))
  expect_identical(packages$janitor$version, "2.2.0")
  expect_true(file.exists(file.path(root, ".claude/skills/framework-data/SKILL.md")))
  expect_identical(jsonlite::read_json(file.path(root, ".framework/setup.lock.json"))$revision, "rev-1")

  # overwrite takes Cloud's settings for the differing package
  # The mocked install leaves janitor 2.1.0 uninstalled, which pull_setup() warns about
  out <- capture.output(result <- suppressWarnings(pull_setup(root, overwrite = TRUE, confirm = TRUE)), type = "message")
  expect_true(any(grepl("janitor (local 2.2.0, Cloud 2.1.0) \u2014 Cloud's will be used", out, fixed = TRUE)))
  expect_identical(.setup_local_packages(root)$janitor$version, "2.1.0")
  expect_identical(names(.setup_local_packages(root)), c("dplyr", "janitor", "here", "tidyr"))

  out <- capture.output(pull_setup(root, confirm = TRUE), type = "message")
  expect_true("Setup is up to date with Framework Cloud (revision rev-1)." %in% out)
})

test_that("pull_setup() stops cleanly offline, without a token, or without the endpoint", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  setup_mock(cloud)
  cloud$missing <- TRUE
  expect_error(pull_setup(root, dry_run = TRUE), "has no setup endpoint yet. Nothing changed.", fixed = TRUE)
  cloud$missing <- NULL; cloud$offline <- "Could not resolve host"
  expect_error(pull_setup(root, dry_run = TRUE), "Framework Cloud not reached (Could not resolve host). Nothing changed.", fixed = TRUE)
  withr::local_envvar(FW_PROJECT_TOKEN = "")
  expect_error(pull_setup(root, dry_run = TRUE), "no project token")
})

test_that("push_setup() previews, warns, asks, and pushes with the pulled revision", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- setup_cloud_packages()
  cloud$reply <- function(body) {
    changes <- list(added = list(list(name = "here", source = "cran", version = NULL, auto_attach = FALSE, repo = NULL)),
                    changed = list(list(name = "janitor", from = list(source = "cran", version = "2.1.0"),
                                        to = list(source = "cran", version = "2.2.0"))),
                    removed = if (isTRUE(body$remove)) list(list(name = "tidyr")) else list(),
                    kept = if (isTRUE(body$remove)) list() else list(list(name = "tidyr")))
    list(applied = !isTRUE(body$dry_run), revision = if (isTRUE(body$dry_run)) cloud$revision else "rev-2", changes = changes)
  }
  setup_mock(cloud)
  local_mocked_bindings(push_skills = function(...) { cloud$skills_pushed <- list(...); list(message = "ok") })

  out <- capture.output(result <- push_setup(root, dry_run = TRUE), type = "message")
  expect_identical(out[1:5], c(
    "Setup changes for Framework Cloud:",
    "  Packages to add: here",
    "  Packages to change: janitor (2.1.0 -> 2.2.0)",
    "  On Cloud only (kept): tidyr",
    "This changes Test Project's setup on Framework Cloud. New setups, zips, and Update on GitHub will use it."
  ))
  body <- cloud$posts[[1]]
  expect_true(body$dry_run)
  expect_identical(body$base_revision, "rev-1")
  expect_identical(vapply(body$packages, `[[`, "", "name"), c("dplyr", "janitor", "here"))
  expect_true(body$packages[[1]]$auto_attach)
  expect_true(isTRUE(cloud$skills_pushed$dry_run))

  expect_error(suppressMessages(push_setup(root)), "pass confirm = TRUE")
  out <- capture.output(result <- push_setup(root, remove = TRUE, confirm = TRUE), type = "message")
  expect_true("  Packages to remove: tidyr" %in% out)
  expect_true("Setup pushed: revision rev-2 (1 added, 1 changed, 1 removed)" %in% out)
  expect_true(cloud$posts[[length(cloud$posts)]]$remove)
  expect_false(cloud$posts[[length(cloud$posts)]]$dry_run)
  expect_identical(jsonlite::read_json(file.path(root, ".framework/setup.lock.json"))$revision, "rev-2")
})

test_that("push_setup() says Pull first when Cloud moved on, and force replaces it", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  cloud$reply <- function(body) list(applied = !isTRUE(body$dry_run), revision = "rev-9",
                                     changes = list(added = list(list(name = "here")), changed = list(), removed = list(), kept = list()))
  setup_mock(cloud)
  local_mocked_bindings(push_skills = function(...) NULL)
  .setup_lock_write(root, "rev-1", "https://cloud.example")
  cloud$revision <- "rev-5"
  expect_error(suppressMessages(push_setup(root, dry_run = TRUE)),
               "changed since this project last pulled it (revision rev-5). Pull first: pull_setup()", fixed = TRUE)
  out <- capture.output(push_setup(root, force = TRUE, confirm = TRUE), type = "message")
  expect_true("Cloud's newer setup changes will be replaced by this project's packages." %in% out)
  expect_true(cloud$posts[[length(cloud$posts)]]$force)
  expect_identical(jsonlite::read_json(file.path(root, ".framework/setup.lock.json"))$revision, "rev-9")
})

test_that("push_setup() reports a setup Cloud already has", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  cloud$reply <- function(body) list(applied = FALSE, revision = "rev-1",
                                     changes = list(added = list(), changed = list(), removed = list(), kept = list()))
  setup_mock(cloud)
  local_mocked_bindings(push_skills = function(...) NULL)
  out <- capture.output(result <- push_setup(root, confirm = TRUE), type = "message")
  expect_identical(out[1], "Setup on Framework Cloud already matches this project.")
  expect_length(cloud$posts, 1L)
})

test_that("pull_setup() warns when a pinned version did not install", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"
  # The mocked install does nothing, so the installed jsonlite is not 0.0.1
  cloud$packages <- list(list(name = "jsonlite", source = "cran", version = "0.0.1", auto_attach = FALSE, repo = NULL))
  setup_mock(cloud)
  expect_warning(suppressMessages(pull_setup(root, confirm = TRUE)), "Could not install jsonlite")
  expect_identical(.setup_local_packages(root)$jsonlite$version, "0.0.1")
})

test_that("pull_setup() and push_setup() explain a refused token and Cloud's own refusals", {
  root <- setup_project()
  local_mocked_bindings(
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_api = function(path, ...) setup_http_error(401, list(message = "Unauthenticated."))
  )
  expect_error(pull_setup(root, dry_run = TRUE),
               "Framework Cloud refused the project token (Unauthenticated). Check FW_PROJECT_TOKEN in the project's .env. Nothing changed.",
               fixed = TRUE)
  expect_error(push_setup(root, dry_run = TRUE), "refused the project token", fixed = TRUE)
  local_mocked_bindings(
    .fw_api = function(path, ...) setup_http_error(422, list(message = "Stata projects have no package list."))
  )
  expect_error(pull_setup(root, dry_run = TRUE), "Stata projects have no package list. Nothing changed.", fixed = TRUE)
})
