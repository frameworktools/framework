# pull_data_registry() and push_data_registry() against a mocked Framework Cloud

registry_project <- function(env = parent.frame(), split = FALSE) {
  root <- withr::local_tempdir(.local_envir = env)
  if (split) {
    dir.create(file.path(root, "settings"))
    writeLines(c(
      "default:",
      "  project_name: Test Project",
      "  # The catalog lives in its own file",
      "  data: settings/data.yml"
    ), file.path(root, "settings.yml"))
    writeLines(c(
      "data:",
      "  inputs:",
      "    raw:",
      "      survey:",
      "        path: inputs/raw/survey.csv",
      "        type: csv",
      "        locked: true"
    ), file.path(root, "settings", "data.yml"))
  } else {
    writeLines(c(
      "# Project settings",
      "default:",
      "  project_name: Test Project",
      "  # Keep this comment",
      "  directories:",
      "    inputs_raw: inputs/raw",
      "  data:",
      "    # Inputs from the field team",
      "    inputs:",
      "      raw:",
      "        survey:",
      "          # Wave 1 only",
      "          path: inputs/raw/survey.csv",
      "          type: csv",
      "          locked: true",
      "          note: local only",
      "        # The clinic sends visits monthly",
      "        visits: inputs/raw/visits.csv"
    ), file.path(root, "settings.yml"))
  }
  withr::local_envvar(FW_PROJECT_TOKEN = "project-token", .local_envir = env)
  root
}

registry_http_error <- function(status, body = list(message = "x")) {
  resp <- httr2::response(status_code = status, headers = list(`Content-Type` = "application/json"),
                          body = charToRaw(jsonlite::toJSON(body, auto_unbox = TRUE)))
  rlang::abort(body$message, class = c(paste0("httr2_http_", status), "httr2_http", "httr2_error"), resp = resp)
}

registry_mock <- function(cloud, env = parent.frame()) {
  local_mocked_bindings(
    .fw_project_cloud_url = function(...) "https://cloud.example",
    .fw_interactive = function() FALSE,
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (!is.null(cloud$offline)) stop(structure(class = c("httr2_failure", "httr2_error", "error", "condition"),
                                                  list(message = cloud$offline, call = NULL)))
      if (isTRUE(cloud$missing)) registry_http_error(404, list(message = "Not found"))
      if (isTRUE(cloud$refused)) registry_http_error(401, list(message = "Unauthenticated."))
      stopifnot(identical(path, "/api/v1/projects/data"))
      if (identical(method, "GET")) return(list(revision = cloud$revision, entries = cloud$entries))
      cloud$posts <- c(cloud$posts, list(body))
      if (!isTRUE(body$force) && !identical(body$base_revision, cloud$revision)) {
        registry_http_error(409, list(message = "Pull first", revision = cloud$revision))
      }
      cloud$reply(body)
    },
    .env = env
  )
}

registry_cloud_entries <- function() {
  list(
    list(name = "inputs.raw.survey", path = "inputs/raw/survey_v2.csv", type = "csv", delimiter = NULL,
         locked = TRUE, private = NULL, description = NULL, stata_names = NULL),
    list(name = "inputs.raw.visits", path = "inputs/raw/visits.csv", type = NULL, delimiter = NULL,
         locked = FALSE, private = NULL, description = NULL, stata_names = NULL),
    list(name = "inputs.final.analysis", path = "inputs/final/analysis.parquet", type = "parquet",
         delimiter = NULL, locked = FALSE, private = NULL, description = "Analysis file", stata_names = NULL)
  )
}

test_that("the spec's data section is checked and written nested", {
  expect_length(.data_registry_problems(list(`inputs.raw.survey` = list(path = "inputs/raw/s.csv", type = "csv"))), 0)
  problems <- .data_registry_problems(list(
    `inputs.raw` = list(path = "inputs/raw.csv"),
    `inputs.raw.survey` = list(path = "../outside.csv", type = "word", hash = "abc")
  ))
  expect_true(any(grepl("unknown field 'hash'", problems)))
  expect_true(any(grepl("must be relative", problems)))
  expect_true(any(grepl("type must be one of", problems)))
  expect_true(any(grepl("'inputs.raw' is an entry", problems)))

  nested <- .data_catalog_nest(list(`inputs.raw.survey` = list(path = "a.csv"), `outputs.x` = list(path = "b.rds")))
  expect_identical(nested$inputs$raw$survey$path, "a.csv")
  expect_identical(nested$outputs$x$path, "b.rds")
  expect_identical(.data_catalog_nest(NULL), list())
})

