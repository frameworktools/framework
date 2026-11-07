# Regressions for the 2026-11-05 audit of exports 64-125 (r/part2).
# No test reaches the network: S3, renv, and Cloud calls are mocked.

local_audit_project <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  withr::local_envvar(FW_CONFIG_HOME = file.path(dir, ".fwconfig"), .local_envir = env)
  yaml::write_yaml(list(default = list(
    project_type = "project",
    directories = list(notebooks = "notebooks", outputs_private = "outputs/private")
  )), "settings.yml")
  dir
}

test_that("publish_list() passes an empty region and use_https for custom endpoints", {
  skip_if_not_installed("aws.s3")
  local_audit_project()
  seen <- NULL
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(...) list(
      bucket = "b", region = "us-east-1", endpoint = "127.0.0.1:5055", use_https = FALSE,
      prefix = "", access_key = "k", secret_key = "s", session_token = NULL
    )
  )
  testthat::local_mocked_bindings(
    get_bucket = function(...) { seen <<- list(...); list() },
    .package = "aws.s3"
  )
  out <- publish_list()
  expect_identical(seen$region, "")
  expect_false(seen$use_https)
  expect_identical(seen$base_url, "127.0.0.1:5055")
  expect_identical(nrow(out), 0L)
})

test_that("publish_list() keeps the region for AWS", {
  skip_if_not_installed("aws.s3")
  local_audit_project()
  seen <- NULL
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(...) list(
      bucket = "b", region = "eu-west-1", endpoint = NULL, prefix = "",
      access_key = "k", secret_key = "s", session_token = NULL
    )
  )
  testthat::local_mocked_bindings(
    get_bucket = function(...) { seen <<- list(...); list() },
    .package = "aws.s3"
  )
  publish_list()
  expect_identical(seen$region, "eu-west-1")
  expect_true(seen$use_https)
})

test_that("publish_notebook() to a bucket finds HTML for a notebook in notebooks/", {
  skip_if(!nzchar(Sys.which("quarto")), "quarto not installed")
  local_audit_project()
  # A Quarto project keeps the source folder under --output-dir
  writeLines(c("project:", "  type: default", "  output-dir: outputs"), "_quarto.yml")
  dir.create("notebooks")
  writeLines(c("---", "title: Cars", "---", "", "Hello cars"), "notebooks/cars.qmd")
  uploads <- list()
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(...) list(bucket = "b", region = "", static_hosting = FALSE, prefix = ""),
    .s3_upload_file = function(file, dest, config) {
      uploads[[length(uploads) + 1L]] <<- list(dest = dest, html = readLines(file, warn = FALSE))
      paste0("http://mock/", dest)
    }
  )
  url <- suppressMessages(publish_notebook("notebooks/cars.qmd", to = "bucket"))
  expect_identical(url, "http://mock/cars.html")
  expect_true(any(grepl("Hello cars", uploads[[1]]$html)))

  # Static hosting without embedding uploads the folder that holds the page
  uploads <- list()
  dirs <- NULL
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(...) list(bucket = "b", region = "", static_hosting = TRUE, prefix = ""),
    .s3_upload_dir = function(dir, dest, config) {
      dirs <<- list.files(dir, recursive = TRUE)
      paste0("http://mock/", dest, "/", dirs)
    },
    .s3_public_url = function(key, config) paste0("http://mock/", key)
  )
  url <- suppressMessages(publish_notebook("notebooks/cars.qmd", to = "bucket", self_contained = FALSE))
  expect_identical(url, "http://mock/cars/")
  expect_true("index.html" %in% dirs)
})

