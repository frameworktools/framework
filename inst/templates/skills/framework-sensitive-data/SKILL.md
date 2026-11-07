---
name: framework-sensitive-data
description: Use before ANY data operation, commit, output, or publish step in this privacy-sensitive Framework project - enforces private/public directory separation and PII/PHI handling rules.
metadata:
  title: Handling sensitive data
  summary: Keep private data in private folders, out of Git and published work.
---

# Sensitive Data Rules

This is a privacy-sensitive project. These rules override convenience — when in
doubt, treat data as private.

## Critical Rules

1. **NEVER commit `inputs/private/` or `outputs/private/` directories** — they contain PII/PHI
2. All raw data with PII goes in `private/` subdirectories
3. Only de-identified, aggregated data goes in `public/` directories
4. Review ALL outputs before moving anything to a public directory
5. Save sensitive data into a private directory: `data_save(df, "inputs.private.intermediate.cleaned")`,
   or a path under `inputs/private/` or `outputs/private/`
6. Run `git_security_audit()` before commits to scan for data leaks, and keep the
   `data_security` git hook on (`git_hooks_list()`, `git_hooks_enable("data_security")`)
7. **NEVER `publish()` anything from a private directory**

## Data Flow

```
Raw PII data      -> inputs/private/raw/
    | clean, de-identify
Intermediate      -> inputs/private/intermediate/
    | aggregate, anonymize
Public-safe data  -> inputs/public/final/
```

## Learning a File's Layout

To learn what a private or restricted file holds, use
`data_info(name, columns = TRUE)` instead of reading the file, printing it, or
calling `head()`, `str()`, `glimpse()`, or `summary()` on it:

```r
info <- data_info("inputs.private.raw.patients", columns = TRUE)
info$columns   # name, type, and count of missing values for each column
info$rows      # number of rows
```

It never shows values, factor levels, ranges, or examples, and it records
nothing in framework.db.

## When Writing Code

- Never print raw rows containing identifiers in notebook output that will be rendered
- Never hardcode identifiers, names, or record-level values in code or comments
- Aggregations shown publicly should respect small-cell suppression rules where applicable
