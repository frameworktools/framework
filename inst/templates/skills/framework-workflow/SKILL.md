---
name: framework-workflow
description: Use when writing or editing an R notebook or script in a project that uses the Framework package. Covers scaffold() and creating notebooks and scripts with make_notebook() and make_script().
metadata:
  title: "Framework: notebooks and scripts"
  summary: Start notebooks and scripts with scaffold(), and create new ones through Framework.
---

# Framework: notebooks and scripts

This project uses the Framework R package. Follow its conventions in code that
calls `scaffold()`. Leave existing code as it is unless the user asks you to
change it.

## scaffold()

Start each notebook and script with `scaffold()`. It sets the working
directory to the project root, loads `.env`, installs and attaches the
project's packages, sources the functions folder, and applies the project's
seed and theme settings.

- Call functions from the functions folder directly. `scaffold()` has already
  sourced them.
- Packages marked `auto_attach` are already loaded. AGENTS.md lists them.
- Prefer the project's seed. When an operation needs its own seed, say why in
  a comment.

## New notebooks and scripts

Prefer Framework's helpers. They put the file in the project's folder and use
its template.

```r
make_notebook("01-data-cleaning")         # notebooks/01-data-cleaning.qmd
make_script("data-processing")            # scripts/data-processing.R
make_notebook("talk", stub = "revealjs")  # slides
```
