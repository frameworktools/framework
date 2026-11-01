# No test reaches a real Framework Cloud account: a token from the
# environment or the keyring is hidden for the whole run. Tests that need a
# token set FW_CLOUD_TOKEN themselves or mock .fw_cloud_token().
withr::local_envvar(
  FW_CLOUD_TOKEN = "",
  FW_TOKEN_FILE = file.path(tempdir(), "fw-tests-no-token"),
  .local_envir = testthat::teardown_env()
)
