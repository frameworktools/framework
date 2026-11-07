# Skip all global config tests on CRAN - they write to user config directory
# and require proper isolation via FW_CONFIG_HOME

test_that("configure_global reads current config when no settings provided", {
  skip_on_cran()

  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Call without settings - should return defaults
  result <- configure_global()

  expect_true(is.list(result))
  expect_true(!is.null(result$author))
  expect_true(!is.null(result$defaults))
})


test_that("configure_global updates author information", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Update author
  result <- configure_global(settings = list(
    author = list(
      name = "Test User",
      email = "test@example.com",
      affiliation = "Test Org"
    )
  ))

  expect_equal(result$author$name, "Test User")
  expect_equal(result$author$email, "test@example.com")
  expect_equal(result$author$affiliation, "Test Org")

  # Verify file was written
  settings_path <- file.path(fw_config_dir(), "settings.yml")
  expect_true(file.exists(settings_path))

  # Read back and verify
  saved <- read_frameworkrc()
  expect_equal(saved$author$name, "Test User")
})


test_that("configure_global updates defaults", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Update defaults
  result <- configure_global(settings = list(
    defaults = list(
      project_type = "presentation",
      notebook_format = "rmarkdown",
      ide = "rstudio",
      use_git = FALSE,
      seed = 12345
    )
  ))

  expect_equal(result$defaults$project_type, "presentation")
  expect_equal(result$defaults$notebook_format, "rmarkdown")
  expect_equal(result$defaults$ide, "rstudio")
  expect_false(result$defaults$use_git)
  expect_equal(result$defaults$seed, 12345)
})


test_that("configure_global validates project_type choices", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Invalid project type should error
  expect_error(
    configure_global(settings = list(
      defaults = list(project_type = "invalid")
    )),
    "project_type"
  )
})


test_that("configure_global validates notebook_format choices", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Invalid format should error
  expect_error(
    configure_global(settings = list(
      defaults = list(notebook_format = "invalid")
    )),
    "notebook_format"
  )
})


test_that("configure_global validates IDE choices", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Invalid IDE should error
  expect_error(
    configure_global(settings = list(
      defaults = list(ide = "invalid")
    )),
    "ide"
  )
})


test_that("configure_global validates boolean flags", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Invalid boolean should error
  expect_error(
    configure_global(settings = list(
      defaults = list(use_git = "yes")  # should be logical
    )),
    "flag"
  )
})


test_that("configure_global accepts numeric or character seed", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Numeric seed
  result1 <- configure_global(settings = list(
    defaults = list(seed = 12345)
  ))
  expect_equal(result1$defaults$seed, 12345)

  # Character seed
  result2 <- configure_global(settings = list(
    defaults = list(seed = "20250102")
  ))
  expect_equal(result2$defaults$seed, "20250102")
})


test_that("configure_global performs deep merge", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Set author first
  configure_global(settings = list(
    author = list(
      name = "First User",
      email = "first@example.com"
    )
  ))

  # Update just email - name should remain
  result <- configure_global(settings = list(
    author = list(
      email = "updated@example.com"
    )
  ))

  expect_equal(result$author$name, "First User")  # unchanged
  expect_equal(result$author$email, "updated@example.com")  # updated
})


test_that("configure_global can skip validation", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Should not error even with invalid data when validate = FALSE
  expect_no_error(
    suppressMessages(
      configure_global(
        settings = list(
          defaults = list(project_type = "invalid")
        ),
        validate = FALSE
      )
    )
  )
})


test_that("configure_global writes YAML format", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  configure_global(settings = list(
    author = list(name = "Test User")
  ))

  settings_path <- file.path(fw_config_dir(), "settings.yml")
  expect_true(file.exists(settings_path))

  # Should be valid YAML
  yaml_content <- yaml::read_yaml(settings_path)
  expect_true(is.list(yaml_content))
  expect_equal(yaml_content$author$name, "Test User")
})


# Tests for extra_directories validation

test_that("configure_global accepts valid extra_directories", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Valid extra_directories
  result <- configure_global(settings = list(
    project_types = list(
      project = list(
        extra_directories = list(
          list(key = "inputs_archive", label = "Archive", path = "inputs/archive", type = "input"),
          list(key = "outputs_animations", label = "Animations", path = "outputs/animations", type = "output")
        )
      )
    )
  ))

  expect_equal(length(result$project_types$project$extra_directories), 2)
  expect_equal(result$project_types$project$extra_directories[[1]]$key, "inputs_archive")
  expect_equal(result$project_types$project$extra_directories[[2]]$type, "output")
})


