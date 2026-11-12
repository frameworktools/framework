# Framework

An R package for structured, reproducible data analysis projects.

**Status:** Version 2.0 is on CRAN and works with Framework Cloud.

## Quick Start

```r
# Install from CRAN
install.packages("framework")

# Or the development version from GitHub
remotes::install_github("frameworktools/framework")

# One-time global setup (author info, preferences) in the GUI
framework::setup()

# Create projects using your saved defaults
framework::new_project()
framework::new_project("my-analysis", "~/code/my-analysis")
framework::new_presentation("quarterly-review", "~/talks/q4")
framework::new_course("stats-101", "~/teaching/stats")

# After cloning a project on another machine or a cluster
framework::bootstrap()
```

Manage your defaults and blueprints at [framework.pub](https://framework.pub)
after `framework::cloud_login()`, or edit `settings.yml` directly. The local
GUI (`gui()`) is retired.

### Project Types

- **project** (default): Full-featured research projects with notebooks, scripts, organized data management, and documentation
- **project_sensitive**: Like project, but with additional privacy protections for sensitive data
- **course**: Teaching materials with slides, assignments, and modules
- **presentation**: Single talks with one Quarto file and minimal setup

**Example project structure:**

```
project/
├── notebooks/              # Exploratory analysis
├── scripts/                # Production pipelines
├── inputs/
│   ├── raw/                # Raw data
│   ├── intermediate/       # Cleaned datasets
│   └── final/              # Curated analytic datasets
├── outputs/                # Made on first save
│   ├── tables/             # save_table()
│   ├── figures/            # save_figure()
│   ├── models/             # save_model()
│   ├── reports/            # save_report()
│   └── cache/              # cache_remember() (gitignored)
├── functions/              # Custom functions
├── docs/                   # Documentation
├── scratch/                # Temporary files (gitignored)
├── logs/                   # Run logs, cluster job output (gitignored)
├── settings.yml            # Project configuration
├── framework.db            # Metadata tracking database (gitignored)
└── .env                    # Secrets (gitignored)
```

The standard project's `.gitignore` does not ignore `inputs/` or `outputs/`:
keep data that must not be committed in a folder named `private/` (any
`private/` folder is ignored), or use the **project_sensitive** type, which
splits inputs and outputs into ignored `private/` and committed `public/`
folders. A project_sensitive project starts with the `data_security` and
`check_sensitive_dirs` pre-commit checks on, installed after the initial
commit (turn them off with `git_hooks_disable()`).

## Skill sync

Bring a project's skills up to date with its Framework Cloud setup, and send
edited ones back:

```r
framework::pull_skills()
framework::push_skills()
```

Sync one local skill and its companion files with your Framework Cloud account:

```r
framework::skills_sync(".claude/skills/my-skill", dry_run = TRUE)
framework::skills_sync(".claude/skills/my-skill")
```

Local edits create account versions. Edited Framework skills become private
forks with an exact source version. Concurrent edits stop for reconciliation.
[Skill sync guide](https://framework.pub/docs/skill-sync).

## Why Framework?

Framework reduces boilerplate and enforces best practices:

- **Project scaffolding**: Standardized directories, config-driven setup
- **Data management**: Declarative data catalog and integrity tracking
- **Auto-loading**: Load packages with one command; no more scattered `library()` calls
- **Pain-free renv**: Reproducible package management without fighting renv
- **Caching**: Smart caching for expensive computations
- **Database helpers**: PostgreSQL, SQLite, DuckDB, MySQL with credential management
- **File formats**: CSV, TSV, RDS, Stata (.dta), SPSS (.sav), SAS (.xpt, .sas7bdat)

## Core Workflow

### 1. Initialize Your Session

```r
library(framework)
scaffold()  # Loads packages, functions, config, standardizes working directory
```

### 2. Create Notebooks & Scripts

```r
# Quarto notebook (default)
make_notebook("exploration")    # → notebooks/exploration.qmd
make_qmd("analysis")            # Always Quarto
make_qmd("bp-ldl", title = "BP and LDL")  # Title as typed, for acronyms
make_rmd("report")              # RMarkdown

# Presentations
make_revealjs("slides")         # reveal.js presentation

# Scripts
make_script("process-data")     # → scripts/process-data.R

# List available templates
stubs_list()
```

**Custom stubs:** Create a `stubs/` directory with your own templates.

### 3. Load Data

**Via config (recommended):**

```yaml
# settings.yml
data:
  inputs:
    raw:
      survey:
        path: inputs/raw/survey.csv
        type: csv
        locked: true  # Errors if file changes
```

```r
df <- data_read("inputs.raw.survey")
```

**Direct path:**

```r
df <- data_read("inputs/raw/my_file.csv")       # CSV
df <- data_read("inputs/raw/stata_file.dta")    # Stata
df <- data_read("inputs/raw/spss_file.sav")     # SPSS
```

Every read is logged with a SHA-256 hash for integrity tracking.

### 4. Cache Expensive Operations

```r
model <- cache_remember("model_v1", {
  expensive_model_fit(df)
}, expire_after = "1 day")  # or a number of hours, such as 24

# Recompute when the data, the code, or a parameter changes
model <- cache_remember("model_v2", {
  expensive_model_fit(data_read("inputs.final.cohort"), k = 4)
}, depends_on = list("inputs.final.cohort", "functions/fit.R", k = 4))
```

### 5. Save Results

**Save data files:**

```r
data_save(processed_df, "inputs.intermediate.cleaned_data")
# → saves to inputs/intermediate/cleaned_data.rds

data_save(final_df, "inputs.final.analysis_ready", type = "csv")
# → saves to inputs/final/analysis_ready.csv
```

**Save analysis outputs:**

```r
save_table(summary_df, "summary")       # → outputs/tables/summary.csv
save_figure(plot, "trend")              # → outputs/figures/trend.png
save_figure(plot, "paper/fig2", format = c("pdf", "eps"))  # → outputs/figures/paper/fig2.pdf, .eps
save_model(model, "regression_model")   # → outputs/models/regression_model.rds
model <- load_model("regression_model")  # read it back
show_table(summary_df, digits = 2)      # Markdown table in a Quarto or Jupyter notebook
```

### 6. Query Databases

```yaml
# settings.yml
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

```r
df <- db_query("SELECT * FROM users WHERE active = true", "db")

# Build a database from SQL and CSV files, in one transaction each
db_execute_file("db", "sql/schema.sql")
db_copy_from("db", "cdm.concept", "inputs/raw/concept.csv")
```

## Enhanced Data Viewing

`view()` provides rich, browser-based data exploration:

```r
view(mtcars)                    # Interactive table with search/filter/export
view(settings())                # Tabbed YAML + R structure for lists
view(ggplot(mtcars, aes(mpg, hp)) + geom_point())  # Interactive plots
```

## Configuration

**Simple:**
```yaml
default:
  packages:
    - dplyr
    - ggplot2
  data:
    example: data/example.csv
```

**Advanced (split files):**
```yaml
default:
  data: settings/data.yml
  packages: settings/packages.yml
  connections: settings/connections.yml
```

**Secrets in `.env`:**
```env
DB_HOST=localhost
DB_PASS=secret
```

**Reference in config:**
```yaml
connections:
  databases:
    db:
      driver: postgres
      host: env("DB_HOST")
      password: env("DB_PASS", "default")
```

### AI Assistant Support

New projects can include instruction files for AI coding assistants
(AGENTS.md, with CLAUDE.md and GitHub Copilot copies) and Framework skills in
`.claude/skills/`. To keep them current:

```r
ai_regenerate_context()   # Refresh the generated sections of AGENTS.md
ai_sync_context()         # Copy AGENTS.md to the other assistants' files
pull_skills()             # Update the project's skills from its Cloud setup
push_skills()             # Send locally edited skills to Cloud
pull_all()                # Bring in Cloud's packages, skills, and data registry
push_all()                # Send packages, edited skills, and the data registry
```

## Key Functions

| Function | Purpose |
|----------|---------|
| `scaffold()` | Initialize session (load packages, functions, config) |
| `data_read()` | Read data from path or catalog |
| `data_save()` | Save data with integrity tracking |
| `project_path()` | A path from the project root, like `here::here()` |
| `db_query()` | Execute SQL query, return data |
| `db_execute()` | Execute SQL command |
| `db_execute_file()`, `db_copy_from()` | Run a .sql file; load a CSV into a table |
| `cache_remember()` | Lazy evaluation with caching |
| `save_table()`, `save_figure()`, `save_model()` | Save analysis outputs (`load_model()` reads a model back) |
| `result_list()` | List saved outputs |
| `package_add()` | Record a package in settings and install it |
| `scratch_capture()` | Quick debug/temp file save |
| `renv_enable()` | Enable renv for reproducibility |
| `packages_snapshot()` | Save package versions to renv.lock |
| `packages_restore()` | Restore packages from renv.lock |
| `git_security_audit()` | Scan for data leaks and security issues |

## Data Integrity & Security

- **Hash tracking**: All data files tracked with SHA-256 hashes
- **Locked data**: Flag files as read-only, errors on modification
- **Gitignore by default**: Any `private/` folder, `.env`, caches, scratch,
  and logs are ignored
- **Security audits**: `git_security_audit()` detects data leaks, publishing
  folders git would commit, passwords written into connection settings, and
  tracked data with identifier-like columns (`data_save()` warns about those too)

Framework does not encrypt data files. Keep sensitive data in ignored
`private/` folders, on encrypted storage, or both.

### Security Auditing

```r
audit <- git_security_audit()                  # Full audit
audit <- git_security_audit(auto_fix = TRUE)   # Auto-fix .gitignore issues
```

## Reproducibility with renv

Optional renv integration (off by default):

```r
renv_enable()           # Enable for this project
packages_snapshot()     # Save current versions
packages_restore()      # Restore from renv.lock
renv_disable()          # Disable (keeps renv.lock)
```

**Version pinning in settings.yml:**

```yaml
packages:
  - dplyr                    # Latest from CRAN
  - ggplot2@3.4.0           # Specific version
  - tidyverse/dplyr@main    # GitHub with branch
```

## Roadmap

- Better database support (DuckDB, MySQL, SQL Server)
- Results publishing to S3
- Enhanced results tracking with blinding support

### Publishing destinations

`publish()` accepts tables, models, figures, rendered documents, and files.
Choose a named destination in `settings.yml`:

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
        bucket: results
```

```r
publish(mtcars, slug = "fuel-economy", title = "Fuel economy")
publish(lm(mpg ~ wt + hp, mtcars), to = "pages", slug = "fuel-economy-model")
publish("outputs/report.html", to = "cloud")
```

Folder and GitHub destinations include a site index, offline reader pages,
SHA-256 file manifests, and version archives. Named S3 destinations upload
immutable version folders and the latest bundle. An explicit `to` overrides
`publish.default`. Without either, existing bucket and Cloud selection applies.
Legacy bucket uploads retain their file paths and formats.

Passwords and unlisted links require Cloud. Private folder and S3 destinations
use `visibility: private` and destination access controls. The `private: true`
configuration remains a compatibility alias. S3 also requires API confirmation of
a non-public bucket policy and all Public Access Block settings.
Private GitHub Pages requires confirmation from GitHub's Pages API through
an authenticated `gh` command. Unsupported sharing options fail before delivery.

External deliveries with a project token record metadata in Cloud. File contents
and local folder paths stay at the destination. Tracking failures produce a warning
and preserve the completed delivery. Legacy bucket metadata uses version 1;
conflicting updates produce a tracking warning.

`new_project()` is the preferred project creation function. `new()` remains
available for existing scripts and can mask `methods::new()` when attached.
