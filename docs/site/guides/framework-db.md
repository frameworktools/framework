---
id: framework-db
title: framework.db
section: features
position: 2
description: 'Local SQLite metadata database for hashes, caches, and saved results'
---
## Database role

Every Framework project uses a local `framework.db` SQLite database at the project root to record data integrity hashes, cache metadata, saved outputs, and connection bookkeeping.

New projects do not contain `framework.db` until the first `scaffold()`, `bootstrap()`, cache write, or `save_*()` call creates it. Both `scaffold()` and `bootstrap()` migrate missing tables when Framework is upgraded.

Project `.gitignore` templates exclude `framework.db`, `framework.db-wal`, and `framework.db-shm` because the database tracks machine-local state.

## Schema tables

| Table | Contents |
|-------|----------|
| `data` | Catalog paths, formats, lock flags, and SHA-256 hashes |
| `cache` | Cache keys, expiration timestamps, last-read times, and file hashes |
| `results` | Saved outputs (`table`, `figure`, `model`, `report`, `notebook`) |
| `connections` | Connection metadata |
| `meta` | Internal project key-value pairs |

## Data hash tracking

`data_read()`, `data_add()`, and `data_save()` store SHA-256 hashes in the `data` table:

```yaml
data:
  inputs.raw.patients:
    path: inputs/raw/patients.csv
    locked: true
```

```r
patients <- data_read("inputs.raw.patients")
```

The first read computes and stores the file hash. Subsequent reads compare the file on disk against the stored hash. Entries with `locked: true` stop with an error on mismatch; entries with `locked: false` warn and update the stored hash.

## Cache metadata

`cache_remember()` and `cache()` write serialized objects to the project's cache directory (`outputs/cache` on standard projects, `outputs/private/cache` on privacy-sensitive projects, and `cache` on courses and presentations; overridden by `FW_CACHE_DIR`) and record metadata in the `cache` table:

```r
result <- cache_remember("expensive_model", {
  fit_complex_model(data)
}, expire_after = "7 days")
```

`expire_after` (or `expire`) accepts numeric hours (such as `4`) or duration strings in seconds, minutes, hours, days, or weeks (`"30 minutes"`, `"1 day"`, `"7 days"`). On lookup, Framework checks expiration and verifies the `.rds` file's SHA-256 hash before returning the cached value.

## Results registry

`save_table()`, `save_figure()`, `save_model()`, `save_report()`, and `save_notebook()` log each written file to the `results` table with its project-relative path, output type, `public` flag, SHA-256 hash, and creation and modification timestamps:

```r
save_table(results, "analysis_results")
save_figure(plot, "summary_chart")
save_model(model, "regression_v1")
```

Query saved outputs with `result_list()`:

```r
result_list()
result_list(type = "figure")
result_list(type = "table", public = TRUE)
```

See [Saving work](guide:saving-work) and [Viewing work](guide:viewing-work).

## Direct SQL queries

Every new project defines a `framework` SQLite connection pointing to `framework.db`. Query its tables directly with `db_query()`:

```r
cache_entries <- db_query("SELECT name, expire_at FROM cache", "framework")
data_registry <- db_query("SELECT name, path, hash, locked FROM data", "framework")
results <- db_query("SELECT name, type, created_at FROM results", "framework")
```

Framework 2.0 writes timestamps as epoch seconds while continuing to parse local date-time strings written by 1.x releases.
