---
name: framework-sensitive-data
description: Use in a privacy-sensitive project that uses the Framework package, before saving data or outputs, committing, or publishing. Covers the private and public folders and the checks Framework runs.
metadata:
  title: "Framework: sensitive data"
  summary: The private and public folders of a privacy-sensitive Framework project.
---

# Framework: sensitive data

This project was created as privacy sensitive. Framework keeps private files
in their own folders and checks them before they leave the project.

## Folders

```
inputs/private/raw/            original data
inputs/private/intermediate/   working data
inputs/private/final/          analysis-ready data
inputs/public/                 data cleared for sharing
outputs/private/               outputs before review
outputs/public/                outputs cleared for sharing
```

- Git ignores the private folders.
- In Claude Code, the project's settings deny reading the private folders and
  `.env`.
- Save private data under `inputs/private/`, for example
  `data_save(df, "inputs.private.intermediate.cleaned")`.
- The `save_*()` helpers save to the private output folders by default. Pass
  `public = TRUE` only when the user asks.

## Checks

- The `data_security` git hook runs `git_security_audit()` before each commit
  and stops a commit that fails it. `git_hooks_list()` shows whether the hook
  is on.
- The publish functions warn about files in private folders and ask the user
  to confirm. In a script they stop. Leave `include_private` off, and let the
  user answer the prompt.
