---
id: framework-db
title: framework.db
section: features
position: 2
description: 'The SQLite database that tracks project metadata and data integrity'
---
## Overview

Every Framework project has a `framework.db` SQLite database for internal tracking. It stores metadata about your data sources, cached computations, saved outputs, and connections.

New projects don't include it. The first `scaffold()`, `bootstrap()`, or saved output creates it. Both `scaffold()` and `bootstrap()` add tables a newer version needs.

You generally don't interact with `framework.db` directly. Framework updates it when you use functions like `data_read()`, `cache_remember()`, and `save_table()`.

New projects gitignore `framework.db`, along with its `-wal` and `-shm` files. It holds local state that differs between collaborators.

## Database schema

| Table | Purpose |
|-------|---------|
| `data` | Tracks data sources, file paths, types, and integrity hashes |
| `cache` | Manages cached computation metadata and expiration |
| `results` | Registry of saved outputs (tables, figures, models) |
| `connections` | Database connection metadata |
| `meta` | Key-value store for project metadata |

## Data integrity

When you read a data file using `data_read()`, Framework stores a hash of the file contents.

```yaml
data:
  inputs.raw.patients:
    path: inputs/raw/patients.csv
    locked: true
```

```r
patients <- data_read("inputs.raw.patients")

# First read: computes and stores hash in framework.db
# Later reads: compares hashes and warns if the file changed
```

If you set `locked: true` in the data catalog, `data_read()` errors when the source file has changed. Unlocked entries warn and record the new hash.

## Cache tracking

The cache table tracks what's cached, when it expires, and integrity hashes:

```r
result <- cache_remember("expensive_model", {
  fit_complex_model(data)
}, expire = "7 days")  # Strings like "7 days" or numeric hours are accepted
# Metadata stored in framework.db
# Actual data stored in the cache folder: outputs/cache/expensive_model.rds
```

Framework uses the database to:
- Check if a cached result exists and is still valid
- Track expiration times
- Verify cached data hasn't been corrupted

**Durations:** `expire_after` (or `expire`) accepts numeric hours (e.g., `4`) or strings like `"30 minutes"`, `"1 day"`, or `"7 days"` (seconds, minutes, hours, days, and weeks).

The cache folder is the `cache` directory setting: `outputs/cache` in standard projects, `outputs/private/cache` in privacy-sensitive projects, and `cache/` in courses and presentations. `FW_CACHE_DIR` overrides it.

## Results registry

When you save outputs, Framework automatically records them:

```r
save_table(results, "analysis_results")
save_figure(plot, "summary_chart")
save_model(model, "regression_v1")
```

The results table tracks:
- Output path from the project root, such as `outputs/tables/analysis_results.csv`, and type (table, figure, model, report, notebook)
- Whether it's public or private (for sensitive projects)
- File hash for integrity
- Creation and update timestamps

Use `result_list()` to query saved results:

```r
result_list()                        # All results
result_list(type = "figure")         # Only figures
result_list(type = "table", public = TRUE)  # Public tables only
```

See [Saving work](guide:saving-work) and [Viewing work](guide:viewing-work) for complete documentation on saving and tracking outputs.

## Direct queries

You can query `framework.db` directly with the built-in "framework" connection:

```r
# View cached items
cache_entries <- db_query("SELECT name, expire_at FROM cache", "framework")

# Check data registry
data_registry <- db_query("SELECT name, path, hash, locked FROM data", "framework")

# List saved results
results <- db_query("SELECT name, type, created_at FROM results", "framework")
```

New rows store timestamps as epoch seconds. Rows written before 2.0 hold local date-time text. `result_list()` reads both.

The `framework` connection is defined in the connections settings of every new project.

## Location

The database lives at your project root:

```text
my-project/
├── framework.db          # Project database
├── settings.yml
├── notebooks/
└── ...
```

---

<div style="display: flex; justify-content: space-between">

[← scaffold()](guide:scaffold)

[Packages →](guide:packages)

</div>
