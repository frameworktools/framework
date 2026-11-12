# framework 2.0.5

One call syncs everything with Framework Cloud: `pull_all()` and
`push_all()` replace `pull_setup()` and `push_setup()` and cover packages,
skills, and the data registry. Matches framework-py 0.1.0.dev19 and fw
0.6.0.

Behavior changes:

* `pull_all()` and `push_all()` replace `pull_setup()` and `push_setup()`,
  and sync everything at once: packages, skills, and the data registry.
  `pull_all()` lists every change, grouped by part (Packages, Skills, Data
  registry), asks `Apply these changes? [y/n]` once, and applies each part.
  `push_all()` previews each part with Cloud, lists the changes with what
  each affects, asks `Push these changes? [y/n]` once, and pushes the
  package list, edited tracked skills, and the data registry. Local edits
  win unless `overwrite = TRUE`; entries only on Cloud stay unless
  `remove = TRUE`. A part that changed on Cloud since the last pull stops
  with "Pull first: pull_all()" unless `force = TRUE`. When one part fails,
  the others still apply, and the error names which parts were applied and
  which weren't. Edited skills need `cloud_login()` only when there are
  some. Without a console, both need `confirm = TRUE` or `dry_run = TRUE`.
  `pull_skills()` / `push_skills()` and `pull_data_registry()` /
  `push_data_registry()` still sync one part. Lock files are unchanged.
  Matches framework-py's `pull_all()` / `push_all()` and `fw pull` /
  `fw push`.

Fixes:

* `pull_data_registry()` adds an entry whose top group isn't in the data
  section yet, as in a new project's empty `data: []`, instead of failing
  with "node stack overflow".

# framework 2.0.4

Data registry sync with Framework Cloud: `pull_data_registry()` and
`push_data_registry()` keep a project's data catalog in step with Cloud, and
specs and layers take a `data` section. Matches framework-py 0.1.0.dev18 and
fw 0.5.1.

New features:

* `pull_data_registry()` and `push_data_registry()` keep a project's data
  registry, the catalog in the settings' `data` section, in step with
  Framework Cloud. Only definitions move: names, paths, types, delimiters,
  the locked and private flags, descriptions, and Stata names. Data files
  never do, and file hashes stay in framework.db. `pull_data_registry()`
  reads `GET /api/v1/projects/data` with the project token, lists entries to
  add, entries that differ (naming the fields that differ), and entries only
  in the project, then asks `Apply these changes? [y/n]`. It writes the new
  entries into the data section, inline or in its split file, editing only
  the fields that change, so comments in the data section stay. Local
  entries are never removed, and local definitions win unless
  `overwrite = TRUE`. `push_data_registry()` previews through
  `POST /api/v1/projects/data` with `dry_run` and asks
  `Push these changes? [y/n]`. Entries only on Cloud stay unless
  `remove = TRUE`. A stale revision in `.framework/data.lock.json` stops it
  with "Pull first" unless `force = TRUE`. Both need `confirm = TRUE` or
  `dry_run = TRUE` without a console. Matches framework-py's functions and
  `fw data pull` / `fw data push`.

* Specs and layers take a `data` section: dot-notation catalog names mapped
  to entries (`path`, and optionally `type`, `delimiter`, `locked`,
  `private`, `description`, and `stata_names`). Each entry is replaced whole
  when a later layer sets it, and `null` removes it. Project creation writes
  the entries nested into the settings' data catalog. `spec_check()`
  refuses paths outside the project, unknown types and fields, and a name
  that is also a group of other names.

# framework 2.0.3

Project setup sync with Framework Cloud: pull and push a project's skills,
and its packages and skills together. Matches framework-py 0.1.0.dev16 and
fw 0.5.0.

New features:

* `pull_skills()` brings a project's skills up to date with its setup on
  Framework Cloud. It reads the project's current skill list with its project
  token (`GET /api/v1/projects/pull`), so changes made with Edit project
  arrive. Missing skills are added. Unedited skills get their latest
  versions: Framework's from the package, and Cloud skills from Cloud (the
  latest Cloud versions need `cloud_login()`; otherwise the setup's versions
  are used). Locally edited skills are kept and listed;
  `overwrite = TRUE` replaces them, after backing them up to
  `.framework/skills-backups/`. Skills no longer in the setup are listed,
  never deleted. The Skills table in `AGENTS.md` is refreshed. It prints
  `Skills: 2 added, 3 updated, 5 up to date, 1 locally edited (kept)` and
  returns the result as a list. Offline, or without a project token, it uses
  the package skills for the project's type and says so. `dry_run = TRUE`
  writes nothing. Matches framework-py's `pull_skills()` and
  `fw skills pull`.
* `push_skills()` sends locally edited skills to Cloud as new versions of
  your own skills, through `skills_sync()`. It warns what each new version
  replaces and asks `Continue? [y/n]`; without a console it needs
  `confirm = TRUE`. A skill that changed on Cloud since the last pull is
  refused with "Pull first" unless `force = TRUE`. Edited built-in skills are
  saved as your own copy. Matches framework-py's `push_skills()` and
  `fw skills push`.
* `pull_setup()` and `push_setup()` keep a project's setup, its packages
  and skills, in step with Framework Cloud. `pull_setup()` reads
  `GET /api/v1/projects/setup` with the project token, lists packages to
  add, packages whose settings differ, packages only in the project, and
  skills to add, update, or keep, then asks `Apply these changes? [y/n]`.
  It adds and installs the new packages (with renv when the project uses
  it) and runs `pull_skills()`. Local packages are never removed, and local
  settings win unless `overwrite = TRUE`. `push_setup()` previews its change
  through `POST /api/v1/projects/setup/packages` with `dry_run`, warns that
  new setups, zips, and Update on GitHub will use it, and asks
  `Push these changes? [y/n]`. Packages only on Cloud stay unless
  `remove = TRUE`. When Cloud's setup changed since the revision in
  `.framework/setup.lock.json`, it stops with "Pull first" unless
  `force = TRUE`. It then runs `push_skills()`. Both need `confirm = TRUE`
  or `dry_run = TRUE` without a console. Matches framework-py's functions
  and `fw setup pull` / `fw setup push`.