test_that("spec_resolve() replaces data entries whole and keeps names flat", {
  state <- .spec_merge_layers(.spec_normalize_layers(list(
    list(layer = list(data = list(`inputs.raw.a` = list(path = "a.csv", delimiter = "tab"),
                                  `inputs.raw.b` = list(path = "b.csv")))),
    list(layer = list(data = list(`inputs.raw.a` = list(path = "a2.csv"), `inputs.raw.b` = NULL)))
  )))
  expect_identical(state$spec$data, list(`inputs.raw.a` = list(path = "a2.csv")))
})

test_that("pull_data_registry() lists the changes, then adds entries and keeps edits", {
  root <- registry_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$entries <- registry_cloud_entries()
  registry_mock(cloud)

  out <- capture.output(result <- pull_data_registry(root, dry_run = TRUE), type = "message")
  expect_identical(out[1], "Data registry changes from Framework Cloud (revision rev-1):")
  expect_true("  Entries to add: inputs.final.analysis" %in% out)
  expect_true(paste0("  Entries that differ (local -> Cloud): inputs.raw.survey ",
                     "(path inputs/raw/survey.csv -> inputs/raw/survey_v2.csv) \u2014 ",
                     "kept; pull_data_registry(overwrite = TRUE) uses Cloud's") %in% out)
  expect_false(file.exists(file.path(root, ".framework/data.lock.json")))

  # Non-interactive without confirm: refused, nothing written
  before <- readLines(file.path(root, "settings.yml"))
  expect_error(suppressMessages(pull_data_registry(root)), "pull_data_registry\\(\\) asks before changing anything")
  expect_identical(readLines(file.path(root, "settings.yml")), before)

  suppressMessages(result <- pull_data_registry(root, confirm = TRUE))
  expect_true(result$applied)
  text <- readLines(file.path(root, "settings.yml"))
  expect_true("# Project settings" %in% text)
  expect_true("  # Keep this comment" %in% text)
  data <- settings_read(file.path(root, "settings.yml"))$data
  expect_identical(data$inputs$final$analysis$path, "inputs/final/analysis.parquet")
  expect_identical(data$inputs$final$analysis$description, "Analysis file")
  # The local edit is kept
  expect_identical(data$inputs$raw$survey$path, "inputs/raw/survey.csv")
  expect_identical(jsonlite::read_json(file.path(root, ".framework/data.lock.json"))$revision, "rev-1")

  suppressMessages(pull_data_registry(root, overwrite = TRUE, confirm = TRUE))
  data <- settings_read(file.path(root, "settings.yml"))$data
  expect_identical(data$inputs$raw$survey$path, "inputs/raw/survey_v2.csv")
  # A field Cloud doesn't keep stays local
  expect_identical(data$inputs$raw$survey$note, "local only")
  # Comments inside the data block stay
  text <- readLines(file.path(root, "settings.yml"))
  for (comment in c("    # Inputs from the field team", "          # Wave 1 only",
                    "        # The clinic sends visits monthly", "  # Keep this comment")) {
    expect_true(comment %in% text, info = comment)
  }
  expect_true("          path: inputs/raw/survey_v2.csv" %in% text)

  out <- capture.output(pull_data_registry(root, dry_run = TRUE), type = "message")
  expect_identical(out, "Data registry is up to date with Framework Cloud (revision rev-1).")
})

