---
id: database
title: Database integration
section: features
position: 14
description: 'SQL queries, transactions, drivers, and read-only connections'
---
## Query helpers

Once connections are configured in `settings/connections.yml` (see [Connections](guide:connections)), Framework's DBI helpers open, use, and close connections automatically.

### Queries and statements

```r
# Return a data frame
users <- db_query("SELECT * FROM users WHERE active = true", "analytics")

# Execute DDL or DML without returning rows
db_execute("UPDATE stats SET last_run = NOW()", "analytics")

# Execute a .sql script or bulk-load a CSV in a single transaction
db_execute_file("analytics", "sql/schema.sql")
db_copy_from("analytics", "public.events", "inputs/raw/events.csv")
```

### Scoped connections and transactions

`db_with()` binds an open DBI connection to `conn` and disconnects on exit, including on error. `db_transaction()` commits when its block finishes and rolls back on error:

```r
tables <- db_with("analytics", {
  DBI::dbListTables(conn)
})

db_with("analytics", {
  db_transaction(conn, {
    DBI::dbExecute(conn, "INSERT INTO runs (name) VALUES ('baseline')")
    DBI::dbExecute(conn, "UPDATE stats SET last_run = NOW()")
  })
})
```

### Manual DBI connections

Open a raw DBI connection with `db_connect()` when needed and disconnect explicitly afterward:

```r
conn <- db_connect("analytics")
DBI::dbListTables(conn)
DBI::dbDisconnect(conn)
```

## Supported database drivers

| Driver | R package | Target database |
|--------|-----------|-----------------|
| `postgres` / `postgresql` | `RPostgres` | PostgreSQL |
| `sqlite` | `RSQLite` | Local SQLite files |
| `duckdb` | `duckdb` | Local DuckDB databases and Parquet queries |
| `mysql` / `mariadb` | `RMariaDB` | MySQL and MariaDB |
| `sqlserver` / `mssql` | `odbc` | Microsoft SQL Server |

Check installed driver packages or install missing ones from R:

```r
db_drivers_status()
db_drivers_install("postgres")
```

For S3-compatible object storage, see [Connections](guide:connections#object-storage-connections).

### SQL Server options

SQL Server connections require `host`, `database`, `user`, and `password` (`port` defaults to `1433`). Framework selects the newest installed Microsoft ODBC driver (Driver 18 or 17) unless `odbc_driver` is specified:

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

### Read-only SQLite and DuckDB connections

Set `read_only: true` on a SQLite or DuckDB connection to open files without write permissions (including `chmod 444` shared databases) and allow concurrent DuckDB readers across processes. `db_query()` succeeds, while `db_execute()` and `db_transaction()` stop with a read-only error:

```yaml
connections:
  databases:
    study:
      driver: sqlite
      database: ../shared/study.sqlite
      read_only: true
```

Pass `read_only = TRUE` on [db_connect()](ref:db_connect) or [db_query()](ref:db_query) to open a writable SQLite or DuckDB connection read-only for a single call. Calls can tighten access to read-only, while passing `read_only = FALSE` on a connection configured with `read_only: true` raises an error. When a build script writes a DuckDB file that notebooks query read-only, define separate connection entries for the same file:

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

Client-server databases enforce write access through database roles, so passing `read_only = TRUE` on PostgreSQL, MySQL, MariaDB, or SQL Server raises an error.

### DuckDB resource limits

Configure DuckDB memory and thread limits in YAML:

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

## Querying framework.db

Every project's internal SQLite database (`framework.db`) is registered as the `framework` connection, exposing the `data`, `cache`, `results`, `connections`, and `meta` tables to standard SQL:

```r
cache_entries <- db_query("SELECT * FROM cache", "framework")
```

See [framework.db](guide:framework-db).
