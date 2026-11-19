---
id: ai-assistants
title: AI assistants
section: features
position: 11
description: 'AGENTS.md context files, assistant skills, and Framework Cloud skill sync'
---
## Context and skills

Each Framework project generates a single canonical instruction file (`AGENTS.md`) alongside on-demand skills (`SKILL.md`) so coding agents understand the project's directory layout, package configuration, and data catalog.

## Generated files

- `AGENTS.md`: canonical project instructions. Edit custom rules directly here.
- Pointer files: `CLAUDE.md` (`@AGENTS.md`) or `.github/copilot-instructions.md`, depending on configured assistants.
- Skills: task-specific `SKILL.md` guides loaded on demand by assistants.

Because `AGENTS.md` is canonical, no file-sync hook is needed; the 1.x `ai_sync` hook was removed in 2.0 and `ai_sync_context()` is deprecated.

## Supported coding assistants

| Assistant | Skills directory | Pointer file |
|-----------|------------------|--------------|
| Claude Code | `.claude/skills/` | `CLAUDE.md` |
| OpenAI Codex | `.agents/skills/` | Reads `AGENTS.md` directly |
| GitHub Copilot | `.agents/skills/` | `.github/copilot-instructions.md` |

Claude Code is enabled by default. Configured assistants are listed under `ai.assistants` in `settings/ai.yml` (or `settings.yml`). When no assistant is selected, skills install into `.agents/skills/`.

## Built-in skills

- `framework-workflow`: project conventions and `scaffold()` initialization
- `framework-data`: data catalog reads, saves, and hashes
- `framework-packages`: `package_add()`, package sets, and `renv`
- `framework-outputs`: `save_table()`, `save_figure()`, `save_model()`, and `save_notebook()`
- `framework-cache`: `cache_remember()` and cache invalidation
- `framework-databases`: `db_query()` and connection configuration
- `framework-publishing`: `publish()` destinations and visibility rules
- `ggplot2-figures`: exploratory and publication figures in `ggplot2`
- `framework-sensitive-data`: private and public directory rules (privacy-sensitive projects)

`AGENTS.md` includes a table of installed skills and relative paths so tools without native skill discovery can read them.

## Syncing skills with Framework Cloud

### Pulling project skills

`pull_skills()` updates a project's skills from its setup on Framework Cloud using `FW_PROJECT_TOKEN` in `.env`:

```r
pull_skills(dry_run = TRUE)
pull_skills()
```

Missing skills are added, and unedited skills update to their latest versions (built-in skills from the installed R package, custom Cloud skills from Framework Cloud when signed in with `cloud_login()`, or the version pinned in the project setup when signed out).

Locally edited skills are kept and reported:

```text
Skills: 2 added, 3 updated, 5 up to date, 1 locally edited (kept)
  Edited: ggplot2-publishing — .claude/skills/ggplot2-publishing has local edits, which were kept. pull_skills(overwrite = TRUE) replaces them with the built-in version.
```

Pass `overwrite = TRUE` to replace locally edited skills after backing them up to `.framework/skills-backups/`. Skills removed from the Cloud setup are listed without being deleted locally, and the Skills table in `AGENTS.md` is refreshed. Offline or without `FW_PROJECT_TOKEN`, `pull_skills()` refreshes built-in package skills for the project's type. `ai_skills_update()` is an alias for `pull_skills()`.

### Skills lock

`.framework/skills.lock.json` tracks each skill by its identity: a Framework built-in, a Cloud skill in one language variant, or text from the project setup. For each copy (such as `.claude/skills/ggplot2-figures` and `.agents/skills/ggplot2-figures`), it records what the last sync wrote there. A copy that still matches its record is unedited. Any other copy is locally edited, including a copy reverted by hand to an older version. Commit the lock with the project. Framework 2.1.0 writes lock schema 2; framework 2.0.17 and earlier can't read it, so update every checkout that shares the project.

A skill's copies are judged together:

| Copies | Pull |
|--------|------|
| All unedited | Updated together. A missing copy, or a new assistant folder, gets the new version. |
| All edited the same way | Kept as edited. `overwrite = TRUE` backs them up and replaces them. |
| An edited copy and a copy that differs | Diverged. Nothing is written, and the row gives the `skills_copy()` call that copies the edit over the others. With two different edits, you pick the copy to keep. |
| An edited copy and a missing copy | Diverged, with the `skills_copy()` call that copies the edit there. `overwrite = TRUE` replaces the edit and fills the missing copy. |
| A copy in a folder that is gone | Missing. The other copies are pulled. |

Skills are matched by identity, never by folder name. A folder that tracks a different skill than the setup names, or another variant of it, is kept, and the row gives the `skills_move()` call that switches it. Setup text never replaces a built-in or your own Cloud skill. No skill moves to an older version: when the project holds a newer version than the setup names (after `push_skills()`), its copies are kept and a new assistant folder gets the project's copy. Pull reads only the enabled assistants' skills folders and the paths the lock tracks. Offline, skills tracked on Cloud are left as they are and listed as unavailable. When every copy of your own Cloud skill is gone, pull restores it from Cloud when you are signed in, and otherwise says to sign in.

### Pushing edited project skills

`push_skills()` publishes locally edited skills recorded in `.framework/skills.lock.json` to your Framework Cloud account (requires `cloud_login()`):

