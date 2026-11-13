---
name: framework-databases
description: Use when querying configured database connections in a project that uses the Framework package. Covers db_query(), db_execute(), and db_with().
metadata:
  title: "Framework: database queries"
  summary: Query configured databases through Framework connections.
---

# Framework: database queries

Connections are defined in the settings (often `settings/connections.yml`),
with credentials in `.env`. Prefer Framework's helpers to opening DBI
connections by hand.

```r
users <- db_query("SELECT * FROM users WHERE active = 1", "main_db")

# Several statements on one connection, available as conn
db_with("main_db", {
  DBI::dbListTables(conn)
})
```

`db_execute()` runs a statement that changes data. Ask the user before
running one.
