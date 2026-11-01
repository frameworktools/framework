# Conformance fixtures

Shared test cases for every Framework engine: the R package, the Python
package, `fw` (which merges layers for Stata scaffolding), and
framework-cloud's preview. They pin down
behavior that must be identical across languages.

## merge/

Each file is one case of the layer merge that `spec_resolve()` performs
before applying a language's package defaults and finalizing the spec.

- `layers` is the input, in the `layers` format of `layers.v1.json`: a list
  of `{kind, key, version, layer}` entries. An entry without `kind` is
  labeled `layer N` (1-based); otherwise the label is `kind`, then `key`, then
  `vN` when `version` is set, separated by spaces.
- `expected.spec` is the merged result with no package defaults. The
  `git.gitignore_content` text is removed from it and reported separately.
- `expected.gitignore_blocks` lists each layer's gitignore text with its
  label, in layer order.
- `expected.conflicts` lists keys set to different values by more than one
  layer. `path` joins keys with `/`, and `layers` joins the labels with `, `.

Compare as parsed JSON, with these rules:

- Object key order does not matter.
- An empty object `{}` equals an empty array `[]` (R cannot tell them apart).
- Conflicts are compared as a set.

## create/

Each file is one case of project creation from a resolved spec. The cases
live in a folder per language, and each language's engine generates its own:
`create/r/` from `data-raw/conformance.R`, `create/stata/` from `fw`
(`go run ./tools/createfixtures --out <this folder>/create/stata`), and
`create/python/` from framework-py. This repository keeps the one copy.

- `layers` records how the spec was resolved: a structure (`base`), the
  workflow's layers from `inst/workflows/` and the tools it requires, and the
  creation choices (`project`). It is for reference; engines do not resolve it.
- `spec` is the resolved spec, the input to creation.
- `expected.paths` lists every file and folder that creating `spec` writes:
  paths relative to the project folder, folders ending in `/`, `.git/` and
  its contents left out, sorted by byte value. Contents are not compared.

Engines create a project from `spec` in an empty folder and compare the
sorted path list exactly. The cloud compares its preview tree against the
same list.

## adopt/

Each file is one case of mapping an existing project's folders to Framework
directory keys, as `adopt()` and `structure_import()` do. The rules are in
`inst/adopt/rules.json`, which every engine syncs.

- `folders` is the input: relative folder paths, as a scanner would list
  them. `language` is optional and defaults to `r`.
- `expected.directories` maps Framework keys to folder paths.
- `expected.extra_directories` maps keys to `{label, path}` for folders no
  rule matched.
- `expected.warnings` lists `{code: "private_path", path}` for each kept
  folder whose path contains "private" in any case, in byte order of path.

The algorithm:

1. Keep only folders at most `max_depth` (3) levels deep in which no
   segment is listed in `skip` (compared ignoring case) or starts with `.`.
   Sort them by byte value.
2. Rules apply in file order, skipping rules whose `languages` leave out the
   project's language (a rule without `languages` applies to every
   language). For each rule, the first of its `patterns`, in order, that
   equals an unassigned folder's whole relative path, ignoring case, gives
   that folder the rule's key. Patterns have no wildcards, so `raw` matches
   only a top-level `raw/`. A key gets at most one folder.
3. A folder inside an assigned folder is covered by it and not listed.
4. Each remaining folder with no assigned folder inside it becomes an extra
   directory, unless its parent also qualifies. So `data/` holding only
   matched folders isn't listed, and `archive/` is listed once for
   `archive/2019/` and `archive/2020/`.
5. An extra directory's key is its path lowercased, with each run of
   characters other than `a-z0-9` turned into `_` and leading or trailing
   `_` removed. `dir_` goes in front when the key doesn't start with a
   letter. A key already used by a rule that applies to the language
   (assigned or not) or by an earlier extra directory (in byte order of
   path) gets `_2`, `_3`, and so on. Scanners don't follow links. The label is the folder's
   own name.

Only paths relative to the project folder are checked for "private", so a
parent folder such as macOS's `/private/tmp` never warns.

## Offline creation

Shared by every client that resolves through Framework Cloud (`new()` in R
and Python, which `fw new` calls).

- The cache file is `<Framework config folder>/cache/defaults/<host[_port]>/<language>.json`
  (the port joined with `_`, since Windows doesn't allow `:` in a folder name),
  holding `{"fetched_at": <RFC 3339>, "defaults_revision": "...", "envelope": {...}}`.
  Only the default envelope is cached, resolved from `{"language": ...}`
  alone. A project with explicit pieces needs a connection.
- The cloud sends a `Framework-Defaults-Revision` header on
  `POST /api/v2/resolve` and `GET /api/v2/defaults`. It is opaque: compare
  it for equality only.
- `POST /api/v2/resolve` with only `{"language": ...}` resolves from the
  person's defaults. When their default blueprint doesn't support the
  language, the cloud falls back to `framework/project` with a notice.
- Offline means network errors, timeouts, and 5xx responses. 401 and 403
  are authentication errors, never offline.
- Offline with a cache: build from it and say "Using your Framework Cloud
  defaults from <date>".
- Offline with no cache: an interactive session asks before building from
  the package's built-ins. A non-interactive session stops unless the caller
  passes `offline = TRUE` (R), `offline=True` (Python), or `--offline` (`fw`).
- Not signed in: build from the package's built-ins without asking.
- Never fall back to a different configuration silently.

## Updating

The merge inputs are written by hand, and the create cases are listed in
`data-raw/conformance.R`. The expected outputs are generated from the R
implementation by that script and reviewed before committing.
A change to the merge rules changes these files in the same commit, and the
Python package and `fw` update their pinned copies from the release tag.
