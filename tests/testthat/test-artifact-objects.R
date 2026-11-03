test_that("structured tables retain types, missing values, all rows, and row names", {
  stage <- withr::local_tempdir()
  data <- data.frame(estimate = c(1.5, NA_real_), included = c(TRUE, NA),
                     count = c(2L, NA_integer_), label = c("<estimate>", NA_character_),
                     date = as.Date(c("2026-01-02", NA)),
                     time = as.POSIXct(c("2026-01-02 03:04:05", NA), tz = "UTC"))
  rownames(data) <- c("row-a", "row-b")
  path <- framework:::.fw_artifact_file(data, stage, cloud = TRUE)
  document <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_identical(basename(path), "table.json")
  expect_identical(document$schema, "framework.artifact/v1")
  expect_identical(document$kind, "table")
  expect_identical(document$source$class, list("data.frame"))
  table <- document$tables[[1]]
  expect_identical(table$role, "data")
  expect_identical(vapply(table$columns, `[[`, character(1), "name")[1], "row")
  expect_identical(vapply(table$columns, `[[`, character(1), "type"),
                   c("string", "number", "boolean", "number", "string", "date", "datetime"))
  expect_equal(table$rows[[1]], list("row-a", 1.5, TRUE, 2L, "<estimate>", "2026-01-02", "2026-01-02T03:04:05.000000Z"))
  expect_identical(table$rows[[2]], c(list("row-b"), rep(list(NULL), 6)))
  expect_identical(table$row_count, 2L)
  single <- framework:::.fw_artifact_structured(data.frame(x = 1))
  parsed <- jsonlite::fromJSON(jsonlite::toJSON(single, auto_unbox = TRUE), simplifyVector = FALSE)
  expect_identical(parsed$tables[[1]]$rows, list(list(1L)))
  expect_identical(parsed$tables[[1]]$columns[[1]]$name, "x")
})

test_that("lm and glm export coefficient statistics without observations", {
  stage <- withr::local_tempdir()
  for (model in list(stats::lm(mpg ~ wt, data = mtcars),
                     stats::glm(am ~ wt, data = mtcars, family = stats::binomial()))) {
    path <- framework:::.fw_artifact_file(model, stage, cloud = TRUE)
    document <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    expect_identical(basename(path), "model.json")
    expect_identical(document$kind, "model")
    expect_identical(document$tables[[1]]$row_count, 2L)
    row <- document$tables[[1]]$rows[[2]]
    expect_equal(row[[2]], unname(stats::coef(model)[[2]]))
    expect_equal(row[[5]], unname(summary(model)$coefficients[2, 4]))
    metrics <- setNames(lapply(document$metrics, `[[`, "value"), vapply(document$metrics, `[[`, character(1), "name"))
    expect_equal(metrics$nobs, 32L)
    expect_match(document$formula, "~ wt", fixed = TRUE)
    expect_false(any(c("residuals", "data", "fitted.values") %in% names(document)))
    expect_true(all(names(document$model) %in% c("type", "family", "link", "response", "exponentiate")))
  }
})

test_that("ggplot objects export portable figures", {
  skip_if_not_installed("ggplot2")
  plot <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  path <- framework:::.fw_artifact_file(plot, withr::local_tempdir(), cloud = TRUE)
  if (requireNamespace("svglite", quietly = TRUE)) {
    expect_identical(basename(path), "figure.svg")
    expect_match(paste(readLines(path, warn = FALSE), collapse = "\n"), "<svg")
  } else {
    expect_identical(basename(path), "figure.png")
    expect_identical(readBin(path, "raw", n = 4L), as.raw(c(137, 80, 78, 71)))
  }
})

test_that("gt tables export HTML when the optional package is present", {
  skip_if_not_installed("gt")
  path <- framework:::.fw_artifact_file(gt::gt(head(mtcars)), withr::local_tempdir(), cloud = TRUE)
  expect_match(paste(readLines(path, warn = FALSE), collapse = "\n"), "<table")
})

test_that("gtsummary tables export HTML when optional packages are present", {
  skip_if_not_installed("gtsummary")
  skip_if_not_installed("gt")
  object <- gtsummary::tbl_summary(mtcars[c("mpg", "wt")])
  path <- framework:::.fw_artifact_file(object, withr::local_tempdir(), cloud = TRUE)
  expect_match(paste(readLines(path, warn = FALSE), collapse = "\n"), "<table")
})

test_that("flextable objects export HTML when the optional package is present", {
  skip_if_not_installed("flextable")
  path <- framework:::.fw_artifact_file(flextable::flextable(head(mtcars)), withr::local_tempdir(), cloud = TRUE)
  expect_match(paste(readLines(path, warn = FALSE), collapse = "\n"), "<table")
})


test_that("integer64 identifiers export exactly as text", {
  skip_if_not_installed("bit64")
  values <- bit64::as.integer64(c("9223372036854775807", NA_character_))
  document <- framework:::.fw_artifact_structured(data.frame(id = values))
  parsed <- jsonlite::fromJSON(jsonlite::toJSON(document, auto_unbox = TRUE, null = "null"), simplifyVector = FALSE)
  expect_identical(parsed$tables[[1]]$columns[[1]]$type, "string")
  expect_identical(parsed$tables[[1]]$rows, list(list("9223372036854775807"), list(NULL)))
})


test_that("model intervals follow the summary t or z reference distribution", {
  gaussian <- stats::glm(mpg ~ wt, data = mtcars, family = stats::gaussian())
  models <- list(stats::lm(mpg ~ wt, data = mtcars), gaussian,
                 stats::glm(mpg ~ wt, data = mtcars, family = stats::quasipoisson()),
                 stats::glm(am ~ wt, data = mtcars, family = stats::binomial()))
  for (model in models) {
    document <- framework:::.fw_artifact_structured(model)
    coefficients <- summary(model)$coefficients
    use_t <- identical(colnames(coefficients)[3], "t value")
    critical <- if (use_t) stats::qt(0.975, stats::df.residual(model)) else stats::qnorm(0.975)
    row <- document$tables[[1]]$rows[[2]]
    expect_equal(row[[6]], unname(coefficients[2, 1] - critical * coefficients[2, 2]))
    expect_equal(row[[7]], unname(coefficients[2, 1] + critical * coefficients[2, 2]))
    metrics <- setNames(lapply(document$metrics, `[[`, "value"), vapply(document$metrics, `[[`, character(1), "name"))
    expect_identical(metrics$confidence_level, 0.95)
    expect_identical(metrics$interval_method, if (use_t) "wald-t" else "wald-normal")
    expect_false(any(c("residuals", "data", "fitted.values") %in% names(document)))
    expect_true(all(names(document$model) %in% c("type", "family", "link", "response", "exponentiate")))
  }
  expect_identical(colnames(summary(gaussian)$coefficients)[3], "t value")
})
