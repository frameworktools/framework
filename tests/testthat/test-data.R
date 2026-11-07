test_that("data_save creates data file and updates database", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create test data
  test_data <- data.frame(x = 1:5, y = letters[1:5])

  # Save as CSV using direct path (force = TRUE to create directory structure)
  suppressMessages(data_save(test_data, "outputs/public/sample.csv", force = TRUE))

  # Check file was created
  expect_true(file.exists("outputs/public/sample.csv"))

  # Check database record was created
  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  record <- DBI::dbGetQuery(conn, "SELECT * FROM data WHERE name = 'outputs/public/sample.csv'")
  expect_equal(nrow(record), 1)
  expect_equal(record$type, "csv")
  expect_false(is.na(record$hash))
})

test_that("data_save creates RDS files", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  test_data <- data.frame(x = 1:5, y = letters[1:5])

  # Use direct path for RDS file
  suppressMessages(data_save(test_data, "outputs/private/rds_data.rds", force = TRUE))

  expect_true(file.exists("outputs/private/rds_data.rds"))
})

test_that("data_read reads saved CSV data", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create directory and save test data using direct path
  dir.create("inputs/raw", recursive = TRUE, showWarnings = FALSE)
  original_data <- data.frame(x = 1:5, y = letters[1:5])
  suppressMessages(data_save(original_data, "inputs/raw/csv_load.csv"))

  # Add to config for catalog lookup
  config <- settings_read()
  config$data$inputs <- list(
    raw = list(
      csv_load = list(
        path = "inputs/raw/csv_load.csv",
        type = "csv",
        delimiter = "comma",
        locked = FALSE,
        encrypted = FALSE
      )
    )
  )
  settings_write(config)

  # Load it back using catalog name
  loaded_data <- suppressWarnings(data_read("inputs.raw.csv_load"))

  expect_equal(nrow(loaded_data), 5)
  expect_equal(loaded_data$x, 1:5)
})

test_that("data_read reads saved RDS data", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create directory and save test data using direct path
  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)
  original_data <- data.frame(x = 1:5, y = letters[1:5])
  suppressMessages(data_save(original_data, "inputs/intermediate/rds_load.rds"))

  # Add to config for catalog lookup
  config <- settings_read()
  config$data$inputs <- list(
    intermediate = list(
      rds_load = list(
        path = "inputs/intermediate/rds_load.rds",
        type = "rds",
        locked = FALSE,
        encrypted = FALSE
      )
    )
  )
  settings_write(config)

  # Load it back using catalog name
  loaded_data <- suppressWarnings(data_read("inputs.intermediate.rds_load"))

  expect_equal(loaded_data, original_data)
})

test_that("data_read reads direct file paths", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a CSV file directly
  dir.create("data/direct", recursive = TRUE)
  test_data <- data.frame(a = 1:3, b = 4:6)
  write.csv(test_data, "data/direct/file.csv", row.names = FALSE)

  # Load using direct path
  loaded <- data_read("data/direct/file.csv")

  expect_equal(nrow(loaded), 3)
  expect_true("a" %in% names(loaded))
})

test_that("data_read fails for non-existent file", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  expect_error(data_read("nonexistent.file.csv"))
})

test_that("data_spec_get retrieves data specification from config", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  config <- settings_read()
  config$data$inputs <- list(
    raw = list(
      test = list(
        path = "inputs/raw/test.csv",
        type = "csv",
        delimiter = "comma"
      )
    )
  )
  settings_write(config)

  spec <- data_spec_get("inputs.raw.test")

  expect_type(spec, "list")
  # Path is normalized to absolute, so check it ends with the expected relative path
  expect_true(endsWith(spec$path, "inputs/raw/test.csv"))
  expect_equal(spec$type, "csv")
  expect_equal(spec$delimiter, "comma")
})

test_that("data_read reads Excel files directly", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create an Excel file
  dir.create("data/excel", recursive = TRUE)
  test_data <- data.frame(x = 1:5, y = letters[1:5], z = 10:14)
  writexl::write_xlsx(test_data, "data/excel/test.xlsx")

  # Load using direct path
  loaded <- data_read("data/excel/test.xlsx")

  expect_equal(nrow(loaded), 5)
  expect_equal(loaded$x, 1:5)
  expect_equal(loaded$y, letters[1:5])
  expect_equal(loaded$z, 10:14)
})

test_that("data_read reads Excel files from config", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("writexl")
  
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create an Excel file
  dir.create("inputs/raw", recursive = TRUE)
  test_data <- data.frame(name = c("Alice", "Bob"), age = c(25, 30))
  writexl::write_xlsx(test_data, "inputs/raw/people.xlsx")

  # Add to config
  config <- settings_read()
  config$data$inputs <- list(
     raw = list(
      people = list(
        path = "inputs/raw/people.xlsx",
        type = "excel",
        locked = FALSE,
        encrypted = FALSE
      )
    )
  )
  settings_write(config)

  # Load it back
  loaded <- suppressWarnings(data_read("inputs.raw.people"))

  expect_equal(nrow(loaded), 2)
  expect_equal(loaded$name, c("Alice", "Bob"))
  expect_equal(loaded$age, c(25, 30))
})

