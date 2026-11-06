# inst/features and inst/sets are copied by framework-cloud, framework-py,
# and fw, so their shape is checked here

test_that("every tool and set definition is well formed", {
  skip_if_not_installed("jsonvalidate")
  schema <- system.file("schema", "layer.v1.json", package = "framework")
  v <- jsonvalidate::json_schema$new(schema, engine = "ajv")
  as_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")

  features <- framework:::.fw_features()
  expect_setequal(names(features), c("quarto", "quarto_manuscript", "quarto_slides", "targets", "renv", "jupyter", "uv"))
  for (id in names(features)) {
    f <- features[[id]]
    expect_true(all(c("id", "name", "description", "language", "requires", "conflicts", "layer") %in% names(f)), info = id)
    expect_true(all(unlist(f$requires) %in% names(features)), info = id)
    expect_true(all(unlist(f$language) %in% c("r", "python")), info = id)
    expect_true(isTRUE(f$layer$tools[[id]]), info = id)
    expect_true(v$validate(as_json(f$layer)), info = id)
    for (lang in names(f$language_layers)) expect_true(v$validate(as_json(f$language_layers[[lang]])), info = paste(id, lang))
  }

  sets <- c(framework:::.fw_skill_sets(), framework:::.fw_package_sets())
  expect_setequal(names(sets), c("framework", "ggplot2", "python-data-analysis", "tidyverse-analysis"))
  for (id in names(sets)) expect_true(v$validate(as_json(sets[[id]]$layer)), info = id)
  shipped <- list.files(system.file("templates", "skills", package = "framework"))
  for (id in names(framework:::.fw_skill_sets())) {
    expect_true(all(names(sets[[id]]$layer$skills) %in% shipped), info = id)
  }
})

test_that("tools bring what they require and respect the language", {
  expect_message(tools <- framework:::.fw_resolve_tools("quarto_slides"), "Also turning on quarto")
  expect_identical(tools, c("quarto", "quarto_slides"))
  expect_silent(framework:::.fw_resolve_tools(c("quarto", "quarto_slides")))
  expect_error(framework:::.fw_resolve_tools("uv"), "isn't available for r")
  expect_error(framework:::.fw_resolve_tools("pants"), "Unknown tool")

  entries <- framework:::.fw_definition_layers(tools = "jupyter", package_sets = "tidyverse-analysis", skill_sets = "ggplot2")
  expect_identical(vapply(entries, `[[`, "", "key"), c(
    "framework/tool-jupyter", "framework/tool-jupyter-r", "framework/packages-tidyverse-analysis", "framework/skills-ggplot2"
  ))
  spec <- spec_resolve(c(list(list(kind = "base", key = "project", layer = list(type = "project"))), entries), name = "x")
  expect_true(spec$tools$jupyter)
  expect_true("IRkernel" %in% names(spec$packages$default_packages))
  expect_true("ggplot2-publishing" %in% names(spec$skills))
  expect_identical(spec_check(spec), character())
})

test_that("workflows turn on their tools and set the notebook format", {
  resolve <- function(workflow, type = "project") {
    layers <- c(list(list(kind = "base", key = type, layer = list(type = type))),
                suppressMessages(framework:::.fw_workflow_layers(workflow)))
    spec_resolve(layers, name = "W")
  }
  spec <- resolve("jupyter")
  expect_identical(spec$scaffold[c("workflow", "notebook_format")], list(workflow = "jupyter", notebook_format = "jupyter"))
  expect_true(isTRUE(spec$tools$jupyter) && isTRUE(spec$tools$quarto))
  expect_true("IRkernel" %in% names(spec$packages$default_packages))

  spec <- resolve("scripts")
  expect_identical(spec$scaffold$notebook_format, "script")
  expect_false(isTRUE(spec$tools$quarto))

  # Bare has no workflow until one is chosen
  expect_null(spec_resolve(list(list(type = "bare")), name = "B")$scaffold$workflow)
  expect_identical(resolve("quarto", "bare")$scaffold$workflow, "quarto")
  expect_error(framework:::.fw_workflow_layers("marimo"), "Unknown workflow")
})