```r
push_skills(dry_run = TRUE)
push_skills()
```

`push_skills()` shows what each new version affects and prompts `Continue? [y/n]` (pass `confirm = TRUE` in non-interactive sessions). If a skill changed on Cloud since the last pull, pushing stops with `"Pull first"` unless `force = TRUE`. Edited built-in Framework skills are saved as private forks under your account rather than modifying built-in skills. When Cloud already has the edited files, nothing is sent and the lock records Cloud's version.

### Copying skills between assistant folders

A project can keep the same skill in `.claude/skills/` (Claude Code) and `.agents/skills/` (Codex and Copilot). `pull_skills()` writes the same copy to both. After you edit one copy, the copies differ. `skills_sync()` stops for that skill with "Assistant skill copies diverged", `push_skills()` reports it as failed and continues with the others, and `pull_skills()` leaves it as it is. A missing copy next to an edited one counts as diverged too. `skills_copy()` copies the version to keep over the others:

```r
skills_copy(from = "claude", dry_run = TRUE)
skills_copy(from = "claude")                      # to every other assistant folder
skills_copy(from = "claude", to = "agents", skills = "ggplot2-figures")
skills_copy(from_dir = ".claude/skills", to_dir = "some/other/skills")
```

`from` and `to` take `"claude"` or `"agents"`. `"codex"` and `"copilot"` also name `.agents/skills/`. `from_dir` and `to_dir` take project-relative folders. They can't be empty, the same folder, or one inside the other. The target can't be in or contain `.framework/`.

A skill is a folder with a regular `SKILL.md` file. Folders whose names start with `.` are skipped, because copies are staged in them. `skills_copy()` copies `SKILL.md` and its syncable companion files, with executable modes. Excluded files, such as `.env`, are not copied and stay in the target. Other files that are only in a replaced copy are removed from it and kept in the backup. Each replaced copy is backed up to `.framework/skills-backups/` and keeps its folder permissions. The output names the backup folder. Identical copies are left alone. Skills only in a target folder are listed, left alone, and not read. When the source skill is tracked in `.framework/skills.lock.json`, a real run adds each copy to its entry with the source copy's record, so the copies sync as one skill. An edited source makes an edited copy, so `push_skills()` then pushes the edit. A target that another skill tracks is refused. A dry run, or an untracked source, leaves the lock alone. A folder name or matching bytes never join a path to a skill.

A real run takes the skill sync lock, then checks every source and target before anything is written. If a copy fails or is interrupted, the copies already made are undone. A copy that can't be restored is named with its backup.

### Moving a skill or switching its identity

`skills_move()` changes what the lock says about a copy:

```r
skills_move("claude", "agents")                                   # every tracked copy in .claude/skills
skills_move(".claude/skills/survey-weights", ".agents/skills/survey-weights")
skills_move(".claude/skills/framework-data", skill_id = "5d0c2a7e-...")   # your fork
skills_move(".claude/skills/framework-data", builtin = "framework-data")
skills_move(".claude/skills/lab-style", variant = "python")
```

When the folder exists, it is renamed and its record moves with it. When the folder was already moved by hand, such as `.claude` renamed to `.agents`, only the record moves; `pull_skills()` and `push_skills()` print this call when they find a tracked copy whose folder is gone next to an untracked folder of the same name. `skill_id`, `builtin`, and `variant` switch the copy's skill. Unedited copies stay unedited, so the next pull updates them to the new skill's version. Edited copies stay edited, and `push_skills()` refuses them until `force = TRUE`. A target folder that exists, or that another skill tracks, stops the move before anything changes. `dry_run = TRUE` shows the plan.

### Syncing an individual skill folder

`skills_sync()` synchronizes any single skill directory (and companion files) with your Framework Cloud account:

```r
skills_sync(".claude/skills/my-review-checklist", dry_run = TRUE)
skills_sync(".claude/skills/my-review-checklist")
```

Unregistered skills become private account skills on Cloud. If both local and Cloud copies changed, `skills_sync()` stops and reports the conflict until you pass `resolve = "local"` or `resolve = "remote"`. Replaced files are backed up first.

### Known limits

- Use one skill per folder name in a project.
- Copy skills between assistant folders with `skills_copy()`, and move them with `skills_move()`. A copy made by hand isn't tracked, and `pull_skills()` leaves it alone and prints the `skills_copy()` call that tracks it.
- On macOS, folder names that differ only in letter case are the same folder. Use one spelling.
- A skill command that refuses changes nothing. Its message says what to do next.

## Privacy-sensitive projects

Privacy-sensitive projects list restricted paths in `AGENTS.md` and install `framework-sensitive-data`. When Claude Code is selected, Framework also writes `.claude/settings.json` with `deny` rules and sandboxing that block access to private directories and `.env`. Other assistants receive the `AGENTS.md` instructions and skill only.

## Regenerating AGENTS.md sections

Blocks delimited by `<!-- @framework:regenerate -->` update from current project metadata while leaving hand-written sections intact:

```r
ai_regenerate_context()
ai_regenerate_context(sections = "packages")
```

`ai_regenerate_context()` refreshes environment details, installed packages, and data catalog entries, and continues to support legacy 1.x projects where `CLAUDE.md` was canonical.
