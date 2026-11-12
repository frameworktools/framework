# pull_all() and push_all() against a mocked Framework Cloud

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
    "        source: cran",
    "  data:",
    "    inputs:",
    "      raw:",
    "        survey:",
    "          path: inputs/raw/survey.csv",
    "          type: csv"
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

setup_cloud_entries <- function() {
  list(
    list(name = "inputs.raw.survey", path = "inputs/raw/survey.csv", type = "csv", locked = FALSE),
    list(name = "inputs.raw.visits", path = "inputs/raw/visits.csv", type = "csv", locked = FALSE)
  )
}

setup_http_error <- function(status, body = list(message = "x")) {
  resp <- httr2::response(status_code = status, headers = list(`Content-Type` = "application/json"),
                          body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE)))
  rlang::abort(body$message, class = c(paste0("httr2_http_", status), "httr2_http", "httr2_error"), resp = resp)
}

setup_no_changes <- function() list(added = list(), changed = list(), removed = list(), kept = list())

# A mocked Cloud: the package list, the layers pull_skills() reads, and the
# data registry, with their pushes. Records POST bodies and installs.
setup_mock <- function(cloud, env = parent.frame()) {
  cloud$data_revision <- cloud$data_revision %||% "data-1"
  cloud$entries <- cloud$entries %||% list()
  cloud$reply <- cloud$reply %||% function(body) list(applied = FALSE, revision = cloud$revision, changes = setup_no_changes())
  cloud$data_reply <- cloud$data_reply %||% function(body) list(applied = FALSE, revision = cloud$data_revision, changes = setup_no_changes())
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
      if (identical(path, "/api/v1/projects/data")) {
        if (isTRUE(cloud$data_missing)) setup_http_error(404, list(message = "Not found"))
        if (identical(method, "GET")) return(list(revision = cloud$data_revision, entries = cloud$entries))
        cloud$data_posts <- c(cloud$data_posts, list(body))
        if (!isTRUE(body$force) && !identical(body$base_revision, cloud$data_revision)) {
          setup_http_error(409, list(message = "Pull first", revision = cloud$data_revision))
        }
        return(cloud$data_reply(body))
      }
      stop("unexpected request: ", path)
    },
    .env = env
  )
}

lock_revision <- function(root, file) jsonlite::read_json(file.path(root, ".framework", file))$revision

test_that("pull_all() lists every part's changes, asks once, then applies them all", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- setup_cloud_packages()
  cloud$entries <- setup_cloud_entries()
  setup_mock(cloud)

  out <- capture.output(result <- pull_all(root, dry_run = TRUE), type = "message")
  expect_identical(out[1:5], c(
    "Changes from Framework Cloud:",
    "Packages (revision rev-1):",
    "  Packages to add: tidyr",
    paste0("  Packages that differ: janitor (local 2.2.0, Cloud 2.1.0) — kept; ",
           "pull_all(overwrite = TRUE) uses Cloud's"),
    "  Only in this project (kept): here"
  ))
  expect_identical(out[6], "Skills:")
  expect_match(out[7], "^  \\d+ to add$")
  expect_true(all(c("Data registry (revision data-1):", "  Entries to add: inputs.raw.visits") %in% out))
  expect_length(result$applied, 0L)
  expect_identical(result$packages$added, "tidyr")
  expect_identical(result$data_registry$added, "inputs.raw.visits")
  expect_false(file.exists(file.path(root, ".framework/setup.lock.json")))
  expect_false(file.exists(file.path(root, ".framework/data.lock.json")))
  expect_false(dir.exists(file.path(root, ".claude")))

  # One question for everything; without a console it needs confirm
  expect_error(suppressMessages(pull_all(root)), "pull_all() asks before changing anything", fixed = TRUE)
  expect_error(suppressMessages(pull_all(root)), "pass confirm = TRUE, or dry_run = TRUE")
  result <- suppressMessages(pull_all(root, confirm = FALSE))
  expect_length(result$applied, 0L)
  expect_null(cloud$installed)

  out <- capture.output(result <- pull_all(root, confirm = TRUE), type = "message")
  expect_identical(result$applied, c("packages", "skills", "data_registry"))
  expect_length(result$failed, 0L)
  expect_true("✓ Data registry: 1 entry added or updated" %in% out)
  expect_identical(cloud$installed, "tidyr")
  packages <- .setup_local_packages(root)
  expect_identical(names(packages), c("dplyr", "janitor", "here", "tidyr"))
  expect_identical(packages$janitor$version, "2.2.0")
  expect_true(file.exists(file.path(root, ".claude/skills/framework-data/SKILL.md")))
  expect_true("inputs.raw.visits" %in% names(.data_registry_local(root)))
  expect_identical(lock_revision(root, "setup.lock.json"), "rev-1")
  expect_identical(lock_revision(root, "data.lock.json"), "data-1")

  # overwrite takes Cloud's settings for the differing package
  # The mocked install leaves janitor 2.1.0 uninstalled, which pull_all() warns about
  out <- capture.output(result <- suppressWarnings(pull_all(root, overwrite = TRUE, confirm = TRUE)), type = "message")
  expect_true(any(grepl("janitor (local 2.2.0, Cloud 2.1.0) — Cloud's will be used", out, fixed = TRUE)))
  expect_identical(.setup_local_packages(root)$janitor$version, "2.1.0")
  expect_identical(result$applied, "packages")

  out <- capture.output(pull_all(root, confirm = TRUE), type = "message")
  expect_identical(out, "Project is up to date with Framework Cloud.")
})

