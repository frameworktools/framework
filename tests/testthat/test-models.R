# load_model(), and save_model(public = TRUE) warning about data rows

local_model_project <- function(sensitive = TRUE, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  default <- list(project_type = "project")
  if (sensitive) default$security <- list(sensitive = TRUE)
  yaml::write_yaml(list(default = default), "settings.yml")
  dir
}

test_that("load_model() reads back what save_model() saved", {
  local_model_project()
  model <- lm(mpg ~ hp, data = mtcars, model = FALSE)
  suppressMessages(save_model(model, "fit"))
  expect_message(loaded <- load_model("fit"), "Loaded model from outputs/private/models/fit.rds")
  expect_equal(coef(loaded), coef(model))

  # The private folder first, then the public one; public = picks one
  suppressMessages(save_model(1, "both", public = TRUE))
  suppressMessages(save_model(2, "both", public = FALSE))
  expect_equal(suppressMessages(load_model("both")), 2)
  expect_equal(suppressMessages(load_model("both", public = TRUE)), 1)
  suppressMessages(save_model(3, "public_only", public = TRUE))
  expect_equal(suppressMessages(load_model("public_only")), 3)
  expect_error(load_model("public_only", public = FALSE), "No saved model named 'public_only'")
})

test_that("load_model() names what it looked for, and refuses Python's models", {
  local_model_project()
  expect_error(
    load_model("nope"),
    "No saved model named 'nope'. Looked for: outputs/private/models/nope.rds, outputs/public/models/nope.rds",
    fixed = TRUE
  )
  dir.create("outputs/public/models", recursive = TRUE)
  writeBin(as.raw(1:3), "outputs/public/models/py.pkl")
  expect_error(
    load_model("py"),
    "outputs/public/models/py.pkl is a model Python saved (.pkl), which R cannot read.",
    fixed = TRUE
  )
})

test_that("load_model() warns when the file changed since save_model() recorded it", {
  local_model_project(sensitive = FALSE)
  suppressMessages(save_model(list(a = 1), "m"))
  expect_no_warning(suppressMessages(load_model("m")))
  saveRDS(list(a = 2), "outputs/models/m.rds")
  expect_warning(
    expect_equal(suppressMessages(load_model("m")), list(a = 2)),
    "m.rds changed since save_model() recorded it.",
    fixed = TRUE
  )
})

test_that("save_model(public = TRUE) warns when the model holds data rows", {
  local_model_project()
  fit <- lm(mpg ~ hp, data = mtcars)
  expect_warning(
    suppressMessages(save_model(fit, "lm_public", public = TRUE)),
    paste0(
      "save_model(public = TRUE): 'lm_public' holds 32 data rows, which would be saved to the ",
      "public models folder with it. Refit with model = FALSE (and without y = TRUE or x = TRUE), ",
      "or save the estimates with save_table() instead."
    ),
    fixed = TRUE
  )
  expect_true(file.exists("outputs/public/models/lm_public.rds"))
  expect_warning(suppressMessages(save_model(mtcars, "frame", public = TRUE)),
                 "holds 32 data rows.*Remove them from the object first.")
  expect_warning(suppressMessages(save_model(glm(am ~ hp, data = mtcars, family = binomial), "g", public = TRUE)),
                 "'g' holds 32 data rows")
  # No rows kept, or saved privately: no warning
  expect_no_warning(suppressMessages(save_model(lm(mpg ~ hp, data = mtcars, model = FALSE), "lean", public = TRUE)))
  expect_no_warning(suppressMessages(save_model(fit, "private_fit")))
  expect_equal(framework:::.fw_model_data_rows(lm(mpg ~ hp, data = mtcars, model = FALSE, x = TRUE)), 32L)
  expect_equal(framework:::.fw_model_data_rows(list(estimates = 1:3)), 0L)
})
