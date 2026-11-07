test_that("cache stores and retrieves values", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  test_value <- data.frame(x = 1:10, y = letters[1:10])

  # Cache the value
  suppressMessages(cache("test_cache", test_value))

  # Retrieve it
  retrieved <- suppressMessages(cache_get("test_cache"))

  expect_equal(retrieved, test_value)
})

test_that("cache_get returns NULL for non-existent cache", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  result <- suppressMessages(cache_get("nonexistent_cache"))

  expect_null(result)
})

test_that("cache_forget removes cached value", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Cache a value
  suppressMessages(cache("test_forget", "some value"))

  # Verify it exists
  expect_false(is.null(suppressMessages(cache_get("test_forget"))))

  # Forget it
  suppressMessages(cache_forget("test_forget"))

  # Verify it's gone
  expect_null(suppressMessages(cache_get("test_forget")))
})

test_that("cache_flush removes all cached values", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Cache multiple values
  suppressMessages(cache("cache1", "value1"))
  suppressMessages(cache("cache2", "value2"))
  suppressMessages(cache("cache3", "value3"))

  # Verify they exist
  expect_false(is.null(suppressMessages(cache_get("cache1"))))
  expect_false(is.null(suppressMessages(cache_get("cache2"))))

  # Flush all
  suppressMessages(cache_flush())

  # Verify they're all gone
  expect_null(suppressMessages(cache_get("cache1")))
  expect_null(suppressMessages(cache_get("cache2")))
  expect_null(suppressMessages(cache_get("cache3")))
})

test_that("cache_remember caches computation result", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create a file to track execution count
  counter_file <- tempfile()
  writeLines("0", counter_file)

  # First call should execute and cache
  result1 <- suppressMessages(cache_remember("test_compute", {
    count <- as.integer(readLines(counter_file))
    writeLines(as.character(count + 1), counter_file)
    Sys.sleep(0.1)
    42
  }))

  expect_equal(result1, 42)
  expect_equal(as.integer(readLines(counter_file)), 1)

  # Second call should use cache (counter won't increment)
  result2 <- suppressMessages(cache_remember("test_compute", {
    count <- as.integer(readLines(counter_file))
    writeLines(as.character(count + 1), counter_file)
    99
  }))

  expect_equal(result2, 42)  # Should still be cached value
  expect_equal(as.integer(readLines(counter_file)), 1)  # Expression shouldn't have run again

  unlink(counter_file)
})

test_that("cache_remember with refresh=TRUE recomputes", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # First call
  result1 <- suppressMessages(cache_remember("test_refresh", {
    42
  }))

  expect_equal(result1, 42)

  # Second call with refresh
  result2 <- suppressMessages(cache_remember("test_refresh", {
    99
  }, refresh = TRUE))

  expect_equal(result2, 99)  # Should be new value
})

test_that("cache stores complex R objects", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Test with list
  complex_obj <- list(
    data = data.frame(a = 1:5),
    nested = list(x = "test", y = c(1, 2, 3)),
    number = 42
  )

  suppressMessages(cache("complex", complex_obj))
  retrieved <- suppressMessages(cache_get("complex"))

  expect_equal(retrieved, complex_obj)
})

test_that("cache with custom file path", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })

  setwd(test_dir)

  # Create custom cache directory
  dir.create("custom_cache", recursive = TRUE)

  # Cache with custom path
  suppressMessages(cache("custom_file", "test value", file = "custom_cache/my_cache.rds"))

  # Verify file exists
  expect_true(file.exists("custom_cache/my_cache.rds"))

  # Retrieve using same custom path
  retrieved <- suppressMessages(cache_get("custom_file", file = "custom_cache/my_cache.rds"))
  expect_equal(retrieved, "test value")
})

test_that("cache() records the cache file path relative to the project", {
  test_dir <- create_test_project()
  old_wd <- getwd()
  on.exit({
    setwd(old_wd)
    cleanup_test_dir(test_dir)
  })
  setwd(test_dir)
  suppressMessages(cache("pathed", 1:3))
  con <- DBI::dbConnect(RSQLite::SQLite(), "framework.db")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  row <- DBI::dbGetQuery(con, "SELECT file_path FROM cache WHERE name = 'pathed'")
  expect_false(startsWith(row$file_path, "/"))
  expect_match(row$file_path, "pathed\\.rds$")
})

test_that("expire_after accepts minutes and seconds as well as hours, days, and weeks", {
  norm <- framework:::.normalize_expire_after
  expect_equal(norm("30 minutes"), 0.5)
  expect_equal(norm("15 min"), 0.25)
  expect_equal(norm("1 minute"), 1 / 60)
  expect_equal(norm("90 seconds"), 90 / 3600)
  expect_equal(norm("2 hours"), 2)
  expect_equal(norm("1 day"), 24)
  expect_equal(norm("1 week"), 168)
  expect_error(norm("3 fortnights"), "30 minutes")
})