test_that("pull_all() keeps local edits to data entries unless overwrite", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  cloud$entries <- list(list(name = "inputs.raw.survey", path = "inputs/raw/survey_v2.csv", type = "csv", locked = FALSE))
  setup_mock(cloud)
  out <- capture.output(pull_all(root, dry_run = TRUE), type = "message")
  expect_true(any(grepl("inputs.raw.survey (path inputs/raw/survey.csv -> inputs/raw/survey_v2.csv) — kept; pull_all(overwrite = TRUE) uses Cloud's",
                        out, fixed = TRUE)))
  suppressMessages(pull_all(root, confirm = TRUE))
  expect_identical(.data_registry_local(root)$inputs.raw.survey$path, "inputs/raw/survey.csv")
  suppressMessages(pull_all(root, overwrite = TRUE, confirm = TRUE))
  expect_identical(.data_registry_local(root)$inputs.raw.survey$path, "inputs/raw/survey_v2.csv")
})

test_that("pull_all() applies the parts it can and names the one it couldn't", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- setup_cloud_packages()
  setup_mock(cloud)
  cloud$data_missing <- TRUE

  out <- capture.output(result <- pull_all(root, dry_run = TRUE), type = "message")
  expect_true("Data registry: not read. This Framework Cloud server has no data registry endpoint yet." %in% out)
  expect_named(result$failed, "data_registry")

  expect_error(
    suppressMessages(pull_all(root, confirm = TRUE)),
    paste0("pull_all() did not finish. Applied: Packages, Skills. ",
           "Not applied: Data registry (This Framework Cloud server has no data registry endpoint yet)."),
    fixed = TRUE)
  expect_identical(cloud$installed, "tidyr")
  expect_identical(lock_revision(root, "setup.lock.json"), "rev-1")
  expect_false(file.exists(file.path(root, ".framework/data.lock.json")))
})

test_that("pull_all() stops cleanly offline, without a token, or without the endpoint", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  setup_mock(cloud)
  cloud$missing <- TRUE
  expect_error(pull_all(root, dry_run = TRUE), "has no setup endpoint yet. Nothing changed.", fixed = TRUE)
  cloud$missing <- NULL; cloud$offline <- "Could not resolve host"
  expect_error(pull_all(root, dry_run = TRUE), "Framework Cloud not reached (Could not resolve host). Nothing changed.", fixed = TRUE)
  withr::local_envvar(FW_PROJECT_TOKEN = "")
  expect_error(pull_all(root, dry_run = TRUE), "no project token")
})

test_that("pull_all() warns when a pinned version did not install", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"
  # The mocked install does nothing, so the installed jsonlite is not 0.0.1
  cloud$packages <- list(list(name = "jsonlite", source = "cran", version = "0.0.1", auto_attach = FALSE, repo = NULL))
  setup_mock(cloud)
  expect_warning(suppressMessages(pull_all(root, confirm = TRUE)), "Could not install jsonlite")
  expect_identical(.setup_local_packages(root)$jsonlite$version, "0.0.1")
})

