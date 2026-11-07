test_that("project_path() joins parts under the project root from any folder", {
  test_dir <- create_test_project()
  on.exit(cleanup_test_dir(test_dir), add = TRUE)
  root <- normalizePath(test_dir, winslash = "/")
  withr::local_dir(file.path(test_dir, "notebooks"))

  expect_equal(project_path(), root)
  expect_equal(project_path("outputs/tables", "x.csv"), paste0(root, "/outputs/tables/x.csv"))
  expect_equal(project_path("outputs", "tables", "x.csv"), paste0(root, "/outputs/tables/x.csv"))
  expect_type(project_path("a"), "character")
  expect_false(file.exists(project_path("outputs/tables/x.csv")))

  withr::local_dir(test_dir)
  expect_equal(project_path("outputs/tables", "x.csv"), paste0(root, "/outputs/tables/x.csv"))
})

test_that("project_path() refuses absolute and rooted parts", {
  test_dir <- create_test_project()
  on.exit(cleanup_test_dir(test_dir), add = TRUE)
  withr::local_dir(test_dir)

  for (part in c("/etc", "C:/data", "C:\\data", "C:data", "\\data", "~/x")) {
    expect_error(project_path("outputs", part), "project_path() parts are relative to the project root", fixed = TRUE)
  }
  expect_error(project_path(c("a", "b")), "single character strings")
})

test_that("project_path() outside a project is an error", {
  outside <- tempfile("no_project_")
  dir.create(outside)
  on.exit(unlink(outside, recursive = TRUE), add = TRUE)
  withr::local_dir(outside)
  skip_if(!is.null(.find_project_root(outside)), "a temp folder is inside a project")

  expect_error(project_path("x.csv"), "No Framework project found at or above", fixed = TRUE)
})