Behavior changes:

* `ai_skills_update()` is now `pull_skills()`: it uses the project's Cloud
  setup when it can, installs into the assistants' skills folders, and
  returns `pull_skills()`'s list instead of a character vector with a
  `status` attribute.

Fixes:

* `push_skills()` saves an edited built-in skill that Cloud never published
  as a new skill of your own, instead of failing.
* Signed out, `pull_skills()` keeps a newer version that `push_skills()`
  pushed, instead of replacing it with the setup's older one.
* `pull_setup()` and `push_setup()` explain a refused project token (check
  `FW_PROJECT_TOKEN` in `.env`) and a setup Cloud refuses (422), and change
  nothing.
* `pull_setup()` reports a pinned package version that fails to install,
  instead of counting the older installed version as up to date.
* Run through `fw setup push`, the "Pull first" advice names
  `fw setup pull` and `--force` (fw 0.5.0).

# framework 2.0.2

Fixes and features from adopting and upgrading real projects, and an explicit
location for new projects. Matches framework-py 0.1.0.dev15 and fw 0.4.9.

Behavior changes:

* The location of a new project is always explicit. `setup("fw_...")`,
  `new_project(key = ...)`, and `new_project()` no longer suggest
  `~/projects/<name>`, and `setup()` no longer creates the project there
  silently when not interactive. With no `location`, an interactive session
  shows the folder it would create in the current directory and asks
  `Create the project here (<path>)? [y/n]`. Enter or `y` uses it. `n` asks
  `Where should the project go? Leave blank to use the current directory
  (<dir>): `; the project folder goes inside the folder typed, unless that
  path already ends in the project's name. With a Projects folder set in
  Framework Cloud Settings (`defaults.projects_dir` in your settings), the
  offer is a folder there instead: `Create the project in <path>? [y/n]`,
  creating the Projects folder if needed. `setup("fw_...")` and
  `new(key = ...)` first use the project owner's Projects folder, which
  Framework Cloud sends with the project. A non-interactive session stops
  and asks for `location =`; it never uses the Projects folder. Both print
  the absolute path before creating the project and `Project ready at <path>`
  after.
* The check before publishing matches folder names, not file names: a path
  is private when one of its folders is named `private` or ends in
  `_private`, as the `.gitignore` templates ignore, or when it is under a
  settings folder whose key contains `private` and not `public`
  (`outputs_private_tables`). File names such as
  `01-private-and-public-data.qmd` no longer count, nor do folders named only
  like confidential or sensitive. The warning says "file(s) to upload are in
  private folders". A notebook reads private data only when its code quotes
  a path with a private folder or a catalog name whose entry is private, not
  a settings key or a string such as `"private|public"`.
* `quarto_regenerate()` no longer replaces your Quarto configuration. By
  default it creates missing files and, in an existing file, adds only the
  keys Framework needs that it lacks (`project:`, `type:`, `output-dir:`, or a
  `format:` when there is none), keeping your theme, `execute:`, and comments.
  Per-folder `_quarto.yml` files from older projects are kept and listed.
  `overwrite = TRUE` replaces the files and, with backups on, removes the
  per-folder files; with `backup = FALSE` it never removes a file (it used to
  delete them even then). Backups go to `.framework/backups/<timestamp>/`,
  which git ignores, instead of `.quarto_backups/`, and `dry_run = TRUE`
  reports what would change. The `.gitignore` templates ignore
  `.quarto_backups/` for backups made by earlier versions.
* `db_connect()` and `db_query()`'s `read_only = TRUE` opens a SQLite or
  DuckDB file read-only for one call. A call can add read-only but never
  remove it: `read_only = FALSE` on a connection with `read_only: true` in its
  settings is an error. A job that rebuilds such a database uses a second
  connection entry for the same file.
* In `cache_remember()` and `cache()`'s `depends_on` list, a named element is
  a value, so `list("inputs.final.bp_long", formula = f)` tracks the data and
  the formula. The out-of-date message names what changed:
  "inputs.final.bp_long and formula changed", or "dependency 3 (a value)
  changed" for a value without a name.

Sensitive data:

* Projects with `project_type: project_sensitive` count as sensitive even
  without a `security:` block, as projects made before Framework 2 have. The
  type wins over `security: sensitive: false`. Without a `security:` block, an
  `inputs_private_*` or `outputs_private_*` folder also counts. `bootstrap()`
  warns and `status()` says so when the type and the setting disagree;
  `upgrade()` adds the block.
* `git_security_audit()`'s history check fails on data files (by extension:
  csv, rds, xlsx, and the rest) committed outside private folders when they
  sit in an inputs folder (configured, or a folder named `inputs`) or their
  header has identifier-like columns. It reads renames and copies too, and a
  new `reason` column says why each file is listed. Patient CSVs committed
  under `inputs/intermediate` in a standard project passed before.
* `git_security_audit()`'s orphaned-file check counts every folder in the
  settings as known, `extra_directories` and `render_dirs` included, skips
  hidden folders, and by default leaves out `.json`, `.txt`, and `.xml` files
  (cohort definitions, manifests, schemas); pass `extensions` to scan them.
  The summary lists orphans by folder. Adopted and course projects went from
  26 to 807 warnings to a useful few.

Fixes:

* `show_table()` with `digits` keeps no decimals in a column of whole numbers
  stored as doubles, such as counts (`12`, not `12.0`).
* A `layout: site-root` folder counts versions per slug: publishing another
  slug there replaces the site, starts again at version 1, and the message
  names the slug it replaced. It never writes a notebook source (`.qmd`,
  `.Rmd`, `.ipynb`), only rendered output.
* `publish_notebook()` publishes only the rendered page: the HTML and its
  own `_files` folder, or the HTML alone for a self-contained render. It no
  longer copies folders such as `outputs/` that Quarto mirrors into the
  render folder.
* `db_execute()`, `db_transaction()`, `db_execute_file()`, and
  `db_copy_from()` refuse a read-only connection with one message that says
  whether the mode came from its settings or from `read_only = TRUE` in the
  call.
