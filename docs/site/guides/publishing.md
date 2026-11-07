---
id: publishing
title: Publishing
section: features
position: 16
description: 'Publishing notebooks, data, and files to Framework Cloud, GitHub Pages, and S3 storage'
---
## Overview

Framework publishes notebooks, R objects, data, and files. Publishing is always an explicit call. Nothing is uploaded on its own.

Destinations:

- **Framework Cloud**: framework.pub or a self-hosted server. Versions, share pages, and access controls.
- **GitHub Pages**: The project's own Pages site, through git.
- **S3-compatible storage**: AWS S3, MinIO, Cloudflare R2, and similar.
- **Folders**: A local or shared folder, through a named destination.

Pick one with `to`: `"cloud"`, `"github"`, `"bucket"`, or a named destination. With no `to`, `publish()` and `publish_notebook()` use `publish.default` from settings. Without one, they use a storage bucket when `connection` is given or a bucket is configured. Otherwise, a project set up from Framework Cloud publishes there. With none of these, publishing stops and shows a bucket example.

## Private paths

Before uploading, Framework checks the full path of every file. A file in a private folder may hold restricted data. A folder is private when it is named `private` or its name ends in `_private`, in any case, such as `outputs/private/tables/detail.csv`, `~/Private/notes.html`, or `data/study_private/ids.csv`, or when the settings mark it private: a `directories` entry whose key contains `private` (and not `public`), such as `outputs_private_tables: results/held`. File names don't count, so `notebooks/01-private-and-public.qmd` is not flagged, and the `/private/` macOS adds to `/tmp` and `/var` doesn't count. Framework warns and, in an interactive session, asks before publishing (default No). A non-interactive session stops unless you pass `include_private = TRUE`:

```text
Warning: 1 file(s) to upload are in private folders:
  /home/me/study/outputs/private/tables/detail.csv
Error: Not uploading files from private folders without confirmation. Review it, then pass include_private = TRUE to upload it.
```

The same confirmation covers sources whose path doesn't tell:

- In a project with `security: sensitive: true`, every notebook (`.qmd`, `.Rmd`, `.ipynb`) published with `publish()` or `publish_notebook()`, and every object, such as a data frame or model given to `publish()` or a data frame given to `publish_data()`.
- In any project, a notebook whose code quotes private data: a path in a private folder (`"inputs/private/raw/ids.csv"`), or a data catalog name whose entry is private (`"inputs.ids"`). Other strings, such as settings keys (`"inputs_private_raw"`) or patterns (`"private|public"`), don't count.

Each reason is a warning, and one question covers them all. This is a quick check of the text, not an analysis: data reached any other way isn't found.

## Framework Cloud setup

Publishing to Framework Cloud uses a project token. Create the project on Framework Cloud, then set it up locally with its token:

```r
framework::setup("fw_...")

# Or
framework::new_project(key = "fw_...", location = "~/projects/study")
```

Both write the token and its server to the project's `.env`:

```bash
FW_PROJECT_TOKEN=...
FW_CLOUD_URL=https://framework.pub
```

`.env` is gitignored. Each collaborator runs `setup()` with the project token. For a self-hosted server, pass `url =` to `setup()` or `new_project()`.

Your own sign-in is separate. `cloud_login()` connects this computer to your account for blueprints, settings sync, and skill sync. `cloud_status()` shows the server in use.

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
A password requires at least eight characters. Visibility can be `"public"`,
`"unlisted"`, or `"private"`. Anyone with an unlisted link can open it unless it
is password protected. Passwords, unlisted links, and collections need Framework Cloud.

### Notebooks on Framework Cloud

`publish_notebook()` renders a Quarto document and publishes the HTML:

```r
publish_notebook("notebooks/analysis.qmd", to = "cloud", slug = "analysis")
```

Framework Cloud takes HTML output only. Each publish adds a version.

`publish_notebook()` takes `title` and `description` too. Without `title`, a document published with `publish()` or `publish_notebook()` uses the `title` in its YAML front matter, then its file name.

## GitHub Pages

`to = "github"` publishes to the project's GitHub Pages site:

```r
publish("outputs/report.html", to = "github", slug = "main-results")
publish_notebook("notebooks/analysis.qmd", to = "github")
```

Framework copies the document to `published/<slug>/` at the top of the repository, replacing what was there. It commits only that folder and the site index, then pushes to the branch's upstream, origin, or another GitHub remote. Anything else you staged stays staged. Interactive sessions confirm first.

- The project must be a git repository with a GitHub remote.
- The default slug is the file name in lowercase, with other characters as `-`. "Final Report (v2).html" becomes `final-report-v2`.
- A folder needs an `index.html` at its top.
- `dest`, `connection`, `password`, `collection`, and a `TRUE` or `FALSE` `slug` are errors here.
- The site is limited to 1 GB.

Turn on **Publish with GitHub Pages** for the project in Framework Cloud. It enables the site and adds the workflow that deploys `published/` from the default branch. Publishing from another branch warns.

> [!WARNING]
> GitHub Pages sites are public, even from a private repository.

## Named destinations

Name destinations under `publish:` in `settings.yml`. `publish.default` picks the one used when `to` is omitted:

```yaml
publish:
  default: site
  destinations:
    site:
      driver: folder
      path: ~/site
```

