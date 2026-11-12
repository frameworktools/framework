---
id: packages
title: Packages
section: features
position: 3
description: 'R package management in Framework projects'
---
## Overview

Framework manages your project's R package dependencies through its settings. When you call `scaffold()`, missing packages are installed and attached packages are loaded.

## Package configuration

Packages are listed under `packages.default_packages`. Projects with split settings files keep them in `settings/packages.yml`. Single-file projects keep them in `settings.yml`.

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

`source` is `cran` (the default), `github`, or `bioc`.

### auto_attach

- `true`: package is loaded when you call `scaffold()`
- `false`: package is installed but not loaded (call `library()` when needed)

## Package commands

Use `package_add()` to record a package and install it in one step:

```r
package_add("janitor")
package_add("forcats", auto_attach = TRUE)
package_add("dplyr@1.1.0")           # pinned CRAN version
package_add("tidyverse/dplyr@main")  # GitHub repository and ref
package_add("bioc::DESeq2")          # Bioconductor
```

Adding a package that is already listed replaces its entry. If the install fails, the settings are left unchanged. Pass `install = FALSE` to record a package without installing it.

| Function | Purpose |
|----------|---------|
| `packages_list()` | Show the configured packages, sources, pins, and auto-attach status |
| `packages_install()` | Install every configured package that is missing |

## Package sets

Framework ships package sets for new projects. The `tidyverse-analysis` set adds dplyr, tidyr, ggplot2, purrr, stringr, forcats, and lubridate, all attached by `scaffold()`:

```r
new_project("study", "~/study", package_sets = "tidyverse-analysis")
```

Add a set to an existing project with `package_set_add()`. It records the packages the project doesn't list yet and installs them. Packages already listed stay as they are. `package_sets_list()` shows the sets for R.

```r
package_sets_list()
package_set_add("bayes-r")
package_set_add("tidy-omop", install = FALSE)
```

Signed in to Framework Cloud, you can also add one of your account's sets by its handle, such as `package_set_add("@yourname/lab-tools")`.

## Setup on Framework Cloud

A project's setup on Framework Cloud is its packages and skills. Folders and structure are not part of it. `pull_setup()` brings Cloud's setup into the project, and `push_setup()` sends the project's packages and edited skills back. Both use the project token in `.env`.

```r
pull_setup(dry_run = TRUE)   # List the changes only
pull_setup()
```

`pull_setup()` lists the changes first, then asks `Apply these changes? [y/n]`:

```text
Setup changes from Framework Cloud (revision 3f2a9c1e):
  Packages to add: tidyr
  Packages that differ: janitor (local 2.2.0, Cloud 2.1.0) — kept; pull_setup(overwrite = TRUE) uses Cloud's
  Only in this project (kept): here
  Skills: 1 to add, 2 to update
```

Applying adds the new packages to `settings.yml` and installs them, with renv when the project uses it. Then it runs `pull_skills()`. Local packages are never removed. A package whose settings differ keeps the local ones unless `overwrite = TRUE`, which also replaces locally edited skills after backing them up.

```r
push_setup(dry_run = TRUE)
push_setup()
```

`push_setup()` asks Cloud what the push would change, lists it with a warning, then asks `Push these changes? [y/n]`:

```text
Setup changes for Framework Cloud:
  Packages to add: here
  Packages to change: janitor (2.1.0 -> 2.2.0)
  On Cloud only (kept): tidyr
This changes Test Project's setup on Framework Cloud. New setups, zips, and Update on GitHub will use it.
```

Packages only on Cloud stay there unless `remove = TRUE`. The revision last pulled is kept in `.framework/setup.lock.json`. When Cloud's setup changed since then, the push stops with "Pull first". `force = TRUE` replaces Cloud's changes. A push resolves the project again from its blueprint's latest version. Edited skills then go through `push_skills()`, with its own warning.

Without a console, pass `confirm = TRUE`, or `dry_run = TRUE` to only see the changes. `fw setup pull` and `fw setup push` run the same steps from a terminal.

## Installation and loading

When `scaffold()` runs:

1. Checks which packages are missing
2. Installs missing packages
3. Loads packages with `auto_attach: true`

You don't need to write `library()` calls for attached packages.

## Version pinning

Pin specific versions or install from GitHub or Bioconductor:

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

A GitHub entry without `ref` installs the default branch.

## renv integration

Framework can route installations through [renv](https://rstudio.github.io/renv/). Turn renv on when you create a project:

```r
new_project("study", "~/study", tools = "renv")
```

Or turn it on in an existing project:

```r
renv_enable()
```

`renv_enable()` initializes renv, installs the configured packages, writes `renv.lock`, and creates a `.framework_renv_enabled` marker file. `renv_enabled()` checks for that marker. `renv_disable()` turns the integration off.

When renv is on:
- Packages install to the project's renv folder
- `renv.lock` tracks exact versions
- Projects are isolated from your global package installation

| Function | Purpose |
|----------|---------|
| `packages_snapshot()` | Write current versions to `renv.lock` |
| `packages_restore()` | Install the versions in `renv.lock` |
| `packages_status()` | Compare the project with `renv.lock` |
| `packages_update()` | Update packages through renv |

`packages_snapshot()`, `packages_restore()`, and `packages_update()` require renv to be on. With renv off, `packages_status()` says so and lists which packages in settings.yml are installed.

---

<div style="display: flex; justify-content: space-between">

[← framework.db](guide:framework-db)

[Data management →](guide:data-management)

</div>
