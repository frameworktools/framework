---
id: functions
title: Functions
section: features
position: 5
description: 'Automatic sourcing for reusable R functions'
---
## Automatic sourcing

`scaffold()` sources every `.R` file in `functions/` into the global environment in alphabetical order:

```text
my-project/
├── functions/
│   ├── data_cleaning.R
│   ├── plotting.R
│   └── stats_helpers.R
├── notebooks/
└── scripts/
```

Once `scaffold()` runs, notebooks and scripts call those functions directly without `source()` boilerplate:

```r
library(framework)
scaffold()

clean_data <- my_cleaning_function(raw_data)
```

Keep only function definitions inside `functions/*.R` so `scaffold()` does not execute side effects on startup. Because files load as a directory, you can split, rename, or reorganize helper files without updating notebooks.

## Custom function directories

To source additional or alternate folders, list them under `directories.functions` in `settings.yml`:

```yaml
default:
  directories:
    functions:
      - functions
      - helpers
```

`scaffold()` emits a warning if none of the configured directories exist or contain `.R` files.

## Disabling automatic sourcing

Set `source_all_functions: false` in `settings/scaffold.yml` (or `settings.yml`) to skip sourcing `functions/*.R`:

```yaml
scaffold:
  source_all_functions: false
```
