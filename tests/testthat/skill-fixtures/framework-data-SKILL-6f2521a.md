---
name: framework-data
description: Use whenever reading or writing data files (CSV, RDS, Excel, Stata, SPSS, SAS) in this Framework project - data_read() and data_save() are mandatory; base R and readr I/O functions are forbidden.
---

# Framework Data Management

**CRITICAL: All data operations MUST go through Framework functions.**
This ensures integrity tracking and reproducibility. Framework records a hash of
every file read or written in the project's `framework.db`.

## Reading Data

**ALWAYS use `data_read()`.** It supports CSV, RDS, Excel, Stata, SPSS, and SAS files.

```r
# From the data catalog in settings.yml (preferred)
survey <- data_read("inputs.raw.survey")

# Direct path
customers <- data_read("inputs/raw/customers.csv")
```

**NEVER use these — they bypass integrity tracking:**

- `read.csv()`, `read_csv()`, `readRDS()`, `read_excel()`, `haven::read_*()`

If you see code using these functions, replace it with `data_read()`.

## Saving Data

**ALWAYS use `data_save()`:**

```r
# Save to intermediate (tracked, integrity-checked)
data_save(cleaned_df, "inputs/intermediate/cleaned.csv")

# Save to final (locked, prevents accidental overwrites)
data_save(final_df, "inputs/final/analysis_ready.csv", locked = TRUE)
```

**NEVER use** `write.csv()`, `write_csv()`, or `saveRDS()` — no tracking.

## Data Catalog

Datasets can be declared in settings.yml and read by dot-notation name
(e.g. `data_read("inputs.raw.survey")`). Prefer catalog names over raw paths
when an entry exists.

## Directory Conventions

Data flows raw → intermediate → final. This project's exact directory layout is
listed in AGENTS.md (it is configured in settings.yml under `directories`).
Raw inputs are immutable; only Framework-tracked writes belong in intermediate
and final directories.
