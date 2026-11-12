test_that(".ai_skills_for_type returns correct skills per project type", {
  base <- c("framework-workflow", "framework-data", "framework-packages", "framework-outputs")
  figures <- c("ggplot2-exploring", "ggplot2-publishing")

  expect_equal(.ai_skills_for_type("project"), c(base, figures))
  expect_equal(.ai_skills_for_type("course"), c(base, figures))
  expect_equal(.ai_skills_for_type("presentation"), c(base, figures))
  expect_equal(
    .ai_skills_for_type("project_sensitive"),
    c(base, "framework-sensitive-data", figures)
  )
})

test_that("shipped skills declare their name and a readable title", {
  dir <- system.file("templates", "skills", package = "framework")
  for (skill in list.files(dir)) {
    lines <- readLines(file.path(dir, skill, "SKILL.md"), warn = FALSE)
    ends <- which(lines == "---")
    meta <- yaml::yaml.load(paste(lines[(ends[1] + 1):(ends[2] - 1)], collapse = "\n"))
    expect_identical(meta$name, skill)
    expect_true(is.character(meta$description) && nzchar(meta$description), info = skill)
    expect_true(is.character(meta$metadata$title) && nzchar(meta$metadata$title), info = skill)
  }
})


test_that(".ai_install_skills installs skill files", {
  skip_on_cran()

  test_dir <- file.path(tempdir(), "test-skills-install")
  dir.create(test_dir, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(test_dir, recursive = TRUE))

  installed <- suppressMessages(.ai_install_skills(test_dir, "project"))

  expect_true("framework-workflow" %in% installed)
  expect_false("framework-sensitive-data" %in% installed)

  for (skill in installed) {
    skill_file <- file.path(test_dir, ".claude", "skills", skill, "SKILL.md")
    expect_true(file.exists(skill_file))

    content <- readLines(skill_file, warn = FALSE)
    expect_equal(content[1], "---")
    expect_true(any(grepl(paste0("^name: ", skill, "$"), content)))
    expect_true(any(grepl("^description: ", content)))
  }
})


test_that(".ai_install_skills includes sensitive-data skill for sensitive projects", {
  skip_on_cran()

  test_dir <- file.path(tempdir(), "test-skills-sensitive")
  dir.create(test_dir, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(test_dir, recursive = TRUE))

  installed <- suppressMessages(.ai_install_skills(test_dir, "project_sensitive"))

  expect_true("framework-sensitive-data" %in% installed)
  expect_true(file.exists(
    file.path(test_dir, ".claude", "skills", "framework-sensitive-data", "SKILL.md")
  ))
})


test_that("ai_skills_update refreshes skills using project settings", {
  skip_on_cran()
  withr::local_envvar(FW_PROJECT_TOKEN = "")
  test_dir <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude]"),
             file.path(test_dir, "settings.yml"))

  result <- suppressMessages(ai_skills_update(test_dir))
  expect_identical(result$source, "package")
  expect_true(result$counts$added >= 4)

  # Local edits survive package updates
  skill_file <- file.path(test_dir, ".claude", "skills", "framework-data", "SKILL.md")
  writeLines("stale content", skill_file)
  suppressMessages(ai_skills_update(test_dir))
  expect_identical(readLines(skill_file, warn = FALSE), "stale content")
})


test_that(".generate_skills_section lists skills with paths", {
  section <- .generate_skills_section("project_sensitive")

  expect_true(grepl("framework-workflow", section))
  expect_true(grepl("framework-sensitive-data", section))
  expect_true(grepl(".claude/skills/framework-data/SKILL.md", section, fixed = TRUE))
})


test_that("ai_skills_update() reports what it actually did", {
  skip_on_cran()
  withr::local_envvar(FW_PROJECT_TOKEN = "")
  test_dir <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude]"),
             file.path(test_dir, "settings.yml"))

  first <- capture.output(result <- ai_skills_update(test_dir), type = "message")
  n <- result$counts$added
  expect_match(first[1], "Framework Cloud not reached (no project token); using the package skills", fixed = TRUE)
  expect_identical(tail(first, 1), sprintf("Skills: %d added", n))

  again <- capture.output(ai_skills_update(test_dir), type = "message")
  expect_identical(tail(again, 1), sprintf("Skills: %d up to date", n))

  writeLines("my edits", file.path(test_dir, ".claude", "skills", "framework-data", "SKILL.md"))
  edited <- capture.output(ai_skills_update(test_dir), type = "message")
  expect_true(sprintf("Skills: %d up to date, 1 locally edited (kept)", n - 1L) %in% edited)
  expect_true(any(grepl("Kept (locally edited): framework-data", edited, fixed = TRUE)))
})

test_that("a skill from an older release without a lock entry is updated, not kept", {
  test_dir <- withr::local_tempdir()
  withr::local_envvar(FW_PROJECT_TOKEN = "")
  writeLines(c("default:", "  project_type: project", "  ai:", "    assistants: [claude]"),
             file.path(test_dir, "settings.yml"))
  old <- testthat::test_path("skill-fixtures", "framework-data-SKILL-6f2521a.md")
  for (skill in c("framework-data", "framework-outputs")) {
    dir.create(file.path(test_dir, ".claude", "skills", skill), recursive = TRUE)
  }
  file.copy(old, file.path(test_dir, ".claude", "skills", "framework-data", "SKILL.md"))
  # The same old version with a local edit stays
  writeLines(c(readLines(old), "", "Our lab's note."),
             file.path(test_dir, ".claude", "skills", "framework-outputs", "SKILL.md"))
  expect_false(file.exists(file.path(test_dir, ".framework", "skills.lock.json")))

  status <- framework:::.skill_package_status(
    system.file("templates", "skills", "framework-data", package = "framework"),
    test_dir, ".claude/skills/framework-data", "framework-data"
  )
  expect_identical(status, "update")

  out <- capture.output(result <- ai_skills_update(test_dir), type = "message")
  statuses <- setNames(vapply(result$skills, `[[`, "", "status"), vapply(result$skills, `[[`, "", "name"))
  expect_identical(statuses[["framework-data"]], "updated")
  expect_identical(statuses[["framework-outputs"]], "edited")
  current <- system.file("templates", "skills", "framework-data", "SKILL.md", package = "framework")
  expect_identical(readLines(file.path(test_dir, ".claude", "skills", "framework-data", "SKILL.md")),
                   readLines(current))
  # Now in the lock, and backed up where git doesn't look
  lock <- jsonlite::read_json(file.path(test_dir, ".framework", "skills.lock.json"))
  expect_true(any(vapply(lock$skills, function(e) ".claude/skills/framework-data" %in% unlist(e$paths), logical(1))))
  expect_length(list.files(file.path(test_dir, ".framework", "skills-backups")), 1)
})

test_that("ai_regenerate_context() without a context file says how to create one", {
  dir <- withr::local_tempdir()
  writeLines(c("default:", "  project_type: project"), file.path(dir, "settings.yml"))
  expect_error(ai_regenerate_context(dir), "ai_generate_context")
})