* Registering a new bare project on Framework Cloud writes its project token
  to `.env`, as for every other type, so the folder is linked to the Cloud
  project.
* `ai_regenerate_context()` in a project without an AI context file (an
  adopted project with AI off) says how to create one with
  `ai_generate_context()`.
* `scaffold()` and `package_add()` install from the cloud CRAN mirror
  (`https://cloud.r-project.org`) when no CRAN mirror is set, as under
  `Rscript`, instead of stopping with "trying to use CRAN without setting a
  mirror". A mirror you set is kept, and the option is restored afterwards.
* `git_security_audit()`'s history check works on Windows. Its `git log`
  format had a `|`, which `cmd` read as a pipe, so it found nothing there.

Adopting and upgrading projects:

* A `config.yml` makes a folder a Framework project only when it has Framework
  keys (`project_type`, `project_name`, `directories`, or 1.x `options:`
  folder keys or package list) in `default:` or at the top level. A project's
  own `config.yml`, such as the config package's, no longer stops `adopt()` or
  makes Framework treat the folder as a project.
* `adopt()` on a folder that is already a Framework project points to
  `upgrade()`.
* `adopt()` and `structure_import()` no longer follow symbolic links to
  folders, so the same tree maps the same way in R, Python, and fw.
* Setting a folder to "(other folder)" in `adopt()`'s review numbers its key
  (`_2`, `_3`) when another folder has it, rather than replacing that folder.
* `adopt()` adopts a folder with no subfolders, such as a single
  `analysis.qmd`, with no folders in `settings.yml`, rather than stopping with
  "No folders found to map".
* `adopt()` no longer proposes Framework's `settings/` folder, Quarto's
  `*_files/` and `*_cache/` render folders, `_site/`, or `_book/` as project
  folders, and maps `outputs/notebooks` and `outputs/docs` to `render_dirs`.
  Skip entries in `inst/adopt/rules.json` take `*` globs.
* `adopt()` infers the project type instead of always writing `bare`: `course`
  when the folder has course folders (`slides/`, `modules/`, `assignments/`,
  `readings/`), `project_sensitive` when it has the private and public layout
  (`inputs/private/raw/`, `outputs/public/figures/`), `project` when any
  folder maps to a Framework directory, and `bare` otherwise. The shared rules
  map the private and public input and output folders and the course folders
  (`data`, `slides`, `assignments`, `course_docs`, `readings`, and `modules`
  as notebooks), and a folder inside a mapped folder gets no key of its own.
* `adopt()` takes `sensitive = TRUE` and `type`, so a non-interactive adopt
  (and `fw adopt`) can mark a project as holding sensitive data or choose its
  type. Without them, when folders look private, it says how to turn sensitive
  data on. It returns the type with the folders.
* `adopt()` turns git on in the settings and spec when the folder is a git
  repository, as framework-py does.
* `adopt()` merges the `.gitignore` rules its spec records into the folder's
  `.gitignore`: `.env`, `framework.db`, private folders, and Quarto's
  `/.quarto/` and `**/*.quarto_ipynb` lines, plus each folder that looks
  private. It appends missing rules in one block and never removes a line,
  leaves out a rule that would ignore files git tracks, and records the
  resulting `.gitignore` in `spec.json`. Before, `framework.db` from
  `scaffold()` showed up as untracked.
* New `cloud_register()` creates the Cloud project for a local project from
  its `.framework/spec.json` in one request, at the slug you give or one made
  from its name, and links the folder (`FW_PROJECT_TOKEN` and `FW_CLOUD_URL`
  in `.env`). Framework Cloud stores the spec as the project's only layer, so
  the Cloud project describes the folder as it is, and an adopted project is
  marked as adopted. When you already have a project with that slug, it
  offers to link to it instead; a slug held by a project in your Trash can't
  be reused. `dry_run = TRUE` prints the request. `adopt(cloud = TRUE)`, or
  saying yes to its offer, calls it. Before, `adopt()` registered a name-only
  project and dropped its token, leaving a Cloud project the folder couldn't
  link to.
* `ai_skills_update()` updates a skill installed before
  `.framework/skills.lock.json` existed when its `SKILL.md` matches any
  version the package has shipped (recorded in
  `inst/templates/skill-history.json`), instead of keeping it as "locally
  edited" forever. A skill with real local edits is still kept.
* New `upgrade()` brings a project made by an older Framework to the current
  layout. It prints a plan by default; `dry_run = FALSE` backs up every file
  it rewrites to `.framework/backups/<timestamp>/` (which git ignores) and
  applies it, and running it again changes nothing. It renames a 1.x
  `config.yml` to `settings.yml`, adds `tools:` and `security:` (`sensitive:
  true` for `project_sensitive` projects and the private layout), rewrites the
  old connection layouts as `default_database` and `databases`, writes or
  refreshes `.framework/spec.json` (so `fw project push-spec` and
  `cloud_register()` work), appends missing `.gitignore` rules without
  removing any, makes AGENTS.md canonical with CLAUDE.md a pointer and
  regenerates its marked sections, adds the Claude Code guards to sensitive
  projects, updates skills from older releases, and adds missing Quarto files
  without replacing custom Quarto config. Keys outside `default:`, passwords
  written into settings (by key, never by value), edited skills, and
  per-folder Quarto projects are reported, not changed.
* `upgrade()` on a sensitive project with no Framework skills installs
  `framework-sensitive-data` in the skills folder its assistants read
  (`.claude/skills` when none is set). Other projects without skills get a
  note pointing to `ai_skills_update()`.
* Every `.framework/spec.json` R writes (`project_create()`, `adopt()`,
  `upgrade()`) holds only what `spec.v1` allows and is checked against it
  before it is written, so Framework Cloud no longer refuses it (HTTP 422) on
  `fw project link --create` or `push-spec`. `upgrade()` no longer writes
  `source.upgraded_from` or old scaffold options such as `positron` (`positron:
  yes` becomes `ide: positron` when no IDE is set), and drops both from a spec
  an earlier `upgrade()` wrote. `cloud_register()` stops before sending a spec
  that doesn't match and says to run `upgrade()`.
