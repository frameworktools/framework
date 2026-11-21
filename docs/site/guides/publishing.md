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
- **Bayesian models**: `brms` models and `rstanarm` models from `stan_glm()`, `stan_glm.nb()`, `stan_lm()`, `stan_aov()`, `stan_glmer()`, `stan_lmer()`, and `stan_glmer.nb()` publish posterior means, posterior SDs, 95% equal-tailed credible intervals, R-hat, and bulk and tail ESS. Logit and log-link count models add odds or rate ratios summarized over the exponentiated draws. Group-level SDs and correlations, distributional parameters such as `sigma`, priors, and sampler diagnostics (chains, draws, divergent transitions, maximum tree depth hits) are included, with Bayes R² for models where it is cheap to compute. LOO and WAIC appear only when the fit already stores them, as after `brms::add_criterion()`. The draws are never published.
- **Static plots**: `ggplot2` / `patchwork` objects, `bayesplot` plots (including `pp_check()` and `mcmc_pairs()`), lists of ggplots such as `brms::conditional_effects()` (combined with `patchwork`), `recordPlot()` captures, and `lattice` plots export as 7x5 in SVG when `svglite` is installed (falling back to 300 dpi PNG when `svglite` is absent or the SVG exceeds 5 MB).
- **Interactive widgets and formatted tables**: `plotly` and other `htmlwidgets` export as self-contained HTML via Pandoc (using Quarto's bundled Pandoc if needed), and `gt`, `gtsummary`, and `flextable` objects export as HTML.
- **DAGs**: `dagitty` graphs and `ggdag` `tidy_dagitty` objects publish as causal diagrams. See [DAGs](#dags).

When published to S3 buckets instead of Cloud, tables export as CSV, `lm` and `glm` export as HTML summaries, and other models and tests export as JSON.

### Notebooks on Framework Cloud

`publish_notebook()` renders a Quarto document to HTML and uploads a new version:

```r
publish_notebook("notebooks/analysis.qmd", to = "cloud", slug = "analysis")
```

When `title` is omitted, Framework uses the YAML frontmatter `title` and falls back to the filename.

### Code snippets

A code snippet holds a chunk's code and the text it printed: output, messages, warnings, and errors. Plots are left out. Blog posts and reports embed snippets beside the results the code produced. Framework Cloud highlights the code, shows ANSI colors, and folds output longer than 12 lines.

In a Quarto or R Markdown notebook, `publish_snippet()` publishes a chunk as the render showed it. Call it from any later chunk:

````markdown
```{r}
#| label: fit-model
fit <- lm(mpg ~ wt + hp, data = mtcars)
summary(fit)
```

```{r}
#| include: false
publish_snippet("fit-model", links = list(notebook = "https://example.org/analysis"))
```
````

`library(framework)` records each chunk's output during `quarto render` and `rmarkdown::render()`, so the labelled chunk must run after it. Chunk options apply: `echo: false` leaves out the code, and `results: hide`, `message: false`, and `warning: false` leave out those outputs. Output shown with `results: asis` and chunks read from the knitr cache are not recorded. Outside a render, as when a chunk runs in the editor, `publish_snippet()` publishes nothing and says why.

In an R script, `fw_snippet()` runs a braced block, prints its output, keeps its assignments, and publishes the code and printed text:

```r
fw_snippet("fit-model", {
  fit <- lm(mpg ~ wt + hp, data = mtcars)
  summary(fit)
})
```

The code keeps its comments and layout when R keeps source references. `Rscript` keeps them only with `options(keep.source = TRUE)` set before the script is parsed, as in `Rscript -e 'options(keep.source = TRUE); source("scripts/fit.R")'`. Otherwise the code is deparsed. When the block stops with an error, nothing is published.

Both functions take these options:

| Argument | Effect |
|----------|--------|
| `output = FALSE` | Publishes the code without its output |
| `folded = TRUE` | Folds the output blocks; `FALSE` opens them |
| `links` | `list(notebook = "https://...", model = "model-slug")`; a model is a slug in the same project or an https URL |
| `slug`, `title` | Default to the label |
| `repository` | Repository URL to name in the snippet |

The snippet names its file (from the git repository's top, else the project root), the chunk label, its code lines, and the commit checked out. It names the repository only when `repository` is passed or `publish.repository` is set in `settings.yml`:

```yaml
publish:
  repository: https://github.com/owner/study
```

With a GitHub repository, Framework Cloud links the snippet to its lines at that commit. Each render publishes again. When the snippet matches its newest version, Framework Cloud adds no version and Framework reports `Unchanged, still version N`.

### DAGs

A DAG artifact is a causal diagram with the DAGitty model text that defines it. Framework Cloud lays it out and draws it, and a reader can copy the text into dagitty.net or `dagitty::dagitty()` to get the same graph back. `publish()` takes a `dagitty` graph or a `ggdag` `tidy_dagitty`. `publish_dag()` adds the code that built the graph:

```r
library(ggdag)

dag <- dagify(
  cancer ~ smoking + age + genotype,
  smoking ~ age + genotype,
  exposure = "smoking", outcome = "cancer", latent = "genotype",
  labels = c(smoking = "Smoking", cancer = "Lung cancer", age = "Age", genotype = "Genotype")
)

publish(dag, slug = "smoking-dag")
publish_dag(dag, code = "dag <- dagify(...)", slug = "smoking-dag", title = "Smoking and lung cancer")
```

The DAG carries:

| Part | Contents |
|------|----------|
| DAGitty text | `as.character(dag)`: exposures, outcomes, and latent, adjusted, and selected nodes, and positions set with `coordinates()` or `dagify(coords = )`. A graph without positions is laid out left to right. |
| Labels | ggdag's labels (`dagify(labels = )`, `label<-`, or a `tidy_dagitty`'s `label` column), then `publish_dag(labels = )`, which wins |
| Adjustment sets | With an exposure and an outcome, the minimal sufficient sets from `adjustmentSets()`. An empty set means no adjustment is needed. No sets means no set of observed variables works, as when a latent variable confounds the effect. |
| Implications | The testable conditional independencies from `impliedConditionalIndependencies()` |
| Code | `publish_dag(code = )` only |

Positions keep the picture drawn in R. ggdag draws y pointing up; `dagitty::plot()`, dagitty.net, and Framework Cloud draw it pointing down. `publish_dag(y = )` says which way the positions were written:

| `y` | Positions |
|-----|-----------|
| `"auto"` | The default: `"up"` for a `tidy_dagitty`, or for a dagitty graph while ggdag is loaded; `"down"` otherwise |
| `"up"` | Written for ggdag. Each y is negated in the published DAGitty text. |
| `"down"` | Written for dagitty. Sent as `as.character(dag)` writes them. |

`publish()` uses `"auto"`. Only `pos` values change.

`publish_dag(effect = "direct")` computes adjustment sets for the direct effect. When dagitty can't compute the sets or implications, they are left out. Only DAGs publish; a pdag, mag, or pag is an error.

A blog post that embeds the DAG shows its legend, analysis, DAGitty text, and code. `display` turns sections off:

```r
publish_dag(dag, code = code, slug = "smoking-dag", display = list(analysis = FALSE, legend = FALSE))
```

The DAG settings are `legend`, `analysis`, `dagitty`, and `code`. See [Display settings](#display-settings).

### Display settings

Display settings choose what an artifact shows when another site embeds it: a blog post, academic.page, or a WordPress, Drupal, or Statamic page. Every setting is on until turned off. `publish()`, `publish_notebook()`, `publish_dag()`, `publish_snippet()`, and `fw_snippet()` take `display` as a named list or a named logical vector:

```r
publish(fitted_model, slug = "adjusted-model", display = list(details = FALSE))
publish(results_table, slug = "estimates", display = c(column_summaries = FALSE))
```

| Setting | Applies to | Off |
|---------|------------|-----|
| `title`, `description`, `author` | All artifacts | Not shown |
| `credit` | All artifacts | No link back to the artifact on Framework Cloud |
| `details` | Models and tests | No details section |
| `variable_tips` | Models | No tips on terms |
| `column_summaries` | Tables | No column summaries in tips |
| `output` | Code snippets | Output starts hidden, with Show output |
| `links` | Code snippets | No notebook and model links |
| `legend`, `analysis`, `dagitty`, `code` | DAGs | No role legend, analysis, DAGitty text, or source code |
| `interactive` | Live charts | The static image shows instead |

Framework Cloud keeps the settings with the artifact, for every version. A publish changes only the settings it names, and `TRUE` turns one back on. The owner can also change them on the artifact's Settings tab, under Embed contents. The reader page on Framework Cloud shows everything. A name that isn't a setting, or a value that isn't `TRUE` or `FALSE`, stops the publish before anything uploads. GitHub Pages, folders, and storage buckets ignore `display`, with a message.

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
