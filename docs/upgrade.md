# Adopting, upgrading, and linking projects

Framework has three tools for projects that already exist. Each does one job.

| Situation | Tool | Changes |
|---|---|---|
| A folder that has never used Framework | `adopt()` | Writes `settings.yml` and `.framework/spec.json`, and appends `.gitignore` rules |
| A project made by an older Framework | `upgrade()` | Brings settings, spec, `.gitignore`, AI files, skills, and Quarto files to the current layout |
| Either of the above, once it has a spec | `cloud_register()` | Creates the Framework Cloud project, links the folder, and sends the spec |

None of them moves, renames, or deletes your code, data, notebooks, or notes.

## Adopt

`adopt()` maps the folders you already have to Framework directories. It
reads folder names only, never file names or contents.

```r
framework::adopt("~/projects/cohort-study")                  # review the mapping
framework::adopt(yes = TRUE)                                 # accept it as proposed
framework::adopt(yes = TRUE, sensitive = TRUE)               # the project holds sensitive data
framework::adopt(yes = TRUE, type = "course")                # choose the type
framework::adopt(yes = TRUE, cloud = TRUE)                   # register and link it too
```

The type follows from the folders unless you pass `type`:

- `course` when the folder has at least two course folders (`slides/`,
  `modules/`, `assignments/`, `readings/`, and similar).
- `project_sensitive` when the private and public layout is present
  (`inputs/private/raw/`, `outputs/public/figures/`).
- `project` when any folder maps to a Framework directory.
- `bare` otherwise.

Framework's `settings/` folder and Quarto's `*_files/` and `*_cache/` folders
are never proposed. `outputs/notebooks/` becomes a render folder. A folder with
no subfolders, such as one `analysis.qmd`, is adopted with no folders.

`adopt()` appends the rules of the type's `.gitignore` template that your
`.gitignore` lacks, under `# Added by framework::adopt()`. It never removes a
line. A rule that would ignore a file git already tracks is left out and
reported. The spec records the resulting `.gitignore`.

`adopt()` refuses a folder that is already a Framework project. A `config.yml`
counts only when it has Framework keys, so a project's own `config.yml` (the
config package's, or a pipeline's) does not block it.

## Upgrade

`upgrade()` is for projects made by Framework 1.x or early 2.0. It prints a
plan by default and changes nothing.

```r
framework::upgrade("~/projects/old-study")                   # the plan
framework::upgrade("~/projects/old-study", dry_run = FALSE)  # apply it
```

Applying the plan copies every file it rewrites to
`.framework/backups/<timestamp>/` first. `.framework/.gitignore` ignores that
folder. Running `upgrade()` again after applying it changes nothing.

The plan covers these parts of a project:

- **Settings.** A 1.x `config.yml` becomes `settings.yml`. Missing `tools:`
  and `security:` sections are added. A `project_sensitive` project, or one
  with `inputs_private_*` or `outputs_private_*` folders, gets
  `security: sensitive: true`. Edits keep the file's comments.
- **Connections.** The old layouts (`options: default_connection:` with
  connections listed flat, or the empty hybrid with `options: []`) become
  `connections:` with `default_database`, `databases`, and `storage_buckets`.
- **Spec.** `.framework/spec.json` is written from the settings when it is
  missing. When it exists, the sections the settings decide (name, type,
  folders, tools, security, and connections) are refreshed and the rest is
  kept. A password written into the settings appears in the spec as
  `env("<CONNECTION>_PASSWORD")`.
- **.gitignore.** Missing rules from the current template are appended under
  `# Added by framework::upgrade()`. These include Quarto's `/.quarto/` and
  `**/*.quarto_ipynb` lines, `framework.db`, and folder publishing
  destinations. No line is removed.
- **AI files.** When CLAUDE.md holds the full Framework guide, its content
  moves to AGENTS.md and CLAUDE.md becomes `@AGENTS.md`. The marked sections
  are regenerated. A hand-written AGENTS.md is kept and reported. Sensitive
  projects get the Claude Code rules that keep agents out of private folders.
- **Skills.** A Framework skill whose `SKILL.md` matches any version the
  package has shipped is updated, and missing skills for the type are added
  to a project that already has a skills folder. Edited skills are kept.
- **Quarto.** Missing Quarto files are created. An existing `_quarto.yml` at
  most gains missing keys, and not while per-folder `_quarto.yml` files
  remain. Custom themes, `execute:` options, and comments stay.

Some things are reported and left for you to change:

- Keys outside `default:` in `settings.yml`, which Framework ignores.
- Passwords and tokens written into the settings (named by key, never shown).
- Skills with local edits.
- Per-folder `_quarto.yml` files. `quarto_regenerate(overwrite = TRUE)` folds
  them into the root configuration, after a backup.

## Link to Framework Cloud

A project created on the website or with `fw new --cloud` is linked from the
start. A local project needs `cloud_register()`, which requires
`.framework/spec.json`, so run `adopt()` or `upgrade()` first.

```r
framework::cloud_register("~/projects/old-study", dry_run = TRUE)  # print the requests
framework::cloud_register("~/projects/old-study")
```

`cloud_register()` makes these requests:

1. `POST /api/v1/structures`, when the folders differ from the type's
   built-in layout. The structure holds the folder mapping.
2. `POST /api/v1/projects`, with the name, language, structure, tools, and
   settings, marked `adopted: true`.
3. `PUT /api/v1/project/spec`, with the new project token, after the token
   and server are written to `.env` as `FW_PROJECT_TOKEN` and `FW_CLOUD_URL`.

It refuses a project that already has a token in `.env` and a project whose
`.env` git tracks. It asks before registering a project inside a folder named
`private`. When a step after creating the project fails, it prints the
project's slug and the commands that finish linking
(`fw project link --from SLUG` and `fw project push-spec`).

## Typical sequences

An existing analysis folder:

```r
framework::adopt("~/projects/cohort-study", yes = TRUE, sensitive = TRUE)
framework::cloud_register("~/projects/cohort-study")
```

A project made by Framework 1.x:

```r
framework::upgrade("~/projects/old-study")
framework::upgrade("~/projects/old-study", dry_run = FALSE)
framework::cloud_register("~/projects/old-study")
```

Commit the changes after reviewing them with `git diff`.