* `git_security_audit()`'s connection-secrets check and `upgrade()` follow
  Framework Cloud's rule for credentials: on a key named like a password,
  secret, token, access key, API key, private key, or credential,
  `env("NAME")` and `env("NAME", "")` (single or double quotes) pass, and
  `env("NAME", "value")` counts as a written-out secret. `upgrade()` writes
  such a value into the spec as `env("NAME")`, keeping its variable.
* `upgrade()` takes `type`, so `upgrade(type = "project_sensitive")` makes a
  project sensitive in one pass: it sets the type and `security: sensitive:
  true`, adds the private and public folders of that layout the project lacks
  (folders it has keep their keys and paths), and adds the sensitive
  `.gitignore` rules, agent guards, and skill. When a project becomes
  sensitive, by `type` or by hand since the last `upgrade()`, the plan says
  that `save_table()`, `save_figure()`, `save_model()`, and `save_report()`
  now write to `outputs/private/...`, and lists data and render folders that
  aren't private. AGENTS.md's regenerated sections describe the upgraded
  settings in the same pass, so a second `upgrade()` changes nothing.
* A fresh checkout of a sensitive project has no private folders, since git
  ignores them, and saving into one failed. `scaffold()` now creates the
  settings' private folders (`directories` keys with `private`, inside the
  project), and `data_save()` creates a missing folder that the settings name
  or that is inside one, without `force = TRUE`. `save_table()`,
  `save_figure()`, `save_model()`, and `save_report()` already created
  theirs. Tracked `.gitkeep` files in private folders are no longer needed.
* `git_security_audit()` false positives from adopting real projects:
  - The private-data-exposure check no longer counts placeholders that keep a
    folder in git: an empty `.gitkeep` or `.keep`, or a `.gitignore` of at
    most 4 KB.
  - The gitignore-coverage check asks git (`git check-ignore --no-index`) in a
    git repository instead of matching `.gitignore` patterns itself, so rules
    such as `inputs/**` with `!inputs/*/` count as git reads them.
  - Files someone has reviewed can be listed under `security: reviewed:` in the
    settings (paths, folders, or globs such as `"**/*_synthetic_*.csv"`). The
    history, private-data-exposure, and identifier-column checks report them
    as reviewed (`findings$reviewed`, and REVIEWED in the printed report)
    instead of failing.
* `upgrade()` refreshes the spec's `author` and its copy of `.gitignore`
  (`git.gitignore_content`) when they no longer match the settings and the
  file, and updates Framework skills in `.agents/skills` as well as the
  assistants' folders. A second copy of a skill (`.agents/skills` beside
  `.claude/skills`) is no longer kept as "edited" once the first is updated.
* When `upgrade()` keeps a written-out connection password out of the spec,
  it refers to it by the variable the project already uses: a name in `.env`
  (preferring the one that holds the value, compared without printing it),
  `.env.example`, or the code, that fits the key and names the connection.
  Only when none does it makes one from the connection's name. The plan names
  the variable, says where it came from, and tells you to set it in `.env`
  and refer to it in the settings.
* `upgrade(move_settings = TRUE)` moves top-level settings keys that no
  environment reads (`ehr_source:` beside `default:`) into
  `settings/<key>.yml`, with their text and comments, and names each file
  under `default:`, so `settings_read()` and `settings()` read them and the
  warning on every `scaffold()` stops. Without it, the plan says the option
  exists.
* `upgrade()`'s Claude Code guard (`.claude/settings.json`) covers every
  private folder: those with a `private` or `*_private` segment, those whose
  key marks them private (`inputs_private_raw: inputs/raw`), and private
  render folders (`render_dirs: notebooks: outputs/private/notebooks`). A
  sensitive project gets it whatever its AI settings, and the plan says so
  when AI is off or Claude isn't among the assistants, and when the settings
  name no private folder to guard. The plan warns when git ignores
  `.claude/`, since the guard and skills then stay on one computer.
  `project_create()` uses the same rule for its guards and AGENTS.md notice.
* `upgrade()` and `adopt()` no longer append negations (`!/inputs/**/README.md`)
  to a `.gitignore` that already has rules: after the project's own rules
  they won, and could make README files in ignored data folders committable.
  They are reported instead. A new or empty `.gitignore` still gets the whole
  template.
* `adopt()` sets `tools: quarto: true` when the folder has a `_quarto.yml`
  or a `.qmd` file at most three folders deep, not only a `_quarto.yml` at
  the root, so a Quarto project in `notebooks/` or loose `.qmd` files count.
* In a sensitive `adopt()`, the plan lists mapped folders that may hold
  restricted data but aren't private (data, exports, reports, results, and
  `inputs_*`/`outputs_*` folders), an interactive review asks about each,
  and the new `private` argument marks folders private in a non-interactive
  adopt: each keeps its path under a private key (`outputs_reports` becomes
  `outputs_private_reports`, `data-files` becomes
  `inputs_private_data_files`) and is added to `.gitignore`. `adopt()` no
  longer writes a stray `//` rule when every private-looking folder is
  already ignored.

# framework 2.0.1

Fixes and features found by porting real R projects to Python and Stata, so
the three languages behave the same.

Behavior changes:

* `data_read()` trims leading and trailing whitespace from CSV and TSV values
  and column names (`trim_ws = TRUE`), as `readr::read_csv()` does. A padded
  value such as `"   1"` now reads as a number. Pass `trim_ws = FALSE` for the
  old behavior.
* `project_sensitive` projects turn on the `data_security` and
  `check_sensitive_dirs` git hooks by default, and the pre-commit hook is
  installed after the initial commit.

New functions and arguments:

* `project_path()` builds an absolute path from the project root, like
  `here::here()`, from any folder in the project.
* `load_model()` reads back a model `save_model()` saved. `save_model(public =
  TRUE)` warns when the model holds data rows.
* `show_table()` prints a data frame as a Markdown table in Quarto and Jupyter.
* `db_execute_file()` runs a SQL file, `db_copy_from()` loads a CSV into an
  existing table, and `db_connect()` and `db_query()` take `read_only` to
  override the connection's setting for SQLite and DuckDB.
