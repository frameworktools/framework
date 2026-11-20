---
id: data-management
title: Data management
section: features
position: 4
description: 'Data files, format readers, and the declarative data catalog'
---
## Data catalog

Instead of repeating file paths across scripts, register datasets under `data:` in `settings/data.yml` (split projects) or `settings.yml` (single-file projects) and load them by dot-notation key (`inputs.raw.sales`). Framework resolves paths from the project root, selects the matching file reader, and checks SHA-256 hashes in `framework.db`.

Dotted and nested YAML keys are interchangeable:

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

`data_add()` writes the nested form:

```yaml
data:
  inputs:
    raw:
      sales:
        path: inputs/raw/sales_2024.csv
        type: csv
```

## Registering existing files

Register a file on disk with `data_add()`:

```r
data_add("inputs/raw/survey.csv")
data_add("inputs/raw/sales_2024.csv", name = "inputs.raw.sales")
```

`data_add()` infers `type` from the file extension, derives a dot-notation key from the path when `name` is omitted, and stores the file's SHA-256 hash in `framework.db`. Entries are unlocked unless you pass `locked = TRUE`. Run `scaffold()` once before the first `data_add()` so `framework.db` is initialized.

`data_list()` returns a data frame of catalog entries with `name`, `path`, `type`, `locked`, and `description`. `data_read()` prints an entry's `description` only when `scaffold.print_description_on_read` is `true`. `data_info("inputs.raw.sales")` returns a single entry's path, type, delimiter, lock flag, and privacy status.

## Supported file formats

| Type | Extensions | Reader | Package |
|------|------------|--------|---------|
| `csv` | `.csv` | `readr::read_delim()` | `readr` |
| `tsv` | `.tsv`, `.txt`, `.dat` | `readr::read_delim()` | `readr` |
| `rds` | `.rds` | `readRDS()` | `base` |
| `excel` | `.xlsx`, `.xls` | `readxl::read_excel()` | `readxl` |
| `stata` | `.dta` | `haven::read_dta()` | `haven` |
| `spss` | `.sav`, `.zsav` | `haven::read_sav()` | `haven` |
| `spss_por` | `.por` | `haven::read_por()` | `haven` |
| `sas` | `.sas7bdat`, `.sas7bcat` | `haven::read_sas()` | `haven` |
| `sas_xpt` | `.xpt` | `haven::read_xpt()` | `haven` |
| `parquet` | `.parquet` | `arrow::read_parquet()` | `arrow` |

For Stata, SPSS, and SAS inputs, `data_read()` strips variable labels and format attributes by default; pass `keep_attributes = TRUE` to retain them.

## Reading data

Load a registered dataset by catalog key or direct path:

```r
sales <- data_read("inputs.raw.sales")
customers <- data_read("inputs.raw.customers")
ad_hoc <- data_read("inputs/raw/sales_2024.csv")
```

Catalog reads verify the file's SHA-256 hash in `framework.db`. Direct file paths bypass catalog hash checks. Relative paths resolve from the project root first, then from the current working directory.

## Saving data

Write a dataset and register it in the catalog with `data_save()`:

```r
merged <- sales |>
  left_join(customers, by = "customer_id")

data_save(merged, "inputs.final.merged")  # Writes inputs/final/merged.rds
```

A dot-notation name begins with a configured `directories` key (`inputs.final` maps to `directories.inputs_final`). `data_save()` writes RDS by default, writes CSV when `type = "csv"` or when the name ends with `.csv` (`"inputs.final.merged.csv"`), and leaves the data unlocked unless you pass `locked = TRUE`. Passing a path containing `/` (`"inputs/final/merged.csv"`) writes the file relative to the project root without adding a catalog entry. Bare filenames without a directory prefix or `/` raise an error, and missing target directories outside the configured settings folders require `force = TRUE`.

## Integrity hashes and locks

When reading or saving a catalog entry, Framework computes the file's SHA-256 hash and compares it with `framework.db`:

- First read or save: records the SHA-256 hash.
- Subsequent read with `locked: true` (set by `locked = TRUE` or in the catalog): stops with an error if the hash changed.
- Subsequent read with `locked: false` (the default): emits a warning and updates the stored hash.

```yaml
data:
  inputs.raw.survey:
    path: inputs/raw/survey_results.csv
    type: csv
    locked: true
```

## Locked data protection

`data_save()` does not change locked data. Saving the same contents again works. New contents stop with an error before the file is written, whether the save names the catalog entry or its path:

```text
Error: data_save() does not overwrite locked data.
  dataset: inputs.raw.survey (locked: true in the data catalog)
  file:    inputs/raw/survey_results.csv
Save the data under another name, or pass unlock = TRUE to replace it.
The new file is then unlocked. Add locked = TRUE to keep it locked.
```

Data is unlocked unless you lock it. Lock data you mean to keep as it is with `locked = TRUE`, or with `locked: true` on its catalog entry. A later save with the same contents keeps the lock.

Save derived data under another name. To replace locked data on purpose, pass `unlock = TRUE`. The new file is unlocked unless you also pass `locked = TRUE`. Setting `locked: false` on the catalog entry also unlocks it. `save_table()`, `save_model()`, and `cache()` never overwrite locked data.

```r
data_save(final, "inputs.final.analysis", locked = TRUE)
data_save(corrected, "inputs.raw.survey.csv", unlock = TRUE, locked = TRUE)
data_save(cleaned, "inputs.intermediate.cleaned", unlock = TRUE)
```

## Cloud integrity ledger

Projects with a `FW_PROJECT_TOKEN` can sync dataset hashes to the Framework Cloud ledger so collaborators can verify local copies without uploading data files. Only catalog names, SHA-256 hashes, byte sizes, and the machine's hostname leave the machine:

- `ledger_push()` uploads hashes recorded in `framework.db`.
- `ledger_list()` lists entries recorded on Framework Cloud.
- `data_verify("inputs.raw.sales")` checks a file against both `framework.db` and the Cloud ledger.

Set `options.cloud_ledger: live` in `settings.yml` or `FW_LEDGER=live` in `.env` to push a ledger record automatically on every `data_save()`.

## Naming conventions

Mirror your `inputs/` directory stages in catalog keys (`inputs.raw.*`, `inputs.intermediate.*`, `inputs.final.*`) so each dataset's pipeline stage is clear from its key.
