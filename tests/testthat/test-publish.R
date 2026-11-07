# Tests for S3 publishing functions
# Note: Most S3 tests require credentials and are skipped in CI

test_that(".resolve_s3_connection finds explicit connection", {
  skip_if_not_installed("aws.s3")

  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create config with S3 connection
  config <- list(
    default = list(
      connections = list(
        storage_buckets = list(
          my_s3 = list(
            bucket = "test-bucket",
            region = "us-east-1",
            prefix = "test-prefix"
          )
        )
      )
    )
  )

  yaml::write_yaml(config, "settings.yml")

  # Set credentials in environment
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = "test-key",
    AWS_SECRET_ACCESS_KEY = "test-secret"
  )

  result <- framework:::.resolve_s3_connection("my_s3")

  expect_equal(result$bucket, "test-bucket")
  expect_equal(result$region, "us-east-1")
  expect_equal(result$prefix, "test-prefix")
  expect_equal(result$access_key, "test-key")
  expect_equal(result$secret_key, "test-secret")
})


test_that(".resolve_s3_connection finds default connection", {
  skip_if_not_installed("aws.s3")

  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create config with default S3 connection
  config <- list(
    default = list(
      connections = list(
        storage_buckets = list(
          s3_backup = list(
            bucket = "backup-bucket",
            region = "us-west-2"
          ),
          s3_primary = list(
            bucket = "primary-bucket",
            region = "us-east-1",
            default = TRUE
          )
        )
      )
    )
  )

  yaml::write_yaml(config, "settings.yml")

  withr::local_envvar(
    AWS_ACCESS_KEY_ID = "test-key",
    AWS_SECRET_ACCESS_KEY = "test-secret"
  )

  # Should find the default connection
  result <- framework:::.resolve_s3_connection(NULL)

  expect_equal(result$bucket, "primary-bucket")
  expect_equal(result$region, "us-east-1")
})


test_that(".resolve_s3_connection errors when connection not found", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  config <- list(
    default = list(
      connections = list(
        framework = list(
          driver = "sqlite",
          database = "framework.db"
        )
      )
    )
  )

  yaml::write_yaml(config, "settings.yml")

  expect_error(
    framework:::.resolve_s3_connection("nonexistent"),
    "No S3 connections configured|not found"
  )
})


test_that(".resolve_s3_connection errors when credentials are missing", {
  skip_if_not_installed("aws.s3")

  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # S3 connection exists but no credentials
  config <- list(
    default = list(
      connections = list(
        storage_buckets = list(
          my_s3 = list(
            bucket = "test-bucket",
            region = "us-east-1"
          )
        )
      )
    )
  )

  yaml::write_yaml(config, "settings.yml")

  expect_error(
    framework:::.resolve_s3_connection(NULL),
    "S3 credentials not found"
  )
})


test_that(".resolve_s3_connection errors for non-S3 connection", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  config <- list(
    default = list(
      connections = list(
        framework = list(
          driver = "sqlite",
          database = "framework.db"
        )
      )
    )
  )

  yaml::write_yaml(config, "settings.yml")

  expect_error(
    framework:::.resolve_s3_connection("framework"),
    "No S3 connections configured|not an S3 connection"
  )
})


test_that(".resolve_s3_connection errors when missing credentials", {
  skip_if_not_installed("aws.s3")

  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  config <- list(
    default = list(
      connections = list(
        storage_buckets = list(
          my_s3 = list(
            bucket = "test-bucket",
            region = "us-east-1"
          )
        )
      )
    )
  )

  yaml::write_yaml(config, "settings.yml")

  # Clear any existing credentials
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = "",
    AWS_SECRET_ACCESS_KEY = ""
  )

  expect_error(
    framework:::.resolve_s3_connection("my_s3"),
    "credentials not found"
  )
})


test_that(".guess_content_type returns correct MIME types", {
  expect_equal(framework:::.guess_content_type("test.html"), "text/html")
  expect_equal(framework:::.guess_content_type("test.css"), "text/css")
  expect_equal(framework:::.guess_content_type("test.js"), "application/javascript")
  expect_equal(framework:::.guess_content_type("test.json"), "application/json")
  expect_equal(framework:::.guess_content_type("test.csv"), "text/csv")
  expect_equal(framework:::.guess_content_type("test.png"), "image/png")
  expect_equal(framework:::.guess_content_type("test.jpg"), "image/jpeg")
  expect_equal(framework:::.guess_content_type("test.pdf"), "application/pdf")
  expect_equal(framework:::.guess_content_type("test.rds"), "application/octet-stream")
  expect_equal(framework:::.guess_content_type("test.unknown"), "application/octet-stream")
})


