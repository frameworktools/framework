local_publish_settings <- function(path, env = parent.frame()) {
  project <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(project, .local_envir = env)
  yaml::write_yaml(list(default = list(publish = list(default = "share", destinations = list(
    share = list(driver = "folder", path = path, url = "https://files.example.org/research"),
    cloud = list(driver = "cloud"), pages = list(driver = "github")
  )))), "settings.yml")
  testthat::local_mocked_bindings(.fw_project_token = function(...) NULL, .env = env)
}

test_that("named destinations precede legacy bucket selection", {
  root <- withr::local_tempdir()
  local_publish_settings(root)
  expect_identical(framework:::.fw_publish_destination()$driver, "folder")
  expect_identical(framework:::.fw_publish_destination("cloud")$driver, "cloud")
  expect_identical(framework:::.fw_publish_destination("pages")$driver, "github")
  expect_error(framework:::.fw_publish_destination("missing"), "Unknown publishing destination")
})

test_that("folder bundles retain typed objects and immutable versions", {
  root <- withr::local_tempdir()
  local_publish_settings(root)
  url <- publish(data.frame(label = c("A", "B"), estimate = c(1.234, 5.678)), slug = "My.Table_Results", title = "Study results")
  expect_identical(url, "https://files.example.org/research/my-table-results/")
  artifact <- file.path(root, "my-table-results")
  manifest <- jsonlite::read_json(file.path(artifact, "artifact.json"))
  expect_identical(manifest$schema, "framework.bundle/v1")
  expect_identical(manifest$kind, "table")
  expect_equal(manifest$version, 1)
  expect_true(file.exists(file.path(artifact, "data.csv")))
  expect_true(file.exists(file.path(artifact, "representation.json")))
  for (file in manifest$files) {
    expect_identical(digest::digest(file = file.path(artifact, file$path), algo = "sha256"), file$sha256)
    expect_equal(file.info(file.path(artifact, file$path))$size, file$bytes)
  }
  initial <- readBin(file.path(artifact, "representation.json"), "raw", n = 100000)
  publish(data.frame(label = "C", estimate = 8), slug = "my-table-results")
  expect_equal(jsonlite::read_json(file.path(artifact, "artifact.json"))$version, 2)
  expect_identical(readBin(file.path(artifact, "v/1/representation.json"), "raw", n = 100000), initial)
  expect_true(file.exists(file.path(artifact, "v/2/index.html")))
  index <- jsonlite::read_json(file.path(root, "index.json"))
  expect_length(index$artifacts, 1)
  expect_equal(index$artifacts[[1]]$version, 2)
  expect_error(publish(data.frame(x = 4), slug = "my-table-results", overwrite = FALSE), "already exists")
})

test_that("unsupported sharing fails before creating destination files", {
  root <- file.path(withr::local_tempdir(), "new-site")
  local_publish_settings(root)
  for (visibility in c("unlisted", "private")) {
    expect_error(publish(data.frame(x = 1), visibility = visibility), "requires|require")
    expect_false(dir.exists(root))
  }
  expect_error(publish(data.frame(x = 1), password = "secret"), "Password")
  expect_error(publish(data.frame(x = 1), collection = "results"), "Collections")
  expect_false(dir.exists(root))
  expect_error(publish(data.frame(x = 1), to = "pages", visibility = "private"), "confirmed private")
})

test_that("static readers safely embed content without remote requests", {
  bundle <- framework:::.fw_bundle_build(data.frame(x = '</script><script>alert("x")</script>'), title = '<img src=x onerror=alert(1)>')
  on.exit(unlink(bundle$path, recursive = TRUE))
  html <- paste(readLines(file.path(bundle$path, "index.html")), collapse = "\n")
  expect_match(html, "&lt;img src=x onerror=alert(1)&gt;", fixed = TRUE)
  expect_false(grepl('</script><script>alert', html, fixed = TRUE))
  expect_match(html, "\\u003c", fixed = TRUE)
  expect_false(grepl('<script[^>]+src=', html))
  expect_false(grepl('__FRAMEWORK_', html, fixed = TRUE))
})