test_that("data_spec_get detects Excel file type", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a fake Excel file
  dir.create("data/excel", recursive = TRUE)
  file.create("data/excel/test.xlsx")

  # Get spec by direct path
  spec <- data_spec_get("data/excel/test.xlsx")

  expect_equal(spec$type, "excel")
  expect_null(spec$delimiter)
})

# New path resolution tests
test_that("data_save resolves dot notation to configured directories", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create inputs/intermediate directory
  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)

  # Create test data
  test_data <- data.frame(x = 1:5, y = letters[1:5])

  # Save using 3-part dot notation (inputs.intermediate.filename)
  suppressMessages(data_save(test_data, "inputs.intermediate.test_file"))

  # Should resolve to inputs/intermediate/test_file.rds
  expect_true(file.exists("inputs/intermediate/test_file.rds"))
})

test_that("data_save accepts direct file paths", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create directory
  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)

  # Create test data
  test_data <- data.frame(x = 1:5, y = letters[1:5])

  # Save using direct path
  suppressMessages(data_save(test_data, "inputs/intermediate/direct_path.csv"))

  # Should save to exact path
  expect_true(file.exists("inputs/intermediate/direct_path.csv"))
})

test_that("data_save auto-detects type from file extension", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)
  test_data <- data.frame(x = 1:5)

  # CSV extension
  suppressMessages(data_save(test_data, "inputs/intermediate/file1.csv"))
  expect_true(file.exists("inputs/intermediate/file1.csv"))

  # RDS extension
  suppressMessages(data_save(test_data, "inputs/intermediate/file2.rds"))
  expect_true(file.exists("inputs/intermediate/file2.rds"))
})

test_that("data_save errors when directory doesn't exist without force", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  test_data <- data.frame(x = 1:5)

  # Should error because inputs/nonexistent doesn't exist
  expect_error(
    data_save(test_data, "inputs/nonexistent/file.csv"),
    "Directory.*does not exist.*force = TRUE"
  )
})

test_that("data_save creates directory with force = TRUE", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  test_data <- data.frame(x = 1:5)

  # Should create directory and save
  suppressMessages(
    data_save(test_data, "inputs/new_dir/file.rds", force = TRUE)
  )

  expect_true(dir.exists("inputs/new_dir"))
  expect_true(file.exists("inputs/new_dir/file.rds"))
})

test_that("data_save errors for simple filename without directory", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  test_data <- data.frame(x = 1:5)

  # Should error - no directory specified
  expect_error(
    data_save(test_data, "just_a_filename"),
    "has no directory.*dot notation.*path from the project root"
  )
})

test_that("data_save updates database with normalized name", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)
  test_data <- data.frame(x = 1:5)

  # Save with 3-part dot notation
  suppressMessages(data_save(test_data, "inputs.intermediate.my_data"))

  # Check database record uses original path as name
  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  record <- DBI::dbGetQuery(conn, "SELECT * FROM data WHERE name = 'inputs.intermediate.my_data'")
  expect_equal(nrow(record), 1)
  # Path may be absolute or relative depending on the platform, and may use backslashes on Windows
  path_normalized <- gsub("\\\\", "/", record$path)
  expect_true(grepl("inputs/intermediate/my_data\\.rds$", path_normalized))
  expect_equal(record$type, "rds")
})

# data_add tests
test_that("data_add registers existing CSV file", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a CSV file manually (simulating external data)
  dir.create("inputs/raw", recursive = TRUE, showWarnings = FALSE)
  test_data <- data.frame(x = 1:5, y = letters[1:5])
  write.csv(test_data, "inputs/raw/external_data.csv", row.names = FALSE)

  # Add it to the catalog
  suppressMessages(
    data_add("inputs/raw/external_data.csv", name = "raw.external_data")
  )

  # Check database record was created
  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  record <- DBI::dbGetQuery(conn, "SELECT * FROM data WHERE name = 'raw.external_data'")
  expect_equal(nrow(record), 1)
  expect_equal(record$type, "csv")
  expect_false(is.na(record$hash))
})

test_that("data_add auto-detects file type from extension", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create an RDS file manually
  dir.create("inputs/intermediate", recursive = TRUE, showWarnings = FALSE)
  test_data <- data.frame(x = 1:5)
  saveRDS(test_data, "inputs/intermediate/processed.rds")

  # Add without specifying type
  suppressMessages(
    data_add("inputs/intermediate/processed.rds", name = "intermediate.processed")
  )

  # Check type was auto-detected
  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  record <- DBI::dbGetQuery(conn, "SELECT * FROM data WHERE name = 'intermediate.processed'")
  expect_equal(record$type, "rds")
})

test_that("data_add errors for non-existent file", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  expect_error(
    data_add("nonexistent/file.csv", name = "test.data"),
    "File not found"
  )
})

