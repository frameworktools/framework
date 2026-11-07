---
id: environment
title: Environment
section: features
position: 15
description: 'Environment variables, secrets, and R session state'
---
## Overview

Framework manages environment variables (secrets, credentials) and R session state. Sensitive values stay out of your code and version control.

## Environment variables

### .env file

Store sensitive values in a `.env` file at your project root:

```bash
# .env (gitignored)
# Database credentials
DB_HOST=db.example.com
DB_USER=analyst
DB_PASSWORD=secret123

# API keys
OPENAI_API_KEY=sk-...
S3_ACCESS_KEY=AKIA...
S3_SECRET_KEY=...
```

Framework's `.gitignore` templates exclude `.env` files to prevent accidental exposure.

### .env loading

`scaffold()` loads `.env` into the R session. Reading settings uses `.env` only while it resolves `env()` values, so one project's token can't leak into the next project. In both cases, a variable already set in the session wins, and empty lines such as `S3_ACCESS_KEY=` are skipped.

To keep `.env` somewhere else, set `dotenv_location` in `settings.yml` to a file or folder. Relative paths start at the project root.

### env() in configuration

Reference environment variables in `settings.yml` using `env()`:

```yaml
connections:
  databases:
    analytics:
      driver: postgres
      host: env("DB_HOST")
      user: env("DB_USER")
      password: env("DB_PASSWORD")
  storage_buckets:
    reports:
      bucket: my-reports-bucket
      region: us-east-1
      access_key: env("S3_ACCESS_KEY")
      secret_key: env("S3_SECRET_KEY")
  default_storage_bucket: reports
```

`env("VAR", "default")` supplies a fallback when the variable is unset. This keeps credentials out of version control while allowing configuration to be shared.

### Default .env template

When you create a new project, Framework generates a `.env` template with common variables:

```bash
# Framework environment defaults
# Populate these values before running scaffold() or publishing.

# PostgreSQL connection (example)
POSTGRES_HOST=
POSTGRES_PORT=5432
POSTGRES_DB=
POSTGRES_SCHEMA=public
POSTGRES_USER=
POSTGRES_PASSWORD=

# S3-compatible storage (AWS S3, MinIO, etc.)
S3_BUCKET=
S3_ACCESS_KEY=
S3_SECRET_KEY=
S3_REGION=
S3_ENDPOINT=
S3_SESSION_TOKEN=
```

### Framework Cloud variables

A project set up from Framework Cloud has two more lines in `.env`:

```bash
FW_PROJECT_TOKEN=...
FW_CLOUD_URL=https://framework.pub
```

`publish()` and the ledger use them to reach the server the project came from. The project token is a secret. Keep it out of git.

### Cloned projects

`.env` isn't committed, so a fresh clone has none. Run `bootstrap()` after cloning:

```r
framework::bootstrap()
```

It makes sure `.gitignore` ignores `.env`. It creates `.env` from `.env.example` when one exists and lists the empty variables that the settings use, through `env("NAME")`, `Sys.getenv("NAME")`, or `${NAME}`. Empty example variables nothing uses are not listed. It never contacts Framework Cloud. Commit a `.env.example` with names and no values to give collaborators the list.

## R session management

### Clearing the session

Reset an environment while optionally keeping specific objects. Name the environment, so nothing is removed by accident:

```r
# Clear your workspace
env_clear(envir = globalenv())

# Keep specific objects
env_clear(keep = c("config", "raw_data"), envir = globalenv())
```

`env_clear()`:
- Removes all objects from the environment, except those in `keep`
- Closes open plot devices
- Detaches attached packages, except framework itself
- Runs garbage collection

### Environment summary

Get an overview of your current R session:

```r
env_summary(envir = globalenv())
```

This displays:
- R version and platform
- Attached packages with versions
- Objects in the environment (largest 10)
- Memory usage

Example output:

```text
=== Environment Summary ===

R Version: R version 4.5.1 (2025-06-13)
Platform: aarch64-apple-darwin20

Loaded Packages (5):
  - framework (2.0.0)
  - dplyr (1.1.4)
  - ggplot2 (3.5.2)
  - readr (2.1.5)
  - tibble (3.3.0)

Objects in Global Environment: 12
  Top 10 by size:
    large_dataset [tbl_df] - 45.2 MB
    model_results [list] - 12.3 MB
    summary_stats [data.frame] - 0.8 KB
    ...

Memory in use: 234.5 MB
```

## Best practices

### Secrets in configuration

```yaml
# Bad - secrets in config
password: "my_secret_password"

# Good - reference environment variable
password: env("DB_PASSWORD")
```

### Gitignored files

Every Framework project template ignores `.env`. When Framework creates a project, it asks git whether `.env` is ignored before the first commit. If it isn't, Framework skips the commit.

`git_security_audit()` fails its `secrets_exposure` check when git tracks a `.env` file. If that happens, rotate the passwords and tokens in it. They stay in git history.

### Variable names

```bash
# Good - clear purpose
PROD_DB_PASSWORD=...
STAGING_DB_PASSWORD=...
ANALYTICS_API_KEY=...

# Avoid - ambiguous
PASSWORD=...
KEY=...
```

### Variable documentation

Add comments to your `.env.example`:

```bash
# Required for database connections
# Get credentials from your team lead
DB_HOST=
DB_PASSWORD=

# Optional - only needed for S3 publishing
S3_ACCESS_KEY=
```

---

<div style="display: flex; justify-content: space-between">

[← Database integration](guide:database)

[Publishing →](guide:publishing)

</div>