test_that("unsafe source trees and destination symlinks preserve existing files", {
  skip_on_os("windows")
  root <- withr::local_tempdir()
  local_publish_settings(root)
  dir.create("render")
  writeLines("<p>safe</p>", "render/index.html")
  writeLines("secret", "outside.txt")
  file.symlink(normalizePath("outside.txt"), "render/leak.txt")
  expect_error(publish("render"), "symbolic links")
  expect_false(file.exists(file.path(root, "render")))
  unlink("render/leak.txt")
  outside <- withr::local_tempdir()
  writeLines("keep", file.path(outside, "keep.txt"))
  file.symlink(outside, file.path(root, "render"))
  expect_error(publish("render"), "symbolic link")
  expect_identical(readLines(file.path(outside, "keep.txt")), "keep")
})

test_that("external tracking sends metadata only and preserves success on failure", {
  bundle <- framework:::.fw_bundle_build(data.frame(x = 1), slug = "study")
  on.exit(unlink(bundle$path, recursive = TRUE))
  calls <- list()
  testthat::local_mocked_bindings(
    .fw_project_token = function(...) "project-token",
    .fw_project_cloud_url = function(...) "https://cloud.example.org",
    .fw_api = function(path, token, method = "GET", body = NULL, ...) {
      if (method == "GET") return(list(kind = "project", project = "my-project"))
      calls[[length(calls) + 1]] <<- list(path = path, body = body)
    }
  )
  receipt <- list(driver = "folder", url = NULL, version_url = NULL, version = 1L, location = "/secret/mount/path")
  framework:::.fw_track_external(bundle, receipt)
  expect_identical(calls[[1]]$path, "/api/v1/projects/my-project/artifacts/external")
  expect_false(grepl("/secret|/var|/tmp|location|representation", jsonlite::toJSON(calls[[1]]$body)))
  expect_identical(calls[[1]]$body$driver, "folder")
  expect_match(calls[[1]]$body$sha256, "^[a-f0-9]{64}$")
  testthat::local_mocked_bindings(.fw_api = function(...) stop("offline"))
  expect_warning(framework:::.fw_track_external(bundle, receipt), "Published successfully")
})

test_that("canonical new_project accepts project tokens without masking methods::new", {
  testthat::local_mocked_bindings(.cloud_setup = function(token, location, browse, url) list(token = token, location = location, url = url))
  expected <- list(token = "1|project", location = "study", url = "https://cloud.example.org")
  expect_identical(new_project(key = "1|project", location = "study", browse = FALSE, url = "https://cloud.example.org"), expected)
  expect_identical(new(key = "1|project", location = "study", browse = FALSE, url = "https://cloud.example.org"), expected)
  expect_error(new_project(name = "conflict", key = "1|project"), "name and type")
})

test_that("project specs preserve publishing defaults in flat and split settings", {
  publishing <- list(default = "share", destinations = list(share = list(driver = "folder", path = "/Volumes/lab/published")))
  for (layout in c("flat", "split")) {
    spec <- spec_resolve(list(list(kind = "project", key = "study", layer = list(
      name = "study", type = "bare", settings_layout = layout, publish = publishing,
      git = list(use_git = FALSE), ai = list(enabled = FALSE)
    ))), name = "study")
    expect_length(spec_check(spec), 0)
    root <- file.path(withr::local_tempdir(), "study")
    suppressMessages(framework:::.project_create_from_spec(spec, location = root))
    expect_identical(yaml::read_yaml(file.path(root, "settings.yml"))$default$publish, publishing)
  }
})

