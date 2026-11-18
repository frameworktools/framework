# publish_snippet() under real renders: quarto render and rmarkdown::render()
# install their own knitr hooks, and the recording wrappers must wrap them.
# Each render runs in its own R process and publishes to a folder destination.

snippet_render_project <- function(env = parent.frame()) {
  project <- withr::local_tempdir(.local_envir = env)
  site <- file.path(project, "site")
  yaml::write_yaml(list(default = list(
    project_type = "project",
    publish = list(default = "site", destinations = list(site = list(driver = "folder", path = site)))
  )), file.path(project, "settings.yml"))
  dir.create(file.path(project, "notebooks"))
  # From a checkout, the rendering process loads this source tree; from an
  # installed package (R CMD check), library(framework) loads it
  root <- normalizePath(testthat::test_path("..", ".."), mustWork = FALSE)
  source_tree <- file.exists(file.path(root, "DESCRIPTION")) && dir.exists(file.path(root, "R"))
  withr::local_envvar(FW_SNIPPET_TEST_PKG = if (source_tree) root else "", .local_envir = env)
  project
}

snippet_notebook <- function(path, title) {
  writeLines(c(
    "---",
    paste0("title: ", title),
    "---",
    "",
    "```{r}",
    "#| label: setup",
    "#| include: false",
    "pkg <- Sys.getenv(\"FW_SNIPPET_TEST_PKG\")",
    "if (nzchar(pkg)) pkgload::load_all(pkg, quiet = TRUE) else library(framework)",
    "```",
    "",
    "```{r}",
    "#| label: fit-model",
    "# Miles per gallon by weight",
    "fit <- lm(mpg ~ wt, data = mtcars)",
    "message(\"fitted\")",
    "round(coef(fit), 2)",
    "plot(fit, which = 1)",
    "```",
    "",
    "```{r}",
    "#| label: publish",
    "#| include: false",
    "publish_snippet(\"fit-model\", folded = TRUE, links = list(notebook = \"https://example.org/fit\"))",
    "publish_snippet(\"fit-model\", output = FALSE, slug = \"fit-model-code\")",
    "```"
  ), path)
}

expect_rendered_snippet <- function(project, file) {
  site <- file.path(project, "site")
  json <- jsonlite::read_json(file.path(site, "fit-model", "code_snippet.json"), simplifyVector = FALSE)
  expect_identical(json$kind, "code_snippet")
  expect_identical(json$source$language, "r")
  expect_identical(json$source$label, "fit-model")
  expect_identical(json$source$file, file)
  # The chunk's code lines: after the fence and the #| line
  expect_identical(json$source$lines, list(14L, 18L))
  expect_null(json$source$repository)
  types <- vapply(json$snippet$blocks, `[[`, "", "type")
  expect_identical(types, c("code", "message", "code", "output", "code"))
  expect_identical(json$snippet$blocks[[1]]$text,
                   "# Miles per gallon by weight\nfit <- lm(mpg ~ wt, data = mtcars)\nmessage(\"fitted\")")
  expect_identical(json$snippet$blocks[[2]]$text, "fitted")
  expect_match(json$snippet$blocks[[4]]$text, "^\\(Intercept\\) +wt *\n +37\\.29 +-5\\.34")
  expect_true(json$snippet$blocks[[4]]$folded)
  expect_identical(json$snippet$blocks[[5]]$text, "plot(fit, which = 1)")
  expect_identical(json$display$links, list(list(rel = "notebook", url = "https://example.org/fit")))

  code <- jsonlite::read_json(file.path(site, "fit-model-code", "code_snippet.json"), simplifyVector = FALSE)
  expect_identical(unique(vapply(code$snippet$blocks, `[[`, "", "type")), "code")
}

test_that("publish_snippet() publishes a chunk from quarto render", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("quarto")), "quarto is not installed")
  skip_if_not_installed("rmarkdown")
  project <- snippet_render_project()
  notebook <- file.path(project, "notebooks", "fit.qmd")
  snippet_notebook(notebook, "Fit")
  output <- system2(Sys.which("quarto"), c("render", shQuote(notebook), "--to", "html", "--quiet"),
                    stdout = TRUE, stderr = TRUE)
  expect_identical(attr(output, "status") %||% 0L, 0L, info = paste(output, collapse = "\n"))
  expect_rendered_snippet(project, "notebooks/fit.qmd")
})

test_that("publish_snippet() publishes a chunk from rmarkdown::render()", {
  skip_on_cran()
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not installed")
  project <- snippet_render_project()
  notebook <- file.path(project, "notebooks", "fit.Rmd")
  snippet_notebook(notebook, "Fit")
  rscript <- file.path(R.home("bin"), "Rscript")
  call <- sprintf("rmarkdown::render(%s, quiet = TRUE)", deparse(notebook))
  output <- system2(rscript, c("-e", shQuote(call)), stdout = TRUE, stderr = TRUE)
  expect_identical(attr(output, "status") %||% 0L, 0L, info = paste(output, collapse = "\n"))
  expect_rendered_snippet(project, "notebooks/fit.Rmd")
})
