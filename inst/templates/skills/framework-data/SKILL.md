---
name: framework-data
description: Use when reading or writing data files (CSV, RDS, Excel, Stata, SPSS, SAS) in a project that uses the Framework package. Covers data_read(), data_save(), the data catalog, and the data folders.
metadata:
  title: "Framework: reading and saving data"
  summary: Read and save data files through Framework, which records each file's hash.
---

# Framework: reading and saving data

`data_read()` and `data_save()` record a hash of each data file in the
project's `framework.db`. A file read with `read.csv()`, readr, readxl, or
haven skips that record, so a changed file goes unnoticed. Follow these
conventions in code that calls `scaffold()`. Leave existing code as it is
unless the user asks you to change it.

## Reading

Prefer `data_read()`. It reads CSV, RDS, Excel, Stata, SPSS, and SAS files.

```r
survey <- data_read("inputs.raw.survey")            # by catalog name
customers <- data_read("inputs/raw/customers.csv")  # by path
```

Datasets listed in the settings (often `settings/data.yml`) have a dotted
catalog name. Prefer it to the path when an entry exists.

## Saving

Prefer `data_save()` to `write.csv()`, `write_csv()`, and `saveRDS()` for
project data.

```r
# Locked by default: a later read stops if the file changed
data_save(final_df, "inputs/final/analysis_ready.csv")

# Data a pipeline rebuilds on every run: unlocked, so a rebuild doesn't warn
data_save(cleaned_df, "inputs/intermediate/cleaned.csv", locked = FALSE)
```

## Folders

Data moves from raw to intermediate to final. AGENTS.md lists this project's
folders. Raw inputs stay unchanged.
