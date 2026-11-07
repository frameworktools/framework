test_that("keys outside the environment sections warn once per session", {
  test_dir <- create_test_project()
  on.exit(cleanup_test_dir(test_dir), add = TRUE)
  withr::local_dir(test_dir)
  fw_env <- framework:::.framework_env
  old <- fw_env$settings_ignored_warned
  fw_env$settings_ignored_warned <- NULL
  withr::defer(fw_env$settings_ignored_warned <- old)

  writeLines(c(
    "default:",
    "  directories: {notebooks: notebooks}",
    "ehr_source: optum",
    "person: {id_column: person_id}",
    "hpc:",
    "  directories: {notebooks: /scratch/notebooks}",
    "cluster: {inherits: default}",
    "production: {}"
  ), "settings.yml")

  expect_warning(
    value <- settings("ehr_source"),
    "^Settings file '"
  )
  fw_env$settings_ignored_warned <- NULL
  expect_warning(
    value <- settings("ehr_source"),
    "settings.yml' has keys outside its environment sections, which are ignored: ehr_source, person. Move them under default: to use them.",
    fixed = TRUE
  )
  expect_null(value)
  expect_no_warning(settings_read())

  # The active environment is not reported
  fw_env$settings_ignored_warned <- NULL
  writeLines(c("default:", "  a: 1", "myenv: {b: 2}", "stray: 3"), "settings.yml")
  withr::local_envvar(R_CONFIG_ACTIVE = "myenv")
  expect_warning(settings_read(), "ignored: stray. Move", fixed = TRUE)
})

test_that("a flat settings file has no ignored keys", {
  test_dir <- create_test_project()
  on.exit(cleanup_test_dir(test_dir), add = TRUE)
  withr::local_dir(test_dir)
  fw_env <- framework:::.framework_env
  fw_env$settings_ignored_warned <- NULL

  writeLines("ehr_source: optum", "settings.yml")
  expect_no_warning(value <- settings("ehr_source"))
  expect_equal(value, "optum")
})

test_that("split files with environment sections warn about their own ignored keys", {
  test_dir <- create_test_project()
  on.exit(cleanup_test_dir(test_dir), add = TRUE)
  withr::local_dir(test_dir)
  fw_env <- framework:::.framework_env
  fw_env$settings_ignored_warned <- NULL

  writeLines(c("default:", "  project_name: X", "  extra: settings/extra.yml"), "settings.yml")
  writeLines(c("default:", "  extra: {a: 1}", "stray: 2"), "settings/extra.yml")
  expect_warning(
    settings_read(),
    "Split file 'settings/extra.yml' has keys outside its environment sections, which are ignored: stray.",
    fixed = TRUE
  )
})