test_that("save_figure() saves a recorded base plot and the plot on the device", {
  skip_if_not_installed("ggplot2")
  local_audit_project()
  png_file <- tempfile(fileext = ".png")
  grDevices::png(png_file)
  on.exit(if (grDevices::dev.cur() > 1L) grDevices::dev.off(), add = TRUE)
  grDevices::dev.control("enable")
  graphics::plot(1:10, main = "base plot")
  recorded <- grDevices::recordPlot()

  f1 <- suppressMessages(save_figure(recorded, "recorded"))
  expect_gt(file.size(f1), 1000)
  # NULL saves what the active device shows, not an older ggplot
  ggplot2::set_last_plot(ggplot2::ggplot(mtcars, ggplot2::aes(mpg, hp)) + ggplot2::geom_point())
  f2 <- suppressMessages(save_figure(name = "current"))
  f3 <- suppressMessages(save_figure(recorded, "again"))
  expect_identical(unname(tools::md5sum(f2)), unname(tools::md5sum(f3)))
  f4 <- suppressMessages(save_figure(name = "current_pdf", format = "pdf"))
  expect_gt(file.size(f4), 1000)
  grDevices::dev.off()
})

test_that("save_figure() errors, not blank, when a base plot can't be recorded", {
  skip_if_not_installed("ggplot2")
  local_audit_project()
  withr::local_pdf(tempfile(fileext = ".pdf"))
  grDevices::dev.control("inhibit")
  ggplot2::set_last_plot(ggplot2::ggplot(mtcars, ggplot2::aes(mpg, hp)) + ggplot2::geom_point())
  graphics::plot(1:10)
  expect_error(save_figure(name = "base"), "base R plot can't be saved")
  expect_false(file.exists("outputs/private/figures/base.png") || file.exists("outputs/figures/base.png"))

  # A ggplot drawn last is still saved through last_plot()
  print(ggplot2::last_plot())
  f <- suppressMessages(save_figure(name = "gg"))
  expect_gt(file.size(f), 1000)
  expect_error(save_figure("not a plot", "x"), "recordPlot")
})

test_that("outputs saved before scaffold() are tracked in result_list()", {
  dir <- local_audit_project()
  # A new project's framework.db has no results table yet
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  DBI::dbExecute(con, "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
  DBI::dbDisconnect(con)
  suppressMessages(save_model(lm(mpg ~ wt, mtcars), "fit"))
  results <- result_list()
  expect_identical(results$name, "outputs/models/fit.rds")
  expect_identical(results$type, "model")
})

test_that("result_list() outside a project does not create framework.db", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  out <- result_list()
  expect_identical(nrow(out), 0L)
  expect_false(file.exists("framework.db"))
})

test_that("scratch_capture() handles lm objects and summaries", {
  local_audit_project()
  fit <- lm(mpg ~ wt, data = mtcars)
  suppressMessages(scratch_capture(fit, "fit"))
  suppressMessages(scratch_capture(summary(fit), "fit_summary"))
  scratch <- "outputs/private/scratch"
  expect_true(any(grepl("Coefficients", readLines(file.path(scratch, "fit.txt")))))
  expect_true(any(grepl("Residual standard error", readLines(file.path(scratch, "fit_summary.txt")))))
  # Plain lists stay YAML
  suppressMessages(scratch_capture(list(a = 1, b = "x"), "plain"))
  expect_identical(readLines(file.path(scratch, "plain.txt"))[1], "List of 2 items:")
})

test_that("scratch_capture() quotes CSV and TSV fields that need it", {
  local_audit_project()
  df <- data.frame(city = c("Springfield, IL", "Tab\there"), n = 1:2)
  suppressMessages(scratch_capture(df, "cities", to = "csv"))
  suppressMessages(scratch_capture(df, "cities", to = "tsv"))
  scratch <- "outputs/private/scratch"
  back <- utils::read.csv(file.path(scratch, "cities.csv"))
  expect_identical(back$city, df$city)
  back_tsv <- utils::read.delim(file.path(scratch, "cities.tsv"))
  expect_identical(back_tsv$city, df$city)
})

test_that("scratch_clean() removes top-level files and dotfiles, keeps subfolders", {
  local_audit_project()
  scratch <- "outputs/private/scratch"
  dir.create(file.path(scratch, "sub"), recursive = TRUE)
  writeLines("a", file.path(scratch, "a.txt"))
  writeLines("h", file.path(scratch, ".hidden"))
  writeLines("n", file.path(scratch, "sub", "n.txt"))
  expect_no_warning(suppressMessages(scratch_clean()))
  expect_identical(list.files(scratch, recursive = TRUE, all.files = TRUE), "sub/n.txt")
})