* `cache_remember()` and `cache()` take `depends_on`: catalog names, files,
  folders, or values. The entry is recomputed when any of them changes, and
  the record is shared with framework-py.
* `data_info(columns = TRUE)` summarizes column names, types, and missing
  counts without showing any values.
* `save_figure()` takes several formats at once, and adds `eps` and `emf`
  (through devEMF).
* `make_notebook()` and its wrappers take `title`, for acronyms in lowercase
  file names.
* Folder publishing destinations take `layout: site-root`, which keeps only the
  latest publish at the folder's root, for a deck or site on GitHub Pages.

Sensitive data:

* `publish()`, `publish_notebook()`, and `publish_data()` ask for confirmation
  before publishing a notebook or an object from a `security: sensitive: true`
  project, and a notebook in any project that reads private data.
* In a sensitive project, `save_table()`, `save_figure()`, and `save_model()`
  with `public = TRUE` warn when the session has read private data.
* `data_save()` warns about identifier-like columns (date of birth, ZIP code,
  SSN, record number, names) saved outside a private folder.
* The `check_sensitive_dirs` hook skips Framework's own skills.
* `git_security_audit()` reports each file once, lists folders outside the
  project instead of checking them, and adds three
  checks: `published_outputs` (folder publishing destinations git doesn't
  ignore), `connection_secrets` (passwords and tokens written into connection
  settings), and `identifier_columns` (tracked data with identifier-like
  columns). New projects add their folder publishing destinations to
  `.gitignore`.

Fixes:

* `data_save()` warns when it replaces locked data with different contents.
* `data_read()` names a missing file by its path from the project root and
  says where it looked.
* Settings warn once about keys outside the environment sections, which are
  ignored.
* `package_add()` refreshes the package list in AGENTS.md.
* `save_figure()`, `save_table()`, and `save_model()` create the subfolders a
  `name` with `/` names.
* `publish_data()`'s message shows the normalized slug, and `publish_dir()`
  keeps the folder part of `dest` in the slug.

# framework 2.0.0

Framework 2.0 works with Framework Cloud (framework.pub or a self-hosted
server). The main changes since 1.1.0:

* `cloud_login()` signs in from the browser. `new()` and `new_project()` build
  projects from your Cloud defaults and blueprints, and `setup()` sets up a
  project created in Cloud.
* Projects are built from layers: a structure, then tools such as Quarto,
  Jupyter, targets, and renv, then package and skill sets. 26 package sets
  ship with the package, and `package_set_add()` adds one to an existing
  project.
* `publish()` publishes tables, models, figures, and notebooks to Cloud, a
  folder, S3, or GitHub Pages. Publishing again adds a version at the same
  link.
* Every project gets an AGENTS.md and agent skills, and `skills_sync()` keeps
  skills in step with Cloud.

The local GUI is retired. `gui()` now only warns and points to Framework
Cloud, and plumber is no longer a suggested package. `setup()` takes a Cloud
project token; with none, it creates the global settings file.

Other changes in this release:

* Package sets: 24 more, and `package_set_add()` adds one to an existing
  project.
* `read_only: true` opens a SQLite connection read-only, including a file
  without write permission. `db_execute()` and `db_transaction()` refuse
  read-only connections.
* `publish_data()`, `publish_dir()`, and `publish_list()` follow
  `publish.default` and `publish.destinations`, and take `to`. A relative
  folder destination `path:` starts at the project root.
* `publish_notebook()` takes `title` and `description`. Titles default to the
  document's YAML title.
* `data_save()` never writes relative to the working directory:
  `"inputs.final.x.csv"` is the catalog name `inputs.final.x` saved as CSV, and
  relative paths start at the project root. `data_verify()` accepts a path.
* `data_add()` names files in every configured inputs folder, so
  `inputs/private/raw/x.csv` becomes `inputs.private.raw.x`.
* `make_*()` resolve `dir` from the project root, give new notebooks a
  readable title, and say "presentation" for presentations.
* `adopt()` writes connections in the layout `db_connect()` reads.
* Git hooks refuse a project nested inside another repository, and
  `git_status()` and `status()` say when they report an enclosing repository.
* `cache` `expire_after` accepts minutes and seconds.
* The security audit's orphan scan respects `.gitignore`.
* Sensitive projects render to `outputs/private/notebooks` by default, and
  course projects gitignore `rendered/`.
* `bootstrap()` leaves output folders lazy and lists only the `.env` variables
  the settings use. `project_list()` marks missing project folders.
* Fixes: `packages_status()` works with renv off; `ai_skills_update()` reports
  what it did; `ai_regenerate_context()` keeps blank lines; new `scaffold.R`
  files don't set the theme and seed twice; the login advice is the same
  everywhere; the README matches the real API.
* Settings writes change only the section they edit. `data_save()` and
  `data_add()` in a project with the catalog in settings.yml no longer drop
  comments, collapse `[claude]` to `claude`, or turn `true` into `yes`, and
  whole-file writes use `true`/`false` and keep one-item lists as lists.
* `data_save()` records a path relative to the project root, so
  `"./x/y.csv"` and `"x/y.csv"` are one record and `data_verify()` finds it.
* `publish_data()` to a folder, GitHub, or Cloud keeps the folder part of
  `dest` in the slug (`"tables/demo.csv"` publishes as `tables-demo`) and
  says which slug it used.
* New notebook titles use sentence case: `"setup-and-settings"` becomes
  "Setup and settings".
* The .gitignore templates hold Quarto's own `/.quarto/` and
  `**/*.quarto_ipynb` lines, so a first render leaves .gitignore unchanged.
* A project created inside an existing git repository is left to it: no
  `git init` and no initial commit. In such a project, `status()` reports
  "Commits touching this project".
* Windows: git hooks, `bootstrap()`, and GitHub Pages publishing work with an
  MSYS or Cygwin git; `data_add()`, `publish_dir()`, and S3 folder uploads
  handle backslash paths; the sensitive-folder hook and the orphan scan
  read `git check-ignore` correctly; temporary and macOS system folders are
  recognized on every platform; `config_sync()` no longer recopies files.

# framework 1.9.0.9004

* The guides cover 2.0: install from GitHub until 2.0 reaches CRAN.
  Framework 1.1 stays on CRAN.

