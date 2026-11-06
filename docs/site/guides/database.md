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

### Managed connections

`db_with()` opens a connection, runs your code with it as `conn`, and closes it, even on error:

```r
tables <- db_with("analytics", {
  DBI::dbListTables(conn)
})
```

### Transactions

`db_transaction()` commits when the code succeeds and rolls back on error:

```r
db_with("analytics", {
  db_transaction(conn, {
    DBI::dbExecute(conn, "INSERT INTO runs (name) VALUES ('baseline')")
    DBI::dbExecute(conn, "UPDATE stats SET last_run = NOW()")
  })
})
```

### Manual connections

For direct DBI access, open a connection and disconnect afterward:

```r
conn <- db_connect("analytics")
DBI::dbListTables(conn)
DBI::dbDisconnect(conn)
```

Prefer `db_query()`, `db_execute()`, and `db_with()` when possible. They open and close connections automatically.

## Supported databases

Framework supports the following database drivers:

| Driver | Package | Use Case |
|--------|---------|----------|
| `postgres` / `postgresql` | RPostgres | PostgreSQL databases |
| `sqlite` | RSQLite | Local SQLite files |
| `duckdb` | duckdb | Analytical workloads, Parquet files |
| `mysql` / `mariadb` | RMariaDB | MySQL/MariaDB |
| `sqlserver` / `mssql` | odbc | SQL Server |

Check and install the driver packages:

```r
db_drivers_status()
db_drivers_install("postgres")
```

Object storage connectors (S3-compatible endpoints) are covered in the [Connections guide](guide:connections#object-storage-connections).

### SQL Server configuration

SQL Server connections need `host`, `database`, `user`, and `password`. The port defaults to 1433. Framework uses the newest installed Microsoft ODBC driver (Driver 18 or 17). Set `odbc_driver` to choose another:

```yaml
connections:
  databases:
    claims:
      driver: sqlserver
      host: env("MSSQL_HOST")
      database: claims
      user: env("MSSQL_USER")
      password: env("MSSQL_PASSWORD")
      odbc_driver: "ODBC Driver 17 for SQL Server"
```

### DuckDB configuration

DuckDB supports additional options in `settings.yml`:

```yaml
connections:
  databases:
    warehouse:
      driver: duckdb
      database: data/warehouse.duckdb
      read_only: false
      memory_limit: "4GB"
      threads: 4
```

## Framework database

Every project has a local SQLite database, `framework.db`, for internal tracking. `scaffold()`, `bootstrap()`, and the first cache or save create it. New projects connect to it as `framework`:

```r
cache_entries <- db_query("SELECT * FROM cache", "framework")
```

Its tables:

- `data`: Data integrity hashes
- `cache`: Cache metadata
- `results`: Saved outputs
- `connections` and `meta`: Internal bookkeeping

Use regular SQL to inspect or export these tables, as with any other connection. See [framework.db](guide:framework-db) for details.

---

<div style="display: flex; justify-content: space-between">

[← Connections](guide:connections)

[Environment →](guide:environment)

</div>
