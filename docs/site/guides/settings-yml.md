---
id: settings-yml
title: settings.yml
section: getting_started
position: 4
description: 'Project configuration file structure and split settings'
---
## Configuration layout

Every Framework project has a `settings.yml` file in its root directory. Settings sit under a `default:` key, with optional named environment blocks such as `production:`. Top-level keys without `default:` are also accepted.

## Split configuration files

Standard and privacy-sensitive projects place individual configuration sections in `settings/*.yml` and reference those files from `settings.yml`. Course and presentation projects keep all settings in `settings.yml`.

```yaml
default:
  author: settings/author.yml
  packages: settings/packages.yml
  connections: settings/connections.yml
  data: settings/data.yml
```

Each referenced file contains its section under the matching key.

`settings/connections.yml`:

```yaml
connections:
  databases:
    analytics:
      driver: postgres
      host: env("DB_HOST")
      database: analytics
```

`settings/data.yml`:

```yaml
data:
  raw:
    survey:
      path: inputs/raw/survey.csv
      type: csv
```

Any section can be moved into `settings/*.yml` or moved back inline in `settings.yml`.

> [!NOTE]
> Inline values in `settings.yml` override conflicting keys in split files and emit a warning. `options` blocks are merged across both files.

## Configuration sections

### Project metadata and tools

```yaml
project_name: my-analysis
project_type: project  # project, project_sensitive, course, presentation, or bare
tools:
  quarto: true
  renv: false
security:
  sensitive: false
```

`tools` records enabled project tools. `security.sensitive` is `true` in privacy-sensitive projects.

### Author metadata

```yaml
author:
  name: "Your Name"
  email: "your.email@example.com"
  affiliation: "Your Institution"
```

### Directory mapping

`directories` maps logical directory keys to project-relative paths. `render_dirs` sets Quarto output directories for each source folder.

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

Privacy-sensitive projects define split keys such as `inputs_private_raw`, `inputs_public_raw`, `outputs_private_tables`, and `outputs_public_tables`. Query paths in R with `settings("notebooks")` or `settings("directories.notebooks")`.

### Packages

`packages` lists R packages installed and optionally attached by `scaffold()`:

```yaml
packages:
  use_renv: false
  default_packages:
    - name: dplyr
      source: cran
      auto_attach: true
    - name: ggplot2
      source: cran
      auto_attach: true
    - name: readr
      source: cran
      auto_attach: false
```

`package_add()` appends or updates an entry and installs the package. See [Packages](guide:packages).

### Data catalog

The `data` section maps logical dot-notation names to file paths using either nested maps or dotted keys.

Nested keys:

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

Dotted keys:

```yaml
data:
  raw.survey:
    path: inputs/raw/survey.csv
    type: csv
  final.analysis:
    path: inputs/final/analysis.rds
    type: rds
```

Read both forms identically in R:

```r
data_read("raw.survey")
data_read("final.analysis")
```

See [Data management](guide:data-management).

### Git hooks

```yaml
git:
  enabled: true
  hooks:
    data_security: false
```

The 1.x `ai_sync` hook was removed in Framework 2.0; any `ai_sync: true` key in existing files is ignored. See [Git integration](guide:git).

### AI assistants

```yaml
ai:
  enabled: true
  canonical_file: AGENTS.md
  assistants:
    - claude
```

`AGENTS.md` holds the canonical project instructions, `CLAUDE.md` references `@AGENTS.md`, and skills live in `.claude/skills/` or `.agents/skills/`. See [AI assistants](guide:ai-assistants).

### Connections

Database and object storage connections read secrets from [environment variables](#environment-variables) with `env()`:

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

See [Connections](guide:connections).

### Scaffold behavior

```yaml
scaffold:
  seed: '123'
  seed_on_scaffold: false
  set_theme_on_scaffold: true
  ggplot_theme: theme_minimal
  source_all_functions: true
  print_description_on_read: false
```

When `seed_on_scaffold: true`, `scaffold()` calls `set.seed(seed)`. Seeding is disabled by default. Project `seed` values take precedence over `FW_SEED`, and `seed_on_scaffold: false` disables seeding even when `FW_SEED` is set.

With `print_description_on_read: true`, `data_read()` prints a catalog entry's `description` on each read as `Note: <name>: <description>`. Printing is off by default. `data_list()` always shows descriptions.

## Environment variables

Reference environment variables in `settings.yml` with `env("NAME")` or `env("NAME", "fallback")`:

```yaml
connections:
  databases:
    db:
      host: env("DB_HOST")
      password: env("DB_PASS", "default_value")
```

Store values in `.env` (gitignored):

```sh
DB_HOST=localhost
DB_PASS=secret123
```

## Named configuration environments

Define environment-specific overrides alongside `default:`:

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

Named environment blocks replace list values in full rather than appending to them. Activate an environment with `R_CONFIG_ACTIVE`:

```r
Sys.setenv(R_CONFIG_ACTIVE = "production")
```

## Reading settings in R

```r
settings("author.name")
settings("directories")
settings("notebooks")                      # Shorthand for directories.notebooks
settings("missing.key", default = "none")
```

## Complete standard project example

Root `settings.yml` for a standard project with split files:

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