# framework 1.9.0.9003

* Framework Cloud calls go to `/api/v1` only. The server no longer serves
  `/api/v2`.
* R writes only its own `cloud.yml`, and the newest sign-in sets the server.
* Cloud interop fixes from the 2026-11-05 audit.

# framework 1.9.0.9002

* `new()` makes a Standard Project (`type = "project"`) by default when
  you are not signed in, as `new_project()` does. Its menu lists the
  Standard Project first. Pass `type = "bare"` for a bare project.
* Skill sync retains executable-mode metadata on Windows. Canonical skill
  checkouts preserve LF line endings for stable source hashes.

# framework 1.9.0.9001

* `skills_sync()` synchronizes full skill directories with Cloud. Private forks
  retain exact canonical ancestry. Conflicts stop sync and explicit resolution
  retains local backups. Package updates preserve locally edited skills.
* Published tables, models, and plots include structured representations for
  Cloud readers. Artifacts can be attached to collections and reports.


* With the Quarto tool off, `make_notebook()` makes Jupyter notebooks (an
  `.ipynb` for the R kernel) when the Jupyter tool is on, R Markdown when
  rmarkdown is installed, and plain scripts otherwise. `type = "jupyter"`
  and `.ipynb` names work in any project. Creating a project with the
  Jupyter tool offers to register the R kernel (`IRkernel::installspec()`)
  in interactive sessions and prints the command otherwise
* `new()` and `new_project()` build projects the same way framework.pub
  does: the user's settings, the structure, then tools and sets, resolved
  into one spec. New `tools`, `package_sets`, and `skill_sets` arguments
  turn on tools (a tool's requirements are added, with a message) and add
  Framework's sets, for example
  `new_project("study", "~/study", tools = "targets", package_sets = "tidyverse-analysis")`.
  Any lowercase id works as `type`. Extra arguments are ignored with a
  warning
* Every new project's AGENTS.md is the full guide generated from its
  settings, including projects from framework.pub, which used to get a
  short stub. The skills table lists the skills actually installed, and
  sensitive projects name the folders agents must not read
* Projects created from layers (framework.pub and
  `project_create_from_layers()`) follow the spec's settings instead of its
  type name. `settings_layout` picks split or single settings files,
  `core_files: false` skips the starter files and `.env`, and
  `tools.quarto` decides whether Quarto configuration is written.
  `tools.renv` turns on renv, with `packages.use_renv` as its older name.
  Any lowercase type label works, and new projects record their tools in
  `settings.yml`
* `save_table()`, `save_figure()`, `save_model()`, `save_report()`, and
  `save_notebook()` split private and public output folders when sensitive
  data is on or the project lists `outputs_private_*` folders, whatever its
  type
* Framework's tools (`quarto`, `quarto_manuscript`, `quarto_slides`,
  `targets`, `renv`, `jupyter`, and `uv`) are defined in `inst/features/`,
  and its skill sets (`framework`, `ggplot2`) and package set
  (`tidyverse-analysis`) in `inst/sets/`, for framework.pub, framework-py,
  and fw to copy
* The project spec and layer schemas (`inst/schema/`) accept any lowercase
  id as `type`, which is now a label for the blueprint a project came from.
  Two optional fields are new: `tools`, a map of tool id to true or false
  (`quarto`, `renv`, `targets`, and so on), and `core_files`, false for
  bare structures that write no starter files or `.env`, and
  `settings_layout` (`split` or `flat`). `spec_check()`
  follows the schemas. A conformance fixture covers how `tools` merges
* New projects get two ggplot2 skills, `ggplot2-exploring` (quick,
  accurate figures for understanding data) and `ggplot2-publishing`
  (figures for papers, reports, and slides), listed in AGENTS.md. Each
  shipped skill now has a readable title in its frontmatter
  (`metadata: title:`), as in the Agent Skills format; `name` stays the id
  agents use. `ai_skills_update()` refreshes the ggplot2 skills too
* `publish(to = "github")` and `publish_notebook(to = "github")` publish to
  the project's GitHub Pages site. The rendered HTML and its `<name>_files/`
  folder are copied to `published/<slug>/` at the top of the repository
  (replacing what was there), only that folder is committed as
  "Publish <slug>", and the commit is pushed to the branch's upstream,
  origin, or another GitHub remote. Interactive sessions confirm first. The
  default slug is the file name in lowercase with other characters as `-`.
  The URL comes from Framework Cloud when the project has its token,
  otherwise from the GitHub remote. Framework Cloud's "Publish with GitHub Pages" turns on
  the site and adds the workflow that deploys `published/` from the default
  branch. Publishing from another branch warns. Pages sites are public, even
  from a private repository
* `docs_export(reference_path = )` also writes the reference for the
  r.framework.pub docs site, in the format shared with framework-py and fw
  (`inst/schema/docs-reference.v1.json`, described in
  `inst/schema/docs-site.md`). The guides now live in `docs/site/`, and each
  release attaches `docs-site.tar.gz`. Cloud functions and the user-wide
  configuration helpers have reference categories
* `git_security_audit()` and the data_security hook count a folder as
  private when its settings key contains `private`, its path has a
  `private`, `confidential`, or `sensitive` folder, or it is `cache`,
  `scratch`, or `logs`. Standard projects can commit files in `inputs/raw`
  and the other input folders, as their `.gitignore` allows; restricted
  data goes under a private folder. Before, every `inputs_*` and
  `outputs_*` folder counted as private, so the hook blocked any commit
  that included a data file in a standard project's inputs
* The pre-commit hook checks that framework (R) or framework-py (Python)
  is installed before running, and says so when neither is
* Fixed: `data_read()` and `data_info()` find catalog entries with dotted
  keys (`raw.survey:` under `inputs:`, or `inputs.raw.survey:` under
  `data:`), as `data_list()` shows them, and `data_add()` updates such an
  entry where it is
* Fixed: `data_save()` picks the folder from the longest leading part of the
  name that names a configured directory, so `inputs.private.raw.ids` goes
  to `inputs_private_raw`
