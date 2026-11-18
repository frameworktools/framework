# CRAN Comments

## Update to 2.0.11

This update follows 2.0.0 (published 2026-11-07) sooner than usual because
2.0.0 has bugs that can lose user data or send a credential to the wrong
server:

* `data_save()` replaced data the user had locked with `locked = TRUE`. It
  issued a warning but wrote the new contents. 2.0.11 stops with an error
  unless the user passes `unlock = TRUE`.
* A project linked to Framework Cloud could send its access token to a server
  other than the one that issued it. When the project's `.env` didn't name
  its server, the token went to the built-in default server. A token that
  `scaffold()` had loaded from another project's `.env` earlier in the session
  took priority over the project's own. 2.0.11 sends a project's token only to
  its own server and stops with an error when the server is unknown.

The other changes are smaller fixes to output folders, settings edits, and
`upgrade()`. They are listed in NEWS.md.

As in 2.0.0, every Framework Cloud feature is opt-in, and the tests mock every
server call, so they make no network requests.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

- Local: macOS 27.0.1, R 4.6.1 (`R CMD check --as-cran`)

## Downstream dependencies

There are no downstream dependencies.