test_that("legacy cloud and bucket publishes construct the same typed bundle", {
  root <- withr::local_tempdir()
  withr::local_dir(root)
  seen <- list()
  real_build <- framework:::.fw_bundle_build
  testthat::local_mocked_bindings(
    .fw_bundle_build = function(...) {
      result <- real_build(...)
      seen[[length(seen) + 1L]] <<- result$manifest
      result
    },
    .fw_publish_target = function(connection = NULL, to = NULL) if (identical(to, "cloud")) "cloud" else "s3",
    .resolve_s3_connection = function(...) list(),
    .s3_upload_file = function(...) "https://files.example.org/result.csv",
    .fw_cloud_publish = function(...) "https://cloud.example.org/result",
    .fw_project_token = function(...) NULL
  )
  publish(data.frame(x = 1), to = "bucket")
  publish(data.frame(x = 1), to = "cloud")
  expect_length(seen, 2)
  expect_identical(seen[[1]]$kind, "table")
  expect_identical(seen[[2]]$kind, "table")
  expect_identical(seen[[1]]$representation, "representation.json")
  expect_identical(seen[[2]]$representation, "representation.json")
})

test_that("S3 bundle driver preserves versions and uploads the front page last", {
  skip_if_not_installed("aws.s3")
  bundle <- framework:::.fw_bundle_build(data.frame(x = 1), slug = "study")
  on.exit(unlink(bundle$path, recursive = TRUE))
  uploaded <- character()
  testthat::local_mocked_bindings(object_exists = function(...) TRUE,
    get_object = function(...) charToRaw('{"schema":"framework.bundle/v1","version":2}'), .package = "aws.s3")
  testthat::local_mocked_bindings(.s3_upload_file = function(file, dest, s3_config, ...) {
    uploaded <<- c(uploaded, dest)
    "https://files.example.org/study/"
  })
  s3 <- list(bucket = "results", region = "us-east-1", prefix = "research", access_key = "test", secret_key = "test", static_hosting = TRUE)
  receipt <- framework:::.fw_s3_bundle_deliver(bundle, list(driver = "s3"), s3)
  expect_equal(receipt$version, 3)
  expect_true(any(grepl("^study/v/3/", uploaded)))
  expect_identical(tail(uploaded, 1), "study/index.html")
  expect_match(receipt$version_url, "/v/3/$")
  uploaded <- character()
  expect_error(framework:::.fw_s3_bundle_deliver(bundle, list(driver = "s3"), s3, overwrite = FALSE), "already exists")
  expect_length(uploaded, 0)
})

test_that("failed folder staging preserves the previous artifact", {
  root <- withr::local_tempdir()
  local_publish_settings(root)
  publish(data.frame(x = 1), slug = "study")
  original <- readLines(file.path(root, "study/artifact.json"))
  testthat::local_mocked_bindings(.fw_bundle_copy = function(...) stop("copy failed"))
  bundle <- list(path = root, manifest = list(slug = "study"))
  expect_error(framework:::.fw_folder_deliver(bundle, list(path = root)), "copy failed")
  expect_identical(readLines(file.path(root, "study/artifact.json")), original)
  expect_false(dir.exists(file.path(root, ".framework-publish.lock")))
})

test_that("destination visibility is effective and legacy private aliases remain supported", {
  expect_identical(framework:::.fw_publish_visibility(list(visibility = "private")), "private")
  expect_identical(framework:::.fw_publish_visibility(list(private = TRUE)), "private")
  expect_identical(framework:::.fw_publish_visibility(list(visibility = "private"), "public"), "public")
  root <- withr::local_tempdir()
  project <- withr::local_tempdir()
  withr::local_dir(project)
  yaml::write_yaml(list(default = list(publish = list(default = "share", destinations = list(
    share = list(driver = "folder", path = root, visibility = "private")
  )))), "settings.yml")
  tracked <- NULL
  testthat::local_mocked_bindings(.fw_track_external = function(bundle, receipt, visibility = NULL) tracked <<- visibility)
  publish(data.frame(x = 1), slug = "study")
  expect_identical(tracked, "private")
})

test_that("publishing credentials require environment references", {
  expect_error(framework:::.fw_publish_assert_secrets(list(share = list(secret_access_key = "literal-secret"))), "env")
  expect_no_error(framework:::.fw_publish_assert_secrets(list(share = list(secret_access_key = 'env("AWS_SECRET_ACCESS_KEY")'))))
  expect_error(spec_resolve(list(list(kind = "project", key = "study", layer = list(
    publish = list(default = "bucket", destinations = list(bucket = list(driver = "s3", api_key = "literal")))
  ))), name = "study"), "credentials must use env")
})

