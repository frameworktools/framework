test_that("project_create generates Quarto configs with render output dirs", {
  skip_on_cran()

  tmp <- withr::local_tempdir()
  project_dir <- file.path(tmp, "standard")

  directories <- list(
    notebooks = "notebooks",
    docs = "docs"
  )
  render_dirs <- list(
    notebooks = "outputs/notebooks",
    docs = "outputs/docs"
  )

  result <- project_create(
    name = "Standard Quarto",
    location = project_dir,
    type = "project",
    directories = directories,
    render_dirs = render_dirs,
    packages = list(use_renv = FALSE, default_packages = list()),
    author = list(name = "", email = "", affiliation = ""),
    ai = list(enabled = FALSE, assistants = list()),
    git = list(initialize = FALSE, hooks = list()),
    scaffold = list(seed_on_scaffold = FALSE, set_theme_on_scaffold = FALSE)
  )

  expect_true(result$success)

  # One root project; notebooks/ and docs/ render under its output-dir
  root <- yaml::read_yaml(file.path(project_dir, "_quarto.yml"))
  expect_equal(root$project$`output-dir`, "outputs")
  expect_equal(root$format$html$theme, "default")
  expect_null(root$format$revealjs)
  expect_false(file.exists(file.path(project_dir, "notebooks", "_quarto.yml")))
  expect_false(file.exists(file.path(project_dir, "docs", "_quarto.yml")))
  expect_false(file.exists(file.path(project_dir, "notebooks", "_metadata.yml")))
})

test_that("course project uses revealjs for slides render dir", {
  skip_on_cran()

  tmp <- withr::local_tempdir()
  project_dir <- file.path(tmp, "course")

  directories <- list(
    slides = "slides",
    assignments = "assignments"
  )
  render_dirs <- list(
    slides = "rendered/slides",
    assignments = "rendered/assignments"
  )

  result <- project_create(
    name = "Course Quarto",
    location = project_dir,
    type = "course",
    directories = directories,
    render_dirs = render_dirs,
    packages = list(use_renv = FALSE, default_packages = list()),
    author = list(name = "", email = "", affiliation = ""),
    ai = list(enabled = FALSE, assistants = list()),
    git = list(initialize = FALSE, hooks = list()),
    scaffold = list(seed_on_scaffold = FALSE, set_theme_on_scaffold = FALSE)
  )

  expect_true(result$success)

  root <- yaml::read_yaml(file.path(project_dir, "_quarto.yml"))
  expect_equal(root$project$`output-dir`, "rendered")
  expect_false(file.exists(file.path(project_dir, "slides", "_quarto.yml")))
  slides <- yaml::read_yaml(file.path(project_dir, "slides", "_metadata.yml"))
  expect_null(slides$project)
  expect_true(!is.null(slides$format$revealjs))
  expect_false(file.exists(file.path(project_dir, "assignments", "_metadata.yml")))
})

test_that("a render target outside the shared output folder keeps its own Quarto project", {
  tmp <- withr::local_tempdir()
  result <- quarto_generate_all(
    tmp, "project",
    render_dirs = list(notebooks = "outputs/notebooks", docs = "outputs/docs", reports = "site"),
    directories = list(notebooks = "notebooks", docs = "docs", reports = "reports")
  )
  expect_equal(yaml::read_yaml(file.path(tmp, "_quarto.yml"))$project$`output-dir`, "outputs")
  reports <- yaml::read_yaml(file.path(tmp, "reports", "_quarto.yml"))
  expect_equal(reports$project$`output-dir`, "../site")
  expect_false(file.exists(file.path(tmp, "notebooks", "_quarto.yml")))
})

test_that("quarto_regenerate(overwrite = TRUE) replaces per-folder projects with one root", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(
    project_type = "project",
    directories = list(notebooks = "notebooks"),
    render_dirs = list(notebooks = "outputs/notebooks")
  )), file.path(tmp, "settings.yml"))
  dir.create(file.path(tmp, "notebooks"))
  writeLines("project:\n  output-dir: ../outputs/notebooks", file.path(tmp, "notebooks", "_quarto.yml"))

  result <- quarto_regenerate(tmp, overwrite = TRUE)
  expect_false(file.exists(file.path(tmp, "notebooks", "_quarto.yml")))
  expect_true("notebooks/_quarto.yml" %in% result$backed_up)
  expect_true(file.exists(file.path(result$backup_location, "notebooks", "_quarto.yml")))
  expect_true("backups/" %in% readLines(file.path(tmp, ".framework", ".gitignore")))
  expect_equal(yaml::read_yaml(file.path(tmp, "_quarto.yml"))$project$`output-dir`, "outputs")
})

