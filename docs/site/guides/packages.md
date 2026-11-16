---
id: packages
title: Packages
section: features
position: 3
description: 'Package configuration, package sets, Cloud sync, and renv lockfiles'
---
## Configuration

Project dependencies live under `packages.default_packages` in `settings/packages.yml` (split projects) or `settings.yml` (single-file projects). During `scaffold()`, Framework installs missing packages and calls `library()` on entries with `auto_attach: true`.

```yaml
packages:
  use_renv: false
  default_packages:
    - name: dplyr
      source: cran
      auto_attach: true
    - name: ggplot2
      source: cran
      auto_attach: true
    - name: jsonlite
      source: cran
      auto_attach: false
```

`source` accepts `cran` (default), `github`, or `bioc`.

- `auto_attach: true`: attached automatically by `scaffold()`.
- `auto_attach: false`: installed without attaching; reference functions as `pkg::fn()` or call `library()` where needed.

## Package management functions

`package_add()` writes a package entry to settings and installs it:

```r
package_add("janitor")
package_add("forcats", auto_attach = TRUE)
package_add("dplyr@1.1.0")           # Pinned CRAN version
package_add("tidyverse/dplyr@main")  # GitHub repository and ref
package_add("bioc::DESeq2")          # Bioconductor package
```

Adding an already listed package updates its entry. If installation fails, settings remain unchanged. Pass `install = FALSE` to record an entry without installing it.

| Function | Purpose |
|----------|---------|
| `packages_list()` | List configured packages, sources, version pins, and `auto_attach` flags |
| `packages_install()` | Install missing configured packages |

## Package sets

Attach curated package sets at project creation or afterward. For example, `tidyverse-analysis` adds `dplyr`, `tidyr`, `ggplot2`, `purrr`, `stringr`, `forcats`, and `lubridate` with `auto_attach: true`:

```r
new_project("study", "~/study", package_sets = "tidyverse-analysis")
```

Add sets to an existing project with `package_set_add()`. Already configured packages keep their existing settings:

```r
package_sets_list()
package_set_add("bayes-r")
package_set_add("tidy-omop", install = FALSE)
```

When signed in with `cloud_login()`, `package_set_add()` also accepts personal or shared Cloud handles such as `"@yourname/lab-tools"`.

## Sync with Framework Cloud

`pull_all()` and `push_all()` synchronize a project's package list, AI skills, and data catalog metadata with its Framework Cloud project using `FW_PROJECT_TOKEN` in `.env`. Directory layout and local data files are never moved.

```r
pull_all(dry_run = TRUE)
pull_all()
```

`pull_all()` summarizes pending changes across packages, skills, and the data registry and prompts `Apply these changes? [y/n]`:

```text
Changes from Framework Cloud:
Packages (revision 3f2a9c1e):
  Packages to add: tidyr
  Packages that differ: janitor (local 2.2.0, Cloud 2.1.0) — kept; pull_all(overwrite = TRUE) uses Cloud's
  Only in this project (kept): here
Skills:
  1 to add, 2 to update
Data registry (revision 8b1d0e44):
  Entries to add: inputs.raw.visits
```

Applying changes appends new packages to project settings and installs them (via `renv` when enabled), updates unedited skills, and adds new data catalog entries. Local entries never get deleted, and differing local packages, data entries, or edited skills are preserved unless `overwrite = TRUE` (which backs up edited skills first).

```r
push_all(dry_run = TRUE)
push_all()
```

`push_all()` previews remote changes and prompts `Push these changes? [y/n]`. Cloud-only packages and data entries remain on Cloud unless `remove = TRUE`. Lockfiles under `.framework/` (`setup.lock.json`, `data.lock.json`, and `skills.lock.json`) track last-pulled revisions; if Cloud changed since the last pull, that component stops with `"Pull first: pull_all()"` unless `force = TRUE`. Pushing edited skills requires `cloud_login()`. If one component fails, completed components remain pushed and the error lists which succeeded and which stopped.

In non-interactive sessions, pass `confirm = TRUE` to apply changes or `dry_run = TRUE` to inspect them. `pull_skills()`, `push_skills()`, `pull_data_registry()`, and `push_data_registry()` sync individual parts, and `fw pull` / `fw push` run the same workflow from a shell.

## Version pins and non-CRAN sources

Pin CRAN versions or install from GitHub and Bioconductor in YAML:

```yaml
packages:
  default_packages:
    - name: dplyr
      version: "1.1.0"
      auto_attach: true

    - name: mypackage
      source: github
      repo: "username/mypackage"
      auto_attach: true

    - name: devpackage
      source: github
      repo: "username/devpackage"
      ref: "develop"
      auto_attach: false

    - name: DESeq2
      source: bioc
      auto_attach: false
```

Omitting `ref` on a GitHub package installs the repository's default branch.

## renv lockfiles

Enable [renv](https://rstudio.github.io/renv/) during project creation or inside an existing project:

```r
new_project("study", "~/study", tools = "renv")
renv_enable()
```

`renv_enable()` initializes an isolated project library, installs configured packages, writes `renv.lock`, and creates `.framework_renv_enabled`. `renv_enabled()` checks for that marker, and `renv_disable()` turns `renv` integration off while keeping `renv.lock`.

| Function | Purpose |
|----------|---------|
| `packages_snapshot()` | Record installed versions in `renv.lock` |
| `packages_restore()` | Install exact versions from `renv.lock` |
| `packages_status()` | Compare installed packages against `renv.lock` (or `settings.yml` when `renv` is off) |
| `packages_update()` | Update packages inside the `renv` library |
