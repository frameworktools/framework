# Settings writes change only the section they mean to change

flat_settings <- c(
  "# Course settings, edited by hand",
  "default:",
  "  project_name: demo",
  "  project_type: course",
  "  directories:",
  "    data: data",
  "  ai:",
  "    enabled: true",
  "    assistants: [claude]",
  "  # The catalog",
  "  data: []",
  "",
  "  # Shared, read-only study database",
  "  connections:",
  "    default_database: framework",
  "    databases:",
  "      framework:",
  "        driver: sqlite",
  "        database: framework.db",
  "      study:",
  "        driver: sqlite",
  "        database: ../study.sqlite",
  "        read_only: true",
  "  packages:",
  "    use_renv: false",
  "    default_packages: []"
)

local_flat_project <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  writeLines(flat_settings, "settings.yml")
  dir.create("data")
  framework:::.ensure_framework_db(dir)
  dir
}

# Lines of `after` outside the block that starts with `key` in `before`
outside_block <- function(lines, key) {
  start <- grep(paste0("^  ", key, ":"), lines)
  end <- start + 1
  while (end <= length(lines) && grepl("^(    |\\s*$)", lines[end]) && !grepl("^\\s*$", lines[end])) end <- end + 1
  lines[-(start:(end - 1))]
}

test_that("data_save() in a flat settings.yml rewrites only the data block", {
  local_flat_project()
  suppressMessages(data_save(data.frame(x = 1:2), "data.bp.csv"))
  after <- readLines("settings.yml")
  expect_identical(outside_block(after, "data"), outside_block(flat_settings, "data"))
  expect_true("    assistants: [claude]" %in% after)
  expect_true("        read_only: true" %in% after)
  expect_true("# Course settings, edited by hand" %in% after)
  catalog <- yaml::read_yaml("settings.yml")$default$data
  expect_identical(catalog$data$bp$path, "data/bp.csv")
  expect_identical(catalog$data$bp$locked, TRUE)
})

test_that("settings writes keep sequences and write true/false", {
  f <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("ai:", "  assistants: [claude]", "  enabled: yes", "seed: !expr 1 + 1"), f)
  x <- framework:::.fw_read_yaml(f)
  out <- framework:::.fw_as_yaml(x)
  expect_match(out, "assistants:\n  - claude", fixed = TRUE)
  expect_match(out, "enabled: true", fixed = TRUE)
  expect_match(out, "seed: !expr 1 + 1", fixed = TRUE)
  expect_false(grepl("\\byes\\b", out))
})

test_that("settings_write(section =) and project_add_directory() leave other lines alone", {
  dir <- local_flat_project()
  suppressMessages(settings_write(list(enabled = FALSE, assistants = list("claude", "copilot")), section = "ai"))
  after <- readLines("settings.yml")
  expect_identical(outside_block(after, "ai"), outside_block(flat_settings, "ai"))
  expect_identical(yaml::read_yaml("settings.yml")$default$ai$assistants, c("claude", "copilot"))
  expect_true("    enabled: false" %in% after)

  result <- project_add_directory(dir, "maps", "Maps", "maps")
  expect_true(result$success)
  after <- readLines("settings.yml")
  expect_true("# Course settings, edited by hand" %in% after)
  expect_true("  # Shared, read-only study database" %in% after)
  expect_identical(yaml::read_yaml("settings.yml")$default$extra_directories[[1]]$path, "maps")
})

test_that("a block that can't be edited in place falls back to a whole-file write", {
  f <- withr::local_tempfile(fileext = ".yml")
  writeLines("default: {data: [], name: x}", f)
  framework:::.fw_yaml_set(f, c("default", "data"), list(a = list(path = "a.csv")))
  expect_identical(yaml::read_yaml(f)$default$data$a$path, "a.csv")
  expect_identical(yaml::read_yaml(f)$default$name, "x")
})

test_that("a missing key is added at the end of its section", {
  f <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("default:", "  name: x  # keep", "other:", "  y: 1"), f)
  framework:::.fw_yaml_set(f, c("default", "data"), list(a = list(path = "a.csv")))
  lines <- readLines(f)
  expect_identical(lines[1:2], c("default:", "  name: x  # keep"))
  expect_identical(lines[3], "  data:")
  expect_identical(tail(lines, 2), c("other:", "  y: 1"))
})

test_that("formatting elsewhere in the file doesn't force a whole-file rewrite", {
  f <- withr::local_tempfile(fileext = ".yml")
  lines <- c("# keep me", "default:", "  alpha: 0.123456789123", "  quoted: 'x'",
             "  flag: yes", "  data: []")
  writeLines(lines, f)
  framework:::.fw_yaml_set(f, c("default", "data"), list(a = list(path = "a.csv")))
  after <- readLines(f)
  expect_identical(after[1:5], lines[1:5])
  expect_identical(yaml::read_yaml(f)$default$data$a$path, "a.csv")
})