Drivers are `cloud`, `github`, `folder`, and `s3`. A folder `path` may start with `~`; a relative path starts at the project root, even when a notebook runs from `notebooks/`. A folder destination writes each artifact to `<path>/<slug>/`, keeps each version under `v/<n>/`, and maintains a site index. Folder destinations use `slug` and reject `dest`. Credential fields in a destination must be `env("VARIABLE")` references, with the values in `.env`.

```r
publish(results_table, to = "site", slug = "estimates")
```

### A folder as a site root

A folder destination with `layout: site-root` keeps only the latest publish, at the folder's root: a rendered deck becomes `docs/index.html`, with no `<slug>/` folder, version archive, or site index. This replaces copying `deck.html` to `docs/index.html` for a GitHub Pages site served from `docs/`.

```yaml
publish:
  destinations:
    pages:
      driver: folder
      path: docs
      url: https://me.github.io/my-talk
      visibility: public
      layout: site-root
```

```r
publish_notebook("presentation.qmd", to = "pages")
```

Each publish first removes the files the previous one wrote, which `docs/.framework-site.json` lists, and leaves other files, such as `CNAME` or `.nojekyll`, alone. A file the new publish writes replaces one of the same name. An HTML source is written once, as `index.html`. Objects and other files get the same offline reader, data, and representation files as a versioned folder, at the root. `publish_list()` shows the one artifact. The default layout is `versioned`; `layout` on any other driver is an error.

Set `visibility: public` on a folder meant to be committed, as a Pages folder is. Otherwise new projects add the folder to `.gitignore`, and the security audit warns about it.

## S3 configuration

Define storage buckets in `settings.yml` (or `settings/connections.yml`):

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

Uploads need the aws.s3 package. `storage_test()` checks a bucket's credentials. When set, the `S3_*` environment variables take precedence over a bucket's own values. See the [Connections guide](guide:connections#object-storage-connections).

### Configuration options

| Option | Description |
|--------|-------------|
| `bucket` | S3 bucket name |
| `region` | AWS region (default: us-east-1) |
| `prefix` | Path prefix for all uploads |
| `endpoint` | Custom endpoint for S3-compatible services |
| `access_key` | AWS access key (use `env()`). `access_key_id` also works. |
| `secret_key` | AWS secret key (use `env()`). `secret_access_key` also works. |
| `session_token` | Temporary session token (use `env()`) |
| `static_hosting` | If true, uploads notebooks as `dest/index.html` |
| `default` | Mark this bucket as the default |

Set a default bucket with `default_storage_bucket` (or `default: true` on a bucket). If no default is set, Framework falls back to the first bucket defined.

## Notebook publishing

Render and upload Quarto notebooks to a bucket in one step:

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

`publish_data()` uploads data frames or existing files to a storage bucket. Formats are CSV, RDS, Parquet (needs arrow), and JSON:

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

`publish_data()`, `publish_dir()`, and `publish_list()` follow `to` and `publish.default` as `publish()` does. With an S3 destination, a `connection`, or no `publish.default`, they work on the storage bucket as shown here. With a folder, GitHub, or Cloud destination, `publish_data()` and `publish_dir()` publish through `publish()`, and `publish_list()` lists a folder destination's artifacts. The slug is `dest` with each `/` turned into `-`, normalized like every slug (lowercase, each run of other characters a `-`); `publish_data()` also drops the file extension. Both say which slug they used:

```r
publish_data(my_results, "tables/bp_by_visit.csv", to = "site")   # slug "tables-bp-by-visit"
publish_dir("figures", dest = "figures/meeting", to = "site")      # slug "figures-meeting"
publish_list(to = "site")
```

## Directory publishing

`publish_dir()` uploads entire directories to a storage bucket:

```r
# Upload a directory
publish_dir("outputs/dashboard/")

# Custom destination
publish_dir("outputs/dashboard/", dest = "dashboards/v2/")

# Filter files
publish_dir("outputs/", pattern = "\\.html$")
```

## Generic publishing

For any file or directory. With a bucket configured, these go to the bucket:

```r
# Single file
publish("outputs/report.html")

# With custom destination
publish("outputs/report.html", dest = "reports/final.html")

# Directory
publish("outputs/charts/", dest = "visualizations/")

# List what is in the bucket
publish_list("reports/")
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

# Publish to Framework Cloud
publish_notebook("notebooks/analysis.qmd", to = "cloud", slug = "q4-analysis")
publish(results, to = "cloud", slug = "q4-results")

# Or to a storage bucket
publish_notebook("notebooks/analysis.qmd", to = "bucket", dest = "reports/q4-analysis")
publish_data(results, "data/q4-results.csv")
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
Outputs page. Publishing again creates another version.

## Data ledger

`data_save()` records a hash of each saved file in `framework.db`. A project set up from Framework Cloud can share that record:

```r
ledger_push()                          # Send new entries to the cloud ledger
ledger_list()                          # List the cloud ledger
data_verify("inputs.raw.enrollment")   # Compare a file with the records
```

Only hashes leave the machine. The data stays local. `ledger_push()` is explicit. For an entry on every save, set `FW_LEDGER=live` or `options: cloud_ledger: live` in `settings.yml`.

---

<div style="display: flex; justify-content: space-between">

[← Environment](guide:environment)

[Project types →](guide:project-types)

</div>