test_that("S3 privacy requires authoritative bucket controls", {
  skip_if_not_installed("aws.s3")
  s3 <- list(bucket = "results", region = "us-east-1", access_key = "test", secret_key = "test")
  testthat::local_mocked_bindings(s3HTTP = function(query, ...) {
    if (!is.null(query$policyStatus)) return(list(PolicyStatus = list(IsPublic = "false")))
    list(PublicAccessBlockConfiguration = list(BlockPublicAcls = "true", IgnorePublicAcls = "true", BlockPublicPolicy = "true", RestrictPublicBuckets = "true"))
  }, .package = "aws.s3")
  expect_no_error(framework:::.fw_s3_confirm_private(s3))
  testthat::local_mocked_bindings(s3HTTP = function(...) list(PolicyStatus = list(IsPublic = "true")), .package = "aws.s3")
  expect_error(framework:::.fw_s3_confirm_private(s3), "could not confirm")
})


test_that("private S3 verification accepts aws.s3 scalar PolicyStatus responses", {
  skip_if_not_installed("aws.s3")
  s3 <- list(bucket = "results", region = "us-east-1", access_key = "test", secret_key = "test")
  testthat::local_mocked_bindings(s3HTTP = function(query, ...) {
    if (!is.null(query$policyStatus)) return(structure("false", server = "AmazonS3"))
    list(BlockPublicAcls="true", IgnorePublicAcls="true", BlockPublicPolicy="true", RestrictPublicBuckets="true")
  }, .package="aws.s3")
  expect_no_error(framework:::.fw_s3_confirm_private(s3))
})

test_that("a relative folder path starts at the project root, not the working directory", {
  local_publish_settings("local-site")
  project <- getwd()
  dir.create("notebooks")
  withr::local_dir("notebooks")
  publish(data.frame(x = 1:2), slug = "from-notebook")
  expect_true(file.exists(file.path(project, "local-site", "from-notebook", "artifact.json")))
  expect_false(dir.exists(file.path(project, "notebooks", "local-site")))
  expect_identical(framework:::.fw_folder_path("/abs/site"), "/abs/site")
  expect_identical(framework:::.fw_folder_path("~/site"), path.expand("~/site"))
})

test_that("publish_data(), publish_dir(), and publish_list() follow publish.default", {
  local_publish_settings("local-site")
  project <- getwd()
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(...) stop("No S3 connections configured")
  )

  df <- data.frame(arm = c("a", "b"), n = c(10, 12))
  # The slug keeps the folder part of dest, and the message names it
  expect_message(url <- publish_data(df, "tables/arm_counts.csv"), "Publishing tables/arm_counts.csv as tables-arm-counts", fixed = TRUE)
  expect_identical(url, "https://files.example.org/research/tables-arm-counts/")
  artifact <- file.path(project, "local-site", "tables-arm-counts")
  expect_true(file.exists(file.path(artifact, "arm_counts.csv")))
  expect_identical(read.csv(file.path(artifact, "arm_counts.csv"))$n, c(10L, 12L))

  dir.create("figures/sub", recursive = TRUE)
  writeLines("a", "figures/a.png")
  writeLines("b", "figures/b.txt")
  writeLines("c", "figures/sub/c.png")
  publish_dir("figures", pattern = "\\.png$")
  files <- list.files(file.path(project, "local-site", "figures"), recursive = TRUE)
  expect_true(all(c("a.png", "sub/c.png") %in% files))
  expect_false("b.txt" %in% files)

  listed <- publish_list()
  expect_setequal(listed$key, c("tables-arm-counts/", "figures/"))
  expect_identical(publish_list("fig")$key, "figures/")
  expect_error(publish_list(to = "cloud"), "lists S3 and folder destinations")
})

