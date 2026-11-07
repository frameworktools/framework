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
