# Output folders follow the settings (sensitive data and the directories in
# settings.yml), not the project type

local_settings <- function(default, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  yaml::write_yaml(list(default = default), "settings.yml")
  dir
}

test_that("one folder per kind without private and public folders", {
  local_settings(list(project_type = "lab_pipeline",
                      directories = list(outputs_tables = "results/tables")))
  expect_identical(framework:::.output_dir("tables"), "results/tables")
  expect_identical(framework:::.output_dir("tables", public = TRUE), "results/tables")
  expect_identical(framework:::.output_dir("figures"), "outputs/figures")
})

test_that("private and public folders split by public", {
  local_settings(list(project_type = "project", directories = list(
    outputs_private_tables = "out/private/tables", outputs_public_tables = "out/public/tables"
  )))
  expect_identical(framework:::.output_dir("tables"), "out/private/tables")
  expect_identical(framework:::.output_dir("tables", public = TRUE), "out/public/tables")
})

test_that("sensitive data on splits even without the folders listed", {
  local_settings(list(project_type = "lab_pipeline", security = list(sensitive = TRUE)))
  expect_identical(framework:::.output_dir("models"), "outputs/private/models")
  expect_identical(framework:::.output_dir("models", public = TRUE), "outputs/public/models")
})