test_that("configure_global rejects extra_directories with missing fields", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Missing 'key' field
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(label = "Archive", path = "inputs/archive", type = "input")
          )
        )
      )
    )),
    "missing required field 'key'"
  )

  # Missing 'type' field
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "test", label = "Test", path = "test")
          )
        )
      )
    )),
    "missing required field 'type'"
  )
})


test_that("configure_global rejects invalid extra_directories key format", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Key with hyphen (invalid)
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "my-dir", label = "My Dir", path = "my-dir", type = "input")
          )
        )
      )
    )),
    "must contain only letters, numbers, and underscores"
  )

  # Key with space (invalid)
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "my dir", label = "My Dir", path = "mydir", type = "input")
          )
        )
      )
    )),
    "must contain only letters, numbers, and underscores"
  )
})


test_that("configure_global rejects duplicate extra_directories keys", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Duplicate keys
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "test_dir", label = "Test 1", path = "test1", type = "input"),
            list(key = "test_dir", label = "Test 2", path = "test2", type = "input")
          )
        )
      )
    )),
    "duplicate extra_directories key 'test_dir'"
  )
})


test_that("configure_global rejects invalid extra_directories type", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Invalid type
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "test", label = "Test", path = "test", type = "invalid")
          )
        )
      )
    )),
    "type 'invalid' must be one of: input, workspace, output"
  )
})


test_that("configure_global rejects absolute paths in extra_directories", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Absolute path
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "test", label = "Test", path = "/absolute/path", type = "input")
          )
        )
      )
    )),
    "must be relative \\(no leading slash\\)"
  )
})


test_that("configure_global rejects path traversal in extra_directories", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Path traversal
  expect_error(
    configure_global(settings = list(
      project_types = list(
        project = list(
          extra_directories = list(
            list(key = "test", label = "Test", path = "../parent", type = "input")
          )
        )
      )
    )),
    "cannot contain '\\.\\.' \\(path traversal\\)"
  )
})


test_that("configure_global preserves extra_directories through modifyList", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Set initial extra_directories
  configure_global(settings = list(
    project_types = list(
      project = list(
        extra_directories = list(
          list(key = "test1", label = "Test 1", path = "test1", type = "input")
        )
      )
    )
  ))

  # Update author (different field) - extra_directories should persist
  result <- configure_global(settings = list(
    author = list(name = "Updated User")
  ))

  # extra_directories should still exist
  expect_equal(length(result$project_types$project$extra_directories), 1)
  expect_equal(result$project_types$project$extra_directories[[1]]$key, "test1")

  # Now update extra_directories
  result2 <- configure_global(settings = list(
    project_types = list(
      project = list(
        extra_directories = list(
          list(key = "test2", label = "Test 2", path = "test2", type = "workspace")
        )
      )
    )
  ))

  # Should be replaced
  expect_equal(length(result2$project_types$project$extra_directories), 1)
  expect_equal(result2$project_types$project$extra_directories[[1]]$key, "test2")
  expect_equal(result2$project_types$project$extra_directories[[1]]$type, "workspace")
})


test_that("configure_global saves global.projects_root", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Set global.projects_root
  test_path <- "/Users/test/my-projects"
  result <- configure_global(settings = list(
    global = list(
      projects_root = test_path
    )
  ))

  # Verify return value has the path
expect_equal(result$global$projects_root, test_path)

  # Verify file was written
  settings_path <- file.path(fw_config_dir(), "settings.yml")
  expect_true(file.exists(settings_path))

  # Read the raw YAML to verify it was actually saved
  saved_yaml <- yaml::read_yaml(settings_path)
  expect_equal(saved_yaml$global$projects_root, test_path)

  # Also verify through read_frameworkrc
  saved <- read_frameworkrc()
  expect_equal(saved$global$projects_root, test_path)
})


test_that("configure_global persists global.projects_root through multiple saves", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # First save: set projects_root
  configure_global(settings = list(
    global = list(
      projects_root = "/first/path"
    )
  ))

  # Second save: change projects_root
  result <- configure_global(settings = list(
    global = list(
      projects_root = "/second/path"
    )
  ))

  expect_equal(result$global$projects_root, "/second/path")

  # Verify in file
  saved <- read_frameworkrc()
  expect_equal(saved$global$projects_root, "/second/path")
})


test_that("configure_global preserves global.projects_root when saving other settings", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # First: set projects_root
  configure_global(settings = list(
    global = list(
      projects_root = "/my/projects"
    )
  ))

  # Second: save author (without sending global)
  configure_global(settings = list(
    author = list(
      name = "New Author"
    )
  ))

  # projects_root should still be there
  saved <- read_frameworkrc()
  expect_equal(saved$global$projects_root, "/my/projects")
  expect_equal(saved$author$name, "New Author")
})