test_that("changes name the fields that differ", {
  survey <- list(name = "inputs.raw.survey", path = "inputs/raw/survey.csv", type = "csv", locked = TRUE)
  expect_identical(.data_registry_diff(survey, c(survey, list(description = "Wave 1"))), "description changed")
  expect_identical(.data_registry_diff(survey, c(survey, list(stata_names = list(long_name = "short")))),
                   "stata_names changed")
  moved <- list(name = "inputs.raw.survey", path = "b.csv", locked = FALSE, description = "Wave 1")
  expect_identical(.data_registry_diff(survey, moved),
                   "path inputs/raw/survey.csv -> b.csv, type csv -> none, locked true -> false, description changed")

  root <- registry_project()
  cloud <- new.env(); cloud$revision <- "rev-1"
  cloud$entries <- list(c(survey, list(description = "Wave 1")),
                        list(name = "inputs.raw.visits", path = "inputs/raw/visits.csv", locked = FALSE))
  cloud$reply <- function(body) list(applied = FALSE, revision = "rev-1", changes = list(
    added = list(), changed = list(list(name = "inputs.raw.survey", from = cloud$entries[[1]], to = body$entries[[1]])),
    removed = list(), kept = list()))
  registry_mock(cloud)
  out <- capture.output(pull_data_registry(root, dry_run = TRUE), type = "message")
  expect_true(any(startsWith(out, "  Entries that differ (local -> Cloud): inputs.raw.survey (description changed)")))
  out <- capture.output(push_data_registry(root, dry_run = TRUE), type = "message")
  expect_true("  Entries to change: inputs.raw.survey (description changed)" %in% out)

  # Pulled, the new description goes in without disturbing the entry's comment
  suppressMessages(pull_data_registry(root, overwrite = TRUE, confirm = TRUE))
  text <- readLines(file.path(root, "settings.yml"))
  expect_true("          # Wave 1 only" %in% text)
  expect_identical(settings_read(file.path(root, "settings.yml"))$data$inputs$raw$survey$description, "Wave 1")
})

test_that("pull_data_registry() writes into a split data file", {
  root <- registry_project(split = TRUE)
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$entries <- registry_cloud_entries()[3]
  registry_mock(cloud)
  suppressMessages(pull_data_registry(root, confirm = TRUE))
  expect_identical(readLines(file.path(root, "settings.yml"))[3], "  # The catalog lives in its own file")
  data <- .fw_read_yaml(file.path(root, "settings/data.yml"))$data
  expect_identical(data$inputs$final$analysis$type, "parquet")
  expect_true(data$inputs$raw$survey$locked)
})

test_that("push_data_registry() previews, asks, pushes, and records the revision", {
  root <- registry_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$entries <- list()
  cloud$reply <- function(body) {
    rows <- lapply(body$entries, function(e) e)
    list(applied = !isTRUE(body$dry_run), revision = if (isTRUE(body$dry_run)) "rev-1" else "rev-2",
         changes = list(added = rows, changed = list(), removed = list(), kept = list()))
  }
  registry_mock(cloud)

  out <- capture.output(result <- push_data_registry(root, dry_run = TRUE), type = "message")
  expect_true("  Entries to add: inputs.raw.survey, inputs.raw.visits" %in% out)
  expect_true(any(grepl("no data files and no hashes", out)))
  sent <- cloud$posts[[1]]$entries
  expect_identical(sent[[1]]$name, "inputs.raw.survey")
  expect_null(sent[[1]]$note)
  expect_identical(sent[[2]]$path, "inputs/raw/visits.csv")
  expect_false(sent[[2]]$locked)

  expect_error(suppressMessages(push_data_registry(root)), "push_data_registry\\(\\) asks before changing anything")

  suppressMessages(result <- push_data_registry(root, confirm = TRUE))
  expect_true(result$applied)
  expect_identical(jsonlite::read_json(file.path(root, ".framework/data.lock.json"))$revision, "rev-2")
})

