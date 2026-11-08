# upgrade() brings a project made by an older Framework to the current layout

# A project like those made by Framework 1.x and early 2.0: split settings
# with the old connection layout, project_sensitive without a security:
# block, CLAUDE.md as the full guide, per-folder Quarto files, and a skill
# from an older release
local_old_project <- function(env = parent.frame(), type = "project_sensitive") {
  dir <- withr::local_tempdir(.local_envir = env)
  w <- function(path, lines) {
    dir.create(dirname(file.path(dir, path)), recursive = TRUE, showWarnings = FALSE)
    writeLines(lines, file.path(dir, path))
  }
  w("settings.yml", c(
    "default:",
    "  project_name: Old Study",
    paste0("  project_type: ", type),
    "  directories:",
    "    functions: functions",
    "    notebooks: notebooks",
    "    inputs_private_raw: inputs/private/raw",
    "    inputs_public_raw: inputs/public/raw",
    "  extra_directories: ~",
    "  render_dirs:",
    "    notebooks: outputs/private/notebooks",
    "  packages: settings/packages.yml",
    "  ai: settings/ai.yml",
    "  connections: settings/connections.yml",
    "  quarto: settings/quarto.yml",
    "",
    "ehr_source:",
    "  partner: north"
  ))
  w("settings/packages.yml", c("packages:", "  use_renv: no", "  default_packages:", "  - name: dplyr",
                               "    source: cran", "    auto_attach: yes"))
  w("settings/ai.yml", c("ai:", "  enabled: yes", "  canonical_file: CLAUDE.md", "  assistants:", "  - claude"))
  w("settings/connections.yml", c(
    "options:", "  default_connection: warehouse", "  default_s3_connection: ''",
    "connections:", "  warehouse:", "    driver: postgres", "    host: db.example.org",
    "    password: hunter2", "  framework:", "    driver: sqlite", "    database: framework.db"
  ))
  w("settings/quarto.yml", c("quarto:", "  html:", "    theme: cosmo"))
  w("CLAUDE.md", c("# Old Study", "", "My notes stay here.", "",
                   "## Installed Packages <!-- @framework:regenerate -->", "", "stale list", "",
                   "## Project Notes", "", "Keep this."))
  w("_quarto.yml", c("# mine", "project:", "  type: default", "format:", "  html:", "    theme: cosmo"))
  w("notebooks/_quarto.yml", c("project:", "  output-dir: ../outputs/private/notebooks"))
  w(".gitignore", c("# my rules", ".env", "*.csv"))
  file.copy(testthat::test_path("skill-fixtures", "framework-data-SKILL-6f2521a.md"),
            file.path(dir, "SKILL.tmp"))
  dir.create(file.path(dir, ".claude", "skills", "framework-data"), recursive = TRUE)
  file.rename(file.path(dir, "SKILL.tmp"), file.path(dir, ".claude", "skills", "framework-data", "SKILL.md"))
  dir
}

snapshot <- function(dir) {
  files <- list.files(dir, recursive = TRUE, all.files = TRUE)
  stats::setNames(vapply(file.path(dir, files), function(f) as.character(openssl::md5(file(f))), ""), files)
}

test_that("a dry run prints the plan and changes nothing", {
  dir <- local_old_project()
  before <- snapshot(dir)
  out <- capture_messages(plan <- upgrade(dir))
  expect_identical(snapshot(dir), before)
  expect_false(plan$applied)
  expect_true(any(grepl("Dry run: nothing was changed", out)))
  expect_setequal(unique(plan$actions$step), c("settings", "connections", "gitignore", "ai", "skills", "spec"))
  expect_true(any(grepl("ehr_source", plan$notes)))
  expect_true(any(grepl("connections.databases.warehouse.password", plan$notes, fixed = TRUE)))
  expect_false(any(grepl("hunter2", c(out, plan$notes))))
  expect_true(any(grepl("notebooks/_quarto.yml", plan$notes, fixed = TRUE)))
})

