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
4. **Sets random seed**: if enabled in settings (off by default)
5. **Sets ggplot theme**: applies your default theme (if enabled and configured)
6. **Installs packages**: any uninstalled packages from your packages settings
7. **Loads packages**: attaches packages with `auto_attach: true`
8. **Sources functions**: loads all `.R` files from `functions/`

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

`scaffold()` behavior is controlled by `settings.yml`:

```yaml
seed: 123
seed_on_scaffold: true

packages:
  - name: dplyr
    auto_attach: true
  - name: ggplot2
    auto_attach: true

directories:
  functions: functions
```

### Seed

Random seed setting is **off by default**. To enable it for reproducibility, set both values:

```yaml
seed: 123
seed_on_scaffold: true
```

### Packages

Packages with `auto_attach: true` are loaded automatically. Others are just installed:

```yaml
packages:
  - name: dplyr
    auto_attach: true    # loaded
  - name: jsonlite
    auto_attach: false   # installed but not loaded
```

### Functions directory

All `.R` files in your `functions/` directory are sourced:

```yaml
directories:
  functions: functions
```

You can also specify multiple directories:

```yaml
directories:
  functions:
    - functions
    - helpers
```

## Custom scaffold.R

If a `scaffold.R` file exists in your project root, it's sourced after the standard setup. Use this for project-specific initialization:

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
