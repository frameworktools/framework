# App projects (Shiny, Plumber) have their own entry point and never call
# scaffold(). Framework manages their packages, skills, and settings only.

app_layers <- function(type, entry) {
  list(
    list(kind = "base", key = type, version = 1, layer = list(
      type = type,
      directories = list(functions = "R", www = "www", data = "data", tests = "tests"),
      files = setNames(list(list(content = "library(shiny)\n")), entry)
    )),
    list(kind = "facet", key = "workflow-scripts", version = 1, layer = list(
      scaffold = list(workflow = "scripts", notebook_format = "script")
    )),
    list(kind = "facet", key = "claude-code", version = 1, layer = list(
      ai = list(enabled = TRUE, assistants = list(claude = TRUE))
    )),
    list(kind = "blueprint", key = type, layer = list(
      packages = list(default_packages = list(
        shiny = list(source = "cran", auto_attach = FALSE),
        bslib = list(source = "cran", auto_attach = FALSE)
      )),
      skills = list(`framework-packages` = list(package = TRUE))
    )),
    list(kind = "project", key = "demo", layer = list(tools = list(quarto = FALSE)))
  )
}

create_app <- function(type, entry) {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(dir, ".framework"))
  layers_file <- file.path(dir, ".framework", "layers.json")
  jsonlite::write_json(list(
    spec_version = 1, name = "Demo App",
    author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""),
    layers = app_layers(type, entry)
  ), layers_file, auto_unbox = TRUE, null = "null")
  suppressMessages(project_create_from_layers(layers_file, path = dir))
  dir
}

test_that("a Shiny app gets no scaffold() setup, Quarto settings, or tidyverse", {
  dir <- create_app("shiny", "app.R")

  expect_true(file.exists(file.path(dir, "app.R")))
  expect_false(file.exists(file.path(dir, "scaffold.R")))
  expect_false(file.exists(file.path(dir, "_quarto.yml")))

  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))$default
  expect_false("quarto" %in% names(settings))
  expect_false("connections" %in% names(settings))
  workspace <- jsonlite::read_json(file.path(dir, "demo-app.code-workspace"))
  expect_null(workspace$settings$files.associations)
  expect_setequal(names(settings$scaffold), c("notebook_format", "workflow", "positron"))
  packages <- vapply(settings$packages$default_packages, `[[`, "", "name")
  expect_setequal(packages, c("shiny", "bslib"))

  agents <- paste(readLines(file.path(dir, "AGENTS.md")), collapse = "\n")
  expect_match(agents, "This is a Shiny app.", fixed = TRUE)
  expect_match(agents, "shiny::runApp()", fixed = TRUE)
  expect_match(agents, "## Installed Packages", fixed = TRUE)
  expect_no_match(agents, "Start each notebook", fixed = TRUE)
  expect_no_match(agents, "data_read()", fixed = TRUE)
  expect_no_match(agents, "Workflow Guidelines", fixed = TRUE)
  expect_no_match(agents, "auto_attach", fixed = TRUE)
})

test_that("regenerating an app's AGENTS.md keeps the app section", {
  dir <- create_app("plumber", "plumber.R")

  suppressMessages(ai_regenerate_context(dir))
  agents <- paste(readLines(file.path(dir, "AGENTS.md")), collapse = "\n")
  expect_match(agents, "This is a Plumber API.", fixed = TRUE)
  expect_match(agents, "Rscript run.R", fixed = TRUE)
  expect_no_match(agents, "Start each notebook", fixed = TRUE)
  expect_no_match(agents, "## Data Management", fixed = TRUE)
})

test_that("app types start without R's default packages or skills beyond packages", {
  defaults <- framework:::.spec_package_defaults("shiny")
  expect_length(defaults$packages$default_packages, 0)
  expect_false(defaults$tools$quarto)
  expect_identical(framework:::.ai_skills_for_type("plumber"), "framework-packages")
  # Analysis projects keep the tidyverse
  expect_true("dplyr" %in% names(framework:::.spec_package_defaults("project")$packages$default_packages))
})

test_that("Workflow Guidelines name the workflow skill only when it is installed", {
  with_skill <- framework:::.generate_project_type_section("project", skills = "framework-workflow")
  expect_match(with_skill, "framework-workflow", fixed = TRUE)
  expect_null(framework:::.generate_project_type_section("project", skills = "framework-packages"))
})
