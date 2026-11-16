---
id: git
title: Git integration
section: features
position: 10
description: 'Gitignore templates, pre-commit hooks, security audits, and R Git helpers'
---
## Repository initialization

Project creation initializes a Git repository, writes a type-specific `.gitignore`, installs the pre-commit hook when checks are enabled, and creates the initial commit once Git identity is configured.

## .gitignore templates

Each built-in project structure uses its own pattern-based `.gitignore`:

- `project`: ignores `.env`, `framework.db`, caches, `scratch/`, `logs/`, and any `**/private/**` directory.
- `project_sensitive`: ignores `inputs/private/`, `outputs/private/`, `**/private/**`, `*_private/`, `sensitive/`, credential files, caches, `scratch/`, `logs/`, and `framework.db`.
- `course`: standard rules plus `rendered/` and `.aws/`.
- `presentation`: standard rules plus `.aws/`.

Before creating the initial commit, Framework checks `git check-ignore` on `.env`. If `.env` is not ignored, Framework appends `.env` to `.gitignore`; if Git still does not ignore `.env`, Framework skips the commit.

## Commit identity

Framework uses your configured `user.name` and `user.email`. If either is unset, project creation skips the initial commit and prints a note. Set them with:

```sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## Pre-commit hooks

Framework uses a single POSIX `sh` pre-commit hook shared across Framework for R, `framework-py`, and `fw`. On each commit, the hook locates R (`framework` >= 2.0) or Python (`framework-py`) and runs the checks enabled in `settings.yml` (or `settings/git.yml`). If neither runtime is installed, the commit stops with an error. Pass `git commit --no-verify` only when intentionally bypassing checks.

Configure checks in `settings/git.yml` or `settings.yml`:

```yaml
git:
  hooks:
    data_security: true
    check_sensitive_dirs: true
    check_notebook_outputs: true
```

Standard, course, presentation, and bare projects start with all checks `false`. Privacy-sensitive (`project_sensitive`) projects enable `data_security` and `check_sensitive_dirs` by default after the initial commit.

- `data_security`: runs `git_security_audit()` and blocks commits when any audit check fails, such as tracked private data files or `.env` files.
- `check_sensitive_dirs` (alias `warn_unignored_sensitive`): warns when directories named like `private`, `confidential`, `sensitive`, `cache`, or `scratch` are not covered by `.gitignore`. Interactive terminals prompt before continuing; non-interactive sessions continue after printing the warning.
- `check_notebook_outputs`: blocks staged `.ipynb` notebooks that still contain cell outputs.

The 1.x `ai_sync` hook was removed in Framework 2.0 because `AGENTS.md` is the single canonical file. Leftover `ai_sync` settings are ignored, and `git_hooks_enable("ai_sync")` raises an error.

### Managing hooks from R

```r
git_hooks_enable("data_security")
git_hooks_disable("check_sensitive_dirs")
git_hooks_list()
git_hooks_install()
git_hooks_uninstall()
```

`git_hooks_install()` respects Git worktrees and `core.hooksPath`, updates existing Framework hooks, and preserves third-party pre-commit hooks unless `force = TRUE`. Because the hook reads `settings.yml` on every commit, toggling checks requires no reinstall.

A project nested inside an outer Git repository cannot install a hook into the outer repository; run `git init` in the project directory first. `bootstrap()` installs enabled hooks automatically when setting up a cloned project.

## Security audit

`git_security_audit()` runs eight checks:

- `gitignore_coverage`: data files in private directories not ignored by `.gitignore`.
- `private_data_exposure`: files in private directories tracked by Git (including files added with `git add -f`).
- `git_history`: private data files committed in earlier Git revisions.
- `orphaned_files`: data files stored outside configured project directories.
- `secrets_exposure`: `.env` files tracked by Git.
- `connection_secrets`: literal credentials written in connection settings (fails when Git tracks the file, otherwise warns).
- `published_outputs`: folder publishing destinations inside the project holding files Git does not ignore (warning only).
- `identifier_columns`: tracked data files whose headers have identifier-like columns (warning only).

A directory counts as private when its `directories` key contains `private`, when its path contains a segment such as `private`, `confidential`, or `sensitive`, or when it is `cache`, `scratch`, or `logs`.

```r
audit <- git_security_audit()
audit$summary

# Skip scanning prior commits
git_security_audit(check_git_history = FALSE)
```

## R Git helpers

Run Git commands directly from R:

```r
git_status()
git_add()
git_add("scripts/clean.R")
git_commit("Add cohort cleaning step")
git_push()
git_pull()
git_diff()
git_log()
```
