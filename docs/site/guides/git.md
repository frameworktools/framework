---
id: git
title: Git integration
section: features
position: 10
description: 'Version control and Git hooks'
---
## Overview

Framework initializes a git repository when you create a project. It writes a `.gitignore` for the project type, installs the pre-commit hook when hooks are on, and provides helpers for common git operations.

## .gitignore templates

Framework generates `.gitignore` files based on project type. Each project type has its own template:

- **project**: Standard research project ignores
- **project_sensitive**: Stricter rules for sensitive data
- **course**: The standard rules, plus rendered slides and local cloud credentials (`.aws/`)
- **presentation**: The standard rules, plus local cloud credentials (`.aws/`)

Templates use pattern-based rules, such as `**/private/**` and `**/cache/**`. They work regardless of how you customize the directory structure. Every template ignores `.env`. Edit the project's `.gitignore` to add your own rules.

Before the first commit, Framework asks git whether `.env` is ignored. If it isn't, Framework adds it to `.gitignore`. If git still doesn't ignore it, Framework skips the commit.

## Commit identity

Framework uses your git identity (`user.name` and `user.email`). If either is missing, Framework skips the initial commit and says so. Set them once:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## Git hooks

Framework installs one pre-commit hook. It is a short POSIX `sh` script shared with framework-py and `fw`. It finds R with framework 2.0 or later, or Python with framework-py, and runs the checks enabled in `settings.yml`. If it finds neither, the commit fails with a message. Use `git commit --no-verify` only when you know the commit is safe.

Turn checks on in `settings.yml` (or `settings/git.yml` in split-settings projects):

```yaml
git:
  hooks:
    data_security: true
    check_sensitive_dirs: true
    check_notebook_outputs: true
```

New projects start with every check off.

**data_security**: Runs `git_security_audit()` and blocks the commit when a check fails. For example, the audit fails when git tracks data files in private folders or tracks a `.env` file.

**check_sensitive_dirs**: Warns about folders named like `private`, `confidential`, `sensitive`, `cache`, or `scratch` that git doesn't ignore. In a terminal, it asks whether to continue. Without a terminal, it continues with the warning. `warn_unignored_sensitive` is an accepted alias.

**check_notebook_outputs**: Blocks staged Jupyter notebooks that still hold cell outputs, since outputs can contain data.

The `ai_sync` hook was removed in 2.0. Projects keep one `AGENTS.md`, so there is nothing to sync. An `ai_sync` setting left in `settings.yml` is ignored, and `git_hooks_enable("ai_sync")` is an error.

### Hook management

```r
git_hooks_enable("data_security")
git_hooks_disable("check_sensitive_dirs")
git_hooks_list()
git_hooks_install()
git_hooks_uninstall()
```

`git_hooks_install()` writes the hook where git looks for it, including worktrees and `core.hooksPath`. It replaces a hook Framework wrote earlier. It keeps any other pre-commit hook unless you pass `force = TRUE`. The hook reads `settings.yml` on every commit, so enabling or disabling a check needs no reinstall.

After cloning a project, `bootstrap()` installs the enabled hooks along with the rest of the project setup.

## Security audit

`git_security_audit()` reports on these checks:

- **gitignore_coverage**: Data files in private folders that `.gitignore` doesn't cover
- **private_data_exposure**: Private data files that git tracks
- **git_history**: Data files committed earlier in the history
- **orphaned_files**: Data files outside the configured folders
- **secrets_exposure**: `.env` files that git tracks

A folder counts as private when its settings key contains `private`, when its path has a folder named like `private`, `confidential`, or `sensitive`, or when it is `cache`, `scratch`, or `logs`. Standard projects can commit files in `inputs/raw` and the other input folders, as their `.gitignore` allows. Put restricted data under a private folder. A data file git tracks under a folder named like `private` fails the audit, even when it was added with `git add -f`.

```r
audit <- git_security_audit()
audit$summary

# Skip the history scan
git_security_audit(check_git_history = FALSE)
```

## Git helper functions

Run common git operations from R without leaving your session:

```r
git_status()
git_add()
git_add("file.R")
git_commit("Fix bug")
git_push()
git_pull()
git_diff()
git_log()
```

Quick workflow:

```r
git_add()
git_commit("Add data cleaning step")
git_push()
```

---

<div style="display: flex; justify-content: space-between">

[← Saving work](guide:saving-work)

[AI assistants →](guide:ai-assistants)

</div>
