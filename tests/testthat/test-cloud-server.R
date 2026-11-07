local_cloud_env <- function(env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  withr::local_envvar(
    FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA,
    FW_TOKEN_FILE = NA, .local_envir = env
  )
  # Never read or write the real keychain
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE, .env = env)
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  dir
}

test_that("server URLs are tidied, and plain http is for localhost only", {
  norm <- framework:::.fw_normalize_cloud_url
  expect_identical(norm("https://framework.example.edu/"), "https://framework.example.edu")
  expect_identical(norm("framework.example.edu"), "https://framework.example.edu")
  expect_identical(norm("http://localhost:8080"), "http://localhost:8080")
  expect_identical(norm("http://127.0.0.1:8080/"), "http://127.0.0.1:8080")
  expect_error(norm("http://framework.example.edu"), "Refusing plain http")
  expect_error(norm("http://localhost.evil.com"), "Refusing plain http")
  expect_error(norm("ftp://framework.example.edu"), "https://")
})

test_that("hosts name the server with its port", {
  expect_identical(framework:::.fw_cloud_host("http://localhost:8080"), "localhost:8080")
  expect_identical(framework:::.fw_cloud_host("https://Framework.Example.edu/x"), "framework.example.edu")
  expect_true(framework:::.fw_is_default_cloud("https://framework.pub/"))
  expect_false(framework:::.fw_is_default_cloud("https://framework.example.edu"))
})

test_that("user-scoped resolution: argument, env var, login default, framework.pub", {
  local_cloud_env()
  server <- framework:::.fw_cloud_server
  writeLines("FW_CLOUD_URL=https://project.example.edu", ".env")

  expect_identical(server()$url, "https://framework.pub")
  expect_identical(server()$source, "the built-in default")

  framework:::.fw_save_cloud_url("http://localhost:8080")
  expect_identical(server()$url, "http://localhost:8080")
  expect_identical(server()$source, "your cloud_login() default")

  withr::local_envvar(FW_CLOUD_URL = "https://env.example.edu")
  expect_identical(server()$url, "https://env.example.edu")

  expect_identical(server("https://arg.example.edu")$url, "https://arg.example.edu")
})

test_that("project-scoped resolution skips the login default", {
  local_cloud_env()
  server <- framework:::.fw_cloud_server
  framework:::.fw_save_cloud_url("http://localhost:8080")

  # A project from before FW_CLOUD_URL was written belongs to framework.pub
  expect_identical(server(scope = "project")$url, "https://framework.pub")

  writeLines("FW_CLOUD_URL=https://project.example.edu", ".env")
  expect_identical(server(scope = "project")$url, "https://project.example.edu")
  expect_identical(server(scope = "project")$source, "the project's .env")
})

test_that("token files are kept per server", {
  local_cloud_env()
  expect_identical(basename(framework:::.fw_token_file("https://framework.pub")), "cloud-token")
  local_file <- framework:::.fw_token_file("http://localhost:8080")
  expect_identical(basename(local_file), "cloud-token-localhost_8080")
  expect_identical(framework:::.fw_keyring_service("http://localhost:8080"), "framework-cloud:localhost:8080")

  writeLines("fw_local_token", local_file)
  expect_identical(framework:::.fw_read_token_file(local_file), "fw_local_token")
  expect_null(framework:::.fw_read_token_file(framework:::.fw_token_file("https://framework.pub")))
})

test_that("cloud_login() saves the server it logged in to as the default", {
  local_cloud_env()
  token_file <- file.path(withr::local_tempdir(), "token")
  withr::local_envvar(FW_TOKEN_FILE = token_file)

  expect_error(cloud_login("fw_1234567890", url = "http://example.edu", verify = FALSE, consent = TRUE),
               "Refusing plain http")
  suppressMessages(cloud_login("fw_1234567890", url = "http://localhost:8080", verify = FALSE, consent = TRUE))
  expect_identical(readLines(token_file), "fw_1234567890")
  expect_identical(framework:::.fw_cloud_url(), "http://localhost:8080")
  expect_message(cloud_status(), "Server: http://localhost:8080 \\(from your cloud_login\\(\\) default\\)")
})

test_that("the consent notice and missing-token error name the server", {
  local_cloud_env()
  notice <- framework:::.fw_consent_notice("https://framework.example.edu")
  expect_match(notice, "https://framework.example.edu/privacy", fixed = TRUE)
  expect_error(
    framework:::.fw_require_token("https://framework.example.edu"),
    'cloud_login("fw_...", url = "https://framework.example.edu")', fixed = TRUE
  )
})