setup_package_reply <- function(cloud) {
  function(body) {
    changes <- list(added = list(list(name = "here", source = "cran", version = NULL, auto_attach = FALSE, repo = NULL)),
                    changed = list(list(name = "janitor", from = list(source = "cran", version = "2.1.0"),
                                        to = list(source = "cran", version = "2.2.0"))),
                    removed = if (isTRUE(body$remove)) list(list(name = "tidyr")) else list(),
                    kept = if (isTRUE(body$remove)) list() else list(list(name = "tidyr")))
    list(applied = !isTRUE(body$dry_run), revision = if (isTRUE(body$dry_run)) cloud$revision else "rev-2", changes = changes)
  }
}

setup_data_reply <- function(cloud) {
  function(body) {
    changes <- list(added = list(list(name = "inputs.raw.survey")), changed = list(), removed = list(), kept = list())
    list(applied = !isTRUE(body$dry_run), revision = if (isTRUE(body$dry_run)) cloud$data_revision else "data-2", changes = changes)
  }
}

# An edited skill to push, without reaching Cloud
setup_skill_mock <- function(cloud, signed_in = TRUE, env = parent.frame()) {
  local_mocked_bindings(
    .fw_cloud_token = function(...) if (signed_in) "user-token",
    .skill_push_edited = function(root) list(list(present = ".claude/skills/analysis")),
    .skill_push_plan = function(root, force) {
      list(plans = list(list(name = "analysis", path = ".claude/skills/analysis", status = "push", builtin = FALSE, forced = FALSE)),
           untracked = list())
    },
    .skill_push_apply = function(root, plans) {
      cloud$skills_pushed <- c(cloud$skills_pushed, "analysis")
      lapply(plans, function(p) { p$status <- "pushed"; p })
    },
    .env = env
  )
}

test_that("push_all() previews every part, asks once, and pushes them all", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- setup_cloud_packages()
  cloud$reply <- setup_package_reply(cloud); cloud$data_reply <- setup_data_reply(cloud)
  setup_mock(cloud)
  setup_skill_mock(cloud)

  out <- capture.output(result <- push_all(root, dry_run = TRUE), type = "message")
  expect_identical(out, c(
    "Changes for Framework Cloud:",
    "Packages:",
    "  Packages to add: here",
    "  Packages to change: janitor (2.1.0 -> 2.2.0)",
    "  On Cloud only (kept): tidyr",
    "  This changes Test Project's package list on Framework Cloud. New setups, zips, and Update on GitHub will use it.",
    "Skills:",
    "  Skills to push: analysis",
    "  This replaces the current version of analysis, used wherever it's attached.",
    "Data registry:",
    "  Entries to add: inputs.raw.survey",
    paste0("  This changes Test Project's data registry on Framework Cloud. New copies of the project, zips, ",
           "and Update on GitHub will use it. Only definitions are sent: no data files and no hashes.")
  ))
  body <- cloud$posts[[1]]
  expect_true(body$dry_run)
  expect_identical(body$base_revision, "rev-1")
  expect_identical(vapply(body$packages, `[[`, "", "name"), c("dplyr", "janitor", "here"))
  expect_true(cloud$data_posts[[1]]$dry_run)
  expect_identical(cloud$data_posts[[1]]$entries[[1]]$name, "inputs.raw.survey")
  expect_null(cloud$skills_pushed)

  expect_error(suppressMessages(push_all(root)), "push_all() asks before changing anything", fixed = TRUE)
  result <- suppressMessages(push_all(root, confirm = FALSE))
  expect_length(result$applied, 0L)
  expect_null(cloud$skills_pushed)

  out <- capture.output(result <- push_all(root, remove = TRUE, confirm = TRUE), type = "message")
  expect_true("  Packages to remove: tidyr" %in% out)
  expect_true("✓ Packages pushed: revision rev-2 (1 added, 1 changed, 1 removed)" %in% out)
  expect_true("✓ Skills pushed: analysis" %in% out)
  expect_true("\u2713 Data registry pushed: revision data-2 (1 added)" %in% out)
  expect_identical(result$applied, c("packages", "skills", "data_registry"))
  expect_true(cloud$posts[[length(cloud$posts)]]$remove)
  expect_false(cloud$posts[[length(cloud$posts)]]$dry_run)
  expect_true(cloud$data_posts[[length(cloud$data_posts)]]$remove)
  expect_identical(cloud$skills_pushed, "analysis")
  expect_identical(lock_revision(root, "setup.lock.json"), "rev-2")
  expect_identical(lock_revision(root, "data.lock.json"), "data-2")
})

