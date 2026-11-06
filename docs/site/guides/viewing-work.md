---
id: viewing-work
title: Viewing work
section: features
position: 8
description: 'Interactive views with view(), saved results, and project info'
---
## Overview

Framework provides tools for interactively exploring your data, viewing saved results, and browsing your project structure.

## Interactive viewer

Use `view()` to open objects in an interactive HTML viewer in your browser. It writes a temporary HTML file and opens it, so it works the same in RStudio, Positron, VS Code, and the terminal. It needs the DT, prismjs, and yaml packages.

### Data frames

Data frames open as a searchable, sortable, filterable table:

```r
view(mtcars)
```

![Data frame viewer](images/view-dataframe.png)

Features:
- Search across all columns
- Filter individual columns
- Sort by clicking headers
- Export to Copy, CSV, or Excel
- Pagination for large datasets

### Complex objects

For lists and other complex objects, `view()` displays a structured view with YAML and R tabs:

```r
x <- list(a = 1, b = c(2, 3), c = list("D", "E", list(F = "G")))
view(x)
```

<div style="display: flex; gap: 1rem;">
<img src="/images/view-list-yaml.png" alt="List viewer - YAML tab" style="max-width: 48%;">
<img src="/images/view-list-r.png" alt="List viewer - R tab" style="max-width: 48%;">
</div>

### Plots

ggplot2 objects and recorded base plots open as images:

```r
p <- ggplot(mtcars, aes(mpg, hp)) + geom_point()
view(p)
```

### Options

```r
# Custom title
view(df, title = "Survey Results")

# Limit rows for very large datasets (default 5000)
view(large_df, max_rows = 1000)
```

## Result list

Query saved results with `result_list()`:

```r
# All results
result_list()

# Filter by type
result_list(type = "figure")
result_list(type = "table")
result_list(type = "model")

# Filter by public status
result_list(public = TRUE)
result_list(public = FALSE)

# Combine filters
result_list(type = "table", public = TRUE)
```

Returns a data frame with each result's name, type, public flag, comment, hash, and timestamps, newest first. The name is the file's path from the project root, such as `outputs/tables/summary.csv`.

## Project info

View your project structure and output mappings:

```r
project_info()
```

This displays:
- Project name and type
- Configured directories, and whether each exists yet
- The cache directory
- The folder each `save_*()` function writes to

---

<div style="display: flex; justify-content: space-between">

[← Quarto integration](guide:quarto)

[Saving work →](guide:saving-work)

</div>
