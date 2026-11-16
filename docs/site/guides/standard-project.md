---
id: standard-project
title: Standard project
section: project_types
position: 11
description: 'Default project type with organized data, work, and output directories'
---
## Structure

The standard project (`project`) is Framework's default layout for data analysis, pipelines, and reporting.

```text
my-project/
├── docs/                # Project documentation
├── functions/           # Reusable R functions sourced by scaffold()
│   └── helpers.R
├── inputs/              # Input datasets
│   ├── raw/             # Unmodified source files
│   ├── intermediate/    # Cleaned pipeline datasets
│   └── final/           # Analysis-ready datasets
├── logs/                # Run logs (gitignored)
├── notebooks/           # Analysis notebooks
│   ├── 01-exploration.qmd
│   └── 02-modeling.qmd
├── outputs/
│   └── notebooks/       # Rendered notebooks
├── scratch/             # Temporary work (gitignored)
├── scripts/             # Standalone scripts
│   └── data-pipeline.R
├── settings/            # Split configuration files
├── _quarto.yml          # Quarto configuration
├── AGENTS.md            # AI assistant context
├── framework.db         # Local metadata database (created on first use)
├── scaffold.R           # Project startup script
└── settings.yml         # Root configuration
```

Output subdirectories are created on first save:

- `outputs/cache` for cached computations
- `outputs/tables` for `save_table()`
- `outputs/figures` for `save_figure()`
- `outputs/models` for `save_model()`
- `outputs/reports` for `save_report()`

`framework.db` is created on the first call to `scaffold()`, `bootstrap()`, or a `save_*()` / `cache_*()` function.

## Typical workflow

### Session setup

Initialize the session at the top of each notebook or script:

```r
library(framework)
scaffold()
```

`scaffold()` loads `.env` and `settings.yml`, attaches configured packages from `settings/packages.yml`, sources `functions/*.R`, and runs `scaffold.R`.

### Notebooks

Create Quarto notebooks in `notebooks/` or a subdirectory:

```r
make_notebook("exploration")
make_notebook("modeling", subdir = "analysis")
```

### Data catalog

Register source files in `settings/data.yml`:

```yaml
data:
  inputs.raw.sales:
    path: inputs/raw/sales_2024.csv
    type: csv
```

Read registered entries by name:

```r
sales <- data_read("inputs.raw.sales")
```

### Computation caching

Cache expensive steps in `outputs/cache/`:

```r
model_results <- cache_remember("sales_model", {
  fit_complex_model(sales)
})
```

## Project conventions

### Numbered notebooks

Prefix sequential notebooks with two-digit numbers so execution order is explicit:

```text
notebooks/
├── 01-data-import.qmd
├── 02-cleaning.qmd
├── 03-exploration.qmd
├── 04-modeling.qmd
└── 05-reporting.qmd
```

### Notebook subdirectories

Group larger analyses into subdirectories under `notebooks/`:

```r
make_notebook("eda", subdir = "exploration")
make_notebook("regression", subdir = "modeling")
```

### Immutable raw inputs

Keep files in `inputs/raw/` unmodified and write cleaned or derived datasets to `inputs/intermediate/` and `inputs/final/`.