test_that("project setup writes the token and its server into .env", {
  local_cloud_env()
  writeLines("SECRET=1", ".env")
  suppressMessages(framework:::.fw_write_project_token(".", "fw_project", "http://localhost:8080"))
  lines <- readLines(".env")
  expect_true("SECRET=1" %in% lines)
  expect_true("FW_PROJECT_TOKEN=fw_project" %in% lines)
  expect_true("FW_CLOUD_URL=http://localhost:8080" %in% lines)
  expect_identical(framework:::.fw_project_cloud_url(), "http://localhost:8080")

  # Idempotent
  expect_false(suppressMessages(framework:::.fw_write_project_token(".", "fw_other", "https://x.org")))
  expect_identical(readLines(".env"), lines)
})

test_that("publishing with no bucket and no project token names both fixes", {
  local_cloud_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines("<p>hi</p>", "report.html")
  expect_error(publish("report.html"), "Nowhere to publish.*setup\\(\"<project token>\"\\)")
  expect_identical(
    tryCatch(framework:::.fw_publish_target(), error = function(e) "error"),
    "error"
  )
  writeLines("FW_PROJECT_TOKEN=fw_project", ".env")
  expect_identical(framework:::.fw_publish_target(), "cloud")
  expect_identical(framework:::.fw_publish_target("my_s3"), "s3")
})

test_that("publish_notebook() routes to Framework Cloud when the project has a token", {
  skip_if(!nzchar(Sys.which("quarto")), "quarto not installed")
  local_cloud_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines("FW_PROJECT_TOKEN=fw_project", ".env")
  writeLines(c("---", "title: Hi", "---", "", "Hello"), "hi.qmd")

  called <- NULL
  testthat::local_mocked_bindings(
    .fw_cloud_publish = function(source, dest = NULL, title = NULL, self_contained = TRUE, slug = NULL, ...) {
      called <<- list(source = source, dest = dest, self_contained = self_contained, slug = slug)
      invisible("https://example/hi")
    }
  )
  suppressMessages(publish_notebook("hi.qmd", dest = "reports/hi", slug = "hi-there"))
  # publish() renders the notebook once and sends the rendered page.
  expect_identical(basename(called$source), "index.html")
  expect_identical(called$dest, "reports/hi")
  expect_identical(called$slug, "hi-there")
  expect_true(called$self_contained)
  expect_error(publish_notebook("hi.qmd", format = "pdf"), "requires HTML output")
})

test_that("publish() sends the slug, and readable only for TRUE or FALSE", {
  skip_if_not_installed("httr2")
  local_cloud_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeLines("<p>hi</p>", "main_report.html")

  sent <- list()
  response <- list(version = 3L, url = "http://localhost:8080/@ada/study/main-results", notice = NULL)
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      sent[[length(sent) + 1]] <<- list(url = req$url, fields = rlang::list2(...))
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) response,
    .package = "httr2"
  )

  expect_message(publish("main_report.html", slug = "main-results"),
                 "Published version 3: http://localhost:8080/@ada/study/main-results", fixed = TRUE)
  last <- sent[[1]]
  expect_identical(last$url, "http://localhost:8080/api/v1/documents")
  expect_identical(last$fields$slug, "main-results")
  # A string slug only names the artifact (a new one is unlisted)
  expect_null(last$fields$readable)
  expect_null(last$fields$visibility)

  suppressMessages(publish("main_report.html", slug = TRUE))
  expect_identical(sent[[2]]$fields$slug, "main_report")
  expect_identical(sent[[2]]$fields$readable, "1")

  suppressMessages(publish("main_report.html", slug = FALSE))
  expect_identical(sent[[3]]$fields$readable, "0")

  suppressMessages(publish("main_report.html"))
  expect_identical(sent[[4]]$fields$slug, "main_report")
  expect_null(sent[[4]]$fields$readable)

  # Public without a handle: the hint, without calling the link unlisted
  response$notice <- "Set a handle in Account > Account details to get a readable URL. The unlisted link works now."
  msgs <- testthat::capture_messages(publish("main_report.html", slug = TRUE))
  expect_true(any(grepl("Set a handle", msgs, fixed = TRUE)))
  expect_false(any(grepl("unlisted", msgs, fixed = TRUE)))

  # Unlisted: no handle hint
  response$notice <- NULL
  response$visibility <- "unlisted"
  msgs <- testthat::capture_messages(publish("main_report.html", slug = "main-results"))
  expect_false(any(grepl("handle", msgs, fixed = TRUE)))

  # Public with a readable URL: no hint either
  response$visibility <- "public"
  response$readable_url <- "http://localhost:8080/@ada/study/main-results"
  msgs <- testthat::capture_messages(publish("main_report.html", visibility = "public"))
  expect_false(any(grepl("handle", msgs, fixed = TRUE)))

  # Public, no handle, and a server that reports visibility
  response$readable_url <- NULL
  msgs <- testthat::capture_messages(publish("main_report.html", visibility = "public"))
  expect_true(any(grepl("Set a handle", msgs, fixed = TRUE)))

  expect_error(publish("main_report.html", slug = ""), "slug")
  expect_error(publish("main_report.html", slug = c("a", "b")), "slug")
})

