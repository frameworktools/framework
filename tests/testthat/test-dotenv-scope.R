# settings_read() uses a project's .env only while it resolves settings.
# Nothing is left in the R session, so values never leak between projects,
# and empty template lines never blank a shell credential.

local_env_project <- function(dir, env_lines, settings = list(default = list(project_type = "project"))) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(settings, file.path(dir, "settings.yml"))
  writeLines(env_lines, file.path(dir, ".env"))
  dir
}

test_that(".fw_read_dotenv follows the dotenv rules", {
  path <- withr::local_tempfile()
  writeLines(c("# note", "", "A=1", "export B=\"two words\"", "C=", "D='x#y'", "A=3"), path)
  values <- framework:::.fw_read_dotenv(path)
  expect_identical(values[["A"]], "3")
  expect_identical(values[["B"]], "two words")
  expect_identical(values[["C"]], "")
  expect_identical(values[["D"]], "x#y")
  expect_length(framework:::.fw_read_dotenv(tempfile()), 0)

  writeLines("not a pair", path)
  expect_error(framework:::.fw_read_dotenv(path), "Cannot parse")
})

test_that("settings_read() does not load .env into the session", {
  withr::local_envvar(FW_PROJECT_TOKEN = NA, FW_CLOUD_URL = NA, FW_TEST_DB_PASS = NA)
  root <- withr::local_tempdir()
  a <- local_env_project(
    file.path(root, "a"),
    c("FW_PROJECT_TOKEN=fw_token_a", "FW_CLOUD_URL=http://127.0.0.1:18765", "FW_TEST_DB_PASS=s3cret"),
    list(default = list(project_type = "project", db_pass = "env(\"FW_TEST_DB_PASS\")",
                        expr_pass = "!expr Sys.getenv(\"FW_TEST_DB_PASS\")"))
  )
  b <- local_env_project(file.path(root, "b"), "S3_BUCKET=b-bucket")

  config <- settings_read(file.path(a, "settings.yml"))
  # Values are available while settings resolve
  expect_identical(config$db_pass, "s3cret")
  expect_identical(config$expr_pass, "s3cret")
  # ...but are gone afterwards
  expect_identical(Sys.getenv("FW_PROJECT_TOKEN"), "")
  expect_identical(Sys.getenv("FW_CLOUD_URL"), "")
  expect_identical(Sys.getenv("FW_TEST_DB_PASS"), "")

  # Project b sees none of project a's values
  withr::local_dir(b)
  expect_null(framework:::.fw_project_token())
  expect_identical(framework:::.fw_cloud_server(scope = "project")$url, "https://framework.pub")
})

test_that("empty .env lines do not blank shell credentials", {
  withr::local_envvar(S3_ACCESS_KEY = "from-shell", S3_SECRET_KEY = "shell-secret", FW_TEST_SET = "shell")
  dir <- local_env_project(
    file.path(withr::local_tempdir(), "p"),
    c("S3_ACCESS_KEY=", "S3_SECRET_KEY=", "FW_TEST_SET=project"),
    list(default = list(project_type = "project", who = "env(\"FW_TEST_SET\")"))
  )
  config <- settings_read(file.path(dir, "settings.yml"))
  expect_identical(Sys.getenv("S3_ACCESS_KEY"), "from-shell")
  expect_identical(Sys.getenv("S3_SECRET_KEY"), "shell-secret")
  # A variable already set in the session wins over the .env value
  expect_identical(config$who, "shell")
  expect_identical(Sys.getenv("FW_TEST_SET"), "shell")
})

test_that(".fw_load_dotenv sets only unset, non-empty values", {
  withr::local_envvar(FW_TEST_KEEP = "shell", FW_TEST_NEW = NA, FW_TEST_EMPTY = "shell-empty")
  path <- withr::local_tempfile()
  writeLines(c("FW_TEST_KEEP=project", "FW_TEST_NEW=added", "FW_TEST_EMPTY="), path)
  framework:::.fw_load_dotenv(path)
  expect_identical(Sys.getenv("FW_TEST_KEEP"), "shell")
  expect_identical(Sys.getenv("FW_TEST_NEW"), "added")
  expect_identical(Sys.getenv("FW_TEST_EMPTY"), "shell-empty")
})

test_that("S3 credentials come from the shell before the project's .env", {
  withr::local_envvar(S3_ACCESS_KEY = "from-shell", S3_SECRET_KEY = NA, S3_BUCKET = NA,
                      AWS_SECRET_ACCESS_KEY = NA, AWS_ACCESS_KEY_ID = NA)
  dir <- local_env_project(
    file.path(withr::local_tempdir(), "p"),
    c("S3_ACCESS_KEY=", "S3_SECRET_KEY=project-secret", "S3_BUCKET=bucket-from-env")
  )
  withr::local_dir(dir)
  skip_if_not_installed("aws.s3")
  client <- framework:::.s3_client(list())
  expect_identical(client$access_key, "from-shell")
  expect_identical(client$secret_key, "project-secret")
  expect_identical(client$bucket, "bucket-from-env")
  expect_identical(Sys.getenv("S3_SECRET_KEY"), "")
})

test_that("the test suite cannot reach a real server", {
  skip_if_not_installed("httr2")
  expect_identical(Sys.getenv("FW_PROJECT_TOKEN"), "")
  expect_match(Sys.getenv("FW_CLOUD_URL"), "^http://127\\.0\\.0\\.1")
  expect_error(
    httr2::req_perform(httr2::request("https://framework.pub/api/v1/me")),
    "Tests may not contact"
  )
})