test_that("save_notebook() finds the render inside the root project's folders", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("quarto")), "quarto not installed")
  tmp <- withr::local_tempdir()
  withr::local_dir(tmp)
  yaml::write_yaml(list(default = list(project_type = "project", directories = list(
    notebooks = "notebooks", outputs_notebooks = "outputs/notebooks"
  ))), "settings.yml")
  quarto_generate_all(tmp, "project", render_dirs = list(notebooks = "outputs/notebooks"),
                      directories = list(notebooks = "notebooks"))
  writeLines(c("---", "title: Look", "---", "", "Plain text."), file.path("notebooks", "look.qmd"))
  path <- suppressMessages(save_notebook("notebooks/look.qmd"))
  expect_true(file.exists(path))
  expect_identical(path, file.path("outputs", "notebooks", "look.html"))
})

test_that("a sensitive project's quarto render_dir stays under outputs/private", {
  render_dirs <- framework:::.default_render_dirs_for_type("project_sensitive")
  root <- framework:::.default_root_render_dir_for_type("project_sensitive")
  expect_true(startsWith(root, "outputs/private/"))
  expect_true(all(startsWith(unlist(render_dirs), "outputs/private/")))
  expect_identical(root, render_dirs$notebooks)
})

test_that("quarto_regenerate() keeps a customized config and adds only missing keys", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(
    project_type = "presentation",
    directories = list(notebooks = "notebooks"),
    render_dirs = list(notebooks = "outputs/notebooks")
  )), file.path(tmp, "settings.yml"))
  custom <- c(
    "# Shared settings for every deck",
    "project:",
    "  type: default",
    "",
    "execute:",
    "  eval: false",
    "",
    "format:",
    "  revealjs:",
    "    theme: [default, assets/jhu.scss]",
    "    width: 1280"
  )
  writeLines(custom, file.path(tmp, "_quarto.yml"))
  dir.create(file.path(tmp, "notebooks"))
  writeLines("project:\n  output-dir: ../outputs/notebooks", file.path(tmp, "notebooks", "_quarto.yml"))

  # While notebooks/ keeps its own Quarto project, the root keeps the old
  # layout: an output-dir would move where root documents render
  kept <- suppressMessages(quarto_regenerate(tmp, dry_run = TRUE))
  expect_identical(kept$kept, "notebooks/_quarto.yml")
  expect_true("_quarto.yml" %in% kept$unchanged)
  unlink(file.path(tmp, "notebooks", "_quarto.yml"))

  dry <- suppressMessages(quarto_regenerate(tmp, dry_run = TRUE))
  expect_identical(readLines(file.path(tmp, "_quarto.yml")), custom)
  # The root gains a key, and notebooks/ (HTML in a revealjs project) gets
  # its _metadata.yml
  expect_identical(dry$regenerated, c("_quarto.yml", "notebooks/_metadata.yml"))

  result <- suppressMessages(quarto_regenerate(tmp))
  lines <- readLines(file.path(tmp, "_quarto.yml"))
  # Every custom line stays, and output-dir is added under project:
  expect_identical(lines[-3], custom)
  expect_identical(lines[3], "  output-dir: outputs")
  parsed <- yaml::read_yaml(file.path(tmp, "_quarto.yml"))
  expect_identical(parsed$format$revealjs$theme, c("default", "assets/jhu.scss"))
  expect_false(parsed$execute$eval)
  expect_identical(result$backed_up, "_quarto.yml")

  # Run again: nothing to do
  again <- suppressMessages(quarto_regenerate(tmp))
  expect_length(again$regenerated, 0)
  expect_identical(again$unchanged, c("_quarto.yml", "notebooks/_metadata.yml"))
})

test_that("quarto_regenerate(backup = FALSE) never removes a file", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(default = list(
    project_type = "project",
    directories = list(notebooks = "notebooks"),
    render_dirs = list(notebooks = "outputs/notebooks")
  )), file.path(tmp, "settings.yml"))
  dir.create(file.path(tmp, "notebooks"))
  writeLines("project:\n  output-dir: ../outputs/notebooks", file.path(tmp, "notebooks", "_quarto.yml"))
  result <- suppressMessages(quarto_regenerate(tmp, backup = FALSE, overwrite = TRUE))
  expect_true(file.exists(file.path(tmp, "notebooks", "_quarto.yml")))
  expect_identical(result$kept, "notebooks/_quarto.yml")
  expect_false(dir.exists(file.path(tmp, ".framework", "backups")))
  expect_false(dir.exists(file.path(tmp, ".quarto_backups")))
})
