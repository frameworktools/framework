---
id: caching
title: Caching
section: features
position: 12
description: 'Cached results of expensive computations'
---
## Overview

Framework's caching system saves the results of expensive computations and reuses them in later sessions. Repeated runs skip the cached computations.

Cached items are stored as RDS files in your project's cache directory. Framework tracks creation time, expiration, and a hash for integrity verification.

**Default cache directories by project type:**

| Project Type | Cache Directory |
|--------------|-----------------|
| project | `outputs/cache` |
| project_sensitive | `outputs/private/cache` |
| course | `cache` |
| presentation | `cache` |

Cache directories are created lazily. They don't exist until you first cache something. Change the folder in `settings.yml`:

```yaml
directories:
  cache: my/cache/path
```

The `FW_CACHE_DIR` environment variable overrides the setting. Cache metadata lives in the `cache` table of `framework.db`.

## Basic caching

Use `cache_remember()` to cache a computation:

```r
# First run: executes the code and caches result
processed_data <- cache_remember("my_analysis", {
  # Expensive operation
  raw_data |>
    mutate(date = parse_date(date_string)) |>
    filter(valid == TRUE) |>
    group_by(category) |>
    summarize(total = sum(amount))
})

# Subsequent runs: returns cached result instantly
processed_data <- cache_remember("my_analysis", {
  # This code won't run - cached result returned
})
```

## Cache expiration

Set an expiration time for cached data. Pass hours as a number, or a string in hours, days, or weeks:

```r
# Cache expires after 1 hour
fresh_data <- cache_remember("live_data", {
  fetch_from_api()
}, expire_after = 1)

# Human-readable strings also work
cache_remember("daily", expr, expire_after = "1 day")
cache_remember("weekly", expr, expire_after = "7 days")
```

## Forced refresh

Force re-computation even if cached:

```r
# Ignore cache and recompute
updated <- cache_remember("my_analysis", {
  # This runs even if cached
  expensive_computation()
}, refresh = TRUE)
```

## Manual caching

```r
# Manually cache a value
cache("processed_results", my_data)

# With expiration (hours)
cache("temp_results", my_data, expire_after = 24)
```

## Cached values

```r
# Get cached value (returns NULL if not found, expired, or changed on disk)
cached <- cache_get("processed_results")
```

`cache_get()` and `cache_remember()` check the file's hash. A cache file that changed since it was written counts as missing, with a warning.

## Removing one item

```r
# Remove a specific cache
cache_forget("my_analysis")
```

## Listing cached items

```r
cache_list()
# Returns a data frame with name, expire_at, created_at, updated_at,
# last_read_at, and status ("active" or "expired")
```

## Clearing the cache

```r
# Remove all cached items
cache_flush()
```

## Best practices

### Descriptive names

```r
# Good
cache_remember("sales_2024_by_region", ...)

# Avoid
cache_remember("data1", ...)
```

### Cache scope

Cache only expensive operations:

```r
# Good: Cache expensive database query
results <- cache_remember("quarterly_report", {
  db_query("SELECT region, SUM(amount) AS total FROM sales GROUP BY region", "warehouse")
})

# Avoid: Don't cache simple operations
# x <- cache_remember("add", { 1 + 1 })
```

### Expiration for live data

```r
# Good: External data should expire
api_data <- cache_remember("exchange_rates", {
  fetch_rates_from_api()
}, expire_after = "1 hour")
```

---

<div style="display: flex; justify-content: space-between">

[← AI assistants](guide:ai-assistants)

[Connections →](guide:connections)

</div>
