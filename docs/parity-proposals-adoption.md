# Adoption and upgrade: R changes and what framework-py must mirror

Source: `framework-ports/ADOPTION-FINDINGS.md` (2026-11-07). Branch
`feat/adoption` in the R package, version 2.0.1 (unreleased). Nothing was
pushed, tagged, or created on Framework Cloud. The Cloud API is mocked in the
tests.

## Commits

| Item | Commit | Subject |
|---|---|---|
| B1, design 1 | 8fd9e11 | project_sensitive projects count as sensitive without a security block |
| B9, design 6 | bddaf6f | a config.yml counts as Framework settings only with Framework keys |
| B27 | 2f76e97 | adopt() doesn't follow symlinked folders |
| B26 | b59386c | a folder set to (other folder) in adopt()'s review never replaces another |
| B20 | b9b123f | adopt() takes a folder with no subfolders |
| B14 | bfe2ff2 | adopt() skips settings/ and Quarto's render folders, and maps render dirs |
| B13, B15 | f266420 | adopt() maps the private/public and course layouts and infers the type |
| B4 | 6759d04 | adopt() takes sensitive = TRUE and a type |
| B24 (R side) | 9312478 | adopt() turns git on for a folder that is a git repository |
| B3 | 56a645f | adopt() merges its .gitignore rules into the folder's .gitignore |
| B2, B21 (R side), Cloud design | c69d71e | cloud_register() creates a local project's Cloud project and links it |
| B5, design 5 | 3b81b54 | the audit's history check catches data committed in inputs folders or with identifiers |
| B5 on Windows | 4966e33 | the audit's history check works on Windows |
| B16, design 5 | 934c35a | the audit's orphaned-file check stops flagging known folders and JSON |
| conformance generator | 819d153 | generate the new adopt conformance cases from data-raw |
| B8, design 4 | 7d136b9 | quarto_regenerate() keeps customized Quarto config |
| B8 follow-up | fe50d02 | quarto_regenerate() leaves the root config alone while per-folder projects stay |
| B10 | 635c77f | skills from an older release are updated, not kept as locally edited |
| B11 | 182cdad | ai_regenerate_context() says how to create a missing context file |
| B28 | 6e5c040 | package installs fall back to the cloud CRAN mirror when none is set |
| B6, B11, B12, B30, design 3 | b4ca43d | upgrade() brings an older Framework project to the current layout |
| design 3 wording | b0b0db3 | upgrade()'s note about missing skills names the type plainly |
| docs | 0f6281e | guide to adopt(), upgrade(), and cloud_register() (`docs/upgrade.md`) |
| Cloud create-from-spec (follow-up) | bbed2d0 | cloud_register() creates the Cloud project from its spec in one request |
| Sensitive skill (follow-up) | cd7e2c4 | upgrade() gives a sensitive project without skills the sensitive-data skill |
| this file | (last commit) | parity proposals and results |

Not R's: B7, B17, B18, B19, B21 (fw help text), B29 (fw), and B22, B23, B25
(framework-py). B24 is R's half only. They are listed under framework-py below
where the shared design affects them.

## Test results

- macOS, full suite (`NOT_CRAN=true`, `testthat::test_local(".")`) at
  4966e33: 3587 passed, 0 failed, 0 errors, 19 skipped. After the follow-ups
  (cd7e2c4): 3606 passed, 0 failed, 19 skipped, and `R CMD check` again
  gives only the incoming-feasibility NOTE. The Windows run below predates
  the follow-ups. The baseline on
  `origin/main` had 3379 passing tests and no failures.
- macOS, `R CMD check --as-cran --no-manual`: Status 1 NOTE. The NOTE is
  CRAN incoming feasibility ("Days since last update: 0").
- Windows, R-devel, `R CMD check --as-cran --no-manual` with `NOT_CRAN` unset
  and the CRAN incoming check off: Status OK, tests `[ FAIL 0 | WARN 46 |
  SKIP 39 | PASS 3510 ]`.
  <https://github.com/frameworktools/framework/actions/runs/42414231064>.
  The first run, <https://github.com/frameworktools/framework/actions/runs/42413306113>,
  failed 4 expectations in the new history-check test: the audit ran
  `git log` through `system()` with a `|` in the format, which `cmd` treats as
  a pipe, so the history check never found anything on Windows. 4966e33
  fixes that. The throwaway branch `ci/windows-check-adopt` was deleted after
  the run.

