---
id: functions
title: Functions
section: features
position: 5
description: 'Organizing reusable functions in Framework projects'
---
## Overview

Framework auto-loads functions from a `functions/` directory. Utility functions grouped by purpose are available in every notebook and script.

## Auto-loading benefits

**Semantic organization**: Group functions by purpose (cleaning, plotting, modeling) without worrying about load order.

**No boilerplate**: No `source()` calls at the top of every script that break when you rename or reorganize your project.

**Consistent environment**: Every notebook and script gets the same functions via `scaffold()`.

## Functions directory

Put reusable functions in `functions/`:

```text
my-project/
├── functions/
│   ├── data_cleaning.R
│   ├── plotting.R
│   └── stats_helpers.R
├── notebooks/
└── scripts/
```

When you call `scaffold()`, all `.R` files in `functions/` are automatically sourced. Scripts can then call the functions directly:

```r
library(framework)
scaffold()

clean_data <- my_cleaning_function(raw_data)
```

Files are sourced into the global environment in alphabetical order.

## Directory configuration

The default is `functions/`. To source other folders, list them under `options.functions_dir` in `settings.yml`:

```yaml
default:
  options:
    functions_dir:
      - functions
      - helpers
```

`scaffold()` warns when none of the listed folders exist.

## Sourcing control

To stop `scaffold()` from sourcing functions, set `source_all_functions` to `false` in the scaffold settings (`settings/scaffold.yml` in split-settings projects):

```yaml
scaffold:
  source_all_functions: false
```

---

<div style="display: flex; justify-content: space-between">

[← Data management](guide:data-management)

[Templates →](guide:templates)

</div>