test_that("upgrade(dry_run = FALSE) applies the plan, backs up, and is idempotent", {
  dir <- local_old_project()
  before <- snapshot(dir)
  res <- suppressMessages(upgrade(dir, dry_run = FALSE))
  expect_true(res$applied)

  # Settings: security and tools added, everything else kept
  settings <- yaml::read_yaml(file.path(dir, "settings.yml"))
  expect_true(settings$default$security$sensitive)
  expect_false(settings$default$tools$renv)
  expect_identical(settings$ehr_source$partner, "north")
  withr::with_dir(dir, expect_true(suppressWarnings(framework:::.fw_project_is_sensitive())))

  # Connections in the current layout, with the default kept
  conns <- yaml::read_yaml(file.path(dir, "settings", "connections.yml"))$connections
  expect_identical(conns$default_database, "warehouse")
  expect_setequal(names(conns$databases), c("warehouse", "framework"))
  cfg <- withr::with_dir(dir, suppressWarnings(settings_read()))
  expect_identical(cfg$connections$default_database, "warehouse")

  # .gitignore: lines appended, none removed
  gitignore <- readLines(file.path(dir, ".gitignore"))
  expect_identical(gitignore[1:3], c("# my rules", ".env", "*.csv"))
  expect_true(all(c("/.quarto/", "**/*.quarto_ipynb", "framework.db") %in% gitignore))

  # AI files: AGENTS.md canonical with the notes, CLAUDE.md a pointer
  agents <- readLines(file.path(dir, "AGENTS.md"))
  expect_true("My notes stay here." %in% agents)
  expect_true("Keep this." %in% agents)
  expect_false("stale list" %in% agents)
  expect_identical(readLines(file.path(dir, "CLAUDE.md")), "@AGENTS.md")
  expect_identical(yaml::read_yaml(file.path(dir, "settings", "ai.yml"))$ai$canonical_file, "AGENTS.md")
  guards <- jsonlite::read_json(file.path(dir, ".claude", "settings.json"))
  expect_true("Read(/inputs/private/**)" %in% unlist(guards$permissions$deny))

  # The old shipped skill is current; the type's other skills are added
  expect_identical(
    readLines(file.path(dir, ".claude", "skills", "framework-data", "SKILL.md")),
    readLines(system.file("templates", "skills", "framework-data", "SKILL.md", package = "framework"))
  )
  expect_true(file.exists(file.path(dir, ".claude", "skills", "framework-sensitive-data", "SKILL.md")))

  # Quarto: custom config untouched while the per-folder project stays
  expect_identical(readLines(file.path(dir, "_quarto.yml"))[1], "# mine")
  expect_true(file.exists(file.path(dir, "notebooks", "_quarto.yml")))

  # The spec, without the password
  spec <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_length(spec_check(spec), 0)
  expect_identical(spec$type, "project_sensitive")
  expect_true(spec$security$sensitive)
  expect_identical(spec$directories$inputs_private_raw, "inputs/private/raw")
  expect_identical(spec$connections$databases$warehouse$password, 'env("WAREHOUSE_PASSWORD")')
  expect_false(grepl("hunter2", paste(readLines(file.path(dir, ".framework", "spec.json")), collapse = "\n")))
  expect_null(spec$source$upgraded_from)
  expect_identical(framework:::.spec_schema_problems(spec), character())

  # Backups of every rewritten file, ignored by git
  backup <- res$backup_location
  expect_true(file.exists(file.path(backup, "settings.yml")))
  expect_identical(readLines(file.path(backup, "CLAUDE.md")), readLines(textConnection(paste(
    c("# Old Study", "", "My notes stay here.", "", "## Installed Packages <!-- @framework:regenerate -->",
      "", "stale list", "", "## Project Notes", "", "Keep this."), collapse = "\n"))))
  expect_true("backups/" %in% readLines(file.path(dir, ".framework", ".gitignore")))
  # Nothing the project had is gone
  expect_true(all(names(before) %in% names(snapshot(dir))))

  again <- suppressMessages(upgrade(dir))
  expect_identical(nrow(again$actions), 0L)
})

