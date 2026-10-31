fake_checkout <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(dir, ".git"))
  dir.create(file.path(dir, ".github", "workflows"), recursive = TRUE)
  writeLines("name: scaffold", file.path(dir, ".github", "workflows", "framework-scaffold.yml"))
  writeLines("# My Study", file.path(dir, "README.md"))
  dir.create(file.path(dir, ".framework"))
  dir
}

write_layers <- function(dir, layers, name = "My Study") {
  envelope <- list(
    spec_version = 1,
    name = name,
    author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""),
    layers = layers
  )
  path <- file.path(dir, ".framework", "layers.json")
  jsonlite::write_json(envelope, path, auto_unbox = TRUE, null = "null")
  path
}

sensitive_layers <- function() {
  list(
    list(kind = "base", key = "project", version = 1, layer = list(type = "project")),
    list(kind = "facet", key = "restricted-data", version = 1, layer = list(
      security = list(sensitive = TRUE),
      directories = list(
        inputs_raw = NULL,
        inputs_private_raw = "inputs/private/raw",
        outputs_private_tables = "outputs/private/tables"
      )
    )),
    list(kind = "facet", key = "manuscript", version = 1, layer = list(
      extra_directories = list(manuscript = list(label = "Manuscript", path = "manuscript")),
      files = list(`manuscript/manuscript.qmd` = list(
        template = TRUE,
        content = "---\ntitle: \"{{project_name}}\"\nauthor: \"{{ author }}\"\n---\n{{< include _common.qmd >}}\n"
      ))
    )),
    list(kind = "facet", key = "claude-code", version = 1, layer = list(
      ai = list(enabled = TRUE, assistants = list(claude = TRUE))
    )),
    list(kind = "facet", key = "codex", version = 1, layer = list(
      ai = list(assistants = list(codex = TRUE))
    )),
    list(kind = "project", key = "my-study", layer = list())
  )
}

test_that("headless creation from a layers file builds the project in a checkout", {
  dir <- fake_checkout()
  layers_file <- write_layers(dir, sensitive_layers())

  result <- suppressMessages(project_create_from_layers(layers_file, path = dir, interactive = FALSE))
  expect_true(result$success)

  expect_true(file.exists(file.path(dir, "settings.yml")))
  expect_true(dir.exists(file.path(dir, "inputs", "private", "raw")))
  expect_false(dir.exists(file.path(dir, "inputs", "raw")))
  expect_true(dir.exists(file.path(dir, "manuscript")))

  # Template placeholders filled; Quarto shortcodes untouched
  qmd <- readLines(file.path(dir, "manuscript", "manuscript.qmd"))
  expect_true("title: \"My Study\"" %in% qmd)
  expect_true("author: \"Ada Analyst\"" %in% qmd)
  expect_true("{{< include _common.qmd >}}" %in% qmd)

  # Headless: no git init, no new workflow files, existing files left alone
  expect_identical(list.files(file.path(dir, ".git")), character())
  expect_identical(list.files(file.path(dir, ".github", "workflows")), "framework-scaffold.yml")

  # Record of how it was made
  record <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(record$name, "My Study")
  expect_true(record$security$sensitive)
  expect_false(is.null(record$source$framework_version))
})

test_that("skills and stubs follow the selected assistants", {
  dir <- fake_checkout()
  suppressMessages(project_create_from_layers(write_layers(dir, sensitive_layers()), path = dir))

  expect_true(file.exists(file.path(dir, ".claude", "skills", "framework-workflow", "SKILL.md")))
  expect_true(file.exists(file.path(dir, ".agents", "skills", "framework-workflow", "SKILL.md")))
  expect_true(file.exists(file.path(dir, ".claude", "skills", "framework-sensitive-data", "SKILL.md")))
  expect_identical(readLines(file.path(dir, "CLAUDE.md")), "@AGENTS.md")
  expect_false(file.exists(file.path(dir, ".github", "copilot-instructions.md")))

  agents <- readLines(file.path(dir, "AGENTS.md"))
  expect_true("# My Study" %in% agents)
  expect_true(any(grepl("framework::scaffold()", agents, fixed = TRUE)))
  expect_true(any(grepl("`inputs/private/`", agents, fixed = TRUE)))
  expect_true("## Project Notes" %in% agents)
})

