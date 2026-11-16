---
id: caching
title: Caching
section: features
position: 12
description: 'Disk-backed computation caching, expiration, and invalidation'
---
## Cache storage

Framework caches expensive R computations as `.rds` files in the project's cache directory and tracks creation times, expirations, last-read timestamps, and SHA-256 integrity hashes in the `cache` table of `framework.db`.

Default cache directories by project type:

| Project type | Cache directory |
|--------------|-----------------|
| `project` | `outputs/cache` |
| `project_sensitive` | `outputs/private/cache` |
| `course` | `cache` |
| `presentation` | `cache` |

Cache directories are created on first write. Override the path in `settings.yml`:

```yaml
directories:
  cache: my/cache/path
```

The `FW_CACHE_DIR` environment variable overrides `directories.cache`.

## Evaluating with cache_remember()

`cache_remember()` evaluates an expression on a cache miss, saves the result to disk, and returns the saved value on subsequent runs:

```r
processed_data <- cache_remember("my_analysis", {
  raw_data |>
    mutate(date = parse_date(date_string)) |>
    filter(valid == TRUE) |>
    group_by(category) |>
    summarize(total = sum(amount))
})
```

Pass `depends_on` to invalidate the entry automatically when catalog datasets, source files, or parameter values change:

```r
model <- cache_remember("cohort_model", {
  fit_model(data_read("inputs.final.cohort"), knots = 4)
}, depends_on = list("inputs.final.cohort", "functions/fit_model.R", knots = 4))
```

## Expiration and refresh

Set `expire_after` as numeric hours or a duration string in seconds, minutes, hours, days, or weeks:

```r
fresh_data <- cache_remember("live_data", {
  fetch_from_api()
}, expire_after = 1)

cache_remember("quick", expr, expire_after = "30 minutes")
cache_remember("daily", expr, expire_after = "1 day")
cache_remember("weekly", expr, expire_after = "7 days")
```

Pass `refresh = TRUE` to recompute and overwrite an entry regardless of cache state:

```r
updated <- cache_remember("my_analysis", {
  expensive_computation()
}, refresh = TRUE)
```

## Direct read, write, and eviction

Write and read cache entries directly with `cache()` and `cache_get()`:

```r
cache("processed_results", my_data)
cache("temp_results", my_data, expire_after = 24)

cached <- cache_get("processed_results")
```

`cache_get()` returns `NULL` when an entry is missing, expired, or fails SHA-256 verification on disk (emitting a warning if the file was modified).

Inspect and clear entries with `cache_list()`, `cache_forget()`, and `cache_flush()`:

```r
cache_list()                  # Data frame of names, timestamps, and status
cache_forget("my_analysis")   # Delete one entry
cache_flush()                 # Delete all entries
```

## Naming and scope

Use descriptive keys (`"sales_2024_by_region"`), reserve caching for slow queries, simulations, or model fits, and set `expire_after` whenever an expression reads live external APIs or mutable tables.
