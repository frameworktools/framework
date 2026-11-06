# Cross-package follow-ups from the 2026-11-05 audit: R now matches the
# fixed framework-py client and the Framework Cloud server.

local_followup_project <- function(settings = list(project_type = "project"), env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  withr::local_envvar(
    FW_CONFIG_HOME = file.path(dir, ".fwconfig"), FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA,
    FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA, FW_LEDGER = NA, .local_envir = env
  )
  yaml::write_yaml(list(default = settings), "settings.yml")
  dir
}

local_cloud_upload <- function(collection_visibility = NULL, env = parent.frame()) {
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeLines("<p>hi</p>", "report.html")
  state <- new.env()
  state$sent <- list()
  state$uploads <- 0L
  testthat::local_mocked_bindings(
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (identical(method, "GET")) {
        return(list(collections = list(list(
          id = 7L, slug = "findings", title = "Findings", visibility = collection_visibility
        ))))
      }
      list(id = 1L)
    },
    .env = env
  )
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      state$sent[[length(state$sent) + 1L]] <- rlang::list2(...)
      req
    },
    req_perform = function(req, ...) {
      state$uploads <- state$uploads + 1L
      req
    },
    resp_body_json = function(resp, ...) {
      force(resp)
      list(id = 14L, version = 1L, url = "http://localhost:8080/d/report")
    },
    .package = "httr2",
    .env = env
  )
  state
}

test_that("an explicit visibility is sent without readable", {
  skip_if_not_installed("httr2")
  local_followup_project()
  state <- local_cloud_upload()

  suppressMessages(publish("report.html", slug = "main-results", visibility = "private"))
  fields <- state$sent[[1]]
  expect_identical(fields$slug, "main-results")
  expect_identical(fields$visibility, "private")
  # The server lets visibility win, but readable is not sent at all, as framework-py does
  expect_null(fields$readable)

  suppressMessages(publish("report.html", slug = FALSE, visibility = "unlisted"))
  expect_null(state$sent[[2]]$readable)
  expect_identical(state$sent[[2]]$visibility, "unlisted")

  # A slug alone only names the artifact: no readable switch
  suppressMessages(publish("report.html", slug = "main-results"))
  expect_null(state$sent[[3]]$readable)
  expect_null(state$sent[[3]]$visibility)
})

test_that("the collection check lets an explicit visibility win over the slug", {
  skip_if_not_installed("httr2")
  local_followup_project()
  state <- local_cloud_upload(collection_visibility = "public")

  # Before: a string slug counted as public, so a private artifact was uploaded
  # and then refused. Now it is refused before the upload.
  expect_error(
    publish("report.html", slug = "x", visibility = "private", collection = "findings"),
    "Public collections require public artifacts"
  )
  expect_identical(state$uploads, 0L)

  suppressMessages(publish("report.html", slug = FALSE, visibility = "public", collection = "findings"))
  expect_identical(state$uploads, 1L)
})

