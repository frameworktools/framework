---
id: settings-yml
title: settings.yml
section: getting_started
position: 4
description: 'The project configuration file'
---
## Overview

Every Framework project has a `settings.yml` file that controls project-specific settings. You can edit it directly in your project root or through the GUI, by selecting the project after running `framework::gui()`.

Settings use the config package's environment format with a `default:` key (and optional environment overrides like `production:`).

## Split files

For larger projects, split complex sections into separate files. Replace inline content with a file path:

```yaml
default:
  connections: settings/connections.yml
  data: settings/data.yml
```

Then create the referenced files:

**settings/connections.yml:**
```yaml
db:
  driver: postgresql
  host: env("DB_HOST")
  database: mydb
```

**settings/data.yml:**
```yaml
raw.survey:
  path: inputs/raw/survey.csv
  type: csv
```

**Note:** Root `settings.yml` values win if they conflict with a split file (Framework warns when this happens; `options` are merged).

## Sections

### Basics

Project type and author information.

```yaml
project_type: project  # project, project_sensitive, course, or presentation

author:
  name: "Your Name"
  email: "your.email@example.com"
  affiliation: "Your Institution"
```

### Project structure

Maps logical directory names to paths. All paths are relative to the project root.

```yaml
directories:
  # Source code and notebooks
  notebooks: notebooks
  scripts: scripts
  functions: functions

  # Input data (read-only)
  inputs_raw: inputs/raw
  inputs_intermediate: inputs/intermediate
  inputs_final: inputs/final
  inputs_reference: inputs/reference

  # Derived outputs (write-only)
  outputs_private: outputs/private
  outputs_public: outputs/public

  # Cache and scratch space
  cache: outputs/private/cache
  scratch: outputs/private/scratch
```

Access with `settings("notebooks")` or `settings("directories.notebooks")`.

### Packages

R packages to install and optionally load with `scaffold()`:

```yaml
packages:
  - name: dplyr
    auto_attach: true   # Load automatically
  - name: tidyr
    auto_attach: true
  - name: ggplot2
    auto_attach: true
  - name: readr
    auto_attach: false  # Install only, namespace explicitly
```

See [Packages](guide:packages) for details on version pinning and GitHub packages.

### Data catalog

The data catalog maps logical names to file paths. You can use three notation styles:

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

**Flat** (full dot-notation keys):
```yaml
data.raw.survey:
  path: inputs/raw/survey.csv
  type: csv
data.final.analysis:
  path: inputs/final/analysis.rds
  type: rds
```

All three styles are accessed the same way:

```r
data_read("raw.survey")
data_read("final.analysis")
```

See [Data management](guide:data-management) for full documentation.

### Git hooks

Git hook configuration:

```yaml
git:
  hooks:
    ai_sync: false        # Sync AI assistant files before commit
    data_security: false  # Check for secrets before commit
```

See [Git integration](guide:git) for details.

### AI assistants

AI assistant configuration:

```yaml
ai:
  canonical_file: "CLAUDE.md"  # CLAUDE.md, AGENTS.md, or .github/copilot-instructions.md
```

The canonical file is the source of truth for AI instructions. Other AI files are synced from it when using git hooks.

See [AI assistants](guide:ai-assistants) for details.

### Connections

Database connections use `env()` to read credentials from [environment variables](#environment-variables):

```yaml
connections:
  db:
    driver: postgresql
    host: env("DB_HOST")
    database: env("DB_NAME")
    user: env("DB_USER")
    password: env("DB_PASS")
```

See [Connections](guide:connections) for full documentation.

### Random seeds

Control random seed behavior for reproducibility:

```yaml
seed: 123                 # Default seed value
seed_on_scaffold: false   # Set seed automatically when scaffold() runs
```

When `seed_on_scaffold: true`, Framework calls `set.seed()` during `scaffold()`. This is off by default.

## Environment variables

Use `env()` to read environment variables in your settings:

```yaml
connections:
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
    db:
      database: dev_database

production:
  connections:
    db:
      database: prod_database
```

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

The full structure of a project's `settings.yml`:

```yaml
default:
  project_type: project

  author:
    name: "Your Name"
    email: "your.email@example.com"
    affiliation: "Your Institution"

  packages:
    - name: dplyr
      auto_attach: true
    - name: tidyr
      auto_attach: true
    - name: ggplot2
      auto_attach: true
    - name: readr
      auto_attach: false

  directories:
    notebooks: notebooks
    scripts: scripts
    functions: functions
    inputs_raw: inputs/raw
    inputs_intermediate: inputs/intermediate
    inputs_final: inputs/final
    inputs_reference: inputs/reference
    outputs_private: outputs/private
    outputs_public: outputs/public
    cache: outputs/private/cache
    scratch: outputs/private/scratch

  seed: 123
  seed_on_scaffold: false

  ai:
    canonical_file: "CLAUDE.md"

  git:
    hooks:
      ai_sync: false
      data_security: false

  data:
    # Data catalog entries

  connections:
    # Database connections
```

---

<div style="display: flex; justify-content: space-between">

[← Conventions](guide:conventions)

[New projects →](guide:new-project)

</div>