test_that("spec_check() reports missing sections instead of crashing", {
  spec <- spec_resolve(list(), name = "ok")
  spec$connections <- NULL
  expect_identical(spec_check(spec), "missing section 'connections'")
  problems <- spec_check(list(name = "only"))
  expect_true("missing section 'connections'" %in% problems)
  expect_true("missing section 'directories'" %in% problems)
})

test_that("quarto_regenerate() works with a relative project path", {
  base <- withr::local_tempdir()
  withr::local_dir(base)
  dir.create("demo/notebooks", recursive = TRUE)
  yaml::write_yaml(list(default = list(
    project_type = "project",
    directories = list(notebooks = "notebooks"),
    render_dirs = list(notebooks = "outputs/notebooks")
  )), "demo/settings.yml")
  writeLines("old: true", "demo/_quarto.yml")
  result <- suppressMessages(quarto_regenerate("demo"))
  expect_true(result$success)
  expect_identical(result$backed_up, "_quarto.yml")
  expect_identical(normalizePath(getwd(), winslash = "/"), normalizePath(base, winslash = "/"))
  expect_true(any(grepl("output-dir: outputs", readLines("demo/_quarto.yml"))))
})

test_that("write_frameworkrc() refuses NULL and keeps the project registry", {
  dir <- withr::local_tempdir()
  withr::local_envvar(FW_CONFIG_HOME = dir)
  yaml::write_yaml(list(author = list(name = "Ada")), file.path(dir, "settings.yml"))
  yaml::write_yaml(list(projects = list(list(id = 1L, path = "/p"))), file.path(dir, "projects.yml"))
  expect_error(write_frameworkrc(NULL), "named, non-empty list")
  expect_error(write_frameworkrc(list()), "named, non-empty list")
  expect_identical(yaml::read_yaml(file.path(dir, "settings.yml"))$author$name, "Ada")
  # Settings without a projects element leave projects.yml alone
  write_frameworkrc(list(author = list(name = "Grace")))
  expect_identical(yaml::read_yaml(file.path(dir, "settings.yml"))$author$name, "Grace")
  expect_length(yaml::read_yaml(file.path(dir, "projects.yml"))$projects, 1L)
  # An explicit projects element still replaces it
  write_frameworkrc(list(author = list(name = "Grace"), projects = list()))
  expect_length(yaml::read_yaml(file.path(dir, "projects.yml"))$projects, 0L)
})

test_that("project_add_directory() records the folder and replaces a same-key entry", {
  dir <- local_audit_project()
  r1 <- project_add_directory(dir, "archive", "Archive", "analysis/archive")
  expect_true(r1$success)
  expect_true(dir.exists(file.path(dir, "analysis/archive")))
  extra <- yaml::read_yaml("settings.yml")$default$extra_directories
  expect_length(extra, 1L)
  expect_identical(extra[[1]]$path, "analysis/archive")
  r2 <- project_add_directory(dir, "archive", "Old analysis", "analysis/old")
  extra <- yaml::read_yaml("settings.yml")$default$extra_directories
  expect_length(extra, 1L)
  expect_identical(extra[[1]]$label, "Old analysis")
  expect_false(project_add_directory(dir, "x", "X", "../out")$success)
})

test_that("saved templates are used by make_notebook() and make_script()", {
  dir <- local_audit_project()
  dir.create("scripts")
  write_framework_template("notebook", "---\ntitle: \"{{ title }}\"\n---\n\nMY TEMPLATE")
  write_framework_template("script", "# MY SCRIPT TEMPLATE")
  nb <- suppressMessages(make_notebook("first", dir = "notebooks"))
  expect_true(any(grepl("MY TEMPLATE", readLines(nb))))
  sc <- suppressMessages(make_script("first", dir = "scripts"))
  expect_true(any(grepl("MY SCRIPT TEMPLATE", readLines(sc))))
  # A project's stubs/ folder still comes first
  dir.create("stubs")
  writeLines("PROJECT STUB", "stubs/notebook-default.qmd")
  nb2 <- suppressMessages(make_notebook("second", dir = "notebooks"))
  expect_identical(readLines(nb2), "PROJECT STUB")
  # Reset returns the shipped stub, and reading does not copy it
  reset_framework_template("notebook")
  expect_identical(read_framework_template("notebook"),
                   paste(readLines(system.file("stubs", "notebook-default.qmd", package = "framework")), collapse = "\n"))
  unlink(framework:::.framework_templates_dir("script-default.R"))
  read_framework_template("script")
  expect_false(file.exists(framework:::.framework_templates_dir("script-default.R")))
})