## upgrade() plans for the five test copies

The copies are in `/tmp/fwfix3/adopt-tests/orig` (structure only: no data
files, nothing over 2 MB, private folders emptied, `.git` whole). Each plan
below is the exact dry-run output on a fresh copy. cannabis-ehr is not a
Framework project, so it is adopted first.

### syphillis-poc-test-analysis

```
Upgrade plan for /tmp/fwfix3/adopt-tests/run/syphillis-poc-test-analysis
  settings    settings.yml                             add tools (quarto: true, renv: false); add security (sensitive: true; project_type is project_sensitive)
  connections settings/connections.yml                 rewrite in the current layout: 0 database(s)
  gitignore   .gitignore                               add 5 rule(s): **/logs/**, slurm-*.out, /.quarto/, **/*.quarto_ipynb, .quarto_backups/
  ai          AGENTS.md                                create from CLAUDE.md (AGENTS.md becomes the canonical file)
  ai          CLAUDE.md                                replace with a pointer to AGENTS.md
  ai          AGENTS.md                                regenerate marked sections (environment, packages, data, functions)
  ai          .claude/settings.json                    keep Claude Code out of inputs/private
  skills      .claude/skills/framework-sensitive-data  add
  spec        .framework/spec.json                     create from the settings
Notes:
  - This project has no other Framework skills; upgrade() adds or keeps framework-sensitive-data. framework::ai_skills_update() installs the others for its type (project_sensitive).
  - notebooks/_quarto.yml makes notebooks/ a separate Quarto project and was kept. quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.
  - docs/_quarto.yml makes docs/ a separate Quarto project and was kept. quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.
Dry run: nothing was changed. Apply with framework::upgrade("syphillis-poc-test-analysis", dry_run = FALSE); every file it rewrites is backed up to .framework/backups/ first.
```

### a2cps-ehr-omop

```
Upgrade plan for /tmp/fwfix3/adopt-tests/run/a2cps-ehr-omop
  settings    settings.yml              add tools (quarto: true, renv: false); add security (sensitive: false)
  connections settings/connections.yml  rewrite in the current layout: 2 database(s), default_database: framework
  gitignore   .gitignore                add 5 rule(s): **/logs/**, slurm-*.out, /.quarto/, **/*.quarto_ipynb, .quarto_backups/
  ai          CLAUDE.md                 regenerate marked sections (environment, packages, data, functions)
  spec        .framework/spec.json      create from the settings
Notes:
  - settings.yml has keys outside default: (ehr_source, person). Framework ignores them; move them under default: to use them.
  - settings/connections.yml has a password or token written in (connections.databases.omop.password). Move the value to .env and write env("NAME") instead; upgrade() leaves it as it is.
  - AGENTS.md is your own file and CLAUDE.md holds Framework's guide, so both were kept and CLAUDE.md stays canonical. To switch, move your notes into CLAUDE.md, rename it AGENTS.md, and run upgrade() again.
  - This project has no Framework skills. framework::ai_skills_update() installs the ones for its type (project).
  - notebooks/_quarto.yml makes notebooks/ a separate Quarto project and was kept. quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.
  - docs/_quarto.yml makes docs/ a separate Quarto project and was kept. quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.
Dry run: nothing was changed. Apply with framework::upgrade("a2cps-ehr-omop", dry_run = FALSE); every file it rewrites is backed up to .framework/backups/ first.
```

### data-visualization-fundamentals

```
Upgrade plan for /tmp/fwfix3/adopt-tests/run/data-visualization-fundamentals
  settings    settings.yml                       add tools (quarto: true, renv: false); add security (sensitive: false)
  gitignore   .gitignore                         add 3 rule(s): **/logs/**, slurm-*.out, .quarto_backups/
  ai          AGENTS.md                          regenerate marked sections (environment, packages, data)
  skills      .claude/skills/framework-workflow  update (an unedited older version)
  skills      .claude/skills/framework-data      update (an unedited older version)
  skills      .claude/skills/framework-packages  update (an unedited older version)
  skills      .claude/skills/framework-outputs   update (an unedited older version)
  skills      .claude/skills/ggplot2-exploring   add
  skills      .claude/skills/ggplot2-publishing  add
  spec        .framework/spec.json               create from the settings
Dry run: nothing was changed. Apply with framework::upgrade("data-visualization-fundamentals", dry_run = FALSE); every file it rewrites is backed up to .framework/backups/ first.
```