* Fixed: `data_info()` marks a file private when any folder between the
  project root and the file is named `private`, not only its own folder
* Fixed: `data_add()` records `.por` files as `spss_por` and `.xpt` files as
  `sas_xpt`, and `data_read()` reads entries recorded the old way correctly
* Fixed: `scaffold()` reads `source_all_functions` from `scaffold:`, where
  new projects write it (then `options:`)
* Fixed: `settings_write(section = )` into a split file merges the values
  under the section key, with or without that wrapper in the values
* Fixed: `bootstrap()` no longer creates folders for directory entries that
  name a file, such as `presentation.qmd`
* Fixed: `settings_write(section = )` on a flat settings.yml (no `default:`
  section) added a `default:` block holding only that section, after which
  settings_read() ignored the file's other settings. It now writes the
  section at the top level
* SQL Server connections use the newest installed Microsoft ODBC driver
  (Driver 18 or 17) unless `odbc_driver` is set, instead of assuming 17
* Tests now run against real PostgreSQL, MySQL, MariaDB, SQL Server, and S3
  servers from `tests/integration/compose.yml` (shared with framework-py and
  fw) when they are running, and in CI on every push
* The `ai_sync` git hook is removed. Projects keep one `AGENTS.md`, which
  `CLAUDE.md` points to, plus skills, so there is nothing to sync.
  `git_hooks_enable("ai_sync")` is an error, an `ai_sync: true` left in
  settings.yml is ignored, and new settings no longer include it.
  `ai_sync_context()` is deprecated
* `bootstrap()` prepares a cloned project: it makes sure `.gitignore`
  ignores `.env`, creates `.env` from `.env.example` and lists empty
  variables (or asks for them when interactive), creates the project folders,
  creates or upgrades `framework.db`, restores packages (renv.lock or
  settings.yml), and installs the enabled git hooks. It never contacts the
  cloud. From a shell: `Rscript -e 'framework::bootstrap(interactive = FALSE)'`
* The pre-commit hook is now a short POSIX `sh` script shared with the
  Python package and `fw` (`inst/hooks/pre-commit`). It finds an R or Python
  runtime and runs the checks enabled in settings.yml, so enabling or
  disabling a hook no longer needs a reinstall. `git_hooks_install()` writes
  it where git looks (worktrees and `core.hooksPath` included), replaces
  hooks Framework wrote earlier without `force`, and keeps any other hook
  unless `force = TRUE`
* `setup("fw_...")` and the new `new(key = ...)` create cloud projects from
  the project's layers (pull v2), resolved with `spec_resolve()`, so cloud
  projects get the same `.framework/spec.json` record as local ones. A
  Python or Stata cloud project stops with a pointer to the right tool
* Registering a new project with Framework Cloud now sends its language (`r`)
* `git_security_audit()` now fails `private_data_exposure` for any tracked
  data file under a folder whose name contains private, confidential, or
  sensitive, even when that folder is not a configured directory (for
  example `inputs/private` added with `git add -f`). Configured folders now
  match on whole path segments, so `inputs/raw` no longer covers
  `inputs/raw_public`. The orphan scan skips `node_modules`
* Global settings refuse values for secret-looking variables in
  `defaults.env` (names containing PASSWORD, SECRET, TOKEN, ACCESS_KEY,
  API_KEY, PRIVATE_KEY, or CREDENTIAL), as specs already do
* Project specs: `spec_resolve()` merges spec layers over the package
  defaults, `spec_check()` reports problems, `project_create()` accepts a
  resolved spec, and `project_create_from_layers()` creates a project from a
  framework.pub layers file (headless mode for GitHub Actions). JSON Schemas
  for specs and layers ship in `inst/schema/`
* Sensitive projects (`security.sensitive`) get Claude Code deny rules and a
  fail-closed sandbox that keep the agent out of restricted directories
* Quarto notebooks, slides, and presentation projects get a full Quarto
  author block (`orcid`, `url`, and `affiliations` with department, city,
  and country) when author settings have those details. With only name,
  email, and affiliation, the one-line `author: "Name"` is unchanged. The
  spec and layers schemas accept the new author fields
* Opt-in framework.pub cloud integration (planned for 2.0): `cloud_login()`,
  `cloud_logout()`, `cloud_status()`, `cloud_settings()`, `cloud_sync()`,
  `ledger_push()`, `ledger_list()`, `data_verify()`, and `setup()` with a
  project token. Nothing contacts the cloud unless you connect explicitly
* Self-hosted Framework Cloud servers: `cloud_login(token, url = )` and
  `setup(token, url = )` take a server URL, tokens are stored per server,
  and the server you log in to becomes the default. Projects record their
  server as `FW_CLOUD_URL` in `.env`, so publishing and the ledger go back
  to the server the project came from. Plain `http` is accepted only for
  `localhost` and `127.0.0.1`. `cloud_status()` reports the server in use
  and where that setting came from
* `publish_notebook()` publishes to Framework Cloud when the project has no
  storage bucket and was set up from Framework Cloud, as `publish()` does.
  With neither, both functions name the two ways to fix it
* `publish()` and `publish_notebook()` take `slug` for Framework Cloud:
  `slug = "main-results"` names the document and turns on its readable URL,
  `slug = TRUE` does the same with the name derived from the file, and
  `slug = FALSE` turns it off. Each publish adds a new version, and the
  message shows the version number and the link to share
* Specs record a primary `language` (`r`, `python`, or `stata`; a layers
  file without one means `r`). The R package builds R projects only and
  names the right tool for the others: the Python package, or `fw` for Stata
  scaffolding
* Layer-merge conformance fixtures in `inst/conformance/` pin the merge
  rules shared by the R package, the Python package, and `fw`
* New `config_sync()` copies user settings, the saved Framework Cloud server,
  and token files from the folder the Python package and `fw` use
  (`~/.config/framework`) into R's config folder, when theirs are missing
  from R's or newer. R only reads that folder and never writes to it, and
  `fw_config_dir()` stays on `tools::R_user_dir()` (or `FW_CONFIG_HOME`)