test_that("live ledger pushes send recorded_at in UTC with a Z", {
  local_followup_project()
  withr::local_envvar(FW_LEDGER = "live", FW_PROJECT_TOKEN = "fw_project",
                      FW_CLOUD_URL = "http://localhost:8080", TZ = "America/New_York")
  sent <- NULL
  testthat::local_mocked_bindings(.fw_api = function(path, token, method = "GET", body = NULL, ...) {
    sent <<- body
    list(sequence = 1L)
  })
  before <- Sys.time()
  suppressMessages(framework:::.fw_ledger_push_quietly("inputs.raw.x", "abc", size_bytes = 3))
  expect_match(sent$recorded_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  stamp <- as.POSIXct(sent$recorded_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  expect_lt(abs(as.numeric(difftime(stamp, before, units = "secs"))), 60)
})

test_that("scaffold()'s .env load keeps shell values and skips empty lines", {
  dir <- local_followup_project()
  withr::local_envvar(S3_ACCESS_KEY = "from-shell", FW_TEST_SHELL = "shell",
                      FW_TEST_NEW = NA, FW_TEST_OTHER = NA)
  writeLines(c("S3_ACCESS_KEY=", "FW_TEST_SHELL=project", "FW_TEST_NEW=from-a"), ".env")
  framework:::.load_environment("settings.yml", dir)
  expect_identical(Sys.getenv("S3_ACCESS_KEY"), "from-shell")
  expect_identical(Sys.getenv("FW_TEST_SHELL"), "shell")
  expect_identical(Sys.getenv("FW_TEST_NEW"), "from-a")

  # Loading another project's .env takes back what the last load set, as in framework-py
  other <- file.path(withr::local_tempdir(), ".env")
  writeLines("FW_TEST_OTHER=from-b", other)
  framework:::.fw_load_dotenv(other)
  expect_identical(Sys.getenv("FW_TEST_NEW"), "")
  expect_identical(Sys.getenv("FW_TEST_OTHER"), "from-b")
  expect_identical(Sys.getenv("FW_TEST_SHELL"), "shell")
})

test_that("results are keyed by project-relative path, and old file-name rows are renamed", {
  local_followup_project(list(project_type = "project", directories = list(outputs_tables = "outputs/tables")))
  suppressMessages(save_table(data.frame(x = 1), "first"))
  expect_identical(result_list()$name, "outputs/tables/first.csv")

  # A row from an older R version, named by the file name alone
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  DBI::dbExecute(con, "INSERT INTO results (name, type, public, blind, hash, created_at, updated_at)
                       VALUES ('legacy.csv', 'table', 0, 0, 'old', 1, 1)")
  DBI::dbDisconnect(con)
  expect_setequal(result_list()$name, c("outputs/tables/first.csv", "legacy.csv"))

  suppressMessages(save_table(data.frame(x = 2), "legacy"))
  listed <- result_list()
  expect_setequal(listed$name, c("outputs/tables/first.csv", "outputs/tables/legacy.csv"))
  expect_false(identical(listed$hash[listed$name == "outputs/tables/legacy.csv"], "old"))
})

test_that("the result name is the path from the project root", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "outputs", "figures"), recursive = TRUE)
  file <- file.path(root, "outputs", "figures", "plot.png")
  expect_identical(framework:::.fw_result_name(file, root), "outputs/figures/plot.png")
  outside <- file.path(withr::local_tempdir(), "x.csv")
  expect_identical(
    framework:::.fw_result_name(outside, root),
    file.path(normalizePath(dirname(outside), winslash = "/"), "x.csv")
  )
})

test_that("cloud_sync() conflict advice is pull, copy edits back, then push", {
  dir <- local_followup_project()
  paths <- list(document = file.path(dir, "cloud-settings.yml"), state = file.path(dir, "sync-state.yml"))
  yaml::write_yaml(list(theme = "edited"), paths$document)
  yaml::write_yaml(list(revision = 1L, hash = "not-the-local-hash"), paths$state)
  testthat::local_mocked_bindings(
    .fw_require_token = function(...) "fw_token",
    .fw_sync_paths = function() paths,
    .fw_api = function(...) list(revision = 5L, document = list(theme = "cloud"))
  )
  error <- tryCatch(cloud_sync(), error = function(e) conditionMessage(e))
  expect_match(error, "Both your local mirror and the cloud changed", fixed = TRUE)
  expect_match(error, "copy your edits from the backup and run cloud_sync(\"push\")", fixed = TRUE)
  # The old advice was a push the server rejects when the cloud is ahead
  expect_false(grepl("overwrite the cloud", error, fixed = TRUE))
})

test_that("stubs_list() lists your templates as personal, in make_notebook()'s order", {
  local_followup_project()
  templates <- framework:::.framework_templates_dir()
  dir.create(templates, recursive = TRUE)
  writeLines("---\ntitle: mine\n---", file.path(templates, "notebook-mine.qmd"))
  writeLines("---\ntitle: my default\n---", file.path(templates, "notebook-default.qmd"))
  dir.create("stubs")
  writeLines("---\ntitle: project\n---", file.path("stubs", "notebook-mine.qmd"))

  listed <- stubs_list()
  expect_identical(listed$source[listed$name == "mine" & listed$type == "quarto"], "user")
  expect_identical(listed$source[listed$name == "default" & listed$type == "quarto"], "personal")
  expect_identical(listed$source[listed$name == "minimal" & listed$type == "quarto"], "framework")
  expect_identical(framework:::.find_stub_template("default", "qmd"), file.path(templates, "notebook-default.qmd"))
})

test_that("a catalog entry with fields but no path is listed by its name", {
  local_followup_project(list(
    project_type = "project",
    data = list(broken = list(type = "csv", locked = TRUE), group = list(type = "data/type.csv"))
  ))
  listed <- suppressMessages(data_list())
  # Before: listed as "broken.type" with path "csv"
  expect_identical(listed$name, c("broken", "group.type"))
  expect_identical(is.na(listed$path), c(TRUE, FALSE))
  expect_identical(listed$path[2], "data/type.csv")
  expect_true(listed$locked[1])
  expect_identical(framework:::.get_data_path_suggestions(), c("broken", "group.type"))
})
