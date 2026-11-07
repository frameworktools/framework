# Outputs and publishing behavior shared with framework-py
# (docs/parity-proposals.md, "Outputs, publishing, and security").

local_outputs_project <- function(settings = list(project_type = "project"), env = parent.frame()) {
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

test_that("a name with / saves tables, figures, and models into subfolders", {
  skip_if_not_installed("ggplot2")
  local_outputs_project(list(project_type = "project", directories = list(
    outputs_tables = "outputs/tables", outputs_figures = "outputs/figures",
    outputs_models = "outputs/models"
  )))
  table <- suppressMessages(save_table(data.frame(x = 1), "meeting-2026-10-16/cohort"))
  expect_identical(table, file.path("outputs/tables", "meeting-2026-10-16/cohort.csv"))
  expect_true(file.exists("outputs/tables/meeting-2026-10-16/cohort.csv"))

  p <- ggplot2::ggplot(data.frame(x = 1:3, y = 1:3), ggplot2::aes(x, y)) + ggplot2::geom_point()
  suppressMessages(save_figure(p, "meeting/a/plot", width = 2, height = 2, dpi = 50))
  expect_true(file.exists("outputs/figures/meeting/a/plot.png"))

  suppressMessages(save_model(lm(mpg ~ hp, data = mtcars), "fits/mpg"))
  expect_true(file.exists("outputs/models/fits/mpg.rds"))

  expect_setequal(result_list()$name, c(
    "outputs/tables/meeting-2026-10-16/cohort.csv",
    "outputs/figures/meeting/a/plot.png",
    "outputs/models/fits/mpg.rds"
  ))
})

test_that("save_figure saves several formats, eps, and checks everything first", {
  skip_if_not_installed("ggplot2")
  local_outputs_project(list(project_type = "project", directories = list(outputs_figures = "outputs/figures")))
  p <- ggplot2::ggplot(data.frame(x = 1:3, y = 1:3), ggplot2::aes(x, y)) + ggplot2::geom_point()
  paths <- suppressMessages(save_figure(p, "journal/figure_2", format = c("pdf", "eps", "png", "pdf"),
                                        width = 2, height = 2, dpi = 20))
  folder <- file.path("outputs/figures", "journal")
  expect_identical(paths, file.path("outputs/figures", paste0("journal/figure_2.", c("pdf", "eps", "png"))))
  expect_identical(readChar(paths[2], 10, useBytes = TRUE), "%!PS-Adobe")
  expect_setequal(result_list(type = "figure")$name,
                  paste0("outputs/figures/journal/figure_2.", c("pdf", "eps", "png")))

  # One format gives one path
  one <- suppressMessages(save_figure(p, "single", format = "png", width = 2, height = 2, dpi = 20))
  expect_identical(one, file.path("outputs/figures", "single.png"))

  # Nothing is written when one file exists or one format is unknown
  expect_error(save_figure(p, "journal/figure_2", format = c("svg", "png"), overwrite = FALSE),
               "File already exists")
  expect_false(file.exists(file.path(folder, "figure_2.svg")))
  expect_error(save_figure(p, "journal/other", format = c("png", "gif")), "format must be one of")
  expect_false(file.exists(file.path(folder, "other.png")))
})

test_that("save_figure writes eps and emf from recorded plots", {
  local_outputs_project(list(project_type = "project", directories = list(outputs_figures = "outputs/figures")))
  grDevices::pdf(NULL)
  grDevices::dev.control("enable")
  plot(1:3)
  recorded <- grDevices::recordPlot()
  grDevices::dev.off()
  path <- suppressMessages(save_figure(recorded, "base", format = "eps", width = 2, height = 2))
  expect_identical(readChar(path, 10, useBytes = TRUE), "%!PS-Adobe")
  if (requireNamespace("devEMF", quietly = TRUE)) {
    emf <- suppressMessages(save_figure(recorded, "base", format = "emf", width = 2, height = 2))
    expect_gt(file.size(emf), 0)
  }
})

test_that("save_figure emf without devEMF says to save svg or pdf and convert", {
  local_outputs_project()
  local_mocked_bindings(.fw_emf_available = function() FALSE)
  expect_error(framework:::.fw_figure_formats(c("png", "emf")), "save svg or pdf and convert")
})

test_that("save_figure writes emf from a ggplot with devEMF", {
  skip_if_not_installed("devEMF")
  skip_if_not_installed("ggplot2")
  local_outputs_project(list(project_type = "project", directories = list(outputs_figures = "outputs/figures")))
  p <- ggplot2::ggplot(data.frame(x = 1:3, y = 1:3), ggplot2::aes(x, y)) + ggplot2::geom_point()
  path <- suppressMessages(save_figure(p, "deck", format = "emf", width = 2, height = 2))
  expect_identical(path, file.path("outputs/figures", "deck.emf"))
  expect_gt(file.size(path), 0)
})
