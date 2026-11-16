---
id: publishing
title: Publishing
section: features
position: 16
description: 'Publishing artifacts and notebooks to Framework Cloud, GitHub Pages, S3, and folders'
---
## Destinations

`publish()` and `publish_notebook()` upload rendered documents, R objects, datasets, and directories only when called explicitly. Supported destinations:

- **Framework Cloud** (`"cloud"`): [framework.pub](https://framework.pub) (includes 1 GB of artifact storage on free accounts) or a self-hosted Framework Cloud server, with version history, interactive readers, passwords, unlisted links, and collections.
- **GitHub Pages** (`"github"`): deploys `published/<slug>/` to the repository's GitHub Pages site.
- **S3-compatible object storage** (`"bucket"` or named `s3` destination): AWS S3, Cloudflare R2, MinIO, and compatible endpoints.
- **Folders** (named `folder` destination): local or shared network directories with offline readers and manifests.

Select a destination with `to` (`"cloud"`, `"github"`, `"bucket"`, or a named key under `publish.destinations`). When `to` is omitted, Framework checks `publish.default`, then an explicit `connection` or configured storage bucket, and then `FW_PROJECT_TOKEN` in `.env`. If none is configured, `publish()` stops and prints a configuration example.

## Private path safeguards

Before uploading, Framework inspects source paths, project sensitivity, and notebook references:

- **Private directories**: any path containing a directory named `private` or ending in `_private` (case-insensitive, excluding macOS `/private/tmp` and `/private/var`), or matching a `directories` entry whose key contains `private` without `public` (such as `outputs_private_tables`). Filenames containing `private` (`notebooks/01-private-and-public.qmd`) are not flagged.
- **Sensitive projects**: in projects with `security.sensitive: true`, every notebook (`.qmd`, `.Rmd`, `.ipynb`) and every R object passed to `publish()`, `publish_notebook()`, or `publish_data()`.
- **Quoted private sources**: in any project, a notebook whose source text quotes a path inside a private folder (`"inputs/private/raw/ids.csv"`) or a private catalog entry (`"inputs.ids"`).

Framework warns for each match and prompts for confirmation in interactive sessions (default No). Non-interactive sessions stop with an error unless `include_private = TRUE` is passed:

```text
Warning: 1 file(s) to upload are in private folders:
  /home/me/study/outputs/private/tables/detail.csv
Error: Not uploading files from private folders without confirmation. Review it, then pass include_private = TRUE to upload it.
```

## Framework Cloud setup

Publishing to Framework Cloud authenticates with a project token stored in `.env`:

```r
framework::setup("fw_...")
# Or
framework::new_project(key = "fw_...", location = "~/code/study")
```

Both write `FW_PROJECT_TOKEN` and `FW_CLOUD_URL` to `.env` (gitignored). Pass `url` when connecting to a self-hosted server. Collaborators run `setup("fw_...")` on their own machines to populate `.env`. Account-level login (`cloud_login()`) is separate and manages blueprints, settings sync, and skill sync.

## Framework Cloud artifacts

Publish files, rendered directories (such as Quarto books), or R objects to a project slug. Repeating a `slug` appends a new version. New artifacts default to `"unlisted"` visibility unless `visibility` is set (`"public"`, `"unlisted"`, or `"private"`), and subsequent versions preserve the existing visibility unless overridden. Passwords require at least eight characters.

```r
publish("outputs/effect.png", to = "cloud", slug = "treatment-effect")
publish("_book", to = "cloud", slug = "study-book")
publish(results_table, to = "cloud", slug = "estimates")
publish(fitted_model, to = "cloud", slug = "adjusted-model", password = "reviewer-password")
```

### Supported R objects

`publish()` converts R objects into structured artifacts without requiring `broom`:

- **Tables**: data frames, tibbles, `data.table` objects, matrices, `table()` / `xtabs()` contingency tables, and `anova()` / `summary(aov(...))` tables publish with column profiles (missingness, distinct counts, numeric histograms, or top text values) and preserve `haven`-style `label` attributes. Non-default row names become a `row` column, and `integer64` columns serialize as text so identifiers stay exact.
- **Hypothesis tests**: `htest` objects (`t.test()`, `chisq.test()`, `wilcox.test()`, `cor.test()`, `prop.test()`, `fisher.test()`, `shapiro.test()`, and others) publish method, statistic, parameters, p-value, estimates, and confidence intervals while omitting `data.name` to avoid leaking expressions.
- **Models**: `lm`, `glm`, `aov`, `MASS::glm.nb`, `MASS::polr`, `nnet::multinom`, `lme4` (`lmer`, `glmer`), `survival` (`coxph`, `survreg`), `fixest`, and `mgcv::gam` publish coefficients, standard errors, test statistics, p-values, 95% Wald intervals, fit statistics, formulas, family/link metadata, random effects, and smooth terms without uploading raw observations, residuals, or fitted values. Framework Cloud renders coefficient plots and optional odds, rate, hazard, or time ratios.
- **Static plots**: `ggplot2` / `patchwork` objects, `recordPlot()` captures, and `lattice` plots export as 7x5 in SVG when `svglite` is installed (falling back to 300 dpi PNG when `svglite` is absent or the SVG exceeds 5 MB).
- **Interactive widgets and formatted tables**: `plotly` and other `htmlwidgets` export as self-contained HTML via Pandoc (using Quarto's bundled Pandoc if needed), and `gt`, `gtsummary`, and `flextable` objects export as HTML.

When published to S3 buckets instead of Cloud, tables export as CSV, `lm` and `glm` export as HTML summaries, and other models and tests export as JSON.

### Notebooks on Framework Cloud

`publish_notebook()` renders a Quarto document to HTML and uploads a new version:

```r
publish_notebook("notebooks/analysis.qmd", to = "cloud", slug = "analysis")
```

When `title` is omitted, Framework uses the YAML frontmatter `title` and falls back to the filename.

### Collection attachment

Attach an artifact to an existing project collection by collection ID or slug:

```r
publish(
  "outputs/effect.png",
  to = "cloud",
  slug = "effect",
  collection = "main-findings",
  share_unlisted = TRUE
)
```

Collections track the artifact's latest version. Public collections require public artifacts, and attaching an unlisted artifact to an unlisted collection requires `share_unlisted = TRUE`. If collection attachment fails after upload, `publish()` returns the artifact URL and warns so you can attach it from the project's **Artifacts** page on Framework Cloud.

## GitHub Pages

`to = "github"` publishes HTML files or directories (with a top-level `index.html`) to `published/<slug>/` at the repository root, updates the site index, commits only those paths without disturbing other staged changes, and pushes to the GitHub remote (confirming first in interactive sessions):

```r
publish("outputs/report.html", to = "github", slug = "main-results")
publish_notebook("notebooks/analysis.qmd", to = "github")
```

Enable **Publish with GitHub Pages** on the project in Framework Cloud to configure Pages and add the deployment workflow on the default branch. GitHub Pages sites have a 1 GB size limit and do not support `dest`, `connection`, `password`, or `collection`.

> [!WARNING]
> GitHub Pages sites are publicly accessible on the web even when the backing GitHub repository is private unless GitHub Enterprise access controls are verified via `gh`.

## Named destinations

Configure named `cloud`, `github`, `folder`, or `s3` destinations under `publish:` in `settings.yml`:

```yaml
publish:
  default: site
  destinations:
    site:
      driver: folder
      path: ~/site
```

```r
publish(results_table, to = "site", slug = "estimates")
```

Relative `folder` paths resolve from the project root. By default (`layout: versioned`), a folder destination writes artifacts under `<path>/<slug>/v/<n>/` with offline readers and a site index. Credential fields in named destinations must use `env("VARIABLE")` references.

### Site-root folder layout

Setting `layout: site-root` on a `folder` destination writes the rendered output directly at `<path>/index.html` without `<slug>/` subdirectories, version archives, or a site index, suited to GitHub Pages sites served from `docs/`:

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

Each publish cleans only the files recorded in `<path>/.framework-site.json` from the previous publish, preserving files such as `CNAME` or `.nojekyll`, and never copies `.qmd`, `.Rmd`, or `.ipynb` sources. Set `visibility: public` on committed folders such as `docs/` so `.gitignore` and `git_security_audit()` treat them as intentional public outputs.

## S3 configuration

Configure S3-compatible buckets under `connections.storage_buckets` in `settings/connections.yml` or `settings.yml`:

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

Bucket uploads require `aws.s3`. Test credentials with `storage_test()`. Session or `.env` `S3_*` variables override bucket YAML fields when set; see [Connections](guide:connections#object-storage-connections).

| Option | Description |
|--------|-------------|
| `bucket` | Target bucket name |
| `region` | Region (defaults to `us-east-1`) |
| `prefix` | Key prefix prepended to all uploads |
| `endpoint` | Custom HTTPS endpoint for S3-compatible storage |
| `access_key` | Access key ID via `env()` (`access_key_id` also accepted) |
| `secret_key` | Secret key via `env()` (`secret_access_key` also accepted) |
| `session_token` | Temporary session token via `env()` |
| `static_hosting` | Uploads notebooks as `<dest>/index.html` when `true` |
| `default` | Marks the bucket as default when `default_storage_bucket` is unset |

### Bucket uploads for notebooks, datasets, and directories

```r
# Render and upload a notebook (self_contained = FALSE requires static_hosting: true)
publish_notebook("notebooks/analysis.qmd", dest = "reports/q4-2024")
publish_notebook("notebooks/analysis.qmd", connection = "backup")

# Upload data frames or files in CSV, Parquet, RDS, or JSON (optional gzip via compress = TRUE)
publish_data(my_results, "datasets/results.csv")
publish_data(my_results, "datasets/results.parquet", format = "parquet")
publish_data(my_results, "datasets/results.csv", compress = TRUE)

# Upload directories or arbitrary files and list bucket keys
publish_dir("outputs/dashboard/", dest = "dashboards/v2/")
publish_dir("outputs/", pattern = "\\.html$")
publish("outputs/report.html", dest = "reports/final.html")
publish_list("reports/")
```

When `to` or `publish.default` targets a `folder`, `github`, or `cloud` destination rather than a raw bucket, `publish_data()` and `publish_dir()` route through `publish()` using a normalized hyphenated slug derived from `dest` (`"tables/bp_by_visit.csv"` becomes `"tables-bp-by-visit"`), and `publish_list(to = "site")` lists artifacts in that folder destination.

## Data integrity ledger

Projects with `FW_PROJECT_TOKEN` can publish SHA-256 dataset hashes from `framework.db` to the Framework Cloud ledger while keeping data files local:

```r
ledger_push()
ledger_list()
data_verify("inputs.raw.enrollment")
```

Set `FW_LEDGER=live` or `options.cloud_ledger: live` in `settings.yml` to push hashes automatically on every `data_save()`.