test_that(".s3_public_url generates correct AWS URLs", {
  s3_config <- list(
    bucket = "my-bucket",
    region = "us-east-1",
    prefix = "",
    endpoint = NULL
  )

  url <- framework:::.s3_public_url("path/to/file.html", s3_config)
  expect_equal(url, "https://my-bucket.s3.us-east-1.amazonaws.com/path/to/file.html")
})


test_that(".s3_public_url handles custom endpoints", {
  s3_config <- list(
    bucket = "my-bucket",
    region = "us-east-1",
    prefix = "",
    endpoint = "https://minio.example.com"
  )

  url <- framework:::.s3_public_url("path/to/file.html", s3_config)
  expect_equal(url, "https://minio.example.com/my-bucket/path/to/file.html")
})


test_that("publish validates source exists", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create minimal config
  config <- list(
    default = list(
      connections = list(
        my_s3 = list(driver = "s3", bucket = "test", region = "us-east-1", default = TRUE)
      )
    )
  )
  yaml::write_yaml(config, "config.yml")

  expect_error(
    publish("nonexistent_file.txt"),
    "Source not found"
  )
})


test_that("publish_notebook validates file extension", {
  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a non-qmd file
  writeLines("test", "test.R")

  expect_error(
    publish_notebook("test.R"),
    "extension"
  )
})


test_that("publish_data handles data frames", {
  skip_if_not_installed("aws.s3")

  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create config with S3 connection
  config <- list(
    default = list(
      connections = list(
        my_s3 = list(
          driver = "s3",
          bucket = "test-bucket",
          region = "us-east-1",
          default = TRUE
        )
      )
    )
  )
  yaml::write_yaml(config, "config.yml")

  # This will fail at S3 upload (no real credentials), but we're testing
  # that data frame handling works up to that point
  withr::local_envvar(
    AWS_ACCESS_KEY_ID = "test",
    AWS_SECRET_ACCESS_KEY = "test"
  )

  df <- data.frame(x = 1:3, y = letters[1:3])

  # Should fail at S3 upload, not at data frame handling
expect_error(
    publish_data(df, "test.csv"),
    "S3|upload|403|Access Denied|Forbidden|InvalidAccessKeyId"
  )
})


# Integration tests - only run if S3_TEST_BUCKET is set
test_that("S3 integration tests", {
  skip_if(
    Sys.getenv("S3_TEST_BUCKET") == "",
    "S3_TEST_BUCKET not set - skipping integration tests"
  )

  test_dir <- create_test_dir()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create config with test bucket
  config <- list(
    default = list(
      connections = list(
        test_s3 = list(
          driver = "s3",
          bucket = Sys.getenv("S3_TEST_BUCKET"),
          region = Sys.getenv("S3_TEST_REGION", "us-east-1"),
          prefix = paste0("framework-test-", format(Sys.time(), "%Y%m%d%H%M%S")),
          default = TRUE
        )
      )
    )
  )
  yaml::write_yaml(config, "config.yml")

  # Test s3_test()
  expect_true(s3_test())

  # Test publish() with a simple file
  writeLines("Hello, World!", "test.txt")
  url <- publish("test.txt")
  expect_match(url, "test\\.txt$")

  # Test publish_data() with data frame
  df <- data.frame(x = 1:3, y = letters[1:3])
  url <- publish_data(df, "test-data.csv")
  expect_match(url, "test-data\\.csv$")

  # Test publish_list()
  files <- publish_list()
  expect_s3_class(files, "data.frame")
  expect_true(nrow(files) >= 2)

  # Test publish_dir()
  dir.create("test_dir")
  writeLines("file1", "test_dir/file1.txt")
  writeLines("file2", "test_dir/file2.txt")
  urls <- publish_dir("test_dir")
  expect_length(urls, 2)
})

test_that("uploads retry without the ACL when the bucket has ACLs disabled", {
  skip_if_not_installed("aws.s3")
  file <- withr::local_tempfile(fileext = ".html")
  writeLines("<p>hi</p>", file)
  calls <- list()
  testthat::local_mocked_bindings(
    put_object = function(file, object, bucket, headers, ...) {
      calls[[length(calls) + 1]] <<- headers
      if (!is.null(headers$`x-amz-acl`)) stop("AccessControlListNotSupported: The bucket does not allow ACLs")
      TRUE
    },
    .package = "aws.s3"
  )
  config <- list(bucket = "b", region = "us-east-1", access_key = "k", secret_key = "s")
  suppressMessages(framework:::.s3_upload_file(file, "report.html", config))
  expect_length(calls, 2)
  expect_null(calls[[2]]$`x-amz-acl`)
})

