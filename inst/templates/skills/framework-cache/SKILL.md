---
name: framework-cache
description: Use when caching expensive computations in a project that uses the Framework package. Covers cache_remember(), cache(), cache_get(), and cache_forget().
metadata:
  title: "Framework: caching computations"
  summary: Cache computed values with explicit names and expiry.
---

# Framework: caching computations

```r
# Computes once, then reuses the result until it expires
model <- cache_remember("fitted_model", {
  fit_complex_model(training_data)
}, expire_after = "7 days")

cache("processed_data", large_dataframe)   # write
df <- cache_get("processed_data")          # read (NULL if missing)
cache_forget("processed_data")             # remove
```

Cache entries are recorded in `framework.db` with a hash and an expiry. Use
names that say what the value is.
