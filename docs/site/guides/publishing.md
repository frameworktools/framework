---
id: publishing
title: Publishing
section: features
position: 15
description: 'Publishing notebooks, data, and files to Framework Cloud and S3 storage'
---
## Overview

Framework provides functions for publishing notebooks, data, and files to S3-compatible storage (AWS S3, MinIO, DigitalOcean Spaces, etc.). Share rendered reports, datasets, and analysis outputs with colleagues or the public.

## Framework Cloud artifacts

Publish a plot, table, report, rendered Quarto book, or other file to your project.
Each publication has a share page and version history. Publishing to the same
`slug` adds a version. `to = "cloud"` selects Cloud even when a bucket is configured.
A new artifact is unlisted. The slug only names it. Add `visibility = "public"`
for a readable URL. A later publish keeps the artifact's visibility unless you
set one.

```r
publish("outputs/effect.png", to = "cloud", slug = "treatment-effect")
publish("_book", to = "cloud", slug = "study-book")
publish(results_table, to = "cloud", slug = "estimates")
publish(fitted_model, to = "cloud", slug = "adjusted-model", password = "reviewer-password")
```

### Publishable R objects

Besides files and rendered folders, `publish()` takes these R objects and
converts them to files:

- **Tables.** Data frames, tibbles, data.tables, matrices, and contingency
  tables from `table()` or `xtabs()` publish with every row. Cloud shows a
  profile of each column above the rows: missing values, distinct values, and
  summary statistics with a small histogram for numbers or the most common
  values for text. Variable labels from `attr(x, "label")` (as haven sets
  them) are kept. Row names other than 1 to n become a first column named
  `row`. One-way tables become `value` and `count` columns; two-way tables
  are wide, with the row variable first.
- **ANOVA tables.** `anova()` results and `summary(aov(...))` publish as
  tables with their row names.
- **Hypothesis tests.** `t.test()`, `chisq.test()`, `wilcox.test()`,
  `cor.test()`, `prop.test()`, `fisher.test()`, `shapiro.test()`, and other
  `htest` results publish the method, statistic, parameters, p-value,
  estimates, and confidence interval. The data name is left out, since it
  can contain expressions with data.
- **Models.** `lm`, `glm`, `aov`, `MASS::glm.nb`, `MASS::polr`,
  `nnet::multinom`, lme4 `lmer` and `glmer`, `survival::coxph`,
  `survival::survreg`, fixest, and `mgcv::gam` models publish their
  coefficients with standard errors, test statistics, p-values, and 95% Wald
  intervals, plus fit statistics, the formula, and the family and link. Cloud
  draws a coefficient plot and can show odds, rate, hazard, or time ratios
  when the model has that reading. Mixed models add their random effects and
  `gam` models their smooth terms. Models never include the observations,
  residuals, fitted values, or the model object. broom isn't needed.
- **Plots.** ggplot and patchwork plots, base graphics saved with
  `recordPlot()`, and lattice plots publish as SVG (7 by 5 inches on a white
  background) when svglite is installed, otherwise as a 300 dpi PNG. A plot
  whose SVG would be larger than 5 MB, such as a scatter plot of many points,
  publishes as PNG.
- **Interactive plots.** plotly and other htmlwidgets publish as a
  self-contained HTML file. This needs pandoc; when it isn't on the PATH,
  the copy that ships with Quarto is used.
- **Formatted tables.** `gt`, `gtsummary`, and `flextable` objects publish as
  HTML when their packages are installed.

Storage buckets receive CSV for tables, HTML summaries for `lm` and `glm`,
and JSON for other models and tests. `integer64` columns export as text so
identifiers stay exact.

`title`, `description`, `kind`, `password`, and `visibility` set Cloud metadata.
A password requires at least eight characters. Visibility can be `"public"` or
`"unlisted"`; anyone with an unlisted link can open it unless it is password protected.

Use `to = "bucket"` for an explicit storage upload or `to = "github"` for GitHub
Pages. With no `to`, existing bucket-first destination selection is preserved.

## S3 configuration

Define S3 connections in `settings.yml` (either format works):

**Preferred (connections.storage_buckets):**
```yaml
connections:
  storage_buckets:
    default:
      bucket: my-reports-bucket
      region: us-east-1
      prefix: projects/analysis
      access_key: env("S3_ACCESS_KEY")
      secret_key: env("S3_SECRET_KEY")
      static_hosting: true
    backup:
      bucket: backup-bucket
      endpoint: https://minio.internal:9000
      access_key: env("MINIO_ACCESS_KEY")
      secret_key: env("MINIO_SECRET_KEY")
  default_storage_bucket: default
```

Store credentials in `.env`:

```bash
S3_ACCESS_KEY=AKIA...
S3_SECRET_KEY=...
```

### Configuration options

