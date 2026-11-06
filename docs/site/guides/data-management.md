---
id: data-management
title: Data management
section: features
position: 4
description: 'Data files and the declarative data catalog'
---
## Overview

Framework provides a declarative approach to data management. Instead of hardcoding file paths throughout your code, you define a data catalog in your settings and reference data using dot notation like `inputs.raw.sales`. Framework resolves paths, selects the correct reader, and tracks file integrity automatically.

## Data catalog

The catalog lives under `data:`. Projects with split settings files keep it in `settings/data.yml`. Single-file projects keep it in `settings.yml`. Keys can be flat dot notation or nested:

```yaml
data:
  inputs.raw.sales:
    path: inputs/raw/sales_2024.csv
    type: csv

  inputs.raw.customers:
    path: inputs/raw/customers.parquet
    type: parquet

  inputs.final.merged:
    path: inputs/final/merged_data.rds
    type: rds
```

The nested form is equivalent. `data_add()` writes this form:

```yaml
data:
  inputs:
    raw:
      sales:
        path: inputs/raw/sales_2024.csv
        type: csv
```

## Catalog editing

Register an existing file with `data_add()`:

```r
data_add("inputs/raw/survey.csv")
# Registered as inputs.raw.survey

data_add("inputs/raw/sales_2024.csv", name = "inputs.raw.sales")
```

`data_add()` detects the type from the extension and derives the name from the path when you omit `name`. It records the file's hash and marks the entry `locked: true` by default.

List the catalog with `data_list()`. It returns a data frame with each entry's name, path, type, lock status, and description.

`scaffold()` must run once before the first `data_add()`, so that `framework.db` exists.

## Supported formats

Framework supports these data formats:

| Type | Extensions | Reader | Package |
|------|------------|--------|---------|
| `csv` | .csv | `readr::read_delim()` | readr |
| `tsv` | .tsv, .txt, .dat | `readr::read_delim()` | readr |
| `rds` | .rds | `readRDS()` | base R |
| `excel` | .xlsx, .xls | `readxl::read_excel()` | readxl |
| `stata` | .dta | `haven::read_dta()` | haven |
| `spss` | .sav, .zsav | `haven::read_sav()` | haven |
| `spss_por` | .por | `haven::read_por()` | haven |
| `sas` | .sas7bdat, .sas7bcat | `haven::read_sas()` | haven |
| `sas_xpt` | .xpt | `haven::read_xpt()` | haven |
| `parquet` | .parquet | `arrow::read_parquet()` | arrow |

For Stata, SPSS, and SAS files, Framework strips variable labels and formats by default for cleaner data frames. Use `keep_attributes = TRUE` to preserve them.

Parquet support requires the `arrow` package.

## Reading data

Use `data_read()` to load data by its catalog name:

```r
# Load from catalog
sales <- data_read("inputs.raw.sales")
customers <- data_read("inputs.raw.customers")

# The function automatically:
# - Resolves the path from the catalog
# - Uses the correct reader for the type
# - Checks the file's hash
```

`data_read()` also accepts a file path, such as `data_read("inputs/raw/sales_2024.csv")`. Hash checks apply to catalog names only.

## Saving data

Save data to the catalog with `data_save()`:

```r
# Process and save
merged <- sales |>
  left_join(customers, by = "customer_id")

data_save(merged, "inputs.final.merged")  # Writes inputs/final/merged.rds
```

A dot-notation name starts with a configured directory key (`inputs.final` is `directories.inputs_final`). The file is saved there and registered in the catalog. `data_save()` writes `rds` by default, or `csv` with `type = "csv"`. A file path such as `"inputs/final/merged.csv"` saves the file without adding a catalog entry. The directory must exist unless you pass `force = TRUE`. Saved files are locked by default.

## Data integrity

Framework automatically tracks data integrity using file hashes. When you read or save data, Framework computes a SHA-256 hash of the file and stores it in the project database.

**Hash checks:**

1. On first read, Framework records the file's hash
2. On subsequent reads, it compares the current hash against the stored hash
3. If the hashes differ, Framework warns you that the file has changed

**Locked data:** Entries marked `locked: true` raise an error instead of a warning when the file changes. `data_add()` and `data_save()` lock entries by default. This prevents accidental use of corrupted or modified source data.

```yaml
data:
  inputs.raw.survey:
    path: inputs/raw/survey_results.csv
    type: csv
    locked: true  # Error if file changes unexpectedly
```

## Data info

Get information about a data entry:

```r
data_info("inputs.raw.sales")
# Returns path, type, delimiter, locked, and private
```

## Cloud ledger

Projects linked to Framework Cloud can copy their data hashes to an integrity ledger on Cloud. The data files stay on your computer. Only names, hashes, and file sizes are sent.

- `ledger_push()` sends the hashes recorded in `framework.db`.
- `ledger_list()` lists the project's ledger entries.
- `data_verify()` compares a file with the local `framework.db` record and the Cloud ledger.

```r
data_verify("inputs.raw.sales")
```

Live mode sends each `data_save()` hash as the file is saved. Turn it on with `options: cloud_ledger: live` in `settings.yml` or the `FW_LEDGER=live` environment variable. It is off by default.

## Recommended organization

### Directory structure

```text
inputs/
├── raw/          # Original, untouched data
├── intermediate/ # Cleaned/transformed data
└── final/        # Analysis-ready datasets
```

### Naming convention

Use dot notation for logical grouping:

```yaml
data:
  # Source.stage.name pattern
  inputs.raw.sales_2024:
    path: inputs/raw/sales_2024.csv

  inputs.intermediate.sales_cleaned:
    path: inputs/intermediate/sales_cleaned.rds

  inputs.final.sales_ready:
    path: inputs/final/sales_ready.rds
```

---

<div style="display: flex; justify-content: space-between">

[← Packages](guide:packages)

[Functions →](guide:functions)

</div>
