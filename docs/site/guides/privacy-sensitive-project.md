---
id: privacy-sensitive-project
title: Privacy-sensitive project
section: project_types
position: 12
description: 'Separate private and public data with stricter privacy controls'
---
## Structure

The privacy-sensitive project (`project_sensitive`) separates restricted inputs and outputs from shareable files and enables stricter `.gitignore`, pre-commit, publishing, and AI assistant rules.

```text
my-study/
├── docs/                # Project documentation
├── functions/           # Reusable R functions sourced by scaffold()
│   └── helpers.R
├── inputs/
│   ├── private/         # Restricted source data (gitignored)
│   │   ├── raw/
│   │   ├── intermediate/
│   │   └── final/
│   └── public/          # Shareable datasets
│       ├── raw/
│       ├── intermediate/
│       └── final/
├── logs/                # Run logs (gitignored)
├── notebooks/           # Analysis notebooks
├── outputs/
│   └── private/
│       └── notebooks/   # Rendered notebooks (gitignored)
├── scratch/             # Temporary work (gitignored)
├── scripts/             # Standalone scripts
├── settings/            # Split configuration files
├── _quarto.yml          # Quarto configuration
├── AGENTS.md            # AI assistant context
├── framework.db         # Local metadata database (created on first use)
├── scaffold.R           # Project startup script
└── settings.yml         # Root configuration
```

Additional output directories are created on first save:

- `outputs/private/cache` for cached computations
- `outputs/private/tables`, `figures`, `models`, and `reports` for restricted outputs
- `outputs/public/tables`, `figures`, `models`, `reports`, and `notebooks` for shareable outputs

## Privacy safeguards

### Gitignored paths

The `project_sensitive` `.gitignore` excludes:

- `inputs/private/` and `outputs/private/`
- Any `private/`, `*_private/`, or `sensitive/` directory
- `cache/`, `scratch/`, `logs/`, and temporary directories
- `.env` and credential files (`*.key`, `*.pem`)
- `framework.db` and its SQLite journal files

### Pre-commit hooks

New `project_sensitive` projects enable the `data_security` and `check_sensitive_dirs` Git pre-commit checks by default, installing the hook after the initial commit. `data_security` runs `git_security_audit()` before each commit and blocks commits that track private data or `.env`. Disable a check with `git_hooks_disable()` if needed.

### AI assistant rules

- `AGENTS.md` lists private directories that coding agents must not read.
- `framework-sensitive-data` documents private and public output handling.
- When Claude Code is enabled, `.claude/settings.json` denies access to `inputs/private/`, `outputs/private/`, and `.env` and enables sandboxing.

### Publishing checks

`publish()` inspects source paths, sensitive-project status, and notebook references before uploading. Files in private directories, notebooks or R objects in projects with `security.sensitive: true`, and notebooks quoting private catalog entries trigger a warning and require confirmation in interactive sessions (or `include_private = TRUE` in non-interactive runs).

### Private and public output routing

`save_table()`, `save_figure()`, `save_model()`, `save_report()`, and `save_notebook()` write to `outputs/private/` by default. Pass `public = TRUE` to write to `outputs/public/`:

```r
# Writes to outputs/private/tables/analysis_results.csv
save_table(results, "analysis_results")

# Writes to outputs/public/tables/summary.csv
save_table(summary_stats, "summary", public = TRUE)
```

Any project uses split output routing when `security.sensitive` is `true` or when `outputs_private_*` keys are defined in `directories`.

## Typical workflow

### Session setup

```r
library(framework)
scaffold()
```

### Catalog entries by sensitivity

Register restricted inputs under `inputs.private.*` and aggregated or de-identified datasets under `inputs.public.*`:

```yaml
data:
  inputs.private.raw.patients:
    path: inputs/private/raw/patients.csv
    type: csv
    locked: true

  inputs.public.final.demographics:
    path: inputs/public/final/demographics.csv
    type: csv
```

### Aggregation and public outputs

Read restricted data, aggregate or de-identify it in R, and explicitly mark shareable outputs with `public = TRUE`:

```r
patients <- data_read("inputs.private.raw.patients")

demographics <- patients |>
  group_by(age_group, region) |>
  summarize(n = n())

data_save(demographics, "inputs.public.final.demographics")

save_figure(detailed_plot, "patient_outcomes")
save_figure(summary_plot, "figure_1", public = TRUE)
```

## Configuration

Example `settings.yml` for a `project_sensitive` project:

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

## Operational practices

### Locked source files

Keep `locked: true` on raw datasets so `data_read()` stops with an error if source files are altered on disk.

### Repository audits

Inspect working tree status and run security audits on demand:

```r
git_status()
git_security_audit()
```
