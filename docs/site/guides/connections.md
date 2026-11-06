---
id: connections
title: Connections
section: features
position: 13
description: 'Database and object storage connections'
---
## Overview

Framework connects to databases and object storage through connections defined once in settings. New projects keep them in `settings/connections.yml`. For queries and database helpers, see the [Database integration guide](guide:database).

## Database connections

Define database connections under `connections.databases`:

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

New projects start with the `framework` connection to the project's own `framework.db`. SQLite and DuckDB paths are relative to the project root, so a notebook in `notebooks/` opens the same file.

Older projects that list connections directly under `connections:`, without `databases:`, still work.

The `env()` syntax reads values from environment variables, keeping credentials out of your settings files. `env("VAR", "default")` supplies a fallback.

Store sensitive values in `.env`:

```bash
# .env (gitignored)
DB_HOST=db.example.com
DB_USER=analyst
DB_PASSWORD=secret
```

## Object storage connections

Define S3-compatible buckets (AWS S3, MinIO, Cloudflare R2, and others) under `connections.storage_buckets`. The publishing functions upload to them:

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

The `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_SESSION_TOKEN`, `S3_REGION`, `S3_BUCKET`, and `S3_ENDPOINT` variables fill these fields. When one is set in the session or `.env`, it takes precedence over the bucket's own value. The matching `AWS_*` names also work. The region defaults to `us-east-1`. Uploads need the aws.s3 package. See the [Publishing guide](guide:publishing#s3-configuration) for every bucket option.

Check that a bucket's credentials work:

```r
storage_test()            # The default bucket
storage_test("reports")   # A named bucket
```

## Connection list

View all configured connections (databases and object storage) with `connections_list()`, or limit to only database entries using `db_list()`:

```r
connections_list()

db_list()  # Databases only
```

## Best practices

### Credentials in env()

Never hardcode credentials:

```yaml
# Good
password: env("DB_PASSWORD")

# Never do this
password: "my_secret_password"
```

### Connection names

```yaml
connections:
  databases:
    production_analytics:  # Clear purpose
      ...
    staging_analytics:     # Environment obvious
      ...
```

---

<div style="display: flex; justify-content: space-between">

[← Caching](guide:caching)

[Database integration →](guide:database)

</div>
