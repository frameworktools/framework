---
id: scaffold
title: scaffold()
section: features
position: 1
description: 'Project environment setup'
---
## Overview

`scaffold()` is the primary entry point for working with Framework projects. Call it at the start of every notebook or script to set up your environment.

```r
library(framework)
scaffold()
```

Or if you prefer explicit namespacing:

```r
framework::scaffold()
```

## scaffold() steps

When you call `scaffold()`, it:

1. **Finds your project**: locates the project root, even from subdirectories
2. **Loads environment variables**: reads secrets from `.env`
3. **Reads configuration**: parses `settings.yml`
4. **Prepares framework.db**: creates it, or adds missing tables
5. **Sets random seed**: if enabled in settings (off by default)
6. **Sets ggplot theme**: applies your default theme (`theme_minimal` in new projects)
7. **Installs packages**: any uninstalled packages from your packages settings
8. **Loads packages**: attaches packages with `auto_attach: true`
9. **Sources functions**: loads all `.R` files from `functions/`
10. **Sources scaffold.R**: runs the project's `scaffold.R`, if there is one
11. **Makes the first git commit**: in a repository with no commits yet, commits every file `.gitignore` allows as "Project initialized."

## Session state after scaffold()

Once `scaffold()` runs:

- Your configured packages are loaded and ready to use
- All functions from `functions/` are available
- Project settings are accessible via `settings()`

```r
# Use your packages directly
df <- read_csv("data.csv") |>
  filter(x > 0) |>
  mutate(y = x * 2)

# Call functions from functions/
result <- my_custom_function(df)

# Access project settings
settings("author.name")
settings("directories.notebooks")
```

## Project discovery

`scaffold()` automatically finds your project by looking for:

- `settings.yml` in current or parent directories
- `.Rproj` or `.code-workspace` file with settings nearby
- Common Framework directories (`notebooks/`, `scripts/`, etc.)

You can call `scaffold()` from any subdirectory:

```text
my-project/
├── settings.yml
├── notebooks/
│   └── 01-analysis.qmd    # scaffold() works here
├── scripts/
│   └── process.R          # and here
└── functions/
    └── helpers.R          # and here
```

## Configuration

`scaffold()` behavior is controlled by the `scaffold` and `packages` settings. Standard and privacy-sensitive projects keep them in `settings/scaffold.yml` and `settings/packages.yml`. Other types keep them in `settings.yml`.

```yaml
scaffold:
  seed_on_scaffold: false
  seed: 123
  set_theme_on_scaffold: true
  ggplot_theme: theme_minimal
  source_all_functions: true

packages:
  use_renv: false
  default_packages:
    - name: dplyr
      auto_attach: true
    - name: ggplot2
      auto_attach: true
```

### Seed

Random seed setting is **off by default**. To enable it for reproducibility, set both values:

```yaml
scaffold:
  seed: 123
  seed_on_scaffold: true
```

With `seed_on_scaffold` unset, the `FW_SEED` environment variable turns seeding on. The project's `seed` wins over `FW_SEED`.

### Theme

`set_theme_on_scaffold: true` applies `ggplot_theme` with `ggplot2::theme_set()`. Set it to `false` to leave the theme alone.

### Packages

Packages with `auto_attach: true` are loaded automatically. Others are just installed:

```yaml
packages:
  default_packages:
    - name: dplyr
      auto_attach: true    # loaded
    - name: jsonlite
      auto_attach: false   # installed but not loaded
```

With renv on, packages install through renv.

### Functions directory

All `.R` files in `functions/` are sourced. Set `source_all_functions: false` under `scaffold:` to skip them.

To source other folders, list them under `options: functions_dir`:

```yaml
options:
  functions_dir:
    - functions
    - helpers
```

## Custom scaffold.R

If a `scaffold.R` file exists in your project root, it's sourced after the standard setup. New projects include a starter `scaffold.R`. Use it for project-specific initialization:

```r
# scaffold.R
message("Welcome to the project!")

# Load reference data used across notebooks
reference_data <- data_read("reference.lookup")

# Set project-wide options
options(scipen = 999)
```

---

<div style="display: flex; justify-content: space-between">

[← New projects](guide:new-project)

[framework.db →](guide:framework-db)

</div>