test_that("slug warns on storage buckets", {
  expect_warning(framework:::.fw_warn_slug_ignored("x"), "Framework Cloud only")
  expect_silent(framework:::.fw_warn_slug_ignored(NULL))
})

test_that("R keeps its own config folder and config_sync() only pulls", {
  base <- withr::local_tempdir()
  r_dir <- file.path(base, "r-user-dir")
  shared <- file.path(base, "xdg", "framework")
  dir.create(r_dir)
  dir.create(shared, recursive = TRUE)
  withr::local_envvar(FW_CONFIG_HOME = NA, XDG_CONFIG_HOME = file.path(base, "xdg"))
  testthat::local_mocked_bindings(R_user_dir = function(...) r_dir, .package = "tools")

  file.create(file.path(shared, ".framework-home"))
  expect_identical(fw_config_dir(), r_dir)

  writeLines("server: http://localhost:8080", file.path(shared, "cloud.yml"))
  writeLines("fw_secret", file.path(shared, "cloud-token-localhost_8080"))
  writeLines("author: {name: Old}", file.path(r_dir, "settings.yml"))
  writeLines("author: {name: Ada}", file.path(shared, "settings.yml"))
  Sys.setFileTime(file.path(r_dir, "settings.yml"), Sys.time() - 3600)
  writeLines("revision: 9", file.path(shared, "sync-state.yml"))
  writeLines("defaults: {}", file.path(shared, "cloud-settings.yml"))
  before <- list.files(shared, all.files = TRUE, no.. = TRUE)

  expect_message(planned <- config_sync(dry_run = TRUE), "Would copy")
  expect_setequal(planned, c("cloud.yml", "cloud-token-localhost_8080", "settings.yml"))
  expect_false(file.exists(file.path(r_dir, "cloud.yml")))

  suppressMessages(config_sync())
  expect_identical(readLines(file.path(r_dir, "settings.yml")), "author: {name: Ada}")
  expect_identical(readLines(file.path(r_dir, "cloud-token-localhost_8080")), "fw_secret")
  expect_false(file.exists(file.path(r_dir, ".framework-home")))
  expect_false(file.exists(file.path(r_dir, "sync-state.yml")))
  expect_false(file.exists(file.path(r_dir, "cloud-settings.yml")))
  expect_identical(list.files(shared, all.files = TRUE, no.. = TRUE), before)   # never written

  expect_message(config_sync(), "already in line")

  withr::local_envvar(FW_CONFIG_HOME = file.path(base, "explicit"))
  expect_identical(fw_config_dir(), file.path(base, "explicit"))
})


test_that("explicit destinations override configured buckets", {
  testthat::local_mocked_bindings(.fw_has_storage_buckets = function() TRUE)
  expect_identical(framework:::.fw_publish_target(to = "cloud"), "cloud")
  expect_identical(framework:::.fw_publish_target(to = "bucket"), "s3")
  expect_error(framework:::.fw_publish_target("bucket", to = "cloud"), "connection")
})

test_that("object exports preserve tables and restrict model output", {
  stage <- withr::local_tempdir()
  path <- framework:::.fw_artifact_file(data.frame(estimate = 1.5), stage)
  expect_equal(utils::read.csv(path), data.frame(estimate = 1.5))
  fit <- stats::lm(mpg ~ wt, data = mtcars)
  path <- framework:::.fw_artifact_file(fit, stage)
  html <- paste(readLines(path), collapse = "\n")
  expect_match(html, "Coefficients")
  expect_match(html, "Observations: 32")
  expect_false(grepl("Mazda RX4", html, fixed = TRUE))
  expect_error(framework:::.fw_artifact_file(list(), stage), "accepts")
})


