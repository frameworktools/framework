---
id: standard-project
title: Standard project
section: project_types
position: 11
description: 'Default project type with organized data, work, and output directories'
---
## Overview

The **Standard Project** is Framework's default project structure. It is designed for data analysis, research, and reporting.

## Directory structure

An example project might look like:

```text
my-project/
├── docs/                # Project documents
├── functions/           # Custom R functions (auto-loaded)
│   └── helpers.R
├── inputs/              # Data inputs
│   ├── raw/             # Original data (never modify)
│   ├── intermediate/    # Cleaned/processed data
│   └── final/           # Analysis-ready datasets
├── logs/                # Logs (gitignored)
├── notebooks/           # Analysis notebooks
│   ├── 01-exploration.qmd
│   └── 02-modeling.qmd
├── outputs/
│   └── notebooks/       # Rendered notebooks
├── scratch/             # Throwaway work (gitignored)
├── scripts/             # Automation scripts
│   └── data-pipeline.R
├── settings/            # Settings sections (packages, data, git, ...)
├── _quarto.yml          # Quarto configuration
├── AGENTS.md            # AI assistant guide
├── framework.db         # Metadata database (created on first use)
├── scaffold.R           # Project startup code
└── settings.yml         # Project configuration
```

Additional directories are created on first use:
- `outputs/cache` - Cached computations
- `outputs/tables` - Saved tables
- `outputs/figures` - Saved figures
- `outputs/models` - Saved models
- `outputs/reports` - Saved reports

`framework.db` is created by the first `scaffold()`, `bootstrap()`, or saved output.

## Workflow

### 1. Environment setup

Start each session by running scaffold:

```r
library(framework)
scaffold()
```

This loads:
- Packages from `settings/packages.yml`
- Custom functions from `functions/`
- Project configuration
- `scaffold.R`, if present

### 2. Notebooks

Create analysis notebooks:

```r
make_notebook("exploration")
make_notebook("modeling", subdir = "analysis")
```

### 3. Data

Define data in `settings/data.yml`:

```yaml
data:
  inputs.raw.sales:
    path: inputs/raw/sales_2024.csv
    type: csv
```

Load and process:

```r
sales <- data_read("inputs.raw.sales")
```

### 4. Caching

Cache expensive computations:

```r
model_results <- cache_remember("sales_model", {
  fit_complex_model(sales)
})
```

## Best practices

### Notebook order

Number notebooks to indicate order:
```text
notebooks/
├── 01-data-import.qmd
├── 02-cleaning.qmd
├── 03-exploration.qmd
├── 04-modeling.qmd
└── 05-reporting.qmd
```

### Subdirectories

For complex projects:
```r
make_notebook("eda", subdir = "exploration")
make_notebook("regression", subdir = "modeling")
```

### Raw and processed data

Never modify raw data:
```text
inputs/
├── raw/          # NEVER modify
├── intermediate/ # Cleaned versions
└── final/        # Ready for analysis
```

---

<div style="display: flex; justify-content: space-between">

[← Project types](guide:project-types)

[Privacy-sensitive project →](guide:privacy-sensitive-project)

</div>