test_that("sensitive projects get Claude Code deny rules and a fail-closed sandbox", {
  dir <- fake_checkout()
  suppressMessages(project_create_from_layers(write_layers(dir, sensitive_layers()), path = dir))

  settings <- jsonlite::read_json(file.path(dir, ".claude", "settings.json"), simplifyVector = TRUE)
  expect_setequal(settings$permissions$deny, c(
    "Read(/inputs/private/**)", "Edit(/inputs/private/**)",
    "Read(/outputs/private/**)", "Edit(/outputs/private/**)",
    "Read(/.env)"
  ))
  expect_true(settings$sandbox$enabled)
  expect_true(settings$sandbox$failIfUnavailable)
  expect_setequal(settings$sandbox$filesystem$denyRead, c("./inputs/private", "./outputs/private", "./.env"))

  gitignore <- readLines(file.path(dir, ".gitignore"))
  expect_true(any(grepl("Sensitive", gitignore, ignore.case = TRUE)))
})

test_that("non-sensitive projects get no deny rules", {
  dir <- fake_checkout()
  layers <- list(list(kind = "facet", key = "claude-code", layer = list(ai = list(enabled = TRUE, assistants = list(claude = TRUE)))))
  suppressMessages(project_create_from_layers(write_layers(dir, layers), path = dir))
  expect_false(file.exists(file.path(dir, ".claude", "settings.json")))
})

test_that("with no assistants, skills go to .agents/skills only", {
  dir <- fake_checkout()
  layers <- list(list(layer = list(ai = list(enabled = TRUE, assistants = list(claude = FALSE)))))
  suppressMessages(project_create_from_layers(write_layers(dir, layers), path = dir))
  expect_true(dir.exists(file.path(dir, ".agents", "skills", "framework-workflow")))
  expect_false(dir.exists(file.path(dir, ".claude")))
  expect_false(file.exists(file.path(dir, "CLAUDE.md")))
})

test_that("headless creation refuses a checkout with other content", {
  dir <- fake_checkout()
  writeLines("x <- 1", file.path(dir, "analysis.R"))
  expect_error(
    project_create_from_layers(write_layers(dir, list()), path = dir),
    "already contains analysis.R"
  )
})

test_that("headless creation refuses to write workflow files", {
  dir <- fake_checkout()
  layers <- list(list(layer = list(files = list(`.github/workflows/ci.yml` = list(content = "on: push")))))
  expect_error(
    project_create_from_layers(write_layers(dir, layers), path = dir),
    "cannot write workflow files"
  )
})

test_that("an invalid layers file stops with a readable message", {
  dir <- fake_checkout()
  layers <- list(list(layer = list(directories = list(raw = "../outside"))))
  expect_error(
    project_create_from_layers(write_layers(dir, layers), path = dir),
    "must be relative"
  )
})

test_that("project_create() accepts a resolved spec", {
  parent <- withr::local_tempdir()
  spec <- spec_resolve(list(list(git = list(use_git = FALSE))), name = "From spec")
  location <- file.path(parent, "from-spec")
  result <- suppressMessages(project_create(spec, location))
  expect_true(result$success)
  expect_true(file.exists(file.path(location, "settings.yml")))
  expect_true(file.exists(file.path(location, ".framework", "spec.json")))
  expect_error(suppressMessages(project_create(spec, location)), "already exists")
})

