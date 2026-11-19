# Framework for R

Structured, reproducible data analysis projects in R.

Version 2.0 is available on CRAN and integrates with [Framework Cloud](https://framework.pub).

## Quick start

```r
# Install from CRAN
install.packages("framework")

# Or install the development version from GitHub
remotes::install_github("frameworktools/framework")

# Optional: sign in to Framework Cloud for blueprints, defaults, and publishing
framework::cloud_login()

# Create projects
framework::new_project("my-analysis", "~/code/my-analysis")
framework::new_project_sensitive("medical-study", "~/code/medical-study")
framework::new_presentation("quarterly-review", "~/talks/q4")
framework::new_course("stats-101", "~/teaching/stats")

# Create a local project from a Framework Cloud project token
framework::setup("fw_...")

# Initialize a cloned project on another machine or cluster
framework::bootstrap()
```

Edit project defaults and blueprints on Framework Cloud under **Settings > Project defaults** after running `framework::cloud_login()`, or edit `settings.yml` directly in each project. The local `gui()` interface is retired.

`new_project()` is the primary project creation function. `new()` remains available for existing scripts and can mask `methods::new()` when attached.

## Project types

- `project` (default): research projects with notebooks, scripts, data directories, outputs, and documentation.
- `project_sensitive`: separates private and public data directories and enables stricter Git and agent rules.
- `course`: teaching materials with slides, assignments, readings, and modules.
- `presentation`: single slide decks or reports with one Quarto file.
- `bare`: minimal configuration (`settings.yml`, `.gitignore`, and `.framework/spec.json`) for custom layouts.

Standard project layout:

```text
project/
├── notebooks/              # Analysis notebooks
├── scripts/                # Standalone scripts and pipelines
├── inputs/
│   ├── raw/                # Read-only source data
│   ├── intermediate/       # Cleaned datasets
│   └── final/              # Analysis-ready datasets
├── outputs/                # Save folders created on first save
│   ├── notebooks/          # Rendered notebooks
│   ├── tables/             # save_table()
│   ├── figures/            # save_figure()
│   ├── models/             # save_model()
│   ├── reports/            # save_report()
│   └── cache/              # cache_remember() (gitignored)
├── functions/              # Reusable R functions
├── docs/                   # Project documentation
├── scratch/                # Temporary files (gitignored)
├── logs/                   # Run logs and cluster output (gitignored)
├── settings/               # Split configuration files
├── settings.yml            # Root project configuration
├── framework.db            # Local metadata database (gitignored)
└── .env                    # Secrets and tokens (gitignored)
```

A standard project's `.gitignore` does not ignore `inputs/` or `outputs/`. Store restricted files in a `private/` directory (every `private/` directory is ignored) or use `project_sensitive`, which splits inputs and outputs into ignored `private/` and tracked `public/` directories. A `project_sensitive` project starts with the `data_security` and `check_sensitive_dirs` pre-commit checks enabled. Disable individual checks with `git_hooks_disable()`.

## Core features

- **Project scaffolding**: standard directory layouts and YAML configuration.
- **Data catalog**: dot-notation data references (`inputs.raw.survey`) with SHA-256 hash verification.
- **Package management**: declarative package lists, auto-attachment during `scaffold()`, and optional `renv` lockfiles.
- **Computation caching**: disk caching in `framework.db` and RDS files with expiration and dependency tracking.
- **Database and storage connections**: PostgreSQL, SQLite, DuckDB, MySQL, MariaDB, SQL Server, and S3-compatible object storage with `.env` credential lookups.
- **Format readers**: CSV, TSV, RDS, Excel, Parquet, Stata (`.dta`), SPSS (`.sav`, `.por`), and SAS (`.sas7bdat`, `.xpt`).
- **Publishing**: versioned artifacts on Framework Cloud, GitHub Pages, S3 buckets, and local or shared folders.

## Workflow

### Session initialization

```r
library(framework)
scaffold()
```

`scaffold()` locates the project root, loads `.env` and `settings.yml`, prepares `framework.db`, installs missing project packages, attaches configured packages, sources `functions/*.R`, and runs `scaffold.R`.

### Notebooks and scripts

```r
make_notebook("exploration")              # -> notebooks/exploration.qmd
make_qmd("bp-ldl", title = "BP and LDL")  # Preserves acronym casing
make_rmd("report")                        # R Markdown
make_revealjs("slides")                   # RevealJS slides
make_script("process-data")               # -> scripts/process-data.R
stubs_list()                              # Available templates
```

Add custom templates in a project's `stubs/` directory or in `fw_config_dir()` with `write_framework_template()`.

### Data catalog and reads

Register datasets in `settings/data.yml` or `settings.yml`:

```yaml
data:
  inputs:
    raw:
      survey:
        path: inputs/raw/survey.csv
        type: csv
        locked: true
```

Read by catalog name or file path:

```r
df <- data_read("inputs.raw.survey")
df_dta <- data_read("inputs/raw/stata_file.dta")
df_sav <- data_read("inputs/raw/spss_file.sav")
```

Every catalog read checks the file's SHA-256 hash against `framework.db`. Locked entries stop with an error when the file changes on disk.

### Caching

```r
model <- cache_remember("model_v1", {
  expensive_model_fit(df)
}, expire_after = "1 day")

model <- cache_remember("model_v2", {
  expensive_model_fit(data_read("inputs.final.cohort"), k = 4)
}, depends_on = list("inputs.final.cohort", "functions/fit.R", k = 4))
```

### Saving datasets and outputs

Save intermediate and final datasets to the catalog:

```r
data_save(processed_df, "inputs.intermediate.cleaned_data")
data_save(final_df, "inputs.final.analysis_ready", type = "csv")
```

Save tables, figures, models, and rendered notebooks to `outputs/`:

```r
save_table(summary_df, "summary")
save_figure(plot, "trend")
save_figure(plot, "paper/fig2", format = c("pdf", "eps"))
save_model(model, "regression_model")
model <- load_model("regression_model")
show_table(summary_df, digits = 2)
```

### Database queries

Configure connections in `settings/connections.yml` or `settings.yml`:

```yaml
connections:
  default_database: db
  databases:
    db:
      driver: postgres
      host: env("DB_HOST")
      database: env("DB_NAME")
      user: env("DB_USER")
      password: env("DB_PASS")
```

Run queries and SQL scripts:

```r
df <- db_query("SELECT * FROM users WHERE active = true", "db")
db_execute_file("db", "sql/schema.sql")
db_copy_from("db", "cdm.concept", "inputs/raw/concept.csv")
```

### Interactive inspection

`view()` opens objects in a browser viewer across RStudio, Positron, VS Code, and terminals:

```r
view(mtcars)
view(settings())
view(ggplot(mtcars, aes(mpg, hp)) + geom_point())
```

## Configuration

Single-file `settings.yml`:

```yaml
default:
  packages:
    - dplyr
    - ggplot2
  data:
    example: data/example.csv
```

Split files (`settings/*.yml`):

```yaml
default:
  data: settings/data.yml
  packages: settings/packages.yml
  connections: settings/connections.yml
```

Secrets in `.env`:

```sh
DB_HOST=localhost
DB_PASS=secret
```

Environment variable lookups in `settings.yml`:

```yaml
connections:
  databases:
    db:
      driver: postgres
      host: env("DB_HOST")
      password: env("DB_PASS", "default")
```

## AI assistants and Cloud sync

New projects include `AGENTS.md`, pointer files for configured assistants (`CLAUDE.md` or `.github/copilot-instructions.md`), and skill files under `.claude/skills/` or `.agents/skills/`:

```r
ai_regenerate_context()   # Refresh generated sections of AGENTS.md
pull_skills()             # Pull skills from the project's Cloud setup
push_skills()             # Push locally edited skills to Cloud
skills_copy(from = "claude")  # Copy edited skills to the other assistant folders
skills_sync(".claude/skills/my-skill")
pull_all()                # Pull packages, skills, and data registry from Cloud
push_all()                # Push packages, skills, and data registry to Cloud
```

## Key functions

| Function | Purpose |
|----------|---------|
| `scaffold()` | Initialize the project session |
| `data_read()` | Read data from a catalog entry or file path |
| `data_save()` | Save data and record its SHA-256 hash |
| `project_path()` | Resolve a path relative to the project root |
| `db_query()` | Run a SQL query and return a data frame |
| `db_execute()` | Execute a SQL statement |
| `db_execute_file()`, `db_copy_from()` | Run a `.sql` file or load a CSV into a table |
| `cache_remember()` | Evaluate and cache an expression |
| `save_table()`, `save_figure()`, `save_model()` | Save analysis outputs (`load_model()` reads a saved model) |
| `result_list()` | List tracked outputs in `framework.db` |
| `package_add()` | Record a package in settings and install it |
| `scratch_capture()` | Save an object to `scratch/` during debugging |
| `renv_enable()` | Enable `renv` lockfile management |
| `packages_snapshot()`, `packages_restore()` | Write or restore `renv.lock` |
| `git_security_audit()` | Check for tracked private data and exposed secrets |

## Data integrity and security

- **SHA-256 hashes**: `data_read()` and `data_save()` record and verify file hashes in `framework.db`.
- **Locked entries**: `locked: true` raises an error if a source file changes.
- **Gitignore rules**: every template ignores `private/`, `.env`, caches, `scratch/`, `logs/`, and `framework.db`.
- **Security audit**: `git_security_audit()` checks `.gitignore` coverage, tracked private files, Git history, data files outside configured directories, `.env` tracking, and identifier-like column names.

```r
audit <- git_security_audit()
audit <- git_security_audit(auto_fix = TRUE)
```

Framework does not encrypt files on disk. Store restricted data in ignored `private/` directories on encrypted storage.

## Reproducibility with renv

`renv` integration is optional and disabled by default:

```r
renv_enable()
packages_snapshot()
packages_restore()
renv_disable()
```

Version pinning in `settings.yml` or `settings/packages.yml`:

```yaml
packages:
  - dplyr
  - ggplot2@3.4.0
  - tidyverse/dplyr@main
```

## Publishing

`publish()` uploads tables, models, hypothesis tests, figures, rendered documents, and directories to Framework Cloud, GitHub Pages, S3-compatible buckets, or local and shared folders. Framework Cloud accounts on `framework.pub` include 1 GB of artifact hosting at no charge.

Configure named destinations in `settings.yml`:

```yaml
default:
  publish:
    default: lab-share
    destinations:
      lab-share:
        driver: folder
        path: /Volumes/lab/published
        url: https://files.example.org/published
      pages:
        driver: github
      cloud:
        driver: cloud
      bucket:
        driver: s3
        bucket: results      # a connections.storage_buckets name
```

```r
publish(mtcars, slug = "fuel-economy", title = "Fuel economy")
publish(lm(mpg ~ wt + hp, mtcars), to = "pages", slug = "fuel-economy-model")
publish("outputs/report.html", to = "cloud")
```

Folder and GitHub destinations generate a site index, offline reader pages, SHA-256 manifests, and version archives. Named S3 destinations write immutable version directories alongside the latest bundle. Passwords, unlisted links, and collections require Framework Cloud. External deliveries in projects with `FW_PROJECT_TOKEN` record metadata in Framework Cloud while keeping file contents at the destination.
