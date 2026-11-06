---
id: connections
title: Connections
section: features
position: 13
description: 'Database and object storage connections'
---
## Overview

Framework connects to databases and object storage through connections defined once in `settings.yml`. For queries and database helpers, see the [Database integration guide](guide:database).

## Database connections

Define database connections in `settings.yml`:

```yaml
connections:
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

  local:
    driver: sqlite
    database: data/local.db
```

The `env()` syntax reads values from environment variables, keeping credentials out of your config files.

Store sensitive values in `.env`:

```bash
# .env (gitignored)
DB_HOST=db.example.com
DB_USER=analyst
DB_PASSWORD=secret
```

## Object storage connections

Define object storage endpoints and buckets in `settings.yml`, then use helpers like `s3_ls()`, `s3_download()`, and `s3_upload()` to browse or sync data:

```yaml
object_storage:
  raw_data:
    provider: s3
    bucket: env("S3_BUCKET")
    region: env("AWS_REGION")
    access_key_id: env("AWS_ACCESS_KEY_ID")
    secret_access_key: env("AWS_SECRET_ACCESS_KEY")
```

Both the GUI and the R helpers respect these connection profiles, so you can browse buckets in `framework::gui()` or automate transfers in code.

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
  production_analytics:  # Clear purpose
    ...
  staging_analytics:     # Environment obvious
    ...
```

---

<div style="display: flex; justify-content: space-between">

[← Caching](guide:caching)

[Environment →](guide:environment)

</div>
