---
name: framework-outputs
description: Use when saving tables, figures, models, or rendered notebooks in a project that uses the Framework package. Covers save_table(), save_figure(), save_model(), save_notebook(), and result_list().
metadata:
  title: "Framework: saving outputs"
  summary: Save and list analysis tables, figures, models, and notebooks.
---

# Framework: saving outputs

Prefer the `save_*()` helpers. Each writes to the project's outputs folder for
that kind of result and records the file, so `result_list()` finds it.

```r
save_table(summary_df, "quarterly_summary")              # outputs/tables/ (csv)
save_table(report_df, "annual_report", format = "xlsx")
save_figure(plot, "enrollment_trend")                    # outputs/figures/ (png)
save_model(model, "regression_model")                    # outputs/models/ (rds)
save_notebook("notebooks/analysis.qmd")                  # render and save HTML

result_list()                 # everything saved so far
result_list(type = "model")   # models only
```

Read a saved model back with `readRDS()` on the path `save_model()` returns.

In a privacy-sensitive project, outputs save to the private folders by
default. Pass `public = TRUE` only when the user asks.
