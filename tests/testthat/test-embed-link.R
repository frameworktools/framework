# After a Framework Cloud publish, Framework prints the answer's embed_link
# and returns it in the URL's embed_link attribute. Older servers send none,
# and Cloud sends null for an artifact that can't be embedded.

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

test_that("the embed link is printed after the publish line and returned with the URL", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 3L, url = "http://localhost:8080/d/abc", visibility = "public",
                           readable_url = "http://localhost:8080/@ada/study/report",
                           embed_link = "http://localhost:8080/go/abcd"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages[1:2], c("Published version 3: http://localhost:8080/d/abc",
                                           "Embed: http://localhost:8080/go/abcd"))
  expect_identical(as.character(result$value), "http://localhost:8080/d/abc")
  expect_identical(attr(result$value, "embed_link"), "http://localhost:8080/go/abcd")
})

test_that("an unchanged snippet still prints its embed link", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 2L, unchanged = TRUE, url = "http://localhost:8080/d/abc",
                           embed_link = "http://localhost:8080/d/abc"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages[1:2], c("Unchanged, still version 2: http://localhost:8080/d/abc",
                                           "Embed: http://localhost:8080/d/abc"))
  expect_identical(attr(result$value, "embed_link"), "http://localhost:8080/d/abc")
})

test_that("a null embed link prints nothing and returns the plain URL", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/abc", embed_link = NULL))
  result <- publish_messages(publish("report.html", visibility = "private"))
  expect_false(any(startsWith(result$messages, "Embed:")))
  expect_identical(result$value, "http://localhost:8080/d/abc")
  expect_null(attr(result$value, "embed_link"))
})

test_that("an older server's answer without embed_link prints nothing extra", {
  skip_if_not_installed("httr2")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/abc"))
  result <- publish_messages(publish("report.html"))
  expect_identical(result$messages, "Published version 1: http://localhost:8080/d/abc")
  expect_identical(result$value, "http://localhost:8080/d/abc")
})

test_that("only a non-empty string counts as an embed link", {
  link <- framework:::.fw_embed_link
  expect_identical(link(list(embed_link = "https://framework.pub/go/abcd")), "https://framework.pub/go/abcd")
  expect_null(link(list(embed_link = NULL)))
  expect_null(link(list()))
  expect_null(link(list(embed_link = "")))
  expect_null(link(list(embed_link = NA_character_)))
  expect_null(link(list(embed_link = list())))
})

test_that("publish_dag() returns the embed link from publish()", {
  skip_if_not_installed("dagitty")
  local_cloud_publish(list(version = 1L, url = "http://localhost:8080/d/dag",
                           embed_link = "http://localhost:8080/d/dag"))
  graph <- dagitty::dagitty("dag { x [exposure] y [outcome] x -> y }")
  result <- publish_messages(publish_dag(graph, slug = "xy"))
  expect_true("Embed: http://localhost:8080/d/dag" %in% result$messages)
  expect_identical(attr(result$value, "embed_link"), "http://localhost:8080/d/dag")
})