test_that("setup(token) and new(key) create the project from pull v2", {
  withr::local_envvar(FW_CONFIG_HOME = withr::local_tempdir(), FW_CLOUD_URL = NA, FW_CLOUD_TOKEN = NA)
  envelope <- list(
    spec_version = 1L,
    name = "My Study",
    author = list(name = "Ada Analyst", email = "ada@example.org", affiliation = ""),
    layers = list(
      list(kind = "base", key = "project", version = 1L, layer = list(type = "project")),
      list(kind = "project", key = "my-study", layer = list(language = "r"))
    ),
    source = list(origin = "cloud", blueprint = list(key = "study", version = 2L))
  )
  calls <- list()
  testthat::local_mocked_bindings(.fw_api = function(path, token, method = "GET", body = NULL, url = NULL) {
    calls[[length(calls) + 1]] <<- list(path = path, token = token, url = url)
    envelope
  })

  root <- withr::local_tempdir()
  location <- file.path(root, "study")
  result <- suppressMessages(setup("1|fw_pull", location = location, browse = FALSE,
                                   url = "https://cloud.example.edu"))
  expect_true(result$success)
  expect_identical(calls[[1]]$path, "/api/v2/projects/pull")
  expect_identical(calls[[1]]$token, "1|fw_pull")
  expect_identical(calls[[1]]$url, "https://cloud.example.edu")

  record <- jsonlite::read_json(file.path(location, ".framework", "spec.json"))
  expect_identical(record$language, "r")
  expect_identical(record$type, "project")
  expect_identical(record$source$blueprint$key, "study")
  env <- readLines(file.path(location, ".env"))
  expect_true("FW_PROJECT_TOKEN=1|fw_pull" %in% env)
  expect_true("FW_CLOUD_URL=https://cloud.example.edu" %in% env)

  # new(key) takes the same path
  location2 <- file.path(root, "study2")
  result2 <- suppressMessages(new(key = "1|fw_pull", location = location2, browse = FALSE,
                                  url = "https://cloud.example.edu"))
  expect_true(result2$success)
  expect_error(new("other", key = "1|fw_pull"), "come from the cloud project")

  # A Python project points elsewhere and creates nothing
  envelope$layers[[2]]$layer$language <- "python"
  location3 <- file.path(root, "py")
  expect_error(suppressMessages(setup("1|fw_pull", location = location3, browse = FALSE,
                                      url = "https://cloud.example.edu")), "Python project")
  expect_false(dir.exists(location3))
})

test_that("registering a new project tells the cloud it is an R project", {
  sent <- NULL
  testthat::local_mocked_bindings(
    .fw_cloud_url = function(url = NULL, scope = "user") "https://cloud.example.edu",
    .fw_cloud_token = function(url = NULL) "user-token",
    .fw_api = function(path, token, method = "GET", body = NULL, url = NULL) {
      sent <<- list(path = path, method = method, body = body)
      list(project = list(slug = "study"), pull_token = "1|fw_new")
    },
    .fw_write_project_token = function(project_dir, token, url) invisible(TRUE)
  )
  suppressMessages(.fw_cloud_register_project(tempdir(), "Study", "project"))
  expect_identical(sent$path, "/api/v1/projects")
  expect_identical(sent$method, "POST")
  expect_identical(sent$body$language, "r")
})

test_that("tools, settings_layout, and core_files decide what is created, not the type", {
  skip_on_cran()
  env <- environment()
  create <- function(layers) {
    dir <- withr::local_tempdir(.local_envir = env)
    dir.create(file.path(dir, ".framework"))
    suppressMessages(project_create_from_layers(write_layers(dir, layers), path = dir, interactive = FALSE))
    dir
  }

  # Framework's project structure: split settings and Quarto on, recorded in settings.yml
  dir <- create(list(list(kind = "base", key = "project", layer = list(type = "project"))))
  expect_true(file.exists(file.path(dir, "settings", "packages.yml")))
  expect_true(file.exists(file.path(dir, "_quarto.yml")))
  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))$default
  expect_true(settings$tools$quarto)
  expect_false(settings$tools$renv)

  # The same structure with Quarto off and a flat settings file
  dir <- create(list(
    list(kind = "base", key = "project", layer = list(type = "project", settings_layout = "flat")),
    list(kind = "project", layer = list(tools = list(quarto = FALSE)))
  ))
  expect_false(file.exists(file.path(dir, "_quarto.yml")))
  expect_false(dir.exists(file.path(dir, "settings")))
  expect_false(yaml::read_yaml(file.path(dir, "settings.yml"))$default$tools$quarto)

  # A blueprint's own label, with its own folders and no core files
  dir <- create(list(list(kind = "base", key = "ada/lab", layer = list(
    type = "lab_pipeline", core_files = FALSE, directories = list(raw = "raw")
  ))))
  expect_true(dir.exists(file.path(dir, "raw")))
  expect_false(file.exists(file.path(dir, "scaffold.R")))
  expect_false(file.exists(file.path(dir, ".env")))
  expect_identical(yaml::read_yaml(file.path(dir, "settings.yml"))$default$project_type, "lab_pipeline")
})
