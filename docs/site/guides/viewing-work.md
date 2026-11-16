---
id: viewing-work
title: Viewing work
section: features
position: 8
description: 'Interactive object viewer, saved results registry, and project info'
---
## Interactive viewer

`view()` writes a standalone HTML view of an R object to a temporary file and opens it in your browser, giving consistent inspection across Positron, VS Code, RStudio, and terminal sessions. `view()` requires the `DT`, `lubridate`, `prismjs`, and `yaml` packages.

### Data frames

Data frames open in an interactive table with global search, per-column filters, sortable headers, pagination, and Copy, CSV, and Excel export buttons:

```r
view(mtcars)
```

![Data frame viewer](images/view-dataframe.png)

### Lists and nested objects

Lists, `settings()` trees, and nested objects open in a two-tab inspector showing formatted YAML and `str()`-style R structure:

```r
x <- list(a = 1, b = c(2, 3), c = list("D", "E", list(F = "G")))
view(x)
```

### Plots

`ggplot2` objects and recorded base R plots open as rendered images:

```r
p <- ggplot(mtcars, aes(mpg, hp)) + geom_point()
view(p)
```

### Viewer options

```r
view(df, title = "Survey Results")
view(large_df, max_rows = 1000)   # Default limit: 5000 rows
```

## Saved results registry

Query outputs recorded in `framework.db` with `result_list()`:

```r
result_list()
result_list(type = "figure")
result_list(type = "table")
result_list(type = "model")
result_list(public = TRUE)
result_list(public = FALSE)
result_list(type = "table", public = TRUE)
```

`result_list()` returns a data frame ordered newest first with each output's project-relative `name` (such as `outputs/tables/summary.csv`), `type`, `public` flag, `comment`, SHA-256 `hash`, and timestamps.

## Project summary

Inspect configured directories and output routing with `project_info()`:

```r
project_info()
```

`project_info()` prints the project name and type, configured directory keys and whether each folder exists on disk, the active cache path, and the target folder for each `save_*()` function.