test_that("push_all() says Pull first for a part Cloud moved on, pushes the rest, and force replaces it", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  cloud$reply <- setup_package_reply(cloud); cloud$data_reply <- setup_data_reply(cloud)
  setup_mock(cloud)
  .setup_lock_write(root, "rev-1", "https://cloud.example")
  .data_registry_lock_write(root, "data-1", "https://cloud.example")
  cloud$revision <- "rev-5"

  pull_first <- paste0("Packages: can't push. Framework Cloud's package list changed since this project last pulled it ",
                       "(revision rev-5). Pull first: pull_all(). push_all(force = TRUE) replaces Cloud's changes.")
  out <- capture.output(result <- push_all(root, dry_run = TRUE), type = "message")
  expect_true(pull_first %in% out)
  expect_named(result$failed, "packages")

  expect_error(
    suppressMessages(push_all(root, confirm = TRUE)),
    paste0("push_all() did not finish. Pushed: Data registry. Already in step: Skills. ",
           "Not pushed: Packages (Framework Cloud's package list changed since this project last pulled it (revision rev-5). ",
           "Pull first: pull_all(). push_all(force = TRUE) replaces Cloud's changes)."),
    fixed = TRUE)
  expect_identical(lock_revision(root, "setup.lock.json"), "rev-1")
  expect_identical(lock_revision(root, "data.lock.json"), "data-2")

  out <- capture.output(result <- push_all(root, force = TRUE, confirm = TRUE), type = "message")
  expect_true("  Cloud's newer package changes will be replaced by this project's packages." %in% out)
  expect_true(cloud$posts[[length(cloud$posts)]]$force)
  expect_identical(lock_revision(root, "setup.lock.json"), "rev-2")
  expect_true("packages" %in% result$applied)
})

test_that("push_all() pushes packages and data when edited skills need a login", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  cloud$reply <- setup_package_reply(cloud); cloud$data_reply <- setup_data_reply(cloud)
  setup_mock(cloud)
  setup_skill_mock(cloud, signed_in = FALSE)
  out <- capture.output(push_all(root, dry_run = TRUE), type = "message")
  expect_true(any(startsWith(out, "Skills: can't push. Not signed in, so edited skills (analysis) can't be pushed.")))
  expect_error(suppressMessages(push_all(root, confirm = TRUE)),
               "Pushed: Packages, Data registry. Not pushed: Skills (Not signed in", fixed = TRUE)
  expect_null(cloud$skills_pushed)
})

test_that("push_all() reports a project Cloud already has", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list()
  setup_mock(cloud)
  out <- capture.output(result <- push_all(root, confirm = TRUE), type = "message")
  expect_identical(out, "Framework Cloud already matches this project.")
  expect_length(cloud$posts, 1L)
  expect_length(cloud$data_posts, 1L)
})

test_that("pull_all() and push_all() explain a refused token and Cloud's own refusals", {
  root <- setup_project()
  local_mocked_bindings(
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_api = function(path, ...) setup_http_error(401, list(message = "Unauthenticated."))
  )
  expect_error(pull_all(root, dry_run = TRUE),
               "Framework Cloud refused the project token (Unauthenticated). Check FW_PROJECT_TOKEN in the project's .env. Nothing changed.",
               fixed = TRUE)
  expect_error(push_all(root, dry_run = TRUE), "refused the project token", fixed = TRUE)
  local_mocked_bindings(
    .fw_api = function(path, ...) setup_http_error(422, list(message = "Stata projects have no package list."))
  )
  expect_error(pull_all(root, dry_run = TRUE), "Stata projects have no package list. Nothing changed.", fixed = TRUE)
})

test_that("pull_all() and push_all() point a Python project to framework-py", {
  root <- setup_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$packages <- list(); cloud$language <- "python"
  setup_mock(cloud)
  expect_error(pull_all(root, dry_run = TRUE), "Use framework-py's pull_all() or fw pull.", fixed = TRUE)
  expect_error(push_all(root, dry_run = TRUE), "Use framework-py's push_all() or fw push.", fixed = TRUE)
})
