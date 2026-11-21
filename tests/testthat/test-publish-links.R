# After a Framework Cloud publish, Framework prints the version, then Share:
# (the answer's embed_link) and Manage: (its artifact_url), and returns them
# as attributes of the URL. Cloud sends a null embed_link for an artifact
# that can't be embedded; older servers send neither link.

local_cloud_publish <- function(response, env = parent.frame()) {
  cleanup <- setup_isolated_config()
  withr::defer(cleanup(), envir = env)
  withr::local_envvar(FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA,
                      .local_envir = env)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE, .env = env)
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeLines("<html></html>", "report.html")
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) req,
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) response,
    .package = "httr2", .env = env
  )
}

publish_messages <- function(expr) {
  messages <- character()
  value <- withCallingHandlers(expr, message = function(m) {
    messages <<- c(messages, sub("\n$", "", conditionMessage(m)))
    invokeRestart("muffleMessage")
  })
  list(value = value, messages = messages)
}

test_that("a public artifact prints its version, Share, and Manage", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 3L, url = "http://localhost:8080/@ada/study/report", visibility = "public",
                           readable_url = "http://localhost:8080/@ada/study/report",
                           embed_link = "http://localhost:8080/go/az7h",
                           artifact_url = "http://localhost:8080/artifacts/123"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages, c("Published version 3.",
                                      "Share:  http://localhost:8080/go/az7h",
                                      "Manage: http://localhost:8080/artifacts/123"))
  expect_identical(as.character(result$value), "http://localhost:8080/@ada/study/report")
  expect_identical(attr(result$value, "embed_link"), "http://localhost:8080/go/az7h")
  expect_identical(attr(result$value, "artifact_url"), "http://localhost:8080/artifacts/123")
})

test_that("an unlisted artifact shares its own link", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/abc", visibility = "unlisted",
                           embed_link = "http://localhost:8080/d/abc",
                           artifact_url = "http://localhost:8080/artifacts/124"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages, c("Published version 1.",
                                      "Share:  http://localhost:8080/d/abc",
                                      "Manage: http://localhost:8080/artifacts/124"))
  expect_identical(attr(result$value, "embed_link"), "http://localhost:8080/d/abc")
})

test_that("a private artifact prints Manage only", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/abc", visibility = "private",
                           embed_link = NULL, artifact_url = "http://localhost:8080/artifacts/125"))
  result <- publish_messages(publish("report.html", visibility = "private"))
  expect_identical(result$messages, c("Published version 1.", "Manage: http://localhost:8080/artifacts/125"))
  expect_identical(as.character(result$value), "http://localhost:8080/d/abc")
  expect_null(attr(result$value, "embed_link"))
  expect_identical(attr(result$value, "artifact_url"), "http://localhost:8080/artifacts/125")
})

test_that("an unchanged snippet says so, then prints its links", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 2L, unchanged = TRUE, url = "http://localhost:8080/d/abc",
                           embed_link = "http://localhost:8080/d/abc",
                           artifact_url = "http://localhost:8080/artifacts/126"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages, c("Unchanged, still version 2.",
                                      "Share:  http://localhost:8080/d/abc",
                                      "Manage: http://localhost:8080/artifacts/126"))
})

test_that("an older server's answer keeps the URL on the first line", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/abc"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages, "Published version 1: http://localhost:8080/d/abc")
  expect_identical(result$value, "http://localhost:8080/d/abc")

  local_cloud_publish(list(version = 4L, unchanged = TRUE, url = "http://localhost:8080/d/abc"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages, "Unchanged, still version 4: http://localhost:8080/d/abc")
})

test_that("only a non-empty string counts as a link", {
  link <- framework:::.fw_answer_link
  expect_identical(link("https://framework.pub/go/abcd"), "https://framework.pub/go/abcd")
  expect_null(link(NULL))
  expect_null(link(""))
  expect_null(link(NA_character_))
  expect_null(link(list()))
  expect_null(link(c("a", "b")))
})

test_that("publish_dag() returns the links from publish()", {
  skip_if_not_installed("dagitty")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/dag",
                           embed_link = "http://localhost:8080/d/dag",
                           artifact_url = "http://localhost:8080/artifacts/127"))
  graph <- dagitty::dagitty("dag { x [exposure] y [outcome] x -> y }")
  result <- publish_messages(publish_dag(graph, slug = "xy"))
  expect_true("Share:  http://localhost:8080/d/dag" %in% result$messages)
  expect_identical(attr(result$value, "embed_link"), "http://localhost:8080/d/dag")
  expect_identical(attr(result$value, "artifact_url"), "http://localhost:8080/artifacts/127")
})