### peanuts

```
Upgrade plan for /tmp/fwfix3/adopt-tests/run/peanuts
  settings    settings.yml              add tools (quarto: true, renv: false); add security (sensitive: false)
  connections settings/connections.yml  rewrite in the current layout: 0 database(s)
  gitignore   .gitignore                add 5 rule(s): **/logs/**, slurm-*.out, /.quarto/, **/*.quarto_ipynb, .quarto_backups/
  ai          AGENTS.md                 create from CLAUDE.md (AGENTS.md becomes the canonical file)
  ai          CLAUDE.md                 replace with a pointer to AGENTS.md
  ai          settings/ai.yml           set ai.canonical_file: AGENTS.md
  ai          AGENTS.md                 regenerate marked sections (environment, packages, data, functions)
  spec        .framework/spec.json      create from the settings
Notes:
  - This project has no Framework skills. framework::ai_skills_update() installs the ones for its type (project).
  - notebooks/_quarto.yml makes notebooks/ a separate Quarto project and was kept. quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.
  - docs/_quarto.yml makes docs/ a separate Quarto project and was kept. quarto_regenerate(overwrite = TRUE) folds it into the root _quarto.yml.
Dry run: nothing was changed. Apply with framework::upgrade("peanuts", dry_run = FALSE); every file it rewrites is backed up to .framework/backups/ first.
```

### cannabis-ehr

`upgrade()` on the copy stops: "Not a Framework project (no settings.yml or Framework config.yml): .../cannabis-ehr. To make it one, use framework::adopt()." Then `adopt("cannabis-ehr", yes = TRUE, cloud = FALSE)` and the dry run after it:

```
Proposed mapping (type: project):
   1. scripts                        scripts
   2. notebooks                      notebooks
   3. outputs/reports                outputs_reports
   4. docs                           docs
   5. hades                          (other folder)
   6. legacy                         (other folder)
   7. outputs/notebookInputs         (other folder)
   8. tidy                           (other folder)
  Created: settings.yml
  Added to .gitignore (56 rules): **/private/**, **/*_private/**, .env, .env.local, .env.*.local, .httr-oauth, and 50 more
  Created: .framework/spec.json

[ok] cannabis-ehr is a Framework project. Run framework::scaffold() in it to start.
=== upgrade dry run after adopt
Upgrade plan for /tmp/fwfix3/adopt-tests/run/cannabis-ehr
  Nothing to change: the project is up to date.
```

### After applying

`upgrade(dry_run = FALSE)` on each copy, then a second dry run, which planned
no actions in all four. Checks on the result:

- Nothing user-owned was lost. Every changed file was diffed against the
  pristine copy. `.gitignore` and `settings.yml` lost no line. Every line of
  CLAUDE.md and AGENTS.md outside the marked sections is still in the
  canonical file. The connection files were rewritten into the new layout
  with the same entries (a2cps: `framework` and `omop`, password unchanged),
  and the originals are in `.framework/backups/<timestamp>/`, which git
  doesn't list.
- a2cps-ehr-omop: `default_database` now resolves to `framework` (it was
  NULL), `connections_list()` lists both connections, and spec.json records
  the password as `env("OMOP_PASSWORD")`.
- data-visualization-fundamentals: `_quarto.yml` is byte-identical after
  `upgrade()` and after `quarto_regenerate()`. Its four pre-lockfile skills
  matched a shipped version (6f2521a) and were updated.
- syphillis-poc-test-analysis: `.fw_project_is_sensitive()` is TRUE,
  `security: sensitive: true` is written, and `.claude/settings.json` denies
  `inputs/private`.
- peanuts: `git_security_audit()` fails `git_history` with 10 findings, all
  "inputs folder" (`inputs/intermediate/peanuts_synthetic_*.csv` and
  `inputs/raw/*.xlsx`).
