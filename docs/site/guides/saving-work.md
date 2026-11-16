---
id: saving-work
title: Saving work
section: features
position: 9
description: 'Saving tables, figures, models, reports, and notebooks with framework.db tracking'
---
## Output functions

Framework provides typed functions for saving tables, figures, models, reports, and rendered notebooks under `outputs/` while logging each file's SHA-256 hash and metadata to `framework.db`.

### Tables

`save_table()` writes data frames as CSV by default, or as RDS, Parquet (`arrow`), or Excel (`writexl`):

```r
save_table(results, "analysis_results")
save_table(results, "analysis_results", format = "rds")
save_table(results, "analysis_results", format = "parquet")
save_table(results, "analysis_results", format = "xlsx")

# Route to outputs/public/tables/ in split-output projects
save_table(summary_stats, "public_summary", public = TRUE)
```

Names containing `/` create subdirectories inside the target output folder (`save_table(df, "meeting-2026-10-16/cohort")` writes `outputs/tables/meeting-2026-10-16/cohort.csv`). `save_figure()` and `save_model()` support `/` paths the same way.

### Figures

`save_figure()` writes `ggplot2` objects, recorded plots, or the active graphics device:

```r
save_figure(my_plot, "revenue_chart")
save_figure(my_plot, "revenue_chart", width = 10, height = 6, dpi = 300)
save_figure(my_plot, "revenue_chart", format = "pdf")
save_figure(my_plot, "revenue_chart", format = "svg")

# Export multiple formats in one call
save_figure(my_plot, "journal/figure_2", format = c("pdf", "eps", "png"))

# Capture the active base R graphics device
plot(mtcars$mpg, mtcars$hp)
save_figure(name = "mpg_vs_hp")
```

Supported formats are `png` (default, 8 by 6 inches at 300 dpi), `pdf`, `svg`, `eps`, `jpg`, `jpeg`, `tiff`, and `emf` (requires `devEMF`; otherwise export `svg` or `pdf` and convert externally). When multiple formats are requested, `save_figure()` validates all formats and `overwrite = FALSE` targets before writing any file, records each file in `result_list()`, and returns the written paths in order.

### Models

`save_model()` serializes fitted model objects as `.rds` files, and `load_model()` reads them back:

```r
model <- lm(y ~ x, data = df)
save_model(model, "regression_v1")
restored <- load_model("regression_v1")
```

### Reports and notebooks

`save_report()` copies or moves an existing rendered file into `outputs/reports/`. `save_notebook()` renders `.qmd`, `.Rmd`, or `.ipynb` documents with Quarto into `outputs/notebooks/`:

```r
save_report("outputs/analysis.html", "quarterly_report")
save_report("outputs/analysis.html", "quarterly_report", move = TRUE)

save_notebook("notebooks/analysis.qmd", "final_analysis")
save_notebook("notebooks/analysis.qmd", format = "pdf")
```

HTML renders embed resources by default. Execute Jupyter notebooks before calling `save_notebook()` because Quarto renders the outputs already stored in `.ipynb` cells.

Every `save_*()` function creates missing output directories on demand and overwrites existing files unless `overwrite = FALSE`.

## Results tracking in framework.db

Each `save_*()` call inside a Framework project writes a row to the `results` table in `framework.db`, even if `scaffold()` has not run yet:

| Column | Contents |
|--------|----------|
| `name` | Project-relative path, such as `outputs/tables/summary.csv` |
| `type` | `table`, `figure`, `model`, `report`, or `notebook` |
| `public` | Whether `public = TRUE` was passed |
| `hash` | SHA-256 digest of the saved file |
| `created_at` | Initial save timestamp |
| `updated_at` | Most recent save timestamp |

Saves outside a Framework project write the file without database tracking.

## Private and public output routing

Projects split outputs into `outputs/private/` and `outputs/public/` whenever `security.sensitive` is `true` or `outputs_private_*` / `outputs_public_*` keys appear under `directories`:

```r
# Default: writes to outputs/private/tables/
save_table(detailed_results, "patient_outcomes")

# Public: writes to outputs/public/tables/
save_table(aggregated_stats, "summary", public = TRUE)
```

Privacy-sensitive `.gitignore` files exclude `outputs/private/` while allowing `outputs/public/` to be committed. In single-tree projects, all outputs write to `outputs/<type>/` and the `public` flag is still recorded in `framework.db`. Run `project_info()` to inspect resolved output directories.

## Directory layout

Standard projects:

```text
outputs/
├── tables/
├── figures/
├── models/
├── reports/
└── notebooks/
```

Privacy-sensitive projects:

```text
outputs/
├── private/
│   ├── tables/
│   ├── figures/
│   ├── models/
│   ├── reports/
│   └── notebooks/
└── public/
    ├── tables/
    ├── figures/
    ├── models/
    ├── reports/
    └── notebooks/
```

Customize paths under `directories` in `settings.yml` (`outputs_tables`, `outputs_private_tables`, and related keys).

## Publishing saved outputs

`save_*()` writes local files only. Call `publish()` to upload saved files or R objects to Framework Cloud, GitHub Pages, S3, or a folder destination. Before uploading files from private paths, `publish()` warns and prompts in interactive sessions and stops in non-interactive runs unless `include_private = TRUE`. See [Publishing](guide:publishing).