test_that("upgrade() renames a 1.x config.yml and refuses a folder that isn't a project", {
  dir <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  directories:", "    notebooks: notebooks"),
             file.path(dir, "config.yml"))
  suppressMessages(upgrade(dir, dry_run = FALSE, backup = FALSE))
  expect_false(file.exists(file.path(dir, "config.yml")))
  expect_identical(yaml::read_yaml(file.path(dir, "settings.yml"))$default$directories$notebooks, "notebooks")
  expect_false(dir.exists(file.path(dir, ".framework", "backups")))
  expect_true(file.exists(file.path(dir, ".framework", "spec.json")))

  other <- withr::local_tempdir()
  writeLines("repositories: {}", file.path(other, "config.yml"))
  expect_error(upgrade(other), "adopt\\(\\)")
})

test_that("upgrade() refreshes a stale spec and keeps its other sections", {
  dir <- withr::local_tempdir()
  spec <- spec_resolve(list(list(type = "project", git = list(use_git = FALSE))), name = "Fresh")
  suppressMessages(project_create(spec, file.path(dir, "p")))
  dir <- file.path(dir, "p")
  expect_identical(nrow(suppressMessages(upgrade(dir))$actions[suppressMessages(upgrade(dir))$actions$step == "spec", ]), 0L)
  settings <- readLines(file.path(dir, "settings.yml"))
  writeLines(sub("    notebooks: notebooks", "    notebooks: analysis", settings, fixed = TRUE),
             file.path(dir, "settings.yml"))
  plan <- suppressMessages(upgrade(dir, dry_run = FALSE))
  expect_true(any(plan$actions$step == "spec" & grepl("directories", plan$actions$change)))
  record <- jsonlite::read_json(file.path(dir, ".framework", "spec.json"))
  expect_identical(record$directories$notebooks, "analysis")
  expect_identical(record$name, "Fresh")
  expect_true(length(record$skills) > 0)
})

test_that("a sensitive project with no skills gets the sensitive-data skill", {
  dir <- local_old_project()
  unlink(file.path(dir, ".claude"), recursive = TRUE)
  plan <- suppressMessages(upgrade(dir))
  skills <- plan$actions[plan$actions$step == "skills", ]
  expect_identical(skills$path, ".claude/skills/framework-sensitive-data")
  expect_true(any(grepl("adds or keeps framework-sensitive-data", plan$notes)))
  suppressMessages(upgrade(dir, dry_run = FALSE))
  expect_true(file.exists(file.path(dir, ".claude", "skills", "framework-sensitive-data", "SKILL.md")))
  expect_false(dir.exists(file.path(dir, ".claude", "skills", "framework-data")))
  expect_identical(nrow(suppressMessages(upgrade(dir))$actions), 0L)

  # No assistants set: .claude/skills all the same
  dir <- local_old_project()
  unlink(file.path(dir, ".claude"), recursive = TRUE)
  writeLines(c("ai:", "  enabled: yes", "  canonical_file: CLAUDE.md"), file.path(dir, "settings", "ai.yml"))
  suppressMessages(upgrade(dir, dry_run = FALSE))
  expect_true(file.exists(file.path(dir, ".claude", "skills", "framework-sensitive-data", "SKILL.md")))
})

test_that("a project that isn't sensitive and has no skills only gets a note", {
  dir <- local_old_project(type = "project")
  unlink(file.path(dir, ".claude"), recursive = TRUE)
  lines <- readLines(file.path(dir, "settings.yml"))
  lines <- lines[!grepl("private|public", lines)]
  writeLines(lines, file.path(dir, "settings.yml"))
  plan <- suppressMessages(upgrade(dir))
  expect_false(any(plan$actions$step == "skills"))
  expect_true(any(grepl("ai_skills_update\\(\\) installs the ones", plan$notes)))
})
