---
id: environment
title: Environment
section: features
position: 15
description: 'Environment variables, .env files, cloned projects, and R session helpers'
---
## Environment variables and .env

Store database passwords, API keys, and project tokens in `.env` at the project root so secrets remain out of source files and Git history:

```sh
# .env (gitignored)
DB_HOST=db.example.com
DB_USER=analyst
DB_PASSWORD=secret123

OPENAI_API_KEY=sk-...
S3_ACCESS_KEY=AKIA...
S3_SECRET_KEY=...
```

All Framework `.gitignore` templates exclude `.env`, and project creation verifies that Git ignores `.env` before making the initial commit. If `.env` is ever committed, rotate its credentials immediately because values remain in Git history (`git_security_audit()` flags tracked `.env` files under `secrets_exposure`).

### Loading rules

`scaffold()` loads non-empty entries from `.env` into the R session without overwriting variables already set in the environment. Direct calls to `settings()` resolve `env()` expressions from `.env` transiently without mutating `Sys.getenv()`, preventing one project's tokens from leaking into another project in the same R process.

Set `dotenv_location` in `settings.yml` (file or directory path, relative to the project root) to load `.env` from an alternate path.

### Referencing variables in settings.yml

Use `env("NAME")` or `env("NAME", "default")` in `settings.yml` and `settings/*.yml`:

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

### Starter .env template

New non-bare projects generate a starter `.env` file with blank PostgreSQL and S3 placeholders. Projects linked to Framework Cloud also include:

```sh
FW_PROJECT_TOKEN=...
FW_CLOUD_URL=https://framework.pub
```

`publish()`, `pull_all()`, `push_all()`, and `ledger_push()` read these two variables to reach the project's Framework Cloud server.

### Bootstrapping cloned projects

Because `.env` is gitignored, freshly cloned repositories have no `.env` file. Run `bootstrap()` after cloning:

```r
framework::bootstrap()
```

`bootstrap()` verifies that `.gitignore` excludes `.env`, copies `.env` from `.env.example` when present, initializes `framework.db`, installs enabled Git hooks, and lists any blank variables actually referenced in project settings (`env("NAME")`, `Sys.getenv("NAME")`, or `${NAME}`). Unused blank placeholders in `.env.example` are omitted, and `bootstrap()` makes no network requests to Framework Cloud. Commit a `.env.example` with variable names and comments so collaborators know which values to populate.

## R session management

### Clearing an environment

`env_clear()` removes objects from a specified environment (preserving any names listed in `keep`), closes open graphics devices, detaches attached packages other than `framework`, and triggers garbage collection. Pass `envir` explicitly so nothing is cleared accidentally:

```r
env_clear(envir = globalenv())
env_clear(keep = c("config", "raw_data"), envir = globalenv())
```

### Inspecting session state

`env_summary()` prints the active R version and platform, attached package versions, the ten largest objects in `envir`, and total memory in use:

```r
env_summary(envir = globalenv())
```