- cannabis-ehr: after `adopt()`, the audit's orphaned-file check passes (it
  reported 26 cohort JSONs before), and `cloud_register(dry_run = TRUE)`
  prints one request: `POST /api/v1/projects` with the spec, `name` and
  `slug` `cannabis-ehr`, and `adopted: true`.
- syphillis-poc-test-analysis after cd7e2c4: the plan adds
  `.claude/skills/framework-sensitive-data`, and a second run plans nothing.
- Fresh projects made by this version plan only the new `.quarto_backups/`
  rule.


## Shared rules framework-py must mirror

### Sensitive detection

`.fw_settings_sensitive(settings)` (Python: `_private.settings_sensitive()`):

1. `project_type: project_sensitive` is sensitive, whatever `security:` says.
2. Otherwise `security.sensitive`, when the key is present, decides.
3. Otherwise a directory key matching `^(inputs|outputs)_private_` makes the
   project sensitive.

Every check that read `security.sensitive` goes through it: private-read
notes, publish confirmations, public-save warnings, the split output folders,
the audit's publishing check, the AGENTS.md type section, and `data_save()`'s
identifier warning. `bootstrap()` warns and `status()` reports when the type is
`project_sensitive` and `security.sensitive` is missing or false. Python's
`_paths.py:56-58`, `ai.py:53,115`, and `_agents_md.py:157` need the same.

### Framework config.yml

A `config.yml` makes a folder a project only when its `default:` section (or
the top level, when there is no `default:`) has `project_type`,
`project_name`, or `directories`, or an `options:` map with `results`,
`framework_db`, or a key ending in `_dir`, or a `packages:` list whose items
have `auto_attach`. `settings.yml` and `settings.yaml` always count. Python's
`adopt.py:240` existing-project check should use the same rule and add
`settings.yaml` (B22).

### adopt()

```
adopt(path = ".", yes = FALSE, sensitive = NULL, type = NULL, cloud = NULL)
```

- `sensitive = TRUE` sets `security.sensitive: true` without asking.
  `type = "project_sensitive"` implies it; with `sensitive = FALSE` it is an
  error. `NULL` asks in an interactive review when folders look private.
  Without it, a non-interactive adopt with private-looking folders says how to
  turn it on (`sensitive = TRUE`, `fw adopt --sensitive`).
- `type` is one of `project`, `project_sensitive`, `course`, `presentation`,
  or `bare`. `NULL` infers it (below).
- `cloud = TRUE` calls `cloud_register()` after adopting. `NULL` asks when
  interactive and signed in. Declining offers to save the layout as a
  structure, as before.
- Returns `type`, `directories`, and `extra_directories`.
- A folder with no subfolders is adopted with empty `directories` (B20).
- An existing project stops with a message that names `upgrade()`.

The adopted spec, which both languages must write the same way:

- `type`: the given or inferred type. `core_files: false`,
  `settings_layout: flat`, `tools: {quarto: false, renv: false}`.
- `directories`, `extra_directories`, and `render_dirs`: exactly the mapping.
  The type's built-in folders and render folders are not merged in.
- `git.use_git`: true when `.git` exists (folder, or file in a worktree).
- `ai.enabled: false`, no skills, no default packages.
- `security.sensitive`: true for `sensitive = TRUE` or `project_sensitive`.
- `source: {origin, adopted: true, framework_version}`.
- `git.gitignore_content`: the project's `.gitignore` after the merge.

### Shared mapping rules (inst/adopt/rules.json)

fw and framework-py copy this file. New fields:

- `skip` entries may contain `*`, which matches any characters within one
  folder name. Added: `settings`, `_site`, `_book`, `*_files`, `*_cache`.
- Rules may have `types`, like `languages`. A rule applies only when the type
  from step 2 below is in its list.
- `types.course`: `signals` (top-level folder names) and `min` (2).
  `types.project_sensitive.key_pattern`: `^(inputs|outputs)_(private|public)_`.
- `render_dirs`: rules that map rendered-notebook folders
  (`outputs/notebooks`, `outputs/docs`) to `render_dirs` keys.
- New keys: `inputs_{private,public}_{raw,intermediate,final}` and
  `outputs_{private,public}_{notebooks,tables,figures,models,reports}`, plus
  course keys `data`, `slides`, `assignments`, `course_docs`, `readings`, and
  `notebooks` (from `modules`), which apply to courses only.

Algorithm changes, also written in `inst/conformance/README.md` (adopt/):

