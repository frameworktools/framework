local_cloned_project <- function(settings = list(), env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  base <- list(
    project_type = "project",
    directories = list(
      inputs_raw = "inputs/raw",
      outputs_private = "outputs/private",
      shared = "/Volumes/shared/study"
    ),
    connections = list(databases = list(warehouse = list(
      driver = "postgres", host = 'env("DB_HOST")', password = 'env("DB_PASSWORD")'
    ))),
    publish = list(destinations = list(site = list(driver = "s3", token = "${API_TOKEN}")))
  )
  yaml::write_yaml(list(default = utils::modifyList(base, settings)), file.path(dir, "settings.yml"))
  writeLines(c("# Database", "DB_HOST=localhost", "DB_PASSWORD=", "export API_TOKEN=", "UNUSED_EXAMPLE="),
             file.path(dir, ".env.example"))
  writeLines(c("!.env"), file.path(dir, ".gitignore"))
  dir
}

test_that("bootstrap() prepares a cloned project without prompting", {
  dir <- local_cloned_project()

  result <- suppressMessages(bootstrap(dir, interactive = FALSE, packages = FALSE))

  expect_true(file.exists(file.path(dir, ".env")))
  expect_identical(utils::tail(readLines(file.path(dir, ".gitignore")), 1), ".env")
  expect_true(dir.exists(file.path(dir, "inputs", "raw")))
  # Output folders are made on first use, as in a new project
  expect_false(dir.exists(file.path(dir, "outputs")))
  expect_false(dir.exists(file.path(dir, "Volumes")))
  expect_true(file.exists(file.path(dir, "framework.db")))
  expect_true("Created .env from .env.example" %in% result$done)
  expect_identical(result$todo, "Fill in .env: DB_PASSWORD, API_TOKEN")

  # Safe to repeat: nothing new to create, .env kept as is
  writeLines(c("DB_HOST=db", "DB_PASSWORD=x", "API_TOKEN=t", "UNUSED_EXAMPLE="), file.path(dir, ".env"))
  again <- suppressMessages(bootstrap(dir, interactive = FALSE, packages = FALSE))
  expect_identical(again$done, "Updated framework.db")
  expect_identical(again$todo, character())
  expect_identical(readLines(file.path(dir, ".env")), c("DB_HOST=db", "DB_PASSWORD=x", "API_TOKEN=t", "UNUSED_EXAMPLE="))
})

test_that("bootstrap() fills empty .env values when interactive", {
  dir <- local_cloned_project()
  answers <- c("s3cret value", "")
  testthat::local_mocked_bindings(readline = function(prompt = "") {
    out <- answers[1]
    answers <<- answers[-1]
    out
  }, .package = "base")
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (identical(package, "askpass")) FALSE else base::requireNamespace(package, ...)
  }, .package = "base")

  result <- suppressMessages(bootstrap(dir, interactive = TRUE, packages = FALSE))
  env <- readLines(file.path(dir, ".env"))
  expect_true("DB_PASSWORD=\"s3cret value\"" %in% env)
  expect_true("export API_TOKEN=" %in% env)
  expect_identical(result$todo, "Fill in .env: API_TOKEN")
})

test_that("bootstrap() refuses other languages, bad specs, and non-projects", {
  expect_error(bootstrap(withr::local_tempdir(), interactive = FALSE), "Is this a Framework project")

  py <- local_cloned_project(list(language = "python"))
  expect_error(bootstrap(py, interactive = FALSE), "python project")
  expect_false(file.exists(file.path(py, ".env")))

  bad <- local_cloned_project()
  dir.create(file.path(bad, ".framework"))
  writeLines("{not json", file.path(bad, ".framework", "spec.json"))
  expect_error(bootstrap(bad, interactive = FALSE), "not valid JSON")
})

test_that("bootstrap() fails when renv.lock needs renv and renv is missing", {
  dir <- local_cloned_project()
  writeLines("{}", file.path(dir, "renv.lock"))
  testthat::local_mocked_bindings(requireNamespace = function(package, ...) {
    if (identical(package, "renv")) FALSE else base::requireNamespace(package, ...)
  }, .package = "base")
  expect_error(suppressMessages(bootstrap(dir, interactive = FALSE)), "renv is not installed")
})

test_that("bootstrap() installs enabled hooks in a git checkout", {
  skip_if(!nzchar(Sys.which("git")), "git not installed")
  dir <- local_cloned_project(list(git = list(hooks = list(data_security = TRUE))))
  system2("git", c("-C", dir, "init", "-q"), stdout = FALSE, stderr = FALSE)
  result <- suppressMessages(bootstrap(dir, interactive = FALSE, packages = FALSE))
  expect_true("Installed git hooks" %in% result$done)
  expect_true(.is_framework_hook(file.path(dir, ".git", "hooks", "pre-commit")))
})

test_that("bootstrap() does not make folders out of file entries", {
  dir <- local_cloned_project(list(directories = list(presentation = "presentation.qmd")))
  suppressMessages(bootstrap(dir, interactive = FALSE, packages = FALSE))
  expect_false(dir.exists(file.path(dir, "presentation.qmd")))
})

test_that("bootstrap() lists only the .env variables the settings use", {
  dir <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(project_type = "project", connections = "settings/connections.yml")),
                   file.path(dir, "settings.yml"))
  dir.create(file.path(dir, "settings"))
  writeLines(c("connections:", "  databases:", "    pg:", "      driver: postgres",
               "      user: !expr Sys.getenv('PG_USER')", "      # password: env(\"COMMENTED_OUT\")"),
             file.path(dir, "settings", "connections.yml"))
  writeLines(c("PG_USER=", "COMMENTED_OUT=", "S3_BUCKET="), file.path(dir, ".env"))
  expect_setequal(framework:::.bootstrap_env_references(dir), "PG_USER")
  result <- suppressMessages(bootstrap(dir, interactive = FALSE, packages = FALSE))
  expect_identical(result$todo, "Fill in .env: PG_USER")
})
