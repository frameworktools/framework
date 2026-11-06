---
id: settings-yml
title: settings.yml
section: getting_started
position: 4
description: 'The project configuration file'
---
## Overview

Every Framework project has a `settings.yml` file in its root that controls project-specific settings. Edit it directly.

Settings sit under a `default:` key, with optional environment overrides such as `production:`. A file without `default:` also works.

## Split files

Standard and sensitive projects split most sections into files under `settings/`. Presentations and courses keep everything in `settings.yml`. A section in `settings.yml` names its file:

```yaml
default:
  author: settings/author.yml
  packages: settings/packages.yml
  connections: settings/connections.yml
  data: settings/data.yml
```

Each file holds its section under the section key:

**settings/connections.yml:**
```yaml
connections:
  databases:
    analytics:
      driver: postgres
      host: env("DB_HOST")
      database: analytics
```

**settings/data.yml:**
```yaml
data:
  raw:
    survey:
      path: inputs/raw/survey.csv
      type: csv
```

You can split any section the same way, or put a split section back inline.

> [!NOTE]
> Root `settings.yml` values win if they conflict with a split file. Framework warns when this happens. `options` sections are merged.

## Sections

### Basics

Project name, type, tools, and privacy.

```yaml
project_name: my-analysis
project_type: project  # project, project_sensitive, course, presentation, or bare
tools:
  quarto: true
  renv: false
security:
  sensitive: false
```

`tools` records the tools the project was created with. `security.sensitive` is true for sensitive projects.

### Author

```yaml
author:
  name: "Your Name"
  email: "your.email@example.com"
  affiliation: "Your Institution"
```

### Project structure

Maps logical directory names to paths. All paths are relative to the project root. A standard project gets:

```yaml
directories:
  notebooks: notebooks
  scripts: scripts
  functions: functions
  inputs_raw: inputs/raw
  inputs_intermediate: inputs/intermediate
  inputs_final: inputs/final
  docs: docs
  outputs_tables: outputs/tables
  outputs_figures: outputs/figures
  outputs_models: outputs/models
  outputs_reports: outputs/reports
  cache: outputs/cache
  scratch: scratch
  logs: logs
render_dirs:
  notebooks: outputs/notebooks
  docs: outputs/docs
```

`render_dirs` sets where Quarto writes rendered files for each source folder. Sensitive projects use `inputs_private_raw`, `inputs_public_raw`, `outputs_private_tables`, `outputs_public_tables`, and so on.

Access with `settings("notebooks")` or `settings("directories.notebooks")`.

### Packages

R packages to install and optionally load with `scaffold()`:

```yaml
packages:
  use_renv: false
  default_packages:
    - name: dplyr
      source: cran
      auto_attach: true   # Load automatically
    - name: ggplot2
      source: cran
      auto_attach: true
    - name: readr
      source: cran
      auto_attach: false  # Install only, namespace explicitly
```

`package_add()` adds an entry and installs the package.

See [Packages](guide:packages) for details on version pinning and GitHub packages.

### Data catalog

The data catalog maps logical names to file paths. You can use two notation styles:

**Hierarchical** (nested structure):
```yaml
data:
  raw:
    survey:
      path: inputs/raw/survey.csv
      type: csv
  intermediate:
    cleaned:
      path: inputs/intermediate/cleaned.rds
      type: rds
  final:
    analysis:
      path: inputs/final/analysis.rds
      type: rds
```

**Mixed** (dots in keys):
```yaml
data:
  raw.survey:
    path: inputs/raw/survey.csv
    type: csv
  final.analysis:
    path: inputs/final/analysis.rds
    type: rds
```

Both styles are accessed the same way:

```r
data_read("raw.survey")
data_read("final.analysis")
```

See [Data management](guide:data-management) for full documentation.

### Git hooks

Git hook configuration:

```yaml
git:
  enabled: true
  hooks:
    data_security: false  # Check for private data and secrets before commit
```

The `ai_sync` hook was removed in 2.0. An `ai_sync: true` left in settings is ignored.

See [Git integration](guide:git) for details.

### AI assistants

AI assistant configuration:

```yaml
ai:
  enabled: true
  canonical_file: AGENTS.md
  assistants:
    - claude
```

`AGENTS.md` holds the AI instructions. `CLAUDE.md` points to it, so there is nothing to sync. Framework skills live in `.claude/skills/`.

See [AI assistants](guide:ai-assistants) for details.

### Connections

Database connections use `env()` to read credentials from [environment variables](#environment-variables):

```yaml
connections:
  default_database: framework
  databases:
    framework:
      driver: sqlite
      database: framework.db
    db:
      driver: postgres
      host: env("DB_HOST")
      database: env("DB_NAME")
      user: env("DB_USER")
      password: env("DB_PASS")
  storage_buckets: {}
```

See [Connections](guide:connections) for full documentation.

### Scaffold behavior

Settings for `scaffold()`:

```yaml
scaffold:
  seed: '123'                   # Default seed value
  seed_on_scaffold: false       # Set seed automatically when scaffold() runs
  set_theme_on_scaffold: true   # Set the ggplot2 theme when scaffold() runs
  ggplot_theme: theme_minimal
  source_all_functions: true    # Source every .R file in functions/
```

When `seed_on_scaffold: true`, Framework calls `set.seed()` during `scaffold()`. This is off by default. The project's seed wins over a user-wide `FW_SEED`, and `seed_on_scaffold: false` turns seeding off even when `FW_SEED` is set.

## Environment variables

Use `env()` to read environment variables in your settings:

```yaml
connections:
  databases:
    db:
      host: env("DB_HOST")
      password: env("DB_PASS", "default_value")  # With default
```

Store actual values in `.env` (which is gitignored):

```text
DB_HOST=localhost
DB_PASS=secret123
```

## Environment-specific settings

For different settings per environment, add named environment blocks:

```yaml
default:
  connections:
    databases:
      db:
        database: dev_database

production:
  connections:
    databases:
      db:
        database: prod_database
```

Environment sections replace lists whole.

Activate with:

```r
Sys.setenv(R_CONFIG_ACTIVE = "production")
```

## Settings access

```r
settings("author.name")
settings("directories")
settings("notebooks")           # Shorthand for directories.notebooks
settings("missing.key", default = "fallback")
```

## Complete structure

The `settings.yml` of a new standard project, with its split files:

```yaml
default:
  project_name: my-analysis
  project_type: project
  tools:
    quarto: true
    renv: false
  directories:
    notebooks: notebooks
    scripts: scripts
    functions: functions
    inputs_raw: inputs/raw
    inputs_intermediate: inputs/intermediate
    inputs_final: inputs/final
    docs: docs
    outputs_tables: outputs/tables
    outputs_figures: outputs/figures
    outputs_models: outputs/models
    outputs_reports: outputs/reports
    cache: outputs/cache
    scratch: scratch
    logs: logs
  render_dirs:
    notebooks: outputs/notebooks
    docs: outputs/docs
  author: settings/author.yml
  packages: settings/packages.yml
  git: settings/git.yml
  ai: settings/ai.yml
  scaffold: settings/scaffold.yml
  connections: settings/connections.yml
  quarto: settings/quarto.yml
  data: settings/data.yml
  security:
    sensitive: false
```

---

<div style="display: flex; justify-content: space-between">

[← Conventions](guide:conventions)

[New projects →](guide:new-project)

</div>