1. Type first: `course` when at least `min` of the course signals are
   top-level folders, ignoring case. A given type replaces this.
2. A rule whose key already has a folder is skipped.
3. A folder inside an assigned folder is never assigned a key of its own (so
   a course's `data/` covers `data/raw/`).
4. `render_dirs` rules run after the directory rules, the same way.
5. Inferred type: `course`; else `project_sensitive` when a key matching the
   pattern has a folder; else `project` when any key has a folder; else
   `bare`.
6. Scanners never follow symbolic links (B27).
7. An extra directory key set by hand in the review is numbered like the
   scanner's (`_2`, `_3`) when taken (B26).

Each case's `expected` now has `type` and `render_dirs`. New cases:
`generated-folders`, `sensitive-layout`, `course`, and `course-one-signal`.
`private-paths` changed: `data/Private/raw` is now `inputs_private_raw`, and
the type is `project_sensitive`. `data-raw/conformance.R` generates them.

### .gitignore merge

Shared by `adopt()` and `upgrade()` (`R/gitignore_merge.R`; Python:
`_gitignore.missing_rules()` and `append_rules()`):

- A rule is a non-blank, non-comment line, trimmed. Rules compare exactly
  after trimming, so `/.quarto/` and `.quarto/` differ.
- Missing rules are appended in one block under a header comment
  (`# Added by framework::adopt()` or `# Added by framework::upgrade()`),
  after a blank line. No line is removed, reordered, or rewritten.
- In a git work tree, a rule that would ignore a tracked file
  (`git ls-files --cached --ignored --exclude=<rule>` lists something) is left
  out and reported with one such file. Negations are never left out.
- The rules wanted: the type's template (`gitignore-sensitive` when
  sensitive). `adopt()` adds `/<folder>/` for each folder that looks private.
  `upgrade()` adds `/<folder>/` for each settings folder whose key contains
  `private` (not `public`) and each folder publishing destination. A folder is
  added only when no folder part is named `private` or ends in `_private`
  (the templates' `**/private/**` covers those) and `.gitignore` doesn't
  already ignore it.
- All four templates now include `.quarto_backups/`. framework-py's templates
  and its create fixtures need the same line; R's `create/r/` fixtures were
  regenerated.

### Backups

Files Framework rewrites are copied to `.framework/backups/<YYYYmmdd-HHMMSS>/`
with their paths from the root (a `-2` suffix when the folder exists).
`.framework/.gitignore` gets `backups/`, as it already gets
`skills-backups/`. Nothing is added to the project's `.gitignore` for it.

### cloud_register()

```
cloud_register(path = ".", name = NULL, slug = NULL, description = NULL,
               dry_run = FALSE, include_private = FALSE)
```

This matches `fw project link --create` at framework-cli 0832476 and the
framework-cloud create-from-spec API (ef3224d).

Order of checks:

1. A Framework project, else stop (run `adopt()`).
2. `FW_PROJECT_TOKEN` already in `.env`: message "This project is already
   linked: .env has FW_PROJECT_TOKEN. Nothing changed. To send its spec, run:
   fw project push-spec" and return with `created: false, linked: true`.
3. `.framework/spec.json` exists (else: run `upgrade(path, dry_run = FALSE)`),
   and is valid JSON.
4. Git doesn't track `.env`. The path has no folder named `private` or
   `*_private` (ask when interactive, else stop, unless `include_private`).
5. Name: the argument, the spec's `name`, then the folder name. Slug: the
   argument, or the name lowercased with each run of characters other than
   `a-z0-9` turned into `-` and leading or trailing `-` removed. It must match
   `^[a-z0-9]+(-[a-z0-9]+)*$`.

One request with the user token, `POST /api/v1/projects`, body built as text
so the spec goes as it is on disk (empty maps stay `{}`):

```
{"spec": <spec.json bytes>, "name": "...", "slug": "...",
 "description": "..." (when given), "adopted": true (when spec.source.adopted)}
```

No `project_type`, no structure first, no separate spec push. The server
stores the spec as the project's only layer and its last-received spec. The
response is `{slug, name, language, type, adopted, url, token, github: null}`.
Then: message "Created <slug> on <host>: <url>", and write `FW_PROJECT_TOKEN`
(the response's pull token) and `FW_CLOUD_URL` to `.env`, after making git
ignore `.env`. If writing fails: "Created <slug> on <host>, but linking this
folder failed: ... To finish, run: fw project link --from <slug>".

Errors on `slug` (HTTP 422 with `errors.slug`, first message):

- Contains "deleted": stop with "<slug> is the slug of a project in your
  Trash on <host>, so it can't be used again. Restore that project and run fw
  project link --from <slug>, or pass slug = with another name."
- Contains "already have": in an interactive session, ask "You already have a
  project <slug> on <host>. Link this folder to it instead?". Yes mints a
  token with `POST /api/v1/projects/<slug>/pull-tokens` `{name: "framework
  (R) on <host name>"}`, writes it with the server to `.env`, and says "To
  send this folder's spec to it, run: fw project push-spec". Otherwise stop
  with "You already have a project <slug> on <host>. To link this folder to it,
  run fw project link --from <slug>. To create a new project, pass slug = with
  another name."
- Anything else: stop with "<host> refused the slug <slug>: <message>".

A server from before the spec API answers without `type`. Then warn "<host>
is older than the spec API, so it made the project from your defaults at
<slug>. ...", link as above, and send `PUT /api/v1/project/spec {spec}` with
the new project token.

The result is `{slug, url, type, adopted, created, linked, spec_changed}`.
`dry_run = TRUE` prints the request (with the spec elided) and sends nothing.
Registration from `new()` now writes the token for every type, `bare`
included. framework-py's `adopt.py:298-310` offer, which sends
`structure: framework/bare` (B25), should call this.

### upgrade()

```
upgrade(path = ".", dry_run = TRUE, backup = TRUE)
```

The plan is computed against the files on disk plus the writes planned by
earlier steps, so later steps see earlier ones. Steps run in this order:

1. **Settings file.** A Framework `config.yml` without `settings.yml` is
   copied to `settings.yml` and removed.
2. **Settings.** In `default:` (or the top level of a flat file), add
   `tools: {quarto, renv}` when missing (`quarto` when `_quarto.yml` exists or
   there are `render_dirs`, `renv` when `renv.lock` exists or
   `packages.use_renv`). Add `security: {sensitive}` when missing, with the
   sensitive rule above. Edits replace only that block of lines and keep
   comments. Keys outside `default:` are reported.
3. **Connections.** Old layouts: a top-level `options`, `databases`,
   `storage_buckets`, `default_database`, or `default_storage_bucket` key in
   the connections file, or entries under `connections:` other than the four
   current keys. The result: `connections: {default_database,
   default_storage_bucket?, databases, storage_buckets}`.
   `default_database` comes from `connections.default_database`, the
   top-level key, `options.default_connection`, or `options.default_database`,
   the first non-empty. Entries with `driver: s3` or a `bucket` go to
   `storage_buckets`, others to `databases`. `!expr` tags are kept. Literal
   secrets are reported by key path and left in place.
4. **.gitignore.** The merge above.
5. **AI files** (only with `ai.enabled`). When CLAUDE.md is a full guide
   (has `<!-- @framework:regenerate -->` markers and isn't a pointer of at
   most 10 lines with `@AGENTS.md`): with no AGENTS.md, or a marked AGENTS.md
   while settings say CLAUDE.md is canonical, AGENTS.md gets CLAUDE.md's
   content; with a marked AGENTS.md otherwise, it stays. CLAUDE.md becomes
   `@AGENTS.md`. With an unmarked (hand-written) AGENTS.md, both are kept and
   CLAUDE.md stays canonical. `ai.canonical_file` is set to match. The marked
   sections of the canonical file are regenerated; a change in blank lines
   alone is not written. Sensitive projects with the `claude` assistant get the
   `.claude/settings.json` deny and sandbox rules for each folder up to its
   `private` part, and `.env`.
6. **Skills** (only with `ai.enabled`). When the assistants' skills folder
   holds any skill other than `framework-sensitive-data`, each skill for the
   type is created when missing, updated when it is an unedited older
   version, and listed when edited. Otherwise a sensitive project gets
   `framework-sensitive-data` only, in the assistants' skills folder
   (`.claude/skills` when no assistant is set), and other projects get a note
   pointing to `ai_skills_update()`.
7. **Quarto** (when `_quarto.yml` exists, or there are `render_dirs` and
   Quarto isn't off). As `quarto_regenerate()` without `overwrite`.
8. **Spec.** Built from the settings as written: a `spec_resolve()` of the
   type with `core_files: true`, `settings_layout` (`split` when `settings/`
   exists), `tools`, `security`, `git.use_git`, and `ai`, then the settings'
   `directories`, `extra_directories`, `render_dirs`, packages, connections,
   `scaffold`, `quarto`, and author replace the defaults. Package skills
   present (or planned) are listed. `env` and `files` are empty.
   `git.gitignore_content` is the planned `.gitignore`.
   `source: {origin: "r", upgraded_from: "<detected>"}` with
   `framework <version>`, `framework 1.x (config.yml)`, or
   `framework before 2.0 (no spec.json)`. A literal secret in a connection
   becomes `env("<CONNECTION>_<KEY>")`, upper case with other characters as
   `_`. A missing spec is written whole. An existing spec has only `name`,
   `type`, `tools`, `directories`, `extra_directories`, `render_dirs`,
   `security`, and `connections` refreshed, and only when they differ.
   `spec_check()` must pass, or the spec is skipped with a note.

Output: one line per action, `step`, `path`, and `change`, then `Notes:`.
The return value has `actions` (data frame), `notes`, `applied`, and
`backup_location`. Applying writes every planned file after backing it up,
then installs the planned skills (which back themselves up to
`.framework/skills-backups/`). A second run plans nothing.

### Skill version detection

`inst/templates/skill-history.json`:

```json
{"description": "...", "skills": {"framework-data": ["<sha256>", ...], ...}}
```

Each list holds the SHA-256 of every `SKILL.md` the package has shipped for
that skill, from git history plus the current file. `data-raw/skill_history.R`
builds it; run it before each release. A skill folder with no
`skills.lock.json` entry whose only file is `SKILL.md`, and whose SHA-256
(as stored, or with CRLF turned into LF) is in the list, is an unedited
release: install the current version over it (backed up) and record it in the
lock. framework-py should ship the same file, or one generated from its own
history, and use the same rule in `ai_skills_update()`.

### quarto_regenerate()

```
quarto_regenerate(project_path, backup = TRUE, overwrite = FALSE, dry_run = FALSE)
```

Without `overwrite`: create missing files; in an existing file, add only
missing `project:`, `project.type`, `project.output-dir`, or a `format:`
when there is none, keeping every other line. While per-folder `_quarto.yml`
files from older projects remain, existing files are not changed at all. With
`overwrite`: replace the files, and with `backup` also remove the per-folder
files. `backup = FALSE` never removes a file. Backups go to
`.framework/backups/`. The result lists `regenerated`, `unchanged`, `kept`,
`removed`, and `backed_up`.

### Security audit

- History (`git_history_issues`, new `reason` column): read every
  `--name-status` line (`A`, `M`, `D`, `T`, `R<n>`, `C<n>`; a rename or copy
  counts for its new path). A data file by extension is flagged with reason
  `private folder` (under a private settings folder, or `private`, `secret`,
  or `confidential` in its path), `inputs folder` (under an `inputs_*` folder,
  or a folder named `inputs` or `input`), or `identifier columns: ...` (the
  header of its last added or modified blob, read through a temporary file of
  at most 50 MB, for csv, tsv, txt, parquet, dta, and sav). Any finding fails
  the check.
- Orphaned files: every settings folder (`directories`,
  `extra_directories`, and `render_dirs`) counts as known; hidden folders and
  `renv`, `packrat`, `node_modules`, `_site`, `_freeze`, `*_cache`, and
  `*_files` are skipped; the default extensions leave out `json`, `txt`, and
  `xml` (passing `extensions` scans exactly those given). The printed summary
  groups orphans by folder. framework-py should also skip all hidden folders
  (B16).

## framework-py items outside the shared rules

- B22: detect the language as fw does before writing `language: python`,
  and refuse a mismatch unless forced.
- B23: print the mapping on stderr with `yes=True`.
- B24: the adopted spec above (R now sets `git.use_git` from `.git`, and both
  keep `adopted: true`).
- B25: replace the registration offer with `cloud_register()`.
- B1: the sensitive rule in every Python check.