test_that("publish_data() slugs are dest without its extension, / as -", {
  slug <- framework:::.fw_data_slug
  expect_identical(slug("tables/demo.csv"), "tables-demo")
  expect_identical(slug("demo.csv"), "demo")
  expect_identical(slug("./tables/sub/demo.csv.gz"), "tables-sub-demo")
  expect_identical(slug("tables\\demo.rds"), "tables-demo")
  expect_identical(slug("a.b/c"), "a-b-c")
  expect_identical(slug("tables/BP_by_visit.csv"), "tables-bp-by-visit")
})

test_that("publish_data() still uploads to a bucket with connection or to = 's3'", {
  local_publish_settings("local-site")
  uploaded <- character()
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(name = NULL, ...) list(bucket = name %||% "default", region = "", prefix = ""),
    .s3_upload_file = function(file, dest, config) {
      uploaded <<- c(uploaded, paste0(config$bucket, ":", dest))
      paste0("http://mock/", dest)
    },
    .fw_track_external = function(...) NULL
  )
  suppressMessages(publish_data(data.frame(x = 1), "d/x.csv", connection = "backup"))
  suppressMessages(publish_data(data.frame(x = 1), "d/y.csv", to = "s3"))
  expect_identical(uploaded, c("backup:d/x.csv", "default:d/y.csv"))
  expect_false(dir.exists("local-site"))
})

test_that("publishing a document defaults the title to its YAML title", {
  dir <- withr::local_tempdir()
  writeLines(c("---", 'title: "Blood pressure summary"', "format: html", "---", "", "Body"), file.path(dir, "bp.qmd"))
  writeLines(c("# No front matter"), file.path(dir, "plain.qmd"))
  writeLines(c("---", "---", "x"), file.path(dir, "empty.qmd"))
  expect_identical(framework:::.fw_doc_title(file.path(dir, "bp.qmd")), "Blood pressure summary")
  expect_null(framework:::.fw_doc_title(file.path(dir, "plain.qmd")))
  expect_null(framework:::.fw_doc_title(file.path(dir, "empty.qmd")))
  expect_null(framework:::.fw_doc_title(file.path(dir, "missing.qmd")))
})

test_that("publish_notebook() passes title and description, defaulting to the YAML title", {
  local_publish_settings("local-site")
  writeLines(c("---", "title: Summary of results", "---", "", "Hi"), "report.qmd")
  seen <- list()
  testthat::local_mocked_bindings(
    .fw_bundle_build = function(source, slug = NULL, title = NULL, description = NULL, ...) {
      seen[[length(seen) + 1L]] <<- list(title = title, description = description)
      stop("stop after bundle")
    }
  )
  expect_error(publish_notebook("report.qmd", slug = "r"), "stop after bundle")
  expect_error(publish_notebook("report.qmd", slug = "r", title = "Custom", description = "About it"), "stop after bundle")
  expect_identical(seen[[1]]$title, "Summary of results")
  expect_identical(seen[[2]], list(title = "Custom", description = "About it"))
})

test_that("publish_dir() slugs keep the folder part of dest", {
  slug <- framework:::.fw_dir_slug
  expect_identical(slug("figures/meeting"), "figures-meeting")
  expect_identical(slug("reports/v1.2"), "reports-v1-2")
  expect_identical(slug("./figures/Meeting_1/"), "figures-meeting-1")
  expect_identical(slug("tables\\demo"), "tables-demo")

  local_publish_settings("local-site")
  project <- getwd()
  dir.create("figures")
  writeLines("png", "figures/a.png")
  writeLines("txt", "figures/b.txt")
  expect_message(url <- publish_dir("figures", dest = "figures/Meeting_1"),
                 "Publishing figures/Meeting_1 as figures-meeting-1", fixed = TRUE)
  expect_identical(url, "https://files.example.org/research/figures-meeting-1/")
  expect_identical(
    suppressMessages(publish_dir("figures", dest = "figures/Meeting_1", pattern = "png")),
    "https://files.example.org/research/figures-meeting-1/"
  )
  expect_true(file.exists(file.path(project, "local-site", "figures-meeting-1", "a.png")))
})
