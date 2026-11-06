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

# Public output (for sensitive projects)
save_table(summary_stats, "public_summary", public = TRUE)
```

### Figures

Save ggplot2 or base R graphics:

```r
# Basic save
save_figure(my_plot, "revenue_chart")

# With dimensions
save_figure(my_plot, "revenue_chart", width = 10, height = 6, dpi = 300)

# Different formats
save_figure(my_plot, "revenue_chart", format = "pdf")
save_figure(my_plot, "revenue_chart", format = "svg")
```

### Models

Save fitted model objects:

```r
# Save a model
model <- lm(y ~ x, data = df)
save_model(model, "regression_v1")

# Save with specific format
save_model(model, "regression_v1", format = "rds")
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
```

## Automatic tracking

Every `save_*` function automatically logs to the `results` table in `framework.db`:

| Field | Description |
|-------|-------------|
| `name` | The name you provided |
| `type` | Output type (table, figure, model, report, notebook) |
| `public` | Whether saved to public or private directory |
| `hash` | File integrity hash |
| `created_at` | When first saved |
| `updated_at` | When last modified |

## Public and private outputs

For Privacy Sensitive projects, the `public` parameter controls output location:

```r
# Private (default) - goes to outputs/private/tables/
save_table(detailed_results, "patient_outcomes")

# Public - goes to outputs/public/tables/
save_table(aggregated_stats, "summary", public = TRUE)
```

Private outputs are gitignored. Public outputs can be shared and committed.

For Standard projects, the `public` parameter still works but outputs go to a single `outputs/` directory structure.

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

---

<div style="display: flex; justify-content: space-between">

[← Viewing work](guide:viewing-work)

[Git integration →](guide:git)

</div>