# ============================================================================
# Cache Directory Configuration Tests
# ============================================================================

test_that("configure_global can set cache directory per project type", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Set cache directory for standard project type
  result <- configure_global(settings = list(
    project_types = list(
      project = list(
        directories = list(
          cache = "custom/cache/path"
        )
      )
    )
  ))

  expect_equal(result$project_types$project$directories$cache, "custom/cache/path")
})


test_that("configure_global supports different cache paths per project type", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Set different cache directories for different project types
  result <- configure_global(settings = list(
    project_types = list(
      project = list(
        directories = list(
          cache = "outputs/cache"
        )
      ),
      project_sensitive = list(
        directories = list(
          cache = "outputs/private/cache"
        )
      ),
      presentation = list(
        directories = list(
          cache = "cache"
        )
      ),
      course = list(
        directories = list(
          cache = "cache"
        )
      )
    )
  ))

  expect_equal(result$project_types$project$directories$cache, "outputs/cache")
  expect_equal(result$project_types$project_sensitive$directories$cache, "outputs/private/cache")
  expect_equal(result$project_types$presentation$directories$cache, "cache")
  expect_equal(result$project_types$course$directories$cache, "cache")
})


test_that("configure_global preserves cache directory when updating other settings", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # First: set cache directory
  configure_global(settings = list(
    project_types = list(
      project = list(
        directories = list(
          cache = "my-custom-cache"
        )
      )
    )
  ))

  # Second: update author (without sending project_types)
  configure_global(settings = list(
    author = list(
      name = "Updated Author"
    )
  ))

  # cache directory should still be there
  saved <- read_frameworkrc()
  expect_equal(saved$project_types$project$directories$cache, "my-custom-cache")
  expect_equal(saved$author$name, "Updated Author")
})


test_that("configure_global saves and loads directories_enabled", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # Save directories_enabled for project type
  result <- configure_global(settings = list(
    project_types = list(
      project = list(
        directories_enabled = list(
          scratch = TRUE,
          outputs_tables = FALSE,
          outputs_figures = TRUE
        )
      )
    )
  ))

  # Verify it was saved
  expect_equal(result$project_types$project$directories_enabled$scratch, TRUE)
  expect_equal(result$project_types$project$directories_enabled$outputs_tables, FALSE)
  expect_equal(result$project_types$project$directories_enabled$outputs_figures, TRUE)

  # Verify it persists in file
  saved <- read_frameworkrc()
  expect_equal(saved$project_types$project$directories_enabled$scratch, TRUE)
  expect_equal(saved$project_types$project$directories_enabled$outputs_tables, FALSE)
  expect_equal(saved$project_types$project$directories_enabled$outputs_figures, TRUE)
})


test_that("configure_global preserves directories_enabled when updating other fields", {
  skip_on_cran()
  
  cleanup <- setup_isolated_config()
  on.exit(cleanup())

  # First: save directories_enabled
  configure_global(settings = list(
    project_types = list(
      project = list(
        directories_enabled = list(
          scratch = TRUE,
          outputs_tables = FALSE
        )
      )
    )
  ))

  # Second: update author (without sending directories_enabled)
  configure_global(settings = list(
    author = list(name = "New Author")
  ))

  # directories_enabled should still be there
  saved <- read_frameworkrc()
  expect_equal(saved$project_types$project$directories_enabled$scratch, TRUE)
  expect_equal(saved$project_types$project$directories_enabled$outputs_tables, FALSE)
  expect_equal(saved$author$name, "New Author")
})

test_that("tests never use the real global config folder", {
  expect_true(startsWith(fw_config_dir(), tempdir()))
})

test_that("project_list() marks projects whose folders are gone", {
  cleanup <- setup_isolated_config()
  on.exit(cleanup(), add = TRUE)
  here <- withr::local_tempdir()
  suppressWarnings(add_project_to_config(here))
  suppressWarnings(add_project_to_config(file.path(tempdir(), "gone-project-xyz")))
  expect_message(projects <- project_list(), "1 registered project folder no longer exists")
  expect_identical(projects$exists, c(TRUE, FALSE))
  remove_project_from_config(projects$id[!projects$exists])
  expect_silent(projects <- project_list())
  expect_identical(nrow(projects), 1L)
})

test_that("projects made in temporary folders are not registered", {
  expect_true(framework:::.fw_temp_path(file.path(tempdir(), "p")))
  expect_true(framework:::.fw_temp_path("/private/var/folders/ab/T/p"))
  expect_false(framework:::.fw_temp_path("/Users/someone/Projects/p"))
})
