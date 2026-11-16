---
id: conventions
title: Conventions
section: getting_started
position: 3
description: 'Directory conventions, session initialization, and data integrity'
---
## Defaults and configuration

Framework provides default directory layouts, package loading rules, and output paths so new projects share a consistent structure. Every directory path, package rule, and tool setting can be customized in Framework Cloud defaults or in a project's `settings.yml`.

## Session initialization with scaffold()

Start each notebook or script with `scaffold()`:

```r
library(framework)
scaffold()
```

Or call `framework::scaffold()` directly without attaching `framework`.

`scaffold()` locates the project root, loads `.env` and `settings.yml`, prepares `framework.db`, applies configured seed or `ggplot2` theme settings, installs missing project packages, attaches configured packages, sources `.R` files in `functions/`, and runs `scaffold.R`.

## Package loading

`scaffold()` calls `library()` on packages marked `auto_attach: true`. Packages marked `auto_attach: false` are installed without being attached; call their functions with `pkg::fn()` or attach them explicitly in the script that needs them.

Example `settings/packages.yml`:

```yaml
packages:
  default_packages:
    - name: dplyr
      auto_attach: true
    - name: readr
      auto_attach: false
```

Corresponding R script:

```r
library(framework)
scaffold()

df <- readr::read_csv("data.csv") |>
  filter(x > 0) |>
  mutate(y = x * 2)
```

`dplyr` verbs (`filter()`, `mutate()`) are attached directly, whereas `readr::read_csv()` uses explicit namespacing.

Run `package_add("janitor")` to record a package in project settings and install it.

## Function sourcing

`scaffold()` sources every `.R` file in `functions/` in alphabetical order:

```text
functions/
├── model_prep.R
├── plotting_helpers.R
└── text_processing.R
```

Keep only function definitions inside `functions/*.R`. Top-level expressions outside `function()` blocks run on every `scaffold()` call.

Automatic sourcing replaces manual `source()` calls at the top of notebooks and allows you to rename or reorganize files in `functions/` without editing callers. Set `source_all_functions: false` under `scaffold:` in `settings.yml` (or `settings/scaffold.yml`) to disable automatic sourcing. See [Functions](guide:functions).

## Inputs and outputs

Framework separates read-only or pipeline datasets (`inputs/`) from generated deliverables (`outputs/`).

### Input stages

```text
inputs/
├── raw/           # Unmodified external source files
├── intermediate/  # Cleaned or transformed pipeline datasets
└── final/         # Analysis-ready datasets
```

### Data catalog

The data catalog in `settings/data.yml` (or `settings.yml`) maps dot-notation names to file paths. Register existing files with `data_add()`:

```r
data_add("inputs/raw/survey_2024.csv", name = "raw.survey")
data_add("inputs/final/analysis.rds", name = "final.analysis")
```

Or write a dataset and register its catalog entry in one call:

```r
data_save(clean_df, "inputs.intermediate.survey_clean")
```

Because `inputs.intermediate` matches the configured `inputs_intermediate` directory, `data_save()` writes `inputs/intermediate/survey_clean.rds`.

Read catalog entries by name from any working directory inside the project:

```r
survey <- data_read("raw.survey")
```

See [Data management](guide:data-management).

### Output directories

Generated artifacts live under `outputs/` by type:

```text
outputs/
├── tables/    # save_table()
├── figures/   # save_figure()
├── models/    # save_model()
├── reports/   # save_report()
├── notebooks/ # save_notebook() and Quarto renders
└── cache/     # cache_remember() and cache()
```

Output directories are created on first save. `save_notebook("notebooks/analysis.qmd")` renders a document into `outputs/notebooks/`, keeping rendered HTML and PDF files separate from `.qmd` sources.

## Working directories

- `notebooks/`: Quarto, R Markdown, or Jupyter analysis notebooks.
- `scripts/`: standalone R scripts and batch jobs.
- `functions/`: reusable R functions sourced by `scaffold()`.
- `scratch/`: temporary exploratory files (gitignored).
- `docs/`: project documentation.
- `logs/`: batch and cluster job logs (gitignored).

## Privacy-sensitive projects

Privacy-sensitive projects (`project_sensitive`) split `inputs/` and `outputs/` into ignored `private/` directories and tracked `public/` directories:

```text
inputs/
├── private/    # Gitignored: raw/, intermediate/, final/
└── public/     # Tracked: raw/, intermediate/, final/
outputs/
├── private/    # Gitignored: tables/, figures/, models/, reports/, notebooks/, cache/
└── public/     # Tracked: tables/, figures/, models/, reports/, notebooks/
```

`save_*()` functions write to `outputs/private/` by default and write to `outputs/public/` when passed `public = TRUE`. Claude Code projects also receive `.claude/settings.json` deny rules for private paths and `.env`. See [Privacy-sensitive project](guide:privacy-sensitive-project).

## Data integrity hashes

`data_add()`, `data_save()`, and the first `data_read()` record a SHA-256 hash for each catalog entry in `framework.db`. Entries saved with `locked = TRUE`, or marked `locked: true` in the catalog, cause `data_read()` to stop with an error if the file changes on disk:

```text
Error: Hash mismatch for locked data 'raw.survey'
Expected hash: 95aecaa7399a
Current hash:  5140963bf019
```

Unlocked entries, the default, emit a warning and update the recorded hash.

## Project structures

- **Standard project** (`project`): general-purpose research and data analysis layout.
- **Privacy-sensitive project** (`project_sensitive`): separated private and public input and output trees.
- **Course** (`course`): slides, assignments, modules, readings, and course documents.
- **Presentation** (`presentation`): single Quarto RevealJS slide deck or report.

Configure user-wide defaults on Framework Cloud or edit a project's `settings.yml`. See [Setup](guide:setup).
