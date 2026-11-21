# Display settings: publish(display = ) sends Framework Cloud a JSON object
# of the embed settings to change. Cloud's artifact display settings
# (framework-cloud docs/plans/2026-11-21-artifact-display.md) list the keys.

test_that("display takes a named list or a named logical vector", {
  settings <- framework:::.fw_display_settings
  expect_null(settings(NULL))
  expect_null(settings(list()))
  expect_identical(settings(list(analysis = FALSE, code = FALSE)), list(analysis = FALSE, code = FALSE))
  expect_identical(settings(c(legend = FALSE, title = TRUE)), list(legend = FALSE, title = TRUE))
  expect_identical(settings(list(interactive = TRUE)), list(interactive = TRUE))
})

test_that("every Cloud setting is accepted", {
  keys <- c("title", "description", "author", "details", "variable_tips", "column_summaries",
            "output", "links", "legend", "analysis", "dagitty", "code", "interactive")
  all_off <- stats::setNames(rep(FALSE, length(keys)), keys)
  expect_identical(names(framework:::.fw_display_settings(all_off)), keys)
})

test_that("bad display settings stop with the list of settings", {
  settings <- framework:::.fw_display_settings
  expect_error(settings(list(legnd = FALSE)), "Unknown display setting: legnd. Settings: title, description")
  expect_error(settings(c(a = FALSE, b = TRUE)), "Unknown display settings: a, b.")
  expect_error(settings(list(FALSE)), "Name every display setting")
  expect_error(settings(c(analysis = FALSE, FALSE)), "Name every display setting")
  expect_error(settings(list(analysis = "no")), "take TRUE or FALSE: analysis.", fixed = TRUE)
  expect_error(settings(list(analysis = NA)), "take TRUE or FALSE: analysis.", fixed = TRUE)
  expect_error(settings(list(analysis = c(TRUE, FALSE))), "take TRUE or FALSE: analysis.", fixed = TRUE)
  expect_error(settings(list(analysis = 0)), "take TRUE or FALSE: analysis.", fixed = TRUE)
  expect_error(settings(c(analysis = FALSE, analysis = TRUE)), "named twice: analysis")
  expect_error(settings("analysis"), "named list or a named logical vector")
  expect_error(settings(data.frame(analysis = FALSE)), "named list or a named logical vector")
})

test_that("the display field is a JSON object of booleans", {
  expect_identical(framework:::.fw_display_json(list(analysis = FALSE, legend = TRUE)),
                   '{"analysis":false,"legend":true}')
})

test_that("display is sent as a JSON form field only when given", {
  skip_if_not_installed("httr2")
  cleanup <- setup_isolated_config()
  withr::defer(cleanup())
  withr::local_envvar(FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA, FW_PROJECT_TOKEN = NA, FW_TOKEN_FILE = NA)
  testthat::local_mocked_bindings(.fw_keychain_available = function() FALSE)
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines(c("FW_PROJECT_TOKEN=fw_project", "FW_CLOUD_URL=http://localhost:8080"), ".env")
  writeLines("<html></html>", "report.html")

  sent <- list()
  testthat::local_mocked_bindings(
    req_body_multipart = function(req, ...) {
      sent[[length(sent) + 1L]] <<- rlang::list2(...)
      req
    },
    req_perform = function(req, ...) req,
    resp_body_json = function(resp, ...) list(version = 1L, url = "http://localhost:8080/d/abc"),
    .package = "httr2"
  )
  expect_message(publish("report.html", display = c(title = FALSE)), "Published version 1")
  expect_identical(sent[[1]]$display, '{"title":false}')

  expect_message(publish("report.html"), "Published version 1")
  expect_null(sent[[2]]$display)
  expect_false("display" %in% names(sent[[2]]))

  # A table's settings travel with its kind
  expect_message(publish(data.frame(x = 1:3), slug = "counts", display = list(column_summaries = FALSE)),
                 "Published version 1")
  expect_identical(sent[[3]]$kind, "table")
  expect_identical(sent[[3]]$display, '{"column_summaries":false}')

  # A bad setting stops before anything uploads
  expect_error(publish("report.html", display = list(legnd = FALSE)), "Unknown display setting: legnd")
  expect_length(sent, 3L)
})

test_that("publish_dag() sends display with the DAG", {
  skip_if_not_installed("dagitty")
  published <- NULL
  testthat::local_mocked_bindings(publish = function(source, ...) {
    published <<- list(source = source, options = list(...))
    "https://cloud.example.org/d/abc"
  })
  graph <- dagitty::dagitty("dag { x [exposure] y [outcome] x -> y }")
  publish_dag(graph, display = list(analysis = FALSE, legend = FALSE))
  expect_identical(published$options$display, list(analysis = FALSE, legend = FALSE))
  expect_s3_class(published$source, "framework_dag")
  expect_error(publish_dag(graph, display = list(legend = "off")), "take TRUE or FALSE: legend")
})

test_that("snippets pass display through, and fw_snippet() checks it before running the block", {
  skip_if_not_installed("evaluate")
  published <- NULL
  testthat::local_mocked_bindings(publish = function(source, ...) {
    published <<- list(...)
    "https://cloud.example.org/d/abc"
  })
  document <- framework:::.fw_snippet_document(list(list(type = "code", text = "1 + 1")),
                                               list(language = "r", label = "sum"))
  framework:::.fw_snippet_publish(document, "sum", display = list(links = FALSE))
  expect_identical(published$display, list(links = FALSE))

  ran <- FALSE
  expect_error(fw_snippet("sum", { ran <- TRUE }, display = list(nope = FALSE)), "Unknown display setting: nope")
  expect_false(ran)
  expect_error(publish_snippet("sum", display = list(output = "x")), "take TRUE or FALSE: output")
})

test_that("destinations other than Framework Cloud ignore display, with a message", {
  expect_message(framework:::.fw_display_ignored(list(legend = FALSE), "GitHub Pages"),
                 "display applies to Framework Cloud only; ignored for GitHub Pages.", fixed = TRUE)
  expect_silent(framework:::.fw_display_ignored(NULL, "GitHub Pages"))

  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(project_type = "project")), "settings.yml")
  writeLines("<html></html>", "report.html")
  delivered <- list()
  testthat::local_mocked_bindings(.fw_publish_bundle = function(source, destination, ...) {
    delivered[[length(delivered) + 1L]] <<- destination$driver
    "https://ada.github.io/study/report/"
  })
  expect_message(url <- publish("report.html", to = "github", display = list(title = FALSE)),
                 "display applies to Framework Cloud only; ignored for GitHub Pages.", fixed = TRUE)
  expect_identical(url, "https://ada.github.io/study/report/")
  expect_identical(delivered, list("github"))
})
