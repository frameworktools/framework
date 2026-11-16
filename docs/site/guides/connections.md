---
id: connections
title: Connections
section: features
position: 13
description: 'Database and S3-compatible object storage configuration'
---
## Connection configuration

Define database and object storage connections once in `settings/connections.yml` (split projects) or `settings.yml` (single-file projects). For SQL execution helpers, see [Database integration](guide:database).

## Database connections

Configure databases under `connections.databases`:

```yaml
connections:
  default_database: framework
  databases:
    framework:
      driver: sqlite
      database: framework.db

    analytics:
      driver: postgres
      host: env("DB_HOST")
      port: 5432
      database: analytics
      user: env("DB_USER")
      password: env("DB_PASSWORD")

    warehouse:
      driver: duckdb
      database: data/warehouse.duckdb
```

New projects include the `framework` connection to `framework.db`. Relative SQLite and DuckDB paths resolve from the project root so notebooks in subdirectories open the same database file. Legacy 1.x configurations that place database entries directly under `connections:` continue to work.

Reference secrets from `.env` with `env("VAR")` or `env("VAR", "fallback")`:

```sh
# .env (gitignored)
DB_HOST=db.example.com
DB_USER=analyst
DB_PASSWORD=secret
```

## Object storage connections

Configure S3-compatible buckets (AWS S3, Cloudflare R2, MinIO, and others) under `connections.storage_buckets`:

```yaml
connections:
  storage_buckets:
    reports:
      bucket: env("S3_BUCKET")
      region: us-east-1
      access_key: env("S3_ACCESS_KEY")
      secret_key: env("S3_SECRET_KEY")
  default_storage_bucket: reports
```

`S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_SESSION_TOKEN`, `S3_REGION`, `S3_BUCKET`, and `S3_ENDPOINT` (or matching `AWS_*` variables) populate bucket fields and override static bucket values when set in the session or `.env`. `region` defaults to `us-east-1`. Bucket uploads require the `aws.s3` package. See [Publishing](guide:publishing#s3-configuration) for all bucket fields.

Verify bucket credentials with `storage_test()`:

```r
storage_test()            # Default storage bucket
storage_test("reports")   # Named bucket
```

## Inspecting connections

List configured database and storage connections with `connections_list()`, or list databases alone with `db_list()`:

```r
connections_list()
db_list()
```

## Credential hygiene

Always reference passwords and access keys via `env("...")` rather than committing literal secrets in YAML, and name connections for both target and environment (`production_analytics`, `staging_analytics`).