test_that("cloud file artifacts preserve filenames and protection metadata", {
  skip_if_not_installed("httr2")
  local_cloud_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeBin(charToRaw("original bytes"), "figure.png")
  sent <- NULL
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      sent <<- rlang::list2(...)
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(url = "https://x/d/figure", version = 1L),
    .package = "httr2"
  )
  suppressMessages(publish("figure.png", to = "cloud", title = "Figure",
                           description = "Adjusted estimates", password = "review-password"))
  expect_identical(basename(sent$file$path), "figure.png")
  expect_identical(sent$slug, "figure")
  expect_identical(sent$title, "Figure")
  expect_identical(sent$description, "Adjusted estimates")
  expect_identical(sent$password, "review-password")
  expect_null(sent$bundle)
  suppressMessages(publish(data.frame(estimate = 1.2), to = "cloud"))
  expect_identical(basename(sent$file$path), "table.json")
  expect_identical(sent$slug, "table")
  expect_identical(sent$kind, "table")
})

test_that("cloud object artifacts name test documents and accept character matrices", {
  skip_if_not_installed("httr2")
  local_cloud_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  sent <- NULL
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      sent <<- rlang::list2(...)
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(url = "https://x/d/test", version = 1L),
    .package = "httr2"
  )
  suppressMessages(publish(stats::t.test(extra ~ group, data = sleep), to = "cloud"))
  expect_identical(basename(sent$file$path), "test.json")
  expect_identical(sent$kind, "test")
  suppressMessages(publish(matrix(c("a", "b", "c", "d"), 2), to = "cloud"))
  expect_identical(basename(sent$file$path), "table.json")
  expect_identical(sent$kind, "table")
})


test_that("collection preflight and attachment preserve a successful publication", {
  skip_if_not_installed("httr2")
  local_cloud_env()
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeBin(charToRaw("png"), "figure.png")
  uploads <- 0L
  attached <- NULL
  mode <- "success"
  testthat::local_mocked_bindings(.fw_api = function(path, token, method = "GET", body = NULL, ...) {
    if (identical(method, "GET")) {
      if (mode == "missing") return(list(collections = list()))
      return(list(collections = list(list(id = 7L, slug = "findings", title = "Findings", visibility = "unlisted"))))
    }
    expect_identical(path, "/api/v1/collections/7/items")
    attached <<- body
    if (mode == "fail") stop("Attachment denied")
    list(id = 1L)
  })
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) { uploads <<- uploads + 1L; req },
    resp_body_json = function(resp, ...) { force(resp); list(id = 14L, url = "https://x/d/figure", version = 1L) },
    .package = "httr2"
  )
  suppressMessages(url <- publish("figure.png", to = "cloud", collection = "findings", share_unlisted = TRUE))
  expect_identical(url, "https://x/d/figure")
  expect_identical(attached, list(document_id = 14L, share_unlisted = TRUE))
  expect_identical(uploads, 1L)
  mode <- "fail"
  expect_warning(suppressMessages(url <- publish("figure.png", to = "cloud", collection = 7L,
                                                share_unlisted = TRUE)), "Artifact published at https://x/d/figure")
  expect_identical(url, "https://x/d/figure")
  expect_identical(uploads, 2L)
  mode <- "missing"
  expect_error(publish("figure.png", to = "cloud", collection = "missing"), "missing or ambiguous")
  expect_identical(uploads, 2L)
  mode <- "success"
  expect_error(publish("figure.png", to = "cloud", slug = FALSE, collection = 7L), "share_unlisted")
  expect_identical(uploads, 2L)
})

test_that("cloud_status() and token errors give the same login advice", {
  hint <- framework:::.fw_login_hint("https://framework.pub")
  expect_identical(hint, paste0(
    "Run framework::cloud_login() to approve this computer in your browser, or create a token at ",
    "https://framework.pub/tokens and run framework::cloud_login(\"fw_...\")."
  ))
  other <- framework:::.fw_login_hint("https://cloud.example.org")
  expect_match(other, 'framework::cloud_login(url = "https://cloud.example.org")', fixed = TRUE)
  expect_match(other, 'framework::cloud_login("fw_...", url = "https://cloud.example.org")', fixed = TRUE)

  testthat::local_mocked_bindings(.fw_cloud_token = function(...) NULL)
  err <- tryCatch(framework:::.fw_require_token("https://framework.pub"), error = conditionMessage)
  expect_true(grepl(hint, err, fixed = TRUE))
  expect_true(grepl("cloud_login() to approve", err, fixed = TRUE))
})

test_that("cloud_status() gives the shared login hint when not connected", {
  testthat::local_mocked_bindings(.fw_cloud_token = function(...) NULL)
  withr::local_envvar(FW_CLOUD_URL = "https://cloud.example.org")
  withr::local_dir(withr::local_tempdir())
  msgs <- capture.output(connected <- cloud_status(), type = "message")
  expect_false(connected)
  expect_true(any(grepl(framework:::.fw_login_hint("https://cloud.example.org"), msgs, fixed = TRUE)))
})
