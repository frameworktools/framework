---
id: conventions
title: Conventions
section: getting_started
position: 3
description: 'Framework conventions and project organization'
---
## Philosophy

Framework favors **convention over configuration**. Its defaults work for most projects. Nearly everything about how Framework structures projects is customizable.

Once your defaults are set on Framework Cloud, new projects use them without further organizational decisions. Projects stay consistent with each other.

This page describes Framework's basic features and conventions.

## scaffold()

Most notebooks or scripts in your project will start with:

```r
library(framework)
scaffold()
```

To namespace it fully, write `framework::scaffold()`.

The `scaffold()` function loads `.env`, installs the packages your project uses, attaches specified packages to the environment, sources functions from the `functions/` directory, and runs the project's `scaffold.R`. Depending on your configuration, it also sets a random seed or `ggplot2` theme.

## Package loading

Scaffold will call `library()` on auto-attached packages. We recommend fully namespacing functions in packages not commonly used across your project. Alternatively, you can call `library()` for these uncommon packages after `scaffold()`.

With an example `settings.yml`:

```yaml
packages:
  default_packages:
    - name: dplyr
      auto_attach: true
    - name: readr
      auto_attach: false
```

Your code would look like:

```r
library(framework)
scaffold()

df <- readr::read_csv("data.csv") |>
  filter(x > 0) |>
  mutate(y = x * 2)
```

Here `dplyr` functions (`filter`, `mutate`) work directly because `auto_attach: true`. But `readr` is namespaced explicitly since it's installed but not auto-loaded.

Add a package with `package_add("janitor")`. It records the package in settings and installs it.

## Functions and auto-loading

Framework automatically sources all `.R` files in your `functions/` directory when `scaffold()` runs.

For example, consider this `functions/` directory:

```text
functions/
├── text_processing.R
├── model_prep.R
└── plotting_helpers.R
```

Every file is sourced on scaffold, so all your functions are available without manual loading.

**Important:** Only include function definitions in these files. Any code outside a `function()` block will execute every time `scaffold()` runs.

Auto-loading replaces manual `source()` calls such as:

```r
source("helpers/cleaning.R")
source("helpers/plotting.R")
source("utils/text_processing.R")
```

With auto-loading, you can reorganize your functions directory (rename files, move functions between files, or add new files) without updating the notebooks or scripts that use them.

Set `source_all_functions: false` under `scaffold:` in `settings.yml` to turn this off.

See [Functions](guide:functions) for full documentation.

## Inputs and outputs

Framework separates **inputs** (read-only data) from **outputs** (generated files).

### Inputs

Data you consume lives in `inputs/`, organized by stage:

```text
inputs/
├── raw/           # External data, untouched
├── intermediate/  # Mid-pipeline transformations
└── final/         # Analysis-ready datasets
```

- **raw/**: Data from outside sources, never modified
- **intermediate/**: Cleaned or transformed data mid-pipeline
- **final/**: Analysis-ready datasets

### Data catalog

Framework tracks your data files in a catalog stored in `settings.yml` (`settings/data.yml` in split projects). As you work, register files with `data_add()`:

```r
data_add("inputs/raw/survey_2024.csv", name = "raw.survey")
data_add("inputs/final/analysis.rds", name = "final.analysis")
```

Or save and register in one step:

```r
data_save(clean_df, "inputs.intermediate.survey_clean")
```

The name starts with a configured directory, so this writes `inputs/intermediate/survey_clean.rds`.

The catalog lists the project's data files and their locations. Load data by name:

```r
survey <- data_read("raw.survey")
```

See [Data management](guide:data-management) for full documentation.

### Outputs

Files your project creates live in `outputs/`, organized by type:

```text
outputs/
├── tables/    # Data tables, CSVs
├── figures/   # Plots, charts
├── models/    # Saved model objects
├── reports/   # Finished reports
├── notebooks/ # Rendered notebooks
└── cache/     # Cached results
```

- **tables/**: `save_table()` writes here
- **figures/**: `save_figure()` writes here
- **models/**: `save_model()` writes here
- **reports/**: `save_report()` copies files here
- **notebooks/**: `save_notebook()` renders and saves here
- **cache/**: `cache_remember()` and the other cache functions write here

Folders are created on first save.

Use `save_notebook("notebooks/analysis.qmd")` to render and save in one step. Generated HTML/PDF files stay separate from source `.qmd` files, so outputs can be gitignored as a group.

## Work directories

- **notebooks/**: Quarto/R Markdown analysis files
- **scripts/**: Standalone R scripts
- **functions/**: Reusable R functions (auto-loaded by `scaffold()`)
- **scratch/**: One-off experiments, throwaway code (gitignored)
- **docs/**: Project documentation
- **logs/**: Run logs and cluster job output (gitignored)

## Sensitive data projects

For projects with privacy requirements, inputs and outputs split into private and public folders:

```text
inputs/
├── private/    # Sensitive data (gitignored): raw/, intermediate/, final/
└── public/     # Shareable data: raw/, intermediate/, final/
outputs/
├── private/    # tables/, figures/, models/, reports/, notebooks/, cache/
└── public/     # tables/, figures/, models/, reports/, notebooks/
```

The directory structure marks the privacy boundary. The `save_*()` functions write to the private folders unless you pass `public = TRUE`. Claude Code deny rules keep the agent out of the private folders. See [Privacy-sensitive projects](guide:privacy-sensitive-project).

## Data integrity

Framework automatically tracks data integrity. `data_add()` and `data_save()` record each file's hash in `framework.db`, which `scaffold()` creates. `data_read()` checks the hash. Entries are locked by default, so a changed file stops with an error:

```text
Error: Hash mismatch for locked data 'raw.survey'
Expected hash: 95aecaa7399a
Current hash:  5140963bf019
```

Unlocked entries (`locked = FALSE`) give a warning instead. The check catches accidental changes to data files.

## Customization

All project types are fully customizable:

- **Standard projects**: Default, general purpose data projects and pipelines
- **Sensitive data projects**: Private and public folders for restricted data
- **Courses**: Structured for lectures, assignments, and course documents
- **Presentations**: Minimal structure for RevealJS slides

Set defaults on Framework Cloud, or change a project's own `settings.yml`. See [Setup](guide:setup).

---

<div style="display: flex; justify-content: space-between">

[← Setup](guide:setup)

[settings.yml →](guide:settings-yml)

</div>
