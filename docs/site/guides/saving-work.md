---
id: saving-work
title: Saving work
section: features
position: 9
description: 'Saved outputs and their tracking in framework.db'
---
## Overview

Framework saves tables, figures, models, reports, and notebooks. Each saved output is logged to `framework.db` with its metadata.

## Output types

### Tables

Save data frames in various formats:

```r
# CSV (default)
save_table(results, "analysis_results")

# Other formats
save_table(results, "analysis_results", format = "rds")
save_table(results, "analysis_results", format = "parquet")
save_table(results, "analysis_results", format = "xlsx")

# Public output (for projects with split outputs)
save_table(summary_stats, "public_summary", public = TRUE)
```

`xlsx` needs the writexl package. `parquet` needs arrow.

A name with `/` saves into subfolders of the output folder, which are created as needed: `save_table(df, "meeting-2026-10-16/cohort")` writes `outputs/tables/meeting-2026-10-16/cohort.csv`. The same holds for `save_figure()` and `save_model()`. Each file is listed in `result_list()` by its path from the project root.

### Figures

Save ggplot2 plots, recorded plots, or the current base R plot:

```r
# Basic save
save_figure(my_plot, "revenue_chart")

# With dimensions
save_figure(my_plot, "revenue_chart", width = 10, height = 6, dpi = 300)

# Different formats
save_figure(my_plot, "revenue_chart", format = "pdf")
save_figure(my_plot, "revenue_chart", format = "svg")

# Several formats at once, one file each
save_figure(my_plot, "journal/figure_2", format = c("pdf", "eps", "png"))

# The current plot on a screen device
plot(mtcars$mpg, mtcars$hp)
save_figure(name = "mpg_vs_hp")
```

Formats are `png` (the default), `pdf`, `svg`, `eps`, `jpg`, `jpeg`, `tiff`, and `emf`. The defaults are 8 by 6 inches at 300 dpi. With several formats, each file gets its own row in `result_list()`, and `save_figure()` returns the paths in the order given. Every format, and every existing file when `overwrite = FALSE`, is checked before anything is written, so a failed call writes nothing. `emf` needs the devEMF package; without it, save `svg` or `pdf` and convert them (for example with Inkscape or LibreOffice).

### Models

Save fitted model objects as `.rds` files:

```r
model <- lm(y ~ x, data = df)
save_model(model, "regression_v1")
```

### Reports and notebooks

Save rendered documents:

```r
# Copy a rendered report to outputs
save_report("outputs/analysis.html", "quarterly_report")

# Move instead of copy
save_report("outputs/analysis.html", "quarterly_report", move = TRUE)

# Render and save a Quarto notebook
save_notebook("notebooks/analysis.qmd", "final_analysis")

# Render to PDF or Word
save_notebook("notebooks/analysis.qmd", format = "pdf")
```

`save_notebook()` renders `.qmd`, `.Rmd`, and `.ipynb` files with Quarto. HTML output embeds its resources by default. Quarto renders a Jupyter notebook from the outputs saved in it without running its cells, so run the notebook first.

Every `save_*()` function overwrites an existing file unless you pass `overwrite = FALSE`. Output folders are created on first use.

## Automatic tracking

Every `save_*` function automatically logs to the `results` table in `framework.db`:

| Field | Description |
|-------|-------------|
| `name` | The file's path from the project root, such as `outputs/tables/summary.csv` |
| `type` | Output type (table, figure, model, report, notebook) |
| `public` | Whether `public = TRUE` was passed |
| `hash` | SHA-256 hash of the file |
| `created_at` | When first saved |
| `updated_at` | When last modified |

Results are tracked from the first save, even before `scaffold()` has run. Saves outside a Framework project are not tracked.

## Public and private outputs

Outputs split into private and public folders when the project has sensitive data on (`security.sensitive: true`) or lists `outputs_private_*` or `outputs_public_*` directories. This applies to any project type. In a split project, the `public` argument picks the folder:

```r
# Private (default) - goes to outputs/private/tables/
save_table(detailed_results, "patient_outcomes")

# Public - goes to outputs/public/tables/
save_table(aggregated_stats, "summary", public = TRUE)
```

Privacy Sensitive projects gitignore `outputs/private/`. Public outputs can be shared and committed.

In other projects, outputs go to one folder per type. The `public` flag is still recorded in `framework.db`. Run `project_info()` to see where each `save_*()` function writes.

## Output directories

Framework organizes outputs by type:

```text
outputs/
├── tables/           # save_table() output
├── figures/          # save_figure() output
├── models/           # save_model() output
├── reports/          # save_report() output
└── notebooks/        # save_notebook() output
```

For Privacy Sensitive projects:

```text
outputs/
├── private/
│   ├── tables/
│   ├── figures/
│   └── ...
└── public/
    ├── tables/
    ├── figures/
    └── ...
```

Folder paths come from the `outputs_*` keys under `directories` in `settings.yml`. For example, `outputs_tables` or `outputs_private_tables`.

## Publishing

`save_*()` writes local files only. To share an output, use `publish()`. It takes a saved file or an R object. Framework Cloud receives data frames, models, and hypothesis tests as structured data that its readers can display. Before uploading a path containing "private", `publish()` warns and asks in interactive sessions. Non-interactive sessions stop unless you pass `include_private = TRUE`. See [Publishing](guide:publishing).

---

<div style="display: flex; justify-content: space-between">

[← Viewing work](guide:viewing-work)

[Git integration →](guide:git)

</div>
