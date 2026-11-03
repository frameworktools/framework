# Framework

An R package for structured, reproducible data analysis projects.

**Status:** Stable 1.x on CRAN. Version 2.0 (in development) adds Framework Cloud integration.

## Quick Start

```r
# Install from CRAN
install.packages("framework")

# Or the development version from GitHub
remotes::install_github("frameworktools/framework")

# One-time global setup (author info, preferences) in the GUI
framework::setup()

# Create projects using your saved defaults
framework::new()
framework::new("my-analysis", "~/projects/my-analysis")
framework::new_presentation("quarterly-review", "~/talks/q4")
framework::new_course("stats-101", "~/teaching/stats")

# After cloning a project on another machine or a cluster
framework::bootstrap()
```

The GUI (`setup()`, `gui()`) needs the optional `plumber` package:
`install.packages("plumber")`. plumber depends on `sodium`, which needs the
system libsodium library and can be hard to install on shared servers and HPC
clusters. Everything else in Framework works without it, so on a cluster you
can skip the GUI and edit `settings.yml` directly.

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
│   ├── raw/                # Raw data (gitignored)
│   ├── intermediate/       # Cleaned datasets (gitignored)
│   ├── final/              # Curated analytic datasets (gitignored)
│   └── reference/          # External documentation (gitignored)
├── outputs/
│   ├── private/            # Tables, figures, models, cache (gitignored)
│   └── public/             # Share-ready artifacts
├── functions/              # Custom functions
├── docs/                   # Documentation
├── logs/                   # Run logs, cluster job output (gitignored)
├── settings.yml            # Project configuration
├── framework.db            # Metadata tracking database
└── .env                    # Secrets (gitignored)
```

## Skill sync

Sync a local skill and its companion files with your Framework Cloud account:

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
- **Data management**: Declarative data catalog, integrity tracking, encryption
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
df <- data_load("inputs.raw.survey")
```

**Direct path:**

```r
df <- data_load("inputs/raw/my_file.csv")       # CSV
df <- data_load("inputs/raw/stata_file.dta")    # Stata
df <- data_load("inputs/raw/spss_file.sav")     # SPSS
```

Every read is logged with a SHA-256 hash for integrity tracking.

### 4. Cache Expensive Operations

```r
model <- get_or_cache("model_v1", {
  expensive_model_fit(df)
}, expire_after = 1440)  # 24 hours
```

### 5. Save Results

**Save data files:**

```r
data_save(processed_df, "intermediate.cleaned_data")
# → saves to inputs/intermediate/cleaned_data.rds

data_save(final_df, "final.analysis_ready", type = "csv")
# → saves to inputs/final/analysis_ready.csv
```

**Save analysis outputs:**

```r
save_table(summary_df, "summary")       # → outputs/tables/summary.csv
save_figure(plot, "trend")              # → outputs/figures/trend.png
save_model(model, "regression_model")   # → outputs/models/regression_model.rds
```

### 6. Query Databases

```yaml
# settings.yml
connections:
  db:
    driver: postgresql
    host: env("DB_HOST")
    database: env("DB_NAME")
    user: env("DB_USER")
    password: env("DB_PASS")
```

```r
df <- db_query("SELECT * FROM users WHERE active = true", "db")
```

## Enhanced Data Viewing

`view()` provides rich, browser-based data exploration:

```r
view(mtcars)                    # Interactive table with search/filter/export
view(config)                    # Tabbed YAML + R structure for lists
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
  db:
    host: env("DB_HOST")
    password: env("DB_PASS", "default")
```

### AI Assistant Support

Framework creates instruction files for AI coding assistants:

```r
framework::configure_ai_agents()
```

Supported: Claude Code (CLAUDE.md), GitHub Copilot, AGENTS.md

## Key Functions

| Function | Purpose |
|----------|---------|
| `scaffold()` | Initialize session (load packages, functions, config) |
| `data_read()` | Read data from path or catalog |
| `data_save()` | Save data with integrity tracking |
| `db_query()` | Execute SQL query, return data |
| `db_execute()` | Execute SQL command |
| `cache_remember()` | Lazy evaluation with caching |
| `save_table()`, `save_figure()`, `save_model()` | Save analysis outputs |
| `result_list()` | List saved outputs |
| `package_add()` | Record a package in settings and install it |
| `scratch_capture()` | Quick debug/temp file save |
| `renv_enable()` | Enable renv for reproducibility |
| `packages_snapshot()` | Save package versions to renv.lock |
| `packages_restore()` | Restore packages from renv.lock |
| `security_audit()` | Scan for data leaks and security issues |

## Data Integrity & Security

- **Hash tracking**: All data files tracked with SHA-256 hashes
- **Locked data**: Flag files as read-only, errors on modification
- **Password-based encryption**: Ansible Vault-style encryption for sensitive data
- **Gitignore by default**: Private directories auto-ignored
- **Security audits**: `security_audit()` detects data leaks

### Encryption

```r
# Save encrypted data
data_save(sensitive_df, "private.data", encrypted = TRUE)

# Load (auto-detects encryption)
data <- data_load("private.data")
```

Password from `ENCRYPTION_PASSWORD` env var or interactive prompt.

### Security Auditing

```r
audit <- security_audit()              # Full audit
audit <- security_audit(auto_fix = TRUE)  # Auto-fix .gitignore issues
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