test_that("publishing warns about private paths and stops in scripts", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  dir.create("outputs/Private", recursive = TRUE)
  writeLines("<p>secret</p>", "outputs/Private/report.html")
  confirm <- framework:::.fw_confirm_private

  withr::local_options(rlang_interactive = FALSE)
  expect_warning(
    expect_error(publish("outputs/Private/report.html"), "include_private = TRUE"),
    "private"
  )
  expect_warning(
    expect_error(
      publish_dir("outputs/Private"),
      "Not uploading files from private folders without confirmation. Review it, then pass include_private = TRUE to upload it.",
      fixed = TRUE
    ),
    "2 file(s) to upload are in private folders:", fixed = TRUE
  )
  expect_silent(confirm("outputs/Private/report.html", include_private = TRUE))
  expect_silent(confirm("/srv/project/outputs/public/report.html"))
  # A folder part named private or ending in _private, in any case; not the
  # file name or other words
  expect_warning(expect_error(confirm("/home/Studies_PRIVATE/report.html")), "private folders")
  expect_silent(confirm("/home/PRIVATE-studies/report.html"))
  expect_silent(confirm("/srv/my_private_notes.html"))
  expect_silent(confirm("/srv/notebooks/01-private-and-public-data.qmd"))
  # macOS puts /tmp, /var, and /etc under /private; a folder the user named
  # private still counts
  expect_silent(confirm("/private/var/folders/xy/T/Rtmp1/report.html"))
  expect_silent(confirm(file.path(tempdir(), "report.html")))
  expect_warning(expect_error(confirm(file.path(tempdir(), "private", "x.html"))), "private")
  expect_warning(expect_error(confirm("/private/var/folders/proj/Private/out.html")), "private")
  expect_warning(expect_error(confirm("~/proj/Private/out.html")), "private")

  # Every file in a folder is checked, and the warning lists at most five
  dir.create("outputs/public/site", recursive = TRUE)
  writeLines("ok", "outputs/public/site/index.html")
  expect_silent(confirm("outputs/public/site"))
  for (i in 1:7) writeLines("x", sprintf("outputs/public/site/private_%d.html", i))
  expect_silent(confirm("outputs/public/site"))
  dir.create("outputs/public/site/private")
  for (i in 1:7) writeLines("x", sprintf("outputs/public/site/private/%d.html", i))
  expect_error(
    expect_warning(confirm("outputs/public/site"), "private/5.html.*and 2 more"),
    "Not uploading files from private folders"
  )

  # Interactive sessions ask, and only an explicit yes publishes
  withr::local_options(rlang_interactive = TRUE)
  answer <- NA
  testthat::local_mocked_bindings(askYesNo = function(...) answer, .package = "utils")
  expect_warning(expect_error(confirm("/srv/private/x.html"), "Cancelled"), "private")
  answer <- FALSE
  expect_warning(expect_error(confirm("/srv/private/x.html"), "Cancelled"), "private")
  answer <- TRUE
  expect_warning(expect_true(confirm("/srv/private/x.html")), "private")
})

test_that("publishing checks settings folders whose key names them private", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project", directories = list(
    outputs_private = "outputs/restricted", outputs_public = "outputs/shared",
    outputs_private_public = "outputs/both"
  ))), "settings.yml")
  dir.create("outputs/restricted", recursive = TRUE)
  dir.create("outputs/shared", recursive = TRUE)
  writeLines("x", "outputs/restricted/a.html")
  writeLines("x", "outputs/shared/a.html")
  withr::local_options(rlang_interactive = FALSE)
  confirm <- framework:::.fw_confirm_private
  expect_warning(expect_error(confirm("outputs/restricted/a.html"), "Not uploading files from private folders"),
                 "1 file(s) to upload are in private folders:", fixed = TRUE)
  expect_warning(expect_error(confirm("outputs/restricted")), "private folders")
  expect_silent(confirm("outputs/shared/a.html"))
  # A key that also says public isn't a private folder
  dir.create("outputs/both")
  writeLines("x", "outputs/both/a.html")
  expect_silent(confirm("outputs/both/a.html"))
  withr::with_dir("outputs", expect_warning(expect_error(confirm("restricted/a.html")), "private folders"))
})


test_that("AWS raw ACL errors retry safely and use the default AWS endpoint", {
  skip_if_not_installed("aws.s3")
  file <- withr::local_tempfile(fileext = ".html")
  writeLines("<p>Synthetic output</p>", file)
  calls <- list()
  testthat::local_mocked_bindings(put_object = function(file, object, bucket, headers, base_url, parse_response, ...) {
    calls[[length(calls) + 1L]] <<- headers
    expect_identical(base_url, "s3.amazonaws.com")
    expect_false(parse_response)
    response <- if (length(calls) == 1L) list(status_code=400L, content=charToRaw("<Error><Code>AccessControlListNotSupported</Code></Error>")) else list(status_code=200L, content=raw())
    structure(FALSE, response=response)
  }, .package="aws.s3")
  config <- list(bucket="b",region="us-east-1",access_key="k",secret_key="s")
  expect_silent(framework:::.s3_upload_file(file, "report.html", config))
  expect_length(calls, 2L)
  expect_null(calls[[2L]]$`x-amz-acl`)
})
