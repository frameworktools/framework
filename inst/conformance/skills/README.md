# Skill sync scenarios

Language-neutral cases for skills lock v2
(`docs/architecture/skills-lock-v2.md`). The R package, framework-py, and
`fw` each run every case. framework-py and `fw` copy this folder with their
asset sync, pinned to an R tag, like the other conformance fixtures.

Each file is one case. A runner builds the project, runs the planner (or the
command with Cloud mocked), and compares the result.

## Content labels

Skill contents are short labels such as `d1` or `e1`. A label stands for a
one-file bundle whose `SKILL.md` is:

```
---
name: fixture
description: Skill scenario fixture.
---

<label>
```

with LF line endings and a final newline. Labels name roles only:

- `d…`: package versions of a built-in.
- `c…`: Cloud versions of a built-in.
- `m…`, `o…`, `f…`: versions of Cloud skills (yours, another, a fork).
- `n…`: inline setup text.
- `e…`: local edits.
- `s…`, `x…`: other folders.

`!unreadable` is a folder that holds only `README.txt` and no `SKILL.md`.

Any hash field holds `@<label>`: the bundle hash of that label's bundle. This
applies to `hash`, `known`, `copies.*.hash`, `base.hash`, `pending.hash`,
`origin.hash`, `offer.*.hash`, `remote.*.hash`, and `push_response.*.hash`.
Replace each with the real hash before running and before comparing.

## Fields

- `id`, `area`, `description`: the case. `covers` (optional) names the
  follow-up items it checks.
- `command`: `pull`, `pull_all`, `upgrade`, `push`, `push_all`, `copy`, or
  `move`.
- `options`: the command's options. Pull: `overwrite`, `dry_run`, `offline`.
  Push: `confirm`, `force`, `dry_run`. Copy: `from`, `to` (folder names or
  paths). Move: `from`, `to`, `skill_id`, `variant`, `builtin`. A missing
  option takes its default.
- `project.variant`: the project's language.
- `project.dirs`: the enabled assistants' skills folders, in order
  (`.claude/skills` for Claude Code, `.agents/skills` for Codex and Copilot).
  Set the project's assistants to match.
- `folders`: folders that exist and are empty apart from what `disk` adds.
- `disk`: skill folder → content label. A folder's parents exist.
- `lock`: `.framework/skills.lock.json` before the command (schema 1 or 2),
  or `null` for no lock file.
- `offer`: what the command's sources return (mock these; the planner takes
  them as its `offer` input):
  - `source`: `cloud` (the setup was read) or `package` (offline fallback, or
    upgrade).
  - `skills`: the setup's skills, or the package skills. Each has `name`,
    `identity`, `channel`, `version`, `server`, `content` (a label, or
    `null` when the package does not ship it), `hash`, and `known`.
  - `by_identity`: sources for lock entries fetched by their own identity, by
    entry key.
  - `remote`: push only. Cloud's head per entry key (`version`, `hash`). An
    entry missing from it has no Cloud version (a built-in Cloud never
    published).
  - `push_response`: push only. What `POST /api/v1/skills/sync` returns per
    entry key (`skill_id`, `version`, `hash`, `server`).
- `expected`:
  - `error`: an error code when the command stops before writing, else
    `null`. Codes: `lock_schema_unsupported`, `move_target_exists`,
    `move_target_owned`, `move_nothing`, `move_untracked`,
    `move_identity_exists`, `copy_target_owned`.
  - `steps`: one per copy, sorted by path. `path`, `entry` (lock key, or
    `null`), `name`, `action` (`none`, `write`, `copy`, `record`, `move`,
    `push`), `status`, `reason_code`, and `hint`. A `write` names its
    `content`. A `copy` or `move` names its `from`. `backup: true` marks a
    write over an existing folder.
  - `rows`: the result rows the command returns, built from `steps` by the
    rules in the spec's "Rows" section.
  - `disk`: every skill folder after the command.
  - `backups`: the copies moved to `.framework/skills-backups/`.
  - `lock`: the lock file after the command, always schema 2, or
    `"unchanged"` when the file must not be rewritten (byte-identical, still
    schema 1 if it was).
  - `failed`: `pull_all` and `push_all` only. The names in the top-level
    `failed` list.

A dry run expects the same `steps` and `rows` as a real run, with `disk`
equal to the input, no backups, and the lock unchanged.

## Hints

`hint` is `null` or an object with a `key` and its arguments:

| Key | Arguments |
|---|---|
| `overwrite` | |
| `copy` | `from` (a path, or `null` when the person picks), `to` (paths), `pick` |
| `move` | `from`, `to` |
| `retarget` | `path`, `identity` |
| `force` | |
| `sync` | `path` |
| `login` | |

## Comparison

- Compare parsed JSON. Object key order does not matter.
- `steps` compare as a list sorted by path. `rows` compare as a list sorted
  by `name`, then `paths`.
- `known` and every `paths` and `to` list compare as sorted lists.
- `backups` compare as paths of the copies that were backed up, not the
  backup folder names.
- `reason` prose and rendered hint commands are not compared. Each language
  checks its own wording in its own tests.
- A runner that tests only the planner checks `error`, `steps`, `rows`, and
  `lock`. A runner that runs the command checks all fields.

## Updating

Cases are written by hand and reviewed with the spec. A change to the rules
changes the spec and these files in the same commit.
