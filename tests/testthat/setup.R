# No test reaches a real Framework Cloud account: a token from the
# environment or the keyring is hidden for the whole run. Tests that need a
# token set FW_CLOUD_TOKEN themselves or mock .fw_cloud_token().
#
# FW_PROJECT_TOKEN is cleared too, and FW_CLOUD_URL points at a closed local
# port, so a token that slips through never reaches framework.pub.
# FW_CONFIG_HOME points at a folder of the run's own, so no test reads or
# writes the user's global settings or adds projects to their registry.
withr::local_envvar(
  FW_CONFIG_HOME = file.path(tempdir(), "fw-test-config-home"),
  FW_CLOUD_TOKEN = "",
  FW_PROJECT_TOKEN = "",
  FW_CLOUD_URL = "http://127.0.0.1:9",
  FW_TOKEN_FILE = file.path(tempdir(), "fw-tests-no-token"),
  .local_envir = testthat::teardown_env()
)

# Tests must not use the network. Any httr2 request to a host other than
# this machine fails at once. Tests that mock responses replace this guard
# for their own scope.
if (requireNamespace("httr2", quietly = TRUE)) {
  httr2::local_mocked_responses(function(req) {
    host <- tryCatch(httr2::url_parse(req$url)$hostname, error = function(e) "")
    if (host %in% c("127.0.0.1", "localhost", "::1", "[::1]")) {
      return(NULL)
    }
    stop("Tests may not contact ", req$url, call. = FALSE)
  }, env = testthat::teardown_env())
}
