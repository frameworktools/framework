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
5. Use `data_save(..., private = TRUE)` for sensitive outputs
6. Run `framework check:sensitive` before commits to scan for data leaks
7. **NEVER `publish()` anything from a private directory**

## Data Flow

```
Raw PII data      -> inputs/private/raw/
    | clean, de-identify
Intermediate      -> inputs/private/intermediate/
    | aggregate, anonymize
Public-safe data  -> inputs/public/final/
```

## When Writing Code

- Never print raw rows containing identifiers in notebook output that will be rendered
- Never hardcode identifiers, names, or record-level values in code or comments
- Aggregations shown publicly should respect small-cell suppression rules where applicable