test_that("push_data_registry() refuses a stale revision unless forced, and sends remove", {
  root <- registry_project()
  dir.create(file.path(root, ".framework"))
  .data_registry_lock_write(root, "rev-old", "https://cloud.example")
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$entries <- list()
  cloud$reply <- function(body) list(applied = !isTRUE(body$dry_run), revision = "rev-1",
                                     changes = list(added = list(), changed = list(),
                                                    removed = list(list(name = "inputs.old", path = "old.csv", locked = FALSE)),
                                                    kept = list()))
  registry_mock(cloud)
  expect_error(suppressMessages(push_data_registry(root, confirm = TRUE)), "Pull first: pull_data_registry\\(\\)")
  out <- capture.output(push_data_registry(root, force = TRUE, remove = TRUE, confirm = TRUE), type = "message")
  expect_true("  Entries to remove: inputs.old" %in% out)
  expect_true(any(grepl("Cloud's newer data registry changes will be replaced", out)))
  expect_true(isTRUE(cloud$posts[[length(cloud$posts)]]$remove))
})

test_that("offline, signed out, and older servers change nothing", {
  root <- registry_project()
  cloud <- new.env(); cloud$revision <- "rev-1"; cloud$entries <- list()
  registry_mock(cloud)
  cloud$offline <- "Could not resolve host."
  expect_error(pull_data_registry(root), "Framework Cloud not reached \\(Could not resolve host\\)\\. Nothing changed\\.")
  cloud$offline <- NULL; cloud$refused <- TRUE
  expect_error(push_data_registry(root), "refused the project token")
  cloud$refused <- NULL; cloud$missing <- TRUE
  expect_error(pull_data_registry(root), "no data registry endpoint yet")
  withr::local_envvar(FW_PROJECT_TOKEN = "")
  local_mocked_bindings(.fw_project_token = function(...) NULL)
  expect_error(pull_data_registry(root), "no project token")
})

test_that("project creation writes the spec's data entries into the settings", {
  spec <- spec_resolve(list(list(
    git = list(use_git = FALSE),
    data = list(`inputs.raw.survey` = list(path = "inputs/raw/survey.csv", type = "csv", locked = TRUE))
  )), name = "Data Project")
  expect_length(spec_check(spec), 0)
  location <- file.path(withr::local_tempdir(), "proj")
  withr::local_options(rlang_interactive = FALSE)
  suppressMessages(project_create(spec, location))
  data <- .fw_read_yaml(file.path(location, "settings", "data.yml"))$data
  expect_identical(data$inputs$raw$survey$path, "inputs/raw/survey.csv")
  expect_true(data$inputs$raw$survey$locked)
})

test_that("pull_data_registry() writes into a new project's empty data section", {
  for (split in c(TRUE, FALSE)) {
    root <- withr::local_tempdir()
    if (split) {
      dir.create(file.path(root, "settings"))
      writeLines(c("default:", "  project_name: Test Project", "  # The catalog lives in its own file",
                   "  data: settings/data.yml"), file.path(root, "settings.yml"))
      writeLines("data: []", file.path(root, "settings", "data.yml"))
    } else {
      writeLines(c("default:", "  project_name: Test Project", "  data: []"), file.path(root, "settings.yml"))
    }
    withr::local_envvar(FW_PROJECT_TOKEN = "project-token")
    cloud <- new.env(); cloud$revision <- "rev-1"; cloud$entries <- registry_cloud_entries()[3]
    registry_mock(cloud)
    suppressMessages(pull_data_registry(root, confirm = TRUE))
    file <- if (split) file.path(root, "settings/data.yml") else file.path(root, "settings.yml")
    data <- .fw_read_yaml(file)
    data <- if (split) data$data else data$default$data
    expect_identical(data$inputs$final$analysis$type, "parquet")
    expect_identical(names(.data_registry_local(root)), "inputs.final.analysis")
  }
})

test_that("pull_data_registry() adds an entry whose top group doesn't exist yet", {
  root <- registry_project()
  cloud <- new.env(); cloud$revision <- "rev-1"
  cloud$entries <- list(list(name = "outputs.tables.summary", path = "outputs/tables/summary.csv", type = "csv", locked = FALSE))
  registry_mock(cloud)
  suppressMessages(pull_data_registry(root, confirm = TRUE))
  expect_identical(.data_registry_local(root)$outputs.tables.summary$path, "outputs/tables/summary.csv")
  expect_true("  # Keep this comment" %in% readLines(file.path(root, "settings.yml")))
})
