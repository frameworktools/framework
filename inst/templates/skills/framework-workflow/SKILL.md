---
name: framework-workflow
description: Use when writing or editing any R notebook or script in this Framework project - covers scaffold() initialization, critical environment rules, and creating notebooks/scripts with make_notebook() and make_script().
metadata:
  title: Notebooks and scripts
  summary: Start every notebook and script with scaffold(), and create new ones through Framework.
---

# Framework Workflow

This project uses the Framework R package for reproducible data analysis.

## scaffold() Comes First

**Every notebook and script MUST begin with `scaffold()`**, which initializes the environment:

1. Sets the working directory to the project root (handles nested notebook execution)
2. Loads environment variables from `.env` (database credentials, API keys)
3. Installs missing packages listed in settings.yml
4. Attaches packages marked with `auto_attach: true`
5. Sources all functions from the project's functions directory — they are globally available
6. Optionally sets the random seed and ggplot2 theme (see AGENTS.md for this project's settings)

## Critical Rules

- **DO NOT** call `library()` for auto-attached packages (listed in AGENTS.md). scaffold() already loaded them.
- **DO NOT** call `set.seed()` after scaffold() if the project sets a seed. If you need a different seed for a specific operation, document why.
- **DO NOT** use `source()` to load functions from the functions directory. They are auto-loaded by scaffold(); just call them directly.

## Standard Analysis Workflow

1. **Import**: Load raw data with `data_read()`
2. **Clean**: Process and save intermediate data with `data_save()`
3. **Analyze**: Work from final, analysis-ready datasets
4. **Export**: Save outputs with `save_table()`, `save_figure()`, or `save_model()`

See the `framework-data` skill for data rules and the `framework-outputs` skill for results, caching, and publishing.

## Creating Notebooks and Scripts

Always create new files through Framework so they land in the right directory with the right template:

```r
make_notebook("01-data-cleaning")     # Creates notebooks/01-data-cleaning.qmd
make_script("data-processing")        # Creates scripts/data-processing.R

# Presentation slides (revealjs)
make_notebook("talk", stub = "revealjs")
```

## Best Practices

- Keep raw data immutable — never modify files in the raw inputs directory
- Document data transformations in notebooks
- Commit notebooks, not rendered outputs