test_that("data_add allows reading via data_read after registration", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a CSV file
  dir.create("inputs/raw", recursive = TRUE, showWarnings = FALSE)
  original_data <- data.frame(a = 1:3, b = c("x", "y", "z"))
  write.csv(original_data, "inputs/raw/readable.csv", row.names = FALSE)

  # Register with data_add
  suppressMessages(
    data_add("inputs/raw/readable.csv", name = "raw.readable")
  )

  # Now read it using data_read with dot notation
  loaded <- suppressWarnings(data_read("raw.readable"))

  expect_equal(nrow(loaded), 3)
  expect_equal(loaded$a, 1:3)
})

test_that("data_add respects locked parameter", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  dir.create("inputs/raw", recursive = TRUE, showWarnings = FALSE)
  write.csv(data.frame(x = 1), "inputs/raw/locked.csv", row.names = FALSE)

  # Add with locked = FALSE
  suppressMessages(
    data_add("inputs/raw/locked.csv", name = "raw.locked_file", locked = FALSE)
  )

  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  record <- DBI::dbGetQuery(conn, "SELECT * FROM data WHERE name = 'raw.locked_file'")
  expect_equal(record$locked, 0)  # SQLite stores FALSE as 0
})

test_that("data_add can skip config update", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  dir.create("inputs/raw", recursive = TRUE, showWarnings = FALSE)
  write.csv(data.frame(x = 1), "inputs/raw/no_config.csv", row.names = FALSE)

  # Add without updating config
  suppressMessages(
    data_add("inputs/raw/no_config.csv", name = "raw.no_config", update_config = FALSE)
  )

  # Database should have record
  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  record <- DBI::dbGetQuery(conn, "SELECT * FROM data WHERE name = 'raw.no_config'")
  expect_equal(nrow(record), 1)

  # But config should NOT have the spec
  spec <- tryCatch(data_spec_get("raw.no_config"), error = function(e) NULL)
  expect_null(spec)
})

test_that("data_add records project-relative paths, even from a subfolder", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })
  setwd(test_dir)
  dir.create("inputs/raw", recursive = TRUE, showWarnings = FALSE)
  write.csv(data.frame(x = 1), "inputs/raw/moved.csv", row.names = FALSE)
  dir.create("notebooks", showWarnings = FALSE)
  setwd("notebooks")

  spec <- suppressMessages(data_add(file.path(test_dir, "inputs/raw/moved.csv"), name = "raw.moved"))
  expect_identical(spec$path, "inputs/raw/moved.csv")
})

test_that("data_add() names files in any configured inputs directory", {
  test_dir <- create_test_project()
  withr::defer(cleanup_test_dir(test_dir))
  withr::local_dir(test_dir)
  settings <- yaml::read_yaml("settings.yml")
  settings$default$directories$inputs_private_raw <- "inputs/private/raw"
  settings$default$directories$inputs_public_final <- "inputs/public/final"
  yaml::write_yaml(settings, "settings.yml")
  for (d in c("inputs/raw", "inputs/private/raw", "inputs/public/final")) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  write.csv(data.frame(x = 1), "inputs/private/raw/participants.csv", row.names = FALSE)
  write.csv(data.frame(x = 1), "inputs/public/final/summary.csv", row.names = FALSE)
  write.csv(data.frame(x = 1), "inputs/raw/visits.csv", row.names = FALSE)

  suppressMessages(data_add("inputs/private/raw/participants.csv"))
  suppressMessages(data_add("inputs/public/final/summary.csv"))
  suppressMessages(data_add("inputs/raw/visits.csv"))

  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  names <- DBI::dbGetQuery(conn, "SELECT name FROM data")$name
  expect_setequal(names, c("inputs.private.raw.participants", "inputs.public.final.summary", "inputs.raw.visits"))
})

test_that("data_save() records a path in one clean project-relative form", {
  test_dir <- create_test_project()
  withr::defer(cleanup_test_dir(test_dir))
  withr::local_dir(test_dir)

  df <- data.frame(x = 1:3)
  suppressMessages(data_save(df, "./outputs/public/bp_preview.csv"))
  suppressMessages(data_save(df, "outputs//public/./bp_preview.csv"))
  suppressMessages(data_save(df, "outputs/private/../public/bp_preview.csv"))

  conn <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(conn), add = TRUE)
  names <- DBI::dbGetQuery(conn, "SELECT name FROM data")$name
  expect_identical(names, "outputs/public/bp_preview.csv")

  expect_message(data_verify("./outputs/public/bp_preview.csv"), "matches local framework.db record")
  withr::with_dir("notebooks", {
    expect_message(data_verify("outputs/public/bp_preview.csv"), "matches local framework.db record")
  })
})

test_that(".fw_lexical_path() resolves . and .. without the disk", {
  lexical <- framework:::.fw_lexical_path
  expect_identical(lexical("./a/b.csv"), "a/b.csv")
  expect_identical(lexical("a/./b/../c.csv"), "a/c.csv")
  expect_identical(lexical("a\\b\\c.csv"), "a/b/c.csv")
  expect_identical(lexical("../x.csv"), "../x.csv")
  expect_identical(lexical("/a/../../b"), "/b")
  expect_identical(lexical("C:/a/./b"), "C:/a/b")
})
