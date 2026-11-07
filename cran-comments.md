# CRAN Comments

## Resubmission

This resubmits 2.0.0 after the incoming pretest failed on Windows
(r-devel-windows-x86_64, 21 test failures; Debian passed). The failures are
fixed, not skipped. They came from Windows path handling: git's MSYS-style
paths (`/d/temp/...`) compared against native paths, short temp-folder names,
CRLF input to `git check-ignore`, and the unquoted `@{u}` revision in MSYS git.
The package now checks cleanly with `R CMD check --as-cran` on Windows R-devel.

Since the first submission, the optional local GUI was also removed (see
below), which shrinks the package.

## Update to 2.0.0

This is an update from 1.1.0. Framework 2.0 adds an optional connection to
Framework Cloud, a web service for creating projects and publishing results.
Every Cloud feature is opt-in: nothing contacts a server unless the user signs
in with `cloud_login()` or passes a server to a function. The tests mock every
server call, so they make no network requests.

Main changes:

* Projects are built from layers (a structure, tools, and package and skill
  sets).
* `publish()` writes versioned outputs to Framework Cloud, a folder, S3, or
  GitHub Pages.
* New projects include AGENTS.md and agent skill files.
* The optional local GUI is retired. `gui()` remains as a deprecated stub, and
  plumber is no longer in Suggests. This removes about 12 MB of web assets.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

- Local: macOS 27.0.1, R 4.6.1 (`R CMD check --as-cran`)
- GitHub Actions: windows-latest, R-devel r90845 ucrt (`R CMD check --as-cran`)
- win-builder: R-devel

## Downstream dependencies

There are no downstream dependencies.
