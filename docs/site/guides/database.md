---
id: database
title: Database integration
section: features
position: 14
description: 'Database queries with Framework helpers'
---
## Overview

Once your connections are defined (see the [Connections guide](guide:connections)), Framework helpers run database queries, execute statements, and read the internal `framework.db`. The helpers manage DBI connections for you.

## Queries

### db_query()

```r
# Query and return results
users <- db_query("SELECT * FROM users WHERE active = true", "analytics")
```

### db_execute()

```r
# Execute without returning data
db_execute("UPDATE stats SET last_run = NOW()", "analytics")
```

### Manual connections

For direct DBI access, open a connection and disconnect afterward:

```r
conn <- db_connect("analytics")
DBI::dbListTables(conn)
DBI::dbDisconnect(conn)
```

Prefer `db_query()` and `db_execute()` when possible. They open and close connections automatically.

## Supported databases

Framework supports the following database drivers:

| Driver | Package | Use Case |
|--------|---------|----------|
| `postgres` / `postgresql` | RPostgres | PostgreSQL databases |
| `sqlite` | RSQLite | Local SQLite files |
| `duckdb` | duckdb | Analytical workloads, Parquet files |
| `mysql` / `mariadb` | RMariaDB | MySQL/MariaDB |
| `sqlserver` / `mssql` | odbc | SQL Server |

Object storage connectors (S3-compatible endpoints) are covered in the [Connections guide](guide:connections#object-storage-connections).

### DuckDB configuration

DuckDB supports additional options in `settings.yml`:

```yaml
connections:
  warehouse:
    driver: duckdb
    database: data/warehouse.duckdb
    read_only: false
    memory_limit: "4GB"
    threads: 4
```

## Framework database

Every project includes a local SQLite database (`framework.db`) for internal tracking:

```r
cache_entries <- db_query("SELECT * FROM cache", "framework")
```

This tracks:

- Data integrity hashes
- Cache metadata
- Results registry

Use regular SQL to inspect or export these tables, as with any other connection.
