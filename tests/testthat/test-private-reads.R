# data_read() remembers private reads; public saves in a sensitive project warn

local_private_project <- function(sensitive = TRUE, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  # The session's private reads start empty and are cleared afterwards
  old <- framework:::.framework_env$private_reads
  assign("private_reads", NULL, envir = framework:::.framework_env)
  withr::defer(assign("private_reads", old, envir = framework:::.framework_env), envir = env)
  default <- list(
    project_type = "project",
    data = list(inputs = list(
      private = list(raw = list(visits = "inputs/private/raw/visits.csv")),
      flagged = list(path = "inputs/raw/flagged.csv", private = TRUE),
      open = "inputs/raw/open.csv"
    ))
  )
  if (sensitive) default$security <- list(sensitive = TRUE)
  yaml::write_yaml(list(default = default), "settings.yml")
  for (f in c("inputs/private/raw/visits.csv", "inputs/raw/flagged.csv", "inputs/raw/open.csv",
              "inputs/private/raw/ids.csv", "inputs/confidential_2024/a.csv", "inputs/b.csv",
              "data/Sensitive/c.csv")) {
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    writeLines(c("x", "1"), f)
  }
  dir
}

read_quietly <- function(name) suppressMessages(suppressWarnings(data_read(name)))
reads <- function() framework:::.framework_env$private_reads

test_that("data_read() remembers private reads once each, as the caller named them", {
  local_private_project()
  read_quietly("inputs.open")
  expect_null(reads())
  read_quietly("inputs.private.raw.visits")
  read_quietly("inputs/private/raw/ids.csv")
  read_quietly("inputs.flagged")
  read_quietly("inputs.private.raw.visits")
  read_quietly("inputs/b.csv")
  read_quietly("inputs/confidential_2024/a.csv")
  read_quietly("data/Sensitive/c.csv")
  expect_equal(reads(), c(
    "inputs.private.raw.visits", "inputs/private/raw/ids.csv", "inputs.flagged",
    "inputs/confidential_2024/a.csv", "data/Sensitive/c.csv"
  ))
})

test_that("files outside the project are private by the private-path rule", {
  local_private_project()
  outside <- withr::local_tempdir()
  dir.create(file.path(outside, "Share_Private"))
  dir.create(file.path(outside, "Private_share"))
  writeLines(c("x", "1"), file.path(outside, "Share_Private", "d.csv"))
  writeLines(c("x", "1"), file.path(outside, "Private_share", "f.csv"))
  writeLines(c("x", "1"), file.path(outside, "e.csv"))
  read_quietly(file.path(outside, "e.csv"))
  # Outside the project, the private-path rule: a folder named private or
  # ending in _private
  read_quietly(file.path(outside, "Private_share", "f.csv"))
  expect_null(reads())
  read_quietly(file.path(outside, "Share_Private", "d.csv"))
  expect_equal(reads(), file.path(outside, "Share_Private", "d.csv"))
})

test_that("public saves in a sensitive project warn after private reads", {
  local_private_project()
  expect_no_warning(suppressMessages(save_table(data.frame(x = 1), "before", public = TRUE)))
  for (name in c("inputs.private.raw.visits", "inputs/private/raw/ids.csv", "inputs.flagged",
                 "inputs/confidential_2024/a.csv", "data/Sensitive/c.csv")) {
    read_quietly(name)
  }
  expect_warning(
    suppressMessages(save_table(data.frame(x = 1), "summary", public = TRUE)),
    paste0(
      "Saved summary.csv as public, and this session read private data (inputs.private.raw.visits, ",
      "inputs/private/raw/ids.csv, inputs.flagged, and 2 more). Check that it holds only aggregated ",
      "or de-identified results before sharing it."
    ),
    fixed = TRUE
  )
  expect_true(file.exists("outputs/public/tables/summary.csv"))
  expect_no_warning(suppressMessages(save_table(data.frame(x = 1), "summary_private")))
  expect_warning(suppressMessages(save_model(list(b = 1), "est", public = TRUE)),
                 "Saved est.rds as public, and this session read private data", fixed = TRUE)
  expect_no_warning(suppressMessages(save_model(list(b = 1), "est_private")))

  skip_if_not_installed("ggplot2")
  plot <- ggplot2::ggplot(data.frame(x = 1:2, y = 1:2), ggplot2::aes(x, y)) + ggplot2::geom_point()
  expect_warning(suppressMessages(save_figure(plot, "fig", public = TRUE, width = 2, height = 2, dpi = 30)),
                 "Saved fig.png as public")
})

test_that("a public model with data rows gives one warning naming the private reads", {
  local_private_project()
  read_quietly("inputs.flagged")
  warnings <- testthat::capture_warnings(
    suppressMessages(save_model(lm(mpg ~ hp, data = mtcars), "fit", public = TRUE))
  )
  expect_length(warnings, 1)
  expect_match(warnings, "'fit' holds 32 data rows", fixed = TRUE)
  expect_match(warnings, "This session also read private data (inputs.flagged).", fixed = TRUE)
})

test_that("other projects never warn", {
  local_private_project(sensitive = FALSE)
  read_quietly("inputs.private.raw.visits")
  expect_equal(reads(), "inputs.private.raw.visits")
  expect_no_warning(suppressMessages(save_table(data.frame(x = 1), "summary", public = TRUE)))
  warnings <- testthat::capture_warnings(
    suppressMessages(save_model(lm(mpg ~ hp, data = mtcars), "fit", public = TRUE))
  )
  expect_length(warnings, 1)
  expect_false(grepl("private data", warnings))
})

test_that("project_sensitive counts as sensitive without a security block", {
  sensitive <- framework:::.fw_settings_sensitive
  expect_true(sensitive(list(project_type = "project_sensitive")))
  expect_true(sensitive(list(project_type = "project_sensitive", security = list())))
  # The type is authoritative, even over an explicit false
  expect_true(sensitive(list(project_type = "project_sensitive", security = list(sensitive = FALSE))))
  expect_true(sensitive(list(project_type = "project", security = list(sensitive = TRUE))))
  expect_false(sensitive(list(project_type = "project", security = list(sensitive = FALSE))))
  expect_false(sensitive(list(project_type = "project")))
  # Without a security block, the privacy-sensitive layout counts
  layout <- list(project_type = "project", directories = list(inputs_private_raw = "inputs/private/raw"))
  expect_true(sensitive(layout))
  layout$security <- list(sensitive = FALSE)
  expect_false(sensitive(layout))
  expect_false(sensitive(NULL))
})

test_that("an old project_sensitive project turns the sensitive guards on", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  yaml::write_yaml(list(default = list(
    project_type = "project_sensitive",
    directories = list(inputs_private_raw = "inputs/private/raw")
  )), "settings.yml")
  expect_true(framework:::.fw_project_is_sensitive())
  expect_match(framework:::.fw_sensitive_mismatch(settings_read()), "no security: block")
  expect_match(framework:::.fw_sensitive_reasons("this table"), "sensitive data")
  expect_warning(
    suppressMessages(bootstrap(".", interactive = FALSE, packages = FALSE)),
    "project_sensitive"
  )
})
