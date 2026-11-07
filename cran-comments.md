# CRAN Comments

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

## R CMD check results

0 errors | 0 warnings | 0 notes

On CRAN's machines the installed size may show as a NOTE (16 MB). Most of it is
the optional local GUI's built web assets in `inst/gui`, the same size as in
1.1.0. The source tarball is 4.2 MB.

## Test environments

- Local: macOS 27.0.1, R 4.6.1 (`R CMD check --as-cran`)

## Downstream dependencies

There are no downstream dependencies.
