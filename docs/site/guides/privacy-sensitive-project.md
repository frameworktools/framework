---
id: privacy-sensitive-project
title: Privacy-sensitive project
section: project_types
position: 12
description: 'Separate private and public data with stricter privacy controls'
---
## Overview

The **Privacy Sensitive Project** is designed for research involving sensitive or protected data. It separates private and public directories and uses stricter `.gitignore` rules that prevent private data from being committed.

## Directory structure

```text
my-study/
├── docs/                # Project documents
├── functions/           # Custom R functions (auto-loaded)
│   └── helpers.R
├── inputs/
│   ├── private/         # Sensitive data (gitignored)
│   │   ├── raw/
│   │   ├── intermediate/
│   │   └── final/
│   └── public/          # Non-sensitive data
│       ├── raw/
│       ├── intermediate/
│       └── final/
├── logs/                # Logs (gitignored)
├── notebooks/           # Analysis notebooks
├── outputs/
│   └── private/
│       └── notebooks/   # Rendered notebooks (gitignored)
├── scratch/             # Throwaway work (gitignored)
├── scripts/             # Automation scripts
├── settings/            # Settings sections (packages, data, git, ...)
├── _quarto.yml          # Quarto configuration
├── AGENTS.md            # AI assistant guide
├── framework.db         # Metadata database (created on first use)
├── scaffold.R           # Project startup code
└── settings.yml         # Project configuration
```

Additional directories are created on first use:
- `outputs/private/cache` - Cached computations
- `outputs/private/tables`, `figures`, `models`, `reports` - Private outputs
- `outputs/public/tables`, `figures`, `models`, `reports` - Shareable results

## Privacy controls

### Gitignored paths

The privacy sensitive `.gitignore` template excludes:
- `inputs/private/` and `outputs/private/` - All private inputs and outputs
- Any `private/`, `*_private/`, or `sensitive/` folder
- `cache/`, `scratch/`, `logs/`, and temporary folders
- `.env` and credential files such as `*.key` and `*.pem`
- `framework.db` - Local metadata, including data hashes

### AI assistant controls

- `AGENTS.md` names the private folders agents must not read.
- The `framework-sensitive-data` skill covers private and public data rules.
- `.claude/settings.json` denies Claude Code access to `inputs/private/`, `outputs/private/`, and `.env`, and turns on its sandbox.

### Publishing checks

`publish()` checks every file it would upload. A file in a private folder (named `private` or ending in `_private`) triggers a warning. Interactive sessions ask first. Scripts stop unless `include_private = TRUE`.

### Public and private outputs

`save_table()`, `save_figure()`, `save_model()`, `save_report()`, and `save_notebook()` save to private folders by default. Use `public = TRUE` for shareable results:

```r
# Save to private (default)
save_table(results, "analysis_results")

# Save to public for sharing
save_table(summary_stats, "summary", public = TRUE)
```

Any project splits outputs this way when `security.sensitive` is on or it lists `outputs_private_*` folders.

## Workflow

### 1. Environment setup

```r
library(framework)
scaffold()
```

### 2. Data organization by sensitivity

Place sensitive data in private directories:

```yaml
data:
  # Private: contains PHI
  inputs.private.raw.patients:
    path: inputs/private/raw/patients.csv
    type: csv
    locked: true

  # Public: aggregated, de-identified
  inputs.public.final.demographics:
    path: inputs/public/final/demographics.csv
    type: csv
```

### 3. Private data

```r
# Load private data
patients <- data_read("inputs.private.raw.patients")

# Process and de-identify
demographics <- patients |>
  group_by(age_group, region) |>
  summarize(n = n())

# Save de-identified data to public
data_save(demographics, "inputs.public.final.demographics")
```

### 4. Public outputs

```r
# Private analysis output
save_figure(detailed_plot, "patient_outcomes")

# Public summary for publication
save_figure(summary_plot, "figure_1", public = TRUE)
```

## Configuration

Example `settings.yml` for a privacy sensitive project:

```yaml
default:
  project_type: project_sensitive
  tools:
    quarto: true
    renv: false

  directories:
    notebooks: notebooks
    scripts: scripts
    functions: functions
    inputs_private_raw: inputs/private/raw
    inputs_private_intermediate: inputs/private/intermediate
    inputs_private_final: inputs/private/final
    inputs_public_raw: inputs/public/raw
    inputs_public_intermediate: inputs/public/intermediate
    inputs_public_final: inputs/public/final
    outputs_private_tables: outputs/private/tables
    outputs_public_tables: outputs/public/tables
    cache: outputs/private/cache

  render_dirs:
    notebooks: outputs/private/notebooks

  packages: settings/packages.yml
  data: settings/data.yml

  security:
    sensitive: true
```

The data catalog lives in `settings/data.yml`:

```yaml
data:
  inputs.private.raw.patients:
    path: inputs/private/raw/patients.csv
    type: csv
    locked: true
```

## Best practices

### Locked source data

Use `locked: true` to ensure source data hasn't changed. `data_read()` warns when an unlocked file changes and errors when a locked one does:

```yaml
data:
  inputs.private.raw.patients:
    path: inputs/private/raw/patients.csv
    type: csv
    locked: true  # Error if file changes
```

### De-identification before publishing

Always aggregate or de-identify data before moving to public directories:

```r
# Never do this
save_table(raw_patient_data, "patients", public = TRUE)

# Do this instead
public_summary <- raw_patient_data |>
  group_by(category) |>
  summarize(mean_value = mean(value), n = n())

save_table(public_summary, "summary", public = TRUE)
```

### Pre-commit review

Check `git status` before committing to ensure no private data is staged:

```r
git_status()
```

Audit the repository for private data, or block such commits with the pre-commit hook. The hook is off by default:

```r
git_security_audit()
git_hooks_enable("data_security")
```

---

<div style="display: flex; justify-content: space-between">

[← Standard project](guide:standard-project)

[Course/Teaching →](guide:course-teaching)

</div>