test_that("renv_enable() locks every project package and copies framework locally", {
  skip_if_not_installed("renv")
  local_audit_project()
  calls <- list()
  testthat::local_mocked_bindings(
    init = function(...) { dir.create("renv"); writeLines("{}", "renv.lock"); invisible() },
    hydrate = function(packages = NULL, ...) { calls$hydrate <<- packages; invisible() },
    install = function(packages, ...) { calls$install <<- c(calls$install, packages); invisible() },
    snapshot = function(..., type = NULL) { calls$snapshot_type <<- type; invisible() },
    .package = "renv"
  )
  testthat::local_mocked_bindings(.has_settings_file = function(...) FALSE,
                                  .fw_framework_installed = function(...) TRUE)
  suppressMessages(renv_enable(sync = FALSE))
  expect_identical(calls$hydrate, "framework")
  expect_false(any(grepl("framework", calls$install)))
  expect_identical(calls$snapshot_type, "all")
  expect_true(renv_enabled())
})

test_that("renv_enable() installs framework from GitHub when no installed copy exists", {
  skip_if_not_installed("renv")
  local_audit_project()
  calls <- list()
  testthat::local_mocked_bindings(
    init = function(...) { dir.create("renv"); writeLines("{}", "renv.lock"); invisible() },
    hydrate = function(packages = NULL, ...) { calls$hydrate <<- packages; invisible() },
    install = function(packages, ...) { calls$install <<- c(calls$install, packages); invisible() },
    snapshot = function(...) invisible(),
    .package = "renv"
  )
  testthat::local_mocked_bindings(.has_settings_file = function(...) FALSE,
                                  .fw_framework_installed = function(...) FALSE)
  suppressMessages(renv_enable(sync = FALSE))
  expect_null(calls$hydrate)
  expect_true("frameworktools/framework" %in% calls$install)
})

test_that("renv_enable() undoes every step when one fails", {
  skip_if_not_installed("renv")
  local_audit_project()
  writeLines("outputs/", ".gitignore")
  paths <- .libPaths()
  testthat::local_mocked_bindings(
    init = function(...) {
      dir.create("renv"); writeLines("{}", "renv.lock")
      writeLines('source("renv/activate.R")', ".Rprofile")
      invisible()
    },
    hydrate = function(...) stop("network down"),
    install = function(...) stop("network down"),
    .package = "renv"
  )
  expect_error(suppressMessages(renv_enable(sync = FALSE)), "network down")
  expect_false(renv_enabled())
  expect_false(file.exists("renv.lock"))
  expect_false(dir.exists("renv"))
  expect_false(file.exists(".Rprofile"))
  expect_false(file.exists(".renvignore"))
  expect_identical(readLines(".gitignore"), "outputs/")
  expect_identical(.libPaths(), paths)
})

test_that("publish_data(compress = TRUE) needs no R.utils and tracks once", {
  local_audit_project()
  uploaded <- NULL
  tracked <- 0L
  testthat::local_mocked_bindings(
    .resolve_s3_connection = function(...) list(bucket = "b", region = "", prefix = ""),
    .s3_upload_file = function(file, dest, config) {
      uploaded <<- list(dest = dest, lines = readLines(gzfile(file)))
      paste0("http://mock/", dest)
    },
    .fw_track_external = function(...) tracked <<- tracked + 1L
  )
  url <- suppressMessages(publish_data(head(mtcars, 3), "data/cars.csv", compress = TRUE))
  expect_identical(url, "http://mock/data/cars.csv.gz")
  expect_length(uploaded$lines, 4L)
  expect_identical(tracked, 1L)
})

