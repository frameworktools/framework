---
id: scaffold
title: scaffold()
section: features
position: 1
description: 'Session initialization for Framework projects'
---
## Session initialization

Call `scaffold()` at the top of every notebook or script to initialize the project environment:

```r
library(framework)
scaffold()
```

Or call `framework::scaffold()`, which attaches `framework` when it is not attached.

## Initialization sequence

`scaffold()` executes these steps in order:

1. **Locates the project root** from the current or parent directories.
2. **Loads `.env`** into the R session without overriding variables already set in the environment.
3. **Reads `settings.yml`** and any split `settings/*.yml` files.
4. **Prepares `framework.db`**, creating the file or adding missing schema tables.
5. **Sets the random seed** when `seed_on_scaffold` is `true` (disabled by default).
6. **Sets the `ggplot2` theme** when `set_theme_on_scaffold` is `true` (`theme_minimal` in new projects).
7. **Installs missing packages** listed in project settings (using `renv` when enabled).
8. **Attaches packages** marked `auto_attach: true`.
9. **Sources `functions/*.R`** in alphabetical order.
10. **Sources `scaffold.R`** at the project root when present.
11. **Creates the initial Git commit** (`"Project initialized."`) if the repository has zero commits and Git identity is configured.

## Session environment

After `scaffold()` finishes, attached packages, project functions, and `settings()` lookups are available:

```r
df <- read_csv("data.csv") |>
  filter(x > 0) |>
  mutate(y = x * 2)

result <- my_custom_function(df)

settings("author.name")
settings("directories.notebooks")
```

## Project root discovery

`scaffold()` walks upward from the working directory looking for `settings.yml`, `.Rproj` or `.code-workspace` files paired with Framework settings, or standard project markers. Notebooks in `notebooks/`, scripts in `scripts/`, and files in subdirectories resolve the same project root:

```text
my-project/
├── settings.yml
├── notebooks/
│   └── 01-analysis.qmd
├── scripts/
│   └── process.R
└── functions/
    └── helpers.R
```

## Configuration options

`scaffold` and `packages` blocks live in `settings/scaffold.yml` and `settings/packages.yml` on split-settings projects or directly in `settings.yml` on single-file projects:

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

### Random seed

Random seeding is off by default. Set both `seed` and `seed_on_scaffold: true` to call `set.seed()` during `scaffold()`:

```yaml
scaffold:
  seed: 123
  seed_on_scaffold: true
```

When `seed_on_scaffold` is unset, setting the `FW_SEED` environment variable enables seeding. A project's `seed` setting takes precedence over `FW_SEED`.

### Plot theme

`set_theme_on_scaffold: true` passes `ggplot_theme` to `ggplot2::theme_set()`. Set `set_theme_on_scaffold: false` to leave the active theme unchanged.

### Package attachment

Entries with `auto_attach: true` are loaded with `library()`. Entries with `auto_attach: false` are installed without attaching:

```yaml
packages:
  default_packages:
    - name: dplyr
      auto_attach: true
    - name: jsonlite
      auto_attach: false
```

### Function directories

Set `source_all_functions: false` under `scaffold:` to skip sourcing `functions/*.R`. To source multiple directories, list them under `directories.functions`:

```yaml
directories:
  functions:
    - functions
    - helpers
```

## Project scaffold.R

New projects include a root `scaffold.R` file sourced after standard initialization. Place project-wide options or shared lookup reads there:

```r
# scaffold.R
reference_data <- data_read("reference.lookup")
options(scipen = 999)
```