| Option | Description |
|--------|-------------|
| `bucket` | S3 bucket name |
| `region` | AWS region (default: us-east-1) |
| `prefix` | Path prefix for all uploads |
| `endpoint` | Custom endpoint for S3-compatible services |
| `access_key` | AWS access key (use `env()`) |
| `secret_key` | AWS secret key (use `env()`) |
| `static_hosting` | If true, uploads notebooks as `dest/index.html` |
| `default` | (connections format) Mark this bucket as the default |

Set a default bucket with `default_storage_bucket` (or `default: true` on a bucket). If no default is set, Framework falls back to the first bucket defined.

## Notebook publishing

Render and upload Quarto notebooks in one step:

```r
# Publish a notebook
publish_notebook("notebooks/analysis.qmd")
# -> https://bucket.s3.amazonaws.com/prefix/analysis.html

# Custom destination
publish_notebook("notebooks/analysis.qmd", dest = "reports/q4-2024")

# Use specific connection
publish_notebook("notebooks/analysis.qmd", connection = "backup")
```

### Static hosting mode

When `static_hosting: true`, notebooks are uploaded as `index.html` files for clean URLs:

```r
publish_notebook("analysis.qmd", dest = "reports/q4")
# Uploads to: reports/q4/index.html
# Access at:  https://bucket.s3.amazonaws.com/reports/q4/
```

Without static hosting, files keep their extension:

```r
publish_notebook("analysis.qmd", dest = "reports/q4")
# Uploads to: reports/q4.html
# Access at:  https://bucket.s3.amazonaws.com/reports/q4.html
```

### Self-contained and multi-file output

By default, notebooks are rendered as self-contained HTML with all resources embedded:

```r
# Self-contained (default) - single file, portable
publish_notebook("analysis.qmd", self_contained = TRUE)

# Multi-file - smaller HTML, separate assets (requires static_hosting)
publish_notebook("analysis.qmd", self_contained = FALSE)
```

## Data publishing

Upload data frames or existing files:

```r
# Publish a data frame as CSV
publish_data(my_results, "datasets/results.csv")

# Publish as other formats
publish_data(my_results, "datasets/results.parquet", format = "parquet")
publish_data(my_results, "datasets/results.rds", format = "rds")

# Publish with compression
publish_data(my_results, "datasets/results.csv", compress = TRUE)
# -> uploads as results.csv.gz

# Publish an existing file
publish_data("outputs/model.rds", "models/v2/model.rds")
```

## Directory publishing

Upload entire directories:

```r
# Upload a directory
publish_dir("outputs/dashboard/")

# Custom destination
publish_dir("outputs/dashboard/", dest = "dashboards/v2/")

# Filter files
publish_dir("outputs/", pattern = "\\.html$")
```

## Generic publishing

For any file or directory:

```r
# Single file
publish("outputs/report.html")

# With custom destination
publish("outputs/report.html", dest = "reports/final.html")

# Directory
publish("outputs/charts/", dest = "visualizations/")
```

## Example workflow

A typical publishing workflow:

```r
library(framework)
scaffold()

# Run analysis
results <- analyze_data(my_data)
summary_plot <- create_visualization(results)

# Save outputs locally
save_table(results, "final_results")
save_figure(summary_plot, "summary")

# Render notebook
save_notebook("notebooks/analysis.qmd")

# Publish to S3
publish_notebook("notebooks/analysis.qmd", dest = "reports/q4-analysis")
publish_data(results, "data/q4-results.csv")

# Share the URL
# https://my-bucket.s3.amazonaws.com/reports/q4-analysis/
```

## Best practices

### Prefixes

```yaml
connections:
  storage_buckets:
    default:
      prefix: team-name/project-name
  default_storage_bucket: default
```

This keeps your bucket organized:

```text
team-name/project-name/reports/...
team-name/project-name/data/...
```

### Versioned destinations

Include dates or versions in destinations:

```r
publish_notebook("analysis.qmd", dest = "reports/analysis-2024-01-15")
publish_data(results, "data/results-v2.csv")
```

### Static hosting for reports

Enable `static_hosting: true` for cleaner URLs when sharing reports:

```text
# With static hosting
https://bucket.s3.amazonaws.com/reports/q4/

# Without
https://bucket.s3.amazonaws.com/reports/q4.html
```

## Collection attachment

Select an existing collection in the current project by its ID or slug. The
client resolves the collection before uploading and does not create collections.
The collection follows the artifact's latest version.

```r
publish("outputs/effect.png", to = "cloud", slug = "effect", collection = "main-findings", share_unlisted = TRUE)
```

Public collections require public artifacts. Sharing an unlisted artifact with
readers of an unlisted collection requires explicit consent through
`share_unlisted`.
If attachment fails after the artifact uploads, publishing returns its URL and
warns that collection attachment failed. Attach the artifact from the project
Outputs page; publishing again creates another version.

---

<div style="display: flex; justify-content: space-between">

[← Environment](guide:environment)

[Project types →](guide:project-types)

</div>