test_that("aws.s3 console noise is kept out of publish output", {
  noisy <- function() {
    print(list(Code = "NoSuchPublicAccessBlockConfiguration", Signature = "secret-signature"))
    message("Client error: (404) Not Found")
    TRUE
  }
  out <- utils::capture.output(value <- framework:::.fw_s3_quiet(noisy()), type = "output")
  expect_true(value)
  expect_length(out, 0L)
  expect_silent(framework:::.fw_s3_quiet(noisy()))
  expect_error(framework:::.fw_s3_quiet(stop("boom")), "boom")
})

test_that("publish(to = \"folder\") without a destination explains the setting", {
  local_audit_project()
  writeLines("<p>hi</p>", "report.html")
  expect_error(publish("report.html", to = "folder"), "named destination with a path")
})

test_that("save_notebook() shows Quarto's error text", {
  skip_if(!nzchar(Sys.which("quarto")), "quarto not installed")
  local_audit_project()
  writeLines(c("---", "title: Broken", "format: {html: {nonsense: [}", "---", "", "x"), "broken.qmd")
  err <- tryCatch(suppressWarnings(suppressMessages(save_notebook("broken.qmd"))), error = function(e) conditionMessage(e))
  expect_match(err, "Quarto render failed:")
  expect_gt(length(strsplit(err, "\n")[[1]]), 2L)
})

test_that("save_table() explains a writer argument that matched name", {
  local_audit_project()
  df <- data.frame(x = c(1, NA))
  expect_error(save_table(df, "with_na", na = "MISSING"), "was matched to")
  # All-positional calls have no argument names at all
  expect_true(file.exists(suppressMessages(save_table(df, "plain"))))
  f <- suppressMessages(save_table(df, name = "with_na", na = "MISSING"))
  expect_true(any(grepl("MISSING", readLines(f))))
})

test_that("status() prints no raw ANSI codes when color is off", {
  local_audit_project()
  withr::local_options(cli.num_colors = 1L)
  out <- utils::capture.output(status(), type = "message")
  expect_false(any(grepl("\033[", out, fixed = TRUE)))
  expect_true(any(grepl("FRAMEWORK PROJECT STATUS", out)))
  expect_true(any(grepl("lazy notebooks", out)))
})

test_that("project_info() shows the split output folders of a sensitive project", {
  local_audit_project()
  yaml::write_yaml(list(default = list(
    project_type = "project_sensitive",
    security = list(sensitive = TRUE),
    directories = list(notebooks = "notebooks")
  )), "settings.yml")
  out <- paste(cli::cli_fmt(project_info()), collapse = "\n")
  expect_match(out, "outputs/private/tables")
  expect_match(out, "outputs/public/tables")
})

test_that("package_add() rejects invalid names and does not record failed installs", {
  local_audit_project()
  expect_error(package_add("not a pkg!", install = FALSE), "Not a valid package name")
  testthat::local_mocked_bindings(.install_package = function(pkg_spec) invisible(TRUE))
  expect_error(suppressMessages(package_add("nonexistentpkg12345")), "could not be installed")
  listed <- yaml::read_yaml("settings.yml")$default$packages
  names_listed <- vapply(listed$default_packages %||% listed, function(p) p$name %||% p, "")
  expect_false("nonexistentpkg12345" %in% names_listed)
})

test_that("new_project() warns about an unknown type offline", {
  base <- withr::local_tempdir()
  withr::local_envvar(FW_CONFIG_HOME = file.path(base, "cfg"))
  expect_warning(
    suppressMessages(new_project("demo", file.path(base, "demo"), type = "no_such_blueprint",
                                 browse = FALSE, offline = TRUE)),
    "Unknown project type 'no_such_blueprint'"
  )
})

test_that("quarto_generate_all() derives the root output folder (root_output_dir is ignored)", {
  dir <- withr::local_tempdir()
  quarto_generate_all(dir, "project", render_dirs = list(notebooks = "outputs/notebooks"),
                      directories = list(notebooks = "notebooks"), root_output_dir = "outputs/notebooks")
  expect_true(any(grepl("output-dir: outputs$", readLines(file.path(dir, "_quarto.yml")))))
})
