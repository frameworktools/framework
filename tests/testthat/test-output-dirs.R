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

test_that("security: sensitive: true splits even when outputs_<kind> is configured, as in 2.0.0", {
  local_settings(list(project_type = "project", security = list(sensitive = TRUE),
                      directories = list(outputs_tables = "results/tables")))
  expect_identical(framework:::.output_dir("tables"), "outputs/private/tables")
  expect_identical(framework:::.output_dir("tables", public = TRUE), "outputs/public/tables")
})

test_that("save_notebook() renders a Jupyter notebook from its saved outputs", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("quarto")), "quarto not installed")
  local_settings(list(project_type = "project", directories = list(outputs_notebooks = "outputs/notebooks")))
  empty <- structure(list(), names = character())
  nb <- list(
    cells = list(list(cell_type = "code", execution_count = 1, metadata = empty,
                      outputs = list(list(output_type = "stream", name = "stdout", text = list("[1] 42\n"))),
                      source = list("21 * 2"))),
    metadata = list(kernelspec = list(name = "ir", display_name = "R", language = "R")),
    nbformat = 4, nbformat_minor = 5
  )
  dir.create("notebooks")
  jsonlite::write_json(nb, "notebooks/answer.ipynb", auto_unbox = TRUE, null = "null")

  path <- suppressMessages(save_notebook("notebooks/answer.ipynb"))
  expect_identical(path, file.path("outputs", "notebooks", "answer.html"))
  expect_true(any(grepl("[1] 42", readLines(path, warn = FALSE), fixed = TRUE)))
})

test_that("a configured outputs_<kind> wins when the project counts as sensitive by layout or type", {
  # An inputs_private_* folder makes the project sensitive; the tables and
  # models folders it names still get the outputs
  local_settings(list(project_type = "project", directories = list(
    inputs_private_raw = "inputs/private/raw",
    outputs_tables = "results/tables", outputs_models = "results/models"
  )))
  expect_identical(framework:::.output_dir("tables"), "results/tables")
  expect_identical(framework:::.output_dir("models", public = TRUE), "results/models")
  # A kind without its own folder splits
  expect_identical(framework:::.output_dir("figures"), "outputs/private/figures")
  path <- suppressMessages(save_table(data.frame(a = 1), "t"))
  expect_identical(path, file.path("results", "tables", "t.csv"))
  expect_true(file.exists("results/tables/t.csv"))
  dir.create("results/models", recursive = TRUE)
  saveRDS(1, "results/models/m.rds")
  expect_equal(suppressMessages(load_model("m")), 1)
})

test_that("project_sensitive without a security block keeps outputs_<kind>", {
  local_settings(list(project_type = "project_sensitive",
                      directories = list(outputs_tables = "results/tables")))
  expect_identical(framework:::.output_dir("tables"), "results/tables")
  expect_identical(framework:::.output_dir("models"), "outputs/private/models")
})

test_that("output folders resolve from the project root, not the working directory", {
  root <- local_settings(list(project_type = "project",
                              directories = list(outputs_tables = "outputs/tables")))
  dir.create("notebooks")
  withr::local_dir("notebooks")
  table <- suppressMessages(save_table(data.frame(a = 1), "t"))
  model <- suppressMessages(save_model(lm(mpg ~ hp, mtcars, model = FALSE), "m"))
  expect_true(file.exists(file.path(root, "outputs", "tables", "t.csv")))
  expect_true(file.exists(file.path(root, "outputs", "models", "m.rds")))
  expect_false(dir.exists(file.path(root, "notebooks", "outputs")))
  expect_true(.fw_same_file(table, file.path(root, "outputs", "tables", "t.csv")))
  expect_true(.fw_same_file(model, file.path(root, "outputs", "models", "m.rds")))
  expect_s3_class(suppressMessages(load_model("m")), "lm")
})
