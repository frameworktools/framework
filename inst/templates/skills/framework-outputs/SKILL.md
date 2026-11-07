---
name: framework-outputs
description: Use when saving analysis outputs, caching expensive computations, running database queries, or publishing files in this Framework project - covers save_table(), save_figure(), save_model(), cache_remember(), db_query(), and publish().
metadata:
  title: Saving outputs and publishing
  summary: Save tables, figures, and models, cache slow steps, query databases, and publish.
---

# Framework Outputs, Caching, Queries, and Publishing

## Saving Outputs

Save outputs with the `save_*()` helpers. Each writes to the configured
outputs directory (created on first use) and records the file so
`result_list()` can find it.

```r
save_table(summary_df, "quarterly_summary")                 # outputs/tables/ (csv)
save_table(report_df, "annual_report", format = "xlsx")
save_figure(plot, "enrollment_trend")                       # outputs/figures/ (png)
save_model(model, "regression_model")                       # outputs/models/ (rds)
save_notebook("notebooks/analysis.qmd")                     # render and save HTML

result_list()                  # Everything saved so far
result_list(type = "model")    # Only models
```

Read a saved model back with `readRDS()` on the path `save_model()` returns.
In sensitive projects outputs are private by default; pass `public = TRUE`
only for outputs that are safe to share.

## Caching Expensive Computations

```r
# Compute once, cache the result; re-runs only if missing or expired
model <- cache_remember("fitted_model", {
  fit_complex_model(training_data)
}, expire_after = "7 days")

# Manual cache read/write
cache("processed_data", large_dataframe)   # Write
df <- cache_get("processed_data")          # Read (NULL if missing)
cache_forget("processed_data")             # Remove one entry
```

Use meaningful cache names; caches are tracked in `framework.db` with hashes
and expiry.

## Database Queries

Connections are defined in settings.yml (or settings/connections.yml). Use
Framework's query helpers rather than opening DBI connections manually:

```r
users <- db_query("SELECT * FROM users WHERE active = 1", "main_db")
db_execute("UPDATE runs SET done = 1 WHERE id = 42", "main_db")

# Several statements on one connection
db_with("main_db", {
  DBI::dbListTables(conn)
})
```

## Publishing

`publish()` and `publish_notebook()` upload to the project's storage bucket
when one is configured, or to Framework Cloud when the project was set up
from it:

```r
publish("outputs/report.html")                       # Upload a file, returns public URL
publish_notebook("notebooks/analysis.qmd")           # Render Quarto doc and upload
publish("outputs/charts/", dest = "reports/charts/") # Upload a directory
publish("outputs/report.html", to = "github")        # GitHub Pages: commits published/report/ and pushes
```

`to = "github"` makes a public website, even from a private repository.
Publish there only when the user asks for it.

Never publish files from private/sensitive directories. The publish functions
warn about any source in a folder named `private` or ending in `_private` (or a
settings folder whose key says private) and ask the user to confirm.
In a script they stop. Never pass `include_private = TRUE` or answer the
prompt on the user's behalf. See the `framework-sensitive-data` skill if this project has one.
