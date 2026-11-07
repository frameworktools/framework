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

### Read-only databases

Add `read_only: true` to a SQLite or DuckDB connection to open it read-only. The file needs no write permission, so a shared database marked read-only on disk (`chmod 444`) opens. `db_query()` works; `db_execute()` and `db_transaction()` stop with a message that the connection is read-only.

```yaml
connections:
  databases:
    study:
      driver: sqlite
      database: ../shared/study.sqlite
      read_only: true
```

### Read-only for one call

`read_only = TRUE` on [db_connect()](ref:db_connect) and [db_query()](ref:db_query) opens a SQLite or DuckDB connection read-only for that call, whatever its setting. A call can add read-only but never remove it: `read_only = FALSE` on a connection with `read_only: true` in its settings is an error, so the settings decide what may write. A job that rebuilds a database that notebooks share read-only gets its own connection entry for the same file:

```yaml
connections:
  databases:
    vizient: {driver: duckdb, database: data/vizient.duckdb, read_only: true}
    vizient_build: {driver: duckdb, database: data/vizient.duckdb}
```

```r
db_execute_file("vizient_build", "sql/build.sql")

db_query("SELECT count(*) AS n FROM encounters", "vizient")
```

Server databases control writes with the database user's permissions, so `read_only = TRUE` on a PostgreSQL, MySQL, or SQL Server connection is an error, and `read_only = FALSE` changes nothing. A DuckDB file opened read-only can be open in several processes at once; one opened writable locks it until the connection closes.

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