* Fixed (security): projects created with `new()`, `new_project()`, and the
  other `new_*()` helpers got no `.gitignore`, so `.env` (which holds
  database passwords and the Framework Cloud project token) was committed
  in the initial commit. 1.1.0 is affected. Every project now gets the
  `.gitignore` for its type, and creation checks that `.env` is ignored
  before the first commit. `git_security_audit()` has a new
  `secrets_exposure` check that fails when git tracks a `.env` file.
  A later `!.env` line cannot re-include it: the last line that mentions
  `.env` decides, and creation asks git (`git check-ignore`) before the
  first commit and skips the commit if `.env` is still not ignored
* `spec_check()` rejects values for secret-looking environment variables
  (names containing PASSWORD, SECRET, TOKEN, ACCESS_KEY, API_KEY, PRIVATE_KEY, or
  CREDENTIAL). Specs pass through the cloud and into git, so those values
  belong in `.env`
* Fixed: `scaffold()` never set the random seed for new projects, which
  store `seed_on_scaffold` and `seed` under `scaffold:`. A project's own
  seed now also takes precedence over the user-wide `FW_SEED`, as
  documented, and `seed_on_scaffold: false` turns seeding off even when
  `FW_SEED` is set
* Fixed: `data_add()` recorded absolute paths in the data catalog, which
  broke once a project was moved or cloned. Paths inside the project are now
  stored relative to the project root
* `spec.v1.json` requires `render_dirs`, `packages`, `scaffold`, and
  `connections` only for R and Python specs, so Stata specs (scaffolded by
  `fw`) leave them out. In `layers.v1.json`, a layer's `kind` is optional,
  and `source.fw_version` records the `fw` version for Stata projects
* Spec schemas accept what Python projects need: `pypi` package sources and
  wider package names, `.py` data hooks, `jupyter` notebooks, and
  `source.origin: python`. `packages.use_renv`, `scaffold.set_theme_on_scaffold`,
  and `scaffold.ggplot_theme` are optional. R's `spec_check()` still accepts
  only what R can build
* `publish()`, `publish_notebook()`, `publish_dir()`, and `publish_data()`
  warn when the absolute path of any file they would upload contains
  "private" in any letter case, apart from the `/private/` that macOS puts
  in front of `/tmp`, `/var`, and `/etc`. The warning lists up to five
  paths. An interactive session asks before publishing, with No as the
  default. A non-interactive session stops unless `include_private = TRUE`.
  Publishing is always an explicit call, and nothing is uploaded
  automatically
* S3 uploads retry without the `public-read` ACL when the bucket has ACLs
  disabled (the AWS default for new buckets), leaving access to the bucket
  policy. They used to fail
* Fixed: projects created from a spec wrote `settings/connections.yml`
  without its `connections:` wrapper, so `db_connect()`, `db_list()`,
  `connections_list()`, and storage lookups found no connections. New
  projects get the wrapper, and `settings_read()` repairs projects already
  created that way
* Fixed: `save_table()`, `save_figure()`, `save_model()`, and the other
  `save_*()` helpers never recorded their outputs in `framework.db` when no
  comment was given, and `result_list()` without filters always returned an
  empty table. Both errors were swallowed. Results timestamps are now epoch
  seconds like the data, cache, and meta tables; older text timestamps
  still read
* Fixed: environment sections in `settings.yml` (for example `production:`)
  now replace sequences whole. A sequence of mappings used to be left
  unchanged, so such an override silently did nothing
* Fixed: `settings_write(section =)` finds split files relative to the
  settings file, so it works from a subfolder
* `data_list()` includes `name: path` shorthand catalog entries and returns
  its entries as a data frame (invisibly), as documented
* New `package_add()` records a package in the project's settings (CRAN,
  pinned, GitHub, or Bioconductor, optionally auto-attached) and installs
  it. The `framework-packages` skill and the generated AI context already
  told assistants to use it
* The `framework-outputs` and `framework-workflow` skills, the generated AI
  context, the cheatsheet, and the README now use current function names
  (`save_table()`, `save_figure()`, `save_model()`, `cache_remember()`,
  `db_query()`, `db_execute()`, and `storage_test()`) instead of removed
  ones. A test fails if a skill or the cheatsheet calls a function the
  package doesn't export

# framework 1.1.0

* `plumber` moved from Imports to Suggests. plumber pulls in `sodium`, which
  needs the system libsodium library and often fails to install on HPC
  clusters. The GUI (`gui()`, `setup()`) now asks you to install plumber when
  you launch it; nothing else needs it
* New standard `logs` directory for run logs and cluster job output. All
  project gitignore templates now ignore `**/logs/**` and `slurm-*.out`, and
  `security_audit()` treats `logs` as a private directory
* `scaffold()` git checks are now portable across platforms
* Skills-based AI context: new projects get a thin canonical `AGENTS.md` plus
  Framework skills installed in `.claude/skills/` (workflow, data, packages,
  outputs, and sensitive-data rules as separate SKILL.md files)
* `AGENTS.md` replaces `CLAUDE.md` as the default canonical AI context file;
  CLAUDE.md and .github/copilot-instructions.md are now thin pointer stubs
* New `ai_skills_update()` refreshes a project's Framework skills after
  upgrading the package
* `ai_regenerate_context()` falls back to `CLAUDE.md` for projects created
  before 1.1.0

# framework 1.0.0

* First stable release
* Zero CRAN check errors/warnings (1 acceptable note for global config object)
* Complete documentation for all exported functions
* Comprehensive test suite (300+ tests)

# framework 0.10.1

* Fixed non-ASCII characters in R source files for CRAN compatibility
* Fixed documentation for `subdir` parameter in `make_rmd()`, `make_revealjs()`, and `make_presentation()`
* Added missing package declarations to DESCRIPTION Suggests
* Improved `scratch_capture()` examples with `\dontrun{}`

# framework 0.10.0

* Initial preparation for CRAN submission
* Comprehensive data management system with declarative YAML catalogs
* SQLite, PostgreSQL, MySQL, DuckDB database connectivity
* Quarto-first notebook generation with stub templates
* S3-compatible object storage publishing
* Project scaffolding with reproducible environments
* Caching system with expiration support
* Git hooks integration for data security
* GUI for project management (via `gui()`)
