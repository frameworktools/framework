---
id: packages
title: Packages
section: features
position: 3
description: 'R package management in Framework projects'
---
## Overview

Framework manages your project's R package dependencies through `settings.yml`. When you call `scaffold()`, packages are automatically installed and loaded.

## Package configuration

Set the default packages in `settings.yml` or through **Packages** in `framework::gui()`. The GUI lets you search CRAN with autocomplete, and you can switch the source dropdown to GitHub or Bioconductor when you need development builds.

![Default package configuration UI with source selector and auto-attach toggles](images/packages-defaults.png)

In your `settings.yml`:

```yaml
packages:
  - name: dplyr
    auto_attach: true
  - name: ggplot2
    auto_attach: true
  - name: jsonlite
    auto_attach: false
```

### auto_attach

- `true`: package is loaded automatically when you call `scaffold()`
- `false`: package is installed but not loaded (use `library()` when needed)

## Installation and loading

When `scaffold()` runs:

1. Checks which packages are missing
2. Installs missing packages
3. Loads packages with `auto_attach: true`

You don't need to write `library()` calls for attached packages.

## Version pinning

Pin specific versions or install from GitHub:

```yaml
packages:
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
```

## renv integration

Framework detects if your project uses [renv](https://rstudio.github.io/renv/) and routes installations through it automatically.

To enable renv in a new project, configure it in your defaults via `setup()` or enable it per-project:

```r
renv::init()
```

When renv is active:
- Packages install to the project library
- `renv.lock` tracks exact versions
- Projects are isolated from your global library

---

<div style="display: flex; justify-content: space-between">

[← framework.db](guide:framework-db)

[Data management →](guide:data-management)

</div>
