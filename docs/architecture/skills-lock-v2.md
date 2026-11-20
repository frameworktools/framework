# Skills lock v2

Status: design, 2026-11-19. Branch `skills-lock-v2`, from R 2.0.17.
Implementations: R (`framework`), Python (`framework-py`), and Go (`fw`).
Scenarios: `inst/conformance/skills/`.

## Scope

This document defines version 2 of `.framework/skills.lock.json`, the
migration from version 1, one planner that every skill command calls, the new
`skills_move()` operation, and the result vocabulary. It also states how v2
resolves each item in the three `docs/notes/skills-followups.md` files.

The bundle format, the bundle hash (`framework-skill-bundle-v1` manifest,
LF-normalized text), the installer (staging, backups, rollback; see "Apply"
for one change to rollback), and the sync
lock folder (`.framework/skills.sync.lock`) do not change.

## Problems in v1

- One `hash` covers every copy of a skill. Once one copy is written and
  another is not, the lock can no longer say which copy is unedited.
- Each command (pull, push, upgrade, `pull_all`, `skills_copy`, assistant add
  or switch) derives "edited", "stale", and "diverged" itself. The three
  languages agreed only after many review rounds, and some commands still
  differ (see "Follow-up items").
- "Unedited older version" is a lookup in a SKILL.md history file for
  package skills and a `setup_hash` side channel for Cloud skills. A deliberate
  revert to an older version looks unedited and is overwritten.
- No operation moves a copy to another folder or switches its identity, so
  pull either guesses or refuses.

## Terms

- **Identity.** What a skill is, independent of where its copies live.
  Four kinds:
  - `builtin`: a Framework skill, `skill_id` `framework:<name>`, delivered by
    the language package or by Cloud. One identity for both channels.
  - `cloud`: any other Cloud skill (yours or one shared with you), keyed by
    server and `skill_id`.
  - `inline`: setup text with no Cloud identity, keyed by its setup name.
  - `local`: a folder `skills_sync()` started tracking that has no Cloud
    identity yet (a first push that has not completed).

  Every identity has a `variant` (`r`, `python`, or `stata`). Two variants of
  one skill are two identities.
- **Channel.** How a version arrived: `package`, `cloud`, or `inline`.
- **Copy.** One folder holding a skill, such as `.claude/skills/x`. Paths are
  project-relative with `/` separators.
- **Record.** The hash a sync last wrote at a copy's path (or, after
  `skills_copy()`, the record of the copy it was copied from). A copy whose
  disk hash equals its record is unedited.
- **Known hashes.** Every hash the package or Cloud has shipped for an
  identity and every hash a sync has written for it. "Unedited older version"
  is membership in this set.
- **Source.** One offering for one identity: a setup skill, a package skill,
  a Cloud version fetched by identity, or (for push) the Cloud head.

## Schema

```json
{
  "schema": 2,
  "skills": {
    "framework:framework-data@r": {
      "identity": {"kind": "builtin", "skill_id": "framework:framework-data", "variant": "r"},
      "base": {"channel": "package", "hash": "9d1e…", "version": null, "server": null},
      "known": ["2cd7…", "44f5…", "9d1e…"],
      "copies": {
        ".agents/skills/framework-data": {"hash": "9d1e…"},
        ".claude/skills/framework-data": {"hash": "9d1e…"}
      }
    },
    "https://framework.pub/5d0c2a7e-…@r": {
      "identity": {"kind": "cloud", "skill_id": "5d0c2a7e-…", "variant": "r", "server": "https://framework.pub"},
      "base": {"channel": "cloud", "hash": "b81f…", "version": 4, "server": "https://framework.pub"},
      "known": ["0a4c…", "b81f…"],
      "copies": {".claude/skills/survey-weights": {"hash": "b81f…"}},
      "pending": {"request_id": "6f1d…", "hash": "e730…", "basis": "4:5d0c2a7e-…:r"}
    }
  }
}
```

### Entry fields

| Field | Type | Meaning |
|---|---|---|
| `identity.kind` | string | `builtin`, `cloud`, `inline`, or `local` |
| `identity.skill_id` | string | `framework:<name>`, a Cloud ID, `inline:<name>`, or absent for `local` |
| `identity.variant` | string | `r`, `python`, or `stata` |
| `identity.server` | string | `cloud` only. No trailing `/`. |
| `base` | object or null | The source version last synced: what push sends as its base |
| `base.channel` | string | `package`, `cloud`, or `inline` |
| `base.hash` | string | Bundle hash of that version |
| `base.version` | int or null | Cloud version number; null for `package` and `inline` |
| `base.server` | string or null | The server that delivered a `cloud` channel version |
| `known` | array | Known hashes, sorted by byte value, unique |
| `copies` | object | Path → `{"hash": <record>}`, one per tracked copy |
| `pending` | object | Unchanged from v1: an unfinished push's request |

### Keys

The key is derived from the identity and is unique:

- `builtin`: `framework:<name>@<variant>`
- `cloud`: `<server>/<skill_id>@<variant>`
- `inline`: `inline:<name>@<variant>`
- `local`: `local:<first path at creation>`

Readers find an entry by its identity fields, never by parsing the key. A
writer that meets a key in another form rewrites it.

### Invariants

1. A path is in at most one entry's `copies`. Paths compare by filesystem
   identity (case on a case-insensitive volume), as v1 does. A path that
   exists compares by its device and inode. One that doesn't compares by its
   nearest existing parent, resolved on disk, then the rest of the path,
   folded to lower case only when that parent's volume ignores case.
2. `base.hash` is in `known`, and every record written by a pull, upgrade, or
   push is in `known`.
3. A `builtin` entry's identity has no server. The server of a Cloud-delivered
   version is `base.server`.
4. An entry with no copies is removed, except a `cloud` entry, which stays
   so that `skills_move()` can attach a copy to it later.

### Known hashes

`known` is stored, so offline pulls and project-token pulls can recognize
older versions. Each sync that changes an entry merges the source's known
hashes into it. Sources supply known hashes as follows:

- Package skills: `skill-history.json` in each package. v1 lists SHA-256 of
  SKILL.md bytes. v2 lists bundle hashes, per variant:
  `{"schema": 2, "skills": {"framework-data": {"r": ["…"]}}}`. Every shipped
  built-in is SKILL.md only (`.framework-skill.json` is excluded from the
  hash), so the generator computes the bundle hash from each historical
  SKILL.md. R regenerates its file with `data-raw/skill_history.R`, Python with
  `scripts/skill_history.py`, and `fw` adds one for its Stata skills.
- Cloud skills: the setup's `sync.hash`, the latest version's hash when one is
  fetched, `sync.known_hashes` when Cloud sends it (see "Cloud API"), and the
  `known_hashes` of any `GET /api/v1/skills/sync/{id}` snapshot the command
  reads (the latest version, or a skill fetched by its own identity).
  `GET /api/v1/skills/sync/{id}/history?variant=` already returns every
  version's hash and may be used when a user token is present.
- Inline skills: the setup's current hash only.

## Copy states

The planner gives each copy one state. `S` is the source for the copy's
entry `E`, or none.

For a path in `E.copies` (tracked):

| State | Condition |
|---|---|
| `unreadable` | The folder exists but is not a valid skill (no SKILL.md, a symlink, an oversized file) |
| `gone` | Absent, and its parent folder is absent too |
| `absent` | Absent, and its parent folder exists |
| `current` | Disk hash equals `S.hash`, and `S` is not older than `E` |
| `clean` | Disk hash equals its record |
| `edited` | Anything else, including a revert to a known older hash |

For a configured path that no entry tracks (untracked), used only when the
setup names the skill:

| State | Condition |
|---|---|
| `unreadable` | As above |
| `new` | Absent (its folder need not exist; pull creates an enabled assistant's folder) |
| `loose` | Present, and `E` already tracks at least one copy |
| `current` | Disk hash equals `S.hash` |
| `clean` | Disk hash is in `E.known` or `S.known` (installed before the lock) |
| `edited` | Anything else |

`S` is **older** than `E` when:

- both are on the `cloud` channel for the same identity, the same server
  delivered both (`S.server == E.base.server`), and `S.version <
  E.base.version` (as after a push, then a pull without a login). Versions
  from different servers don't compare: such a source is not older. Or
- both are on the `package` channel and `E.base.hash` is not in `S.known`
  (the copy came from a newer package).

## Planner

One pure function. It reads no files and makes no requests. The command
gathers its inputs, calls it, shows or applies its actions, and saves its lock.

### Inputs

- `disk`: path → hash, `ABSENT`, or `UNREADABLE`, for every path the planner
  may ask about; and `folder_exists(dir)`.
- `lock`: the lock after `migrate()`.
- `offer`:
  - `source`: `cloud` (the setup was read) or `package` (offline fallback, or
    upgrade).
  - `skills`: setup sources, in setup order. Each has `name`, `identity`,
    `channel`, `version`, `hash`, `known`, `server`, and `bundle`. The
    planner reads only whether `bundle` is null (the package does not ship
    the skill).
  - `by_identity`: sources fetched for lock entries by their own identity
    (key → source). Pull fetches these, with a login, only for `cloud`
    entries all of whose copies are absent.
  - `remote`: for push, the Cloud head per entry key (`version`, `hash`), or
    absent when Cloud has no such skill (a built-in Cloud never published).
- `options`: `command` (`pull`, `upgrade`, `copy`, `push`, `move`), `dirs`
  (the enabled assistants' skills folders, `.agents/skills` when none),
  `overwrite`, `force`, `dry_run`, `offline`, and `scope` (`all`, or
  `builtin` for upgrade).

### Outputs

- `steps`: one per copy: `path`, `entry` (key), `action`, `status`, `reason`,
  `hint`. Actions:
  - `none`: nothing written.
  - `write`: install `S.bundle` at the path. `backup` is true when a folder is
    there.
  - `copy`: install the bundle of sibling copy `from` at the path.
  - `record`: no file written; the lock changes.
  - `move`: rename the folder (move only).
  - `push`: send the copy's bundle to Cloud (push only, one request per
    entry).
- `rows`: the steps grouped into result rows (see "Rows").
- `lock_after`: the lock if every action succeeds.

`dry_run` does not change the plan. The command applies nothing and saves
nothing.

### Pseudocode

The pseudocode uses Python syntax. `plan.step()` appends one step.
`all_rows(plan, key, copies, status, reason, hint)` gives each listed copy a
`none` step with that status. `hint(key, …)` builds a hint object.

```python
def plan_pull(disk, lock, offer, opt):
    plan = Plan(lock_after=copy(lock))
    accounted = set()                       # paths a step already covers

    for S in offer.skills:
        key = key_of(S.identity)
        E = lock.skills.get(key)            # by identity only, never by name or path
        extra = []
        for d in opt.dirs:
            p = d + "/" + S.name
            if alias(p) in claimed and claimed[alias(p)] != p:
                raise PlanError("paths_alias", path=p)   # two setup names, one folder on this volume
            claimed[alias(p)] = p
            owner = owner_of(lock, p)       # filesystem identity
            if owner == key:
                continue                    # planned as one of E's copies
            if owner is not None:
                accounted.add(p)
                if disk[p] is ABSENT:
                    continue                # the owner's entry plans it (restored or missing)
                O = lock.skills[owner]
                other_variant = (O.identity.kind == S.identity.kind
                                 and O.identity.skill_id == S.identity.skill_id
                                 and O.identity.server == S.identity.server   # cloud only
                                 and O.identity.variant != S.identity.variant)
                # skills_move() switches O's whole entry, and refuses an
                # identity the lock already tracks: hint only when it works
                movable = len(O.copies) == 1 and E is None
                plan.step(p, owner, "none", "kept",
                          "other_variant" if other_variant else "other_identity",
                          hint("retarget", path=p, identity=S.identity) if movable else None)
                plan.kept_paths.add(p)
                continue
            extra.append(p)
        plan.planned.add(key)
        plan_entry(plan, key, E, S, extra, disk, opt, offer)
        accounted |= set(E.copies if E else []) | set(extra)

    for key, E in lock.skills.items():
        if key in plan.planned or (opt.scope == "builtin" and E.identity.kind != "builtin"):
            continue
        plan_unlisted(plan, key, E, offer.by_identity.get(key), disk, opt)
        accounted |= set(E.copies)

    if offer.source == "cloud" and opt.command == "pull":
        for d in opt.dirs:
            for name in skill_folders(disk, d):
                p = d + "/" + name
                if p not in accounted:
                    plan.step(p, None, "none", "removed", "not_in_setup")
    return plan


def plan_entry(plan, key, E, S, extra, disk, opt, offer):
    E = E or Entry(identity=S.identity, base=None, known=set(), copies={})
    C = sorted([state_tracked(p, E, S, disk) for p in E.copies] +
               [state_untracked(p, E, S, disk) for p in extra], key=path)   # byte order, always

    if any(c.state == "unreadable" for c in C):
        return all_rows(plan, key, C, "failed", "unreadable")

    if S.bundle is None:                    # the package doesn't ship it (fw for R skills)
        return all_rows(plan, key, C, "unavailable", "not_shipped")

    # The package's copy (offline, or upgrade) never writes over a built-in
    # tracked on Cloud. A Cloud setup that names the package copy may.
    if offer.source == "package" and E.base and E.base.channel == "cloud":
        if opt.offline:
            return all_rows(plan, key, C, "unavailable", "offline")
        return all_rows(plan, key, C, "kept", "cloud_tracked")

    older = is_older(S, E)
    present = [c for c in C if c.state in ("current", "clean", "edited")]
    edited  = [c for c in present if c.state == "edited"]
    holes   = [c for c in C if c.state in ("absent", "new")]
    for c in C:
        if c.state == "loose":              # copy from a tracked copy, else move a gone one here
            src = first_tracked(present)
            gone = first_gone(C)
            plan.step(c.path, key, "none", "untracked", "untracked",
                      hint("copy", from_=src, to=[c.path]) if src else
                      hint("move", from_=gone, to=c.path) if gone else None)
        if c.state == "gone":
            plan.step(c.path, key, "none", "missing", "folder_gone",
                      hint("move", from_=c.path, to=loose_twin(C, c)) if loose_twin(C, c) else None)

    if edited:
        differ = len({c.disk for c in present}) > 1
        if differ:
            src = edited[0].path if len(edited) == 1 else None    # None: the person picks
            return all_rows(plan, key, present + holes, "diverged", "copies_differ",
                            hint("copy", from_=src, to=others(present + holes, src),
                                 pick=src is None))
        if holes and (older or not opt.overwrite):
            return all_rows(plan, key, present + holes, "diverged", "copy_absent",
                            hint("copy", from_=edited[0].path, to=paths(holes)))
        if older:                           # overwrite never moves to an older version
            for c in present: plan.step(c.path, key, "none", "edited", "newer_in_project")
            return
        if not opt.overwrite:
            for c in present:
                plan.step(c.path, key, "none", "edited", "local_edits", hint("overwrite"))
            return
        for c in present:
            if c.state == "current": plan.step(c.path, key, "record", "current")
            else: plan.step(c.path, key, "write", "replaced", "replaced_edits", backup=True)
        for c in holes:
            plan.step(c.path, key, "write", added_or_restored(c))
        return finish(plan, key, E, S)

    # Unedited copies at different versions (a pull that wrote only some of
    # them): update only to a source that knows every version they hold
    disks = {c.disk for c in present}
    if len(disks) > 1 and (older or not disks <= set(S.known) | {S.hash}):
        return all_rows(plan, key, present + holes, "diverged", "copies_differ",
                        hint("copy", from_=None, to=paths(present + holes), pick=True))

    if older:
        # present copies all hold one version here; prefer the one at base.hash
        src = first([c for c in present if c.disk == E.base.hash]) or first(present)
        for c in present:
            plan.step(c.path, key, "none", "current", "newer_in_project")
        for c in holes:
            if src: plan.step(c.path, key, "copy", added_or_restored(c), from_=src.path)
            else:   plan.step(c.path, key, "none", "unavailable", "setup_older", hint("login"))
        return finish(plan, key, E, None)    # copies recorded; base unchanged

    for c in present:
        if c.state == "current":
            record = E.copies[c.path].hash if c.path in E.copies else None
            stale = record != S.hash or E.base != base_of(S)
            plan.step(c.path, key, "record" if stale else "none", "current")
        else:
            plan.step(c.path, key, "write", "updated", backup=True)
    for c in holes:
        plan.step(c.path, key, "write", added_or_restored(c))
    return finish(plan, key, E, S)


def added_or_restored(c):
    return "restored" if c.state == "absent" else "added"   # tracked absent vs new folder


def finish(plan, key, E, S):
    """lock_after for one entry, when any of its steps writes, copies, or records."""
    steps = plan.steps_for(key)
    if not any(s.action in ("write", "copy", "record") for s in steps):
        return
    F = copy(E)
    for s in steps:
        if s.action in ("write", "record"): F.copies[s.path] = {"hash": S.hash}
        if s.action == "copy":              F.copies[s.path] = {"hash": E.copies[s.from_]["hash"]}
    if S is not None:
        F.base = base_of(S)
        F.known = sorted(set(E.known) | set(S.known) | {S.hash})
        F.pending = None
    plan.lock_after.skills[key] = F
```

`plan.planned` holds the keys of setup skills: an entry is planned by
`plan_entry` exactly when it is a setup skill's identity. Every other entry,
including one that owns a folder a setup skill reported as `kept`, goes
through `plan_unlisted`, so its own state (diverged, missing, restored) is
still reported. Such a folder then has two steps, `kept` and the owner's, and
is never also `removed`.

A folder another entry tracks is `kept` only while it holds a copy. When the
owner's copy there is absent, the setup skill does not claim the path; the
owner's entry plans it, so a deleted copy of your fork is restored by its own
identity (or reported `missing` with a `login` hint), never replaced by the
built-in the setup names.

`other_variant` needs the same skill ID and a different variant. The same ID
on another server is `other_identity`.

`plan_unlisted` covers a lock entry the setup does not name:

```python
def plan_unlisted(plan, key, E, S, disk, opt):
    C = [state_tracked(p, E, S, disk) for p in E.copies]
    if any(c.state == "unreadable" for c in C):
        return all_rows(plan, key, C, "failed", "unreadable")
    if opt.offline:
        return all_rows(plan, key, C, "unavailable", "offline")
    present = [c for c in C if c.state in ("current", "clean", "edited")]
    holes = [c for c in C if c.state == "absent"]
    if not present:
        if S is not None and holes:        # fetched by its own identity
            for c in C:
                plan.step(c.path, key, "write" if c in holes else "none",
                          "restored" if c in holes else "missing",
                          None if c in holes else "folder_gone")
            return finish(plan, key, E, S)
        return all_rows(plan, key, C, "missing", "all_gone",
                        hint("login") if E.identity.kind == "cloud" else None)
    edited = [c for c in present if c.state == "edited"]
    differ = len({c.disk for c in present}) > 1
    if edited and (differ or holes):
        src = edited[0].path if len(edited) == 1 else None
        return all_rows(plan, key, present + holes, "diverged",
                        "copies_differ" if differ else "copy_absent",
                        hint("copy", from_=src, to=others(present + holes, src), pick=src is None))
    for c in C:
        # A folder a setup skill reported as kept is not also removed
        if in_dirs(c.path, opt.dirs) and c.path not in plan.kept_paths:
            plan.step(c.path, key, "none", "removed", "not_in_setup")
```

Upgrade applies `write`, `copy`, and `record` steps (a project whose copies
are already current but has no lock gets one). A lock it can't read
(`lock_schema_unsupported`, `lock_migrate_conflict`) stops `upgrade()` before
it writes anything.

Upgrade calls `plan_pull` with `offer.source = "package"`, the package
skills for the project type, `scope = "builtin"`, and its own `dirs` (v1:
the assistants' folders plus `.agents/skills` when it exists). It ignores
`removed` steps. The offline fallback of pull calls `plan_pull` with
`offer.source = "package"` and `offline = true`.

### Copy

```python
def plan_copy(disk, lock, from_dir, to_dirs, names, opt):
    for t in to_dirs:
        for n in names:
            src, dst = from_dir + "/" + n, t + "/" + n
            if disk[src] is ABSENT:      raise PlanError("copy_source_missing", path=src)
            if disk[src] is UNREADABLE:  raise PlanError("copy_source_unreadable", path=src)
            if disk[dst] is UNREADABLE:  raise PlanError("copy_target_unreadable", path=dst)
            E = owner_of(lock, src); D = owner_of(lock, dst)
            if D is not None and E is not None and D != E:
                raise PlanError("copy_target_owned", path=dst)
            same = disk[dst] == disk[src]
            plan.step(dst, E, "none" if same else "copy", "current" if same else "copied",
                      from_=src, backup=disk[dst] is not ABSENT)
            if E is not None:            # tracked source: the target joins its entry
                plan.lock_after.skills[E].copies[dst] = {"hash": lock.skills[E].copies[src]["hash"]}
        if names_is_all:
            for n in skill_folders(disk, t) - set(names):
                plan.step(t + "/" + n, None, "none", "missing")
```

A copy onto a folder another entry tracks is refused (`copy_target_owned`)
only when the source is tracked too. An untracked source may be copied onto a
tracked folder: that is how a hand-made copy is adopted, and the lock stays as
it is.

The target takes the source copy's record. An edited source makes an edited
target, so push still sees the skill as edited and pull keeps both copies as
`edited`. An untracked source changes no lock entry.

### Push

```python
def plan_push(disk, lock, offer, opt):
    for key, E in lock.skills.items():
        C = [state_tracked(p, E, None, disk) for p in E.copies]
        if any(c.state == "unreadable" for c in C):
            step_all(key, C, "failed", "unreadable"); continue
        present = [c for c in C if c.state in ("clean", "edited")]
        if not present:
            m = twins_of_entry(key)      # matches of its absent copies (see "Twin rule")
            step_all(key, C, "missing", "folder_gone" if m else "all_gone",
                     hint("move", from_=m[0].from_, to=m[0].to) if unique(m) else None); continue
        edited = [c for c in present if c.state == "edited"]
        if not edited:
            continue                                     # nothing to push
        differ = len({c.disk for c in present}) > 1
        if differ or any(c.state == "absent" for c in C):
            absent = [c for c in C if c.state == "absent"]
            m = twins_of_copy(absent[0].path) if not differ and len(absent) == 1 else []
            step_all(key, C, "failed", "copies_differ" if differ else "copy_absent",
                     hint("move", from_=m[0].from_, to=m[0].to) if unique(m) else
                     hint("copy", from_=edited[0].path if len(edited) == 1 else None, ...)); continue
        local = present[0].disk
        R = offer.remote.get(key)
        if R is not None and R.hash == local:
            step_all(key, C, "record", "current")        # Cloud already has it: adopt
        elif E.identity.kind == "builtin":
            step_all(key, C, "push", "pushed", fork=True)   # becomes your own skill
        elif E.base is None and E.pending is not None and not opt.force:
            # a first push that stopped before Cloud replied may have reached it
            step_all(key, C, "none", "refused", "first_push_pending", hint("force"))
        elif E.base is None:
            step_all(key, C, "push" if opt.force else "none",
                     "pushed" if opt.force else "refused", None if opt.force else "no_base",
                     None if opt.force else hint("force"))
        elif R is None or R.version == E.base.version:
            step_all(key, C, "push", "pushed")
        else:
            step_all(key, C, "push" if opt.force else "none",
                     "pushed" if opt.force else "refused", None if opt.force else "cloud_changed",
                     None if opt.force else hint("force"))
    for p in untracked_folders(disk, lock, opt.dirs):
        m = twins_of_folder(p)       # absent copies of any entry it matches by name or bytes (see "Twin rule")
        step(p, None, "none", "untracked", "untracked",
             hint("move", from_=m[0].from_, to=p) if unique(m) else
             None if m else hint("sync", path=p))
```

After a push, the lock entry takes the response: `base = {cloud, hash,
version, server}`, the record of every copy whose disk hash, read again just
before the lock is saved, equals the pushed hash = the pushed hash (a copy whose folder is gone keeps its own record),
`known += hash`,
and `pending` cleared. A pushed built-in becomes a `cloud` entry under the
response's `skill_id` (a new key) whose `known` is only the pushed hash: the
built-in's versions are not versions of the fork. `confirm = FALSE` turns
every `pushed` step into `cancelled`.

When Cloud's head already holds the local bytes (pushed from another
checkout), nothing is sent. The steps are `record` with status `current`, and
the entry adopts Cloud's head as for a push: `base = {cloud, hash, version,
server}`, every record = that hash, `known += hash`, with the same rule for which copies take the record. The
row is `current`
with no reason code. A push request that fails (network, a refused reply)
makes its entry's steps `failed` with no reason code; the prose names the
error. The same holds when Cloud can't be asked at all: an entry whose Cloud
identity is on another server than the project's fails, with no hint, where
the plan would push, adopt, or refuse it.

Twin rule (push only): an untracked folder in a configured folder is a
hand-moved copy of an absent copy of any entry (whether or not the entry
still has other copies) when it has that copy's name (moved to another
folder) or holds that copy's recorded bytes (renamed, in the same folder or
another). A match is unique when it is that copy's only match and that
folder's only match.

- The folder's `untracked` row gets a `move` hint from the copy to the folder
  on a unique match, no hint when it has several matches, and the `sync`
  hint only when it has none.
- An entry with no copy left gets `missing` (`folder_gone`) with the same
  `move` hint when it has exactly one match and that match is unique, with no
  hint when it has several, and `missing` (`all_gone`) when it has none. This
  holds whether or not the old parent folder still exists.
- An entry with copies left keeps its row. One exception: when it fails with
  `copy_absent` and its one absent copy has a unique match, the hint is that
  `move` instead of a `copy` over the absent copy.

The prose for a match with no hint says to record the move with
`skills_move()`. Only a folder with
no match gets the `sync` hint, so a moved copy is never offered as a new
Cloud skill. Pull never gives the `sync` hint: an untracked folder the setup
doesn't name is `removed`. Pull applies it only when the old
parent folder is gone; while it exists, pull restores the absent copy (see
"Accepted limits"), and the twin stays `untracked` with a `copy` or `move`
hint as above.

Push plans under no lock while it waits for confirmation. Under the sync
lock, before sending or saving, it reads the lock again; if the lock changed
since planning (another command ran), it stops with `lock_changed` and the
person runs the push again.

### Move

```python
def plan_move(disk, lock, from_, to, identity, opt):
    # from_ and to: a skill path, or a skills folder (each tracked copy under it moves)
    pairs = expand(lock, from_, to)
    for src, dst in pairs:
        E = owner_of(lock, src)
        if E is None:                       raise PlanError("move_untracked", path=src)
        # a destination with a record, even in the same entry, is never overwritten
        if owner_of(lock, dst) is not None and alias(dst) != alias(src):
            raise PlanError("move_target_owned", path=dst)
        if disk[src] is not ABSENT and disk[dst] is not ABSENT:
            raise PlanError("move_target_exists", path=dst)
        if disk[src] is ABSENT and disk[dst] is ABSENT:
            raise PlanError("move_nothing", path=src)
        action = "move" if disk[src] is not ABSENT else "record"   # record: already moved on disk
        plan.step(dst, E, action, "moved", "path_moved" if action == "move" else "lock_moved")
        record = lock_after.skills[E].copies.pop(src)    # the input lock is never changed
        lock_after.skills[E].copies[dst] = record
    if identity:                            # retarget one entry
        E = entry_for(from_)
        new_key = key_of(identity)
        if new_key in lock.skills:          raise PlanError("move_identity_exists", key=new_key)
        E = lock_after.skills[key]          # after the moves above
        # a moved copy's bytes: at dst, or at src when this move hasn't renamed it yet
        bytes = lambda p: disk[p] if disk[p] is not ABSENT else disk[src_of(p)] if p in moved else ABSENT
        clean = {r.hash for p, r in E.copies.items() if bytes(p) == r.hash}
        F = Entry(identity=identity, base=None, known=sorted(clean), copies=E.copies)
        lock_after.skills.pop(key); lock_after.skills[new_key] = F
        # a moved copy has two steps: path_moved or lock_moved under the old
        # key (above), then retargeted under the new key
        for p in sorted(E.copies): plan.step(p, new_key, "record", "moved", "retargeted")
```

A retargeted entry keeps its records. Its unedited copies stay unedited
(their hashes go into `known`), so the next pull updates them to the new
identity's version. Its edited copies stay edited, and push refuses them
(`no_base`) until `force = TRUE`. When a rename or the lock save fails,
`skills_move()` undoes the renames it made, newest first, and names any it
could not undo. Move refuses errors before any write and
writes nothing in a dry run.

API:

- R: `skills_move(from, to = NULL, skill_id = NULL, variant = NULL,
  builtin = NULL, project_path = ".", dry_run = FALSE)`. `from` and `to` are
  paths or assistant folder names (`"claude"`, `"agents"`), as in
  `skills_copy()`. `builtin = "framework-data"` retargets to a built-in.
- Python: `skills_move(from_, to=None, *, skill_id=None, variant=None,
  builtin=None, project_path=".", dry_run=False)`.
- Go: `fw skills move <from> [<to>] [--id ID] [--variant V] [--builtin NAME]
  [--dry-run] [--json]`.

### Rows

Steps become result rows as in v1:

- Pull, upgrade, and push: one row per lock entry, plus one row per
  `untracked`, `kept`, or `removed` step.
- Copy and move: one row per step.
- A row's status is the first of its steps' statuses in this order:
  `failed`, `diverged`, `missing`, `unavailable`, `kept`, `untracked`,
  `edited`, `replaced`, `updated`, `restored`, `added`, `current`. Its reason
  and hint come from the first step (in path order) with that status. Push
  rows hold one status, since push treats an entry's copies as one.
- A row's `name` is the setup name, else the basename of its first path.
  `paths` are sorted by byte value.

### Apply

The command applies steps in path order under the sync lock:

1. Before each `write` or `copy`, it hashes the copy again. A copy that
   changed since planning is left alone and its step becomes `edited`
   (`changed_during_pull`).
2. It installs with the v1 installer (backup to
   `.framework/skills-backups/`). One change: a rollback never deletes a copy
   it wrote, since the copy may hold an edit made after the write. It moves
   that copy to `.framework/skills-backups/` and names it in the error.
3. It saves `lock_after`, adjusted for declined steps: a declined copy keeps
   its old record, and its entry keeps its old `base` while `known` still
   gains the source's hashes. Per-copy records keep this lock accurate after
   a partial write.
4. A lock that comes out unchanged is not rewritten.

`pull_all()` / `fw pull` applies a plan when any step's action is not
`none`, so a `record`-only plan (a metadata update) is applied.

## Migration from v1

`migrate()` is pure and runs on every read. A v1 lock is never rejected for
its age.

1. Map each v1 entry on its own:

   | v1 entry | v2 identity | v2 base |
   |---|---|---|
   | `skill_id` starts with `framework:` | `builtin`, that ID, `variant` | `cloud`, `hash`, `version`, `server` |
   | other `skill_id` | `cloud`, `server`, `skill_id`, `variant` | `cloud`, `hash`, `version`, `server` |
   | no `skill_id`, `origin.skill_id` `framework:<n>` | `builtin`, `framework:<n>`, `variant` | `package`, `origin.hash`, null, null |
   | neither | `local`, `variant` | null |

   `variant` defaults to `r`.
2. Every path gets its own v1 entry's `hash` as its record. A v1 entry without `hash`
   gets records equal to `origin.hash`; with neither, no record (its copies
   classify as `edited`).
3. `known` is `{hash, origin.hash}` without nulls. The package history and
   Cloud known hashes join it at the next sync.
4. `pending` is copied unchanged.
5. Keys are rebuilt from identities. v1 entries that map to one key merge
   (copies and known joined) when their bases are equal and at most one has
   `pending`. Otherwise (a package copy and a Cloud copy of one built-in, or
   two Cloud versions of one skill) the command stops with
   `lock_migrate_conflict`, naming both v1 keys, and writes nothing. The
   person deletes the entry for the copy they don't keep. This replaces v1's
   merge, which gave every path the winning entry's hash.

A non-dry-run command that changes the lock saves it as v2. A command that
changes nothing leaves a v1 file as it is.

### Old clients

All three v1 readers reject `schema != 1` with no upgrade advice:

- R `.skill_load()`: `Unsupported skill lock file` (stop).
- Python `_load()`: `ValueError("Unsupported skill lock file")`.
- Go `load()`: `unsupported skill lock file`.

The lock is committed, so a teammate on an older version hits this after the
first v2 write. Two steps:

1. Ship a patch release in each language before v2 that reads `schema` first
   and, for any value above 1, stops with: "This project's skills lock
   (.framework/skills.lock.json) uses schema 2. Update framework to 2.1.0 or
   later." (framework-py and fw name their own package and version.)
2. v2 readers reject `schema > 2` with the same message and error code
   `lock_schema_unsupported`.

## Vocabulary

Pull, upgrade, and pull_all keep the v1 statuses: `added`, `restored`,
`updated`, `current`, `edited`, `replaced`, `diverged`, `missing`, `removed`,
`unavailable`, `failed`, `kept`, `untracked`. Push keeps `pushed`, `refused`,
`missing`, `untracked`, `cancelled`, `failed`, and adds `current` for an
entry whose edited bytes Cloud already has. Copy keeps `copied`, `current`,
`missing`.

One status is new: `moved`, for `skills_move()`. No existing word fits a path
or identity change.

Rows keep `reason` (prose) and `hint` (the exact command). v2 adds two
machine fields every language must produce: `reason_code` and `hint_key`
(with hint arguments). Prose stays per language. Scenarios compare codes and
keys only.

### Reason codes

| Code | Status | Meaning |
|---|---|---|
| `local_edits` | edited | Edited copy kept |
| `replaced_edits` | replaced | Edited copy backed up and replaced |
| `newer_in_project` | current, edited | The project holds a newer version than the source |
| `copies_differ` | diverged, failed | Present copies differ and at least one is edited |
| `copy_absent` | diverged, failed | A copy is absent beside an edited one |
| `other_identity` | kept | The folder tracks another identity |
| `other_variant` | kept | The folder tracks the same skill ID in another variant |
| `cloud_tracked` | kept | Upgrade: a built-in tracked on Cloud |
| `untracked` | untracked | A copy no entry tracks, beside tracked copies |
| `folder_gone` | missing | A tracked copy's parent folder is gone |
| `all_gone` | missing | Every tracked copy is absent and no source can restore it |
| `not_in_setup` | removed | The setup no longer names it |
| `offline` | unavailable | Cloud was not reached |
| `not_shipped` | unavailable | The package does not ship it |
| `setup_older` | unavailable | No copy left and the only source is older than the project |
| `unreadable` | failed | A copy is not a valid skill |
| `changed_during_pull` | edited | Changed between plan and write (apply only) |
| `cloud_changed` | refused | Cloud moved since the base |
| `no_base` | refused | The entry has no base (after a retarget) |
| `first_push_pending` | refused | A first push stopped before Cloud replied; it may be on Cloud. Check Cloud, then `skills_sync(path, skill_id =)` or `force` |
| `cancelled` | cancelled | Push not confirmed |
| `path_moved`, `lock_moved`, `retargeted` | moved | Move |

Success rows (`added`, `restored`, `updated`, `current`, `copied`, `pushed`)
have no code, except `current` with `newer_in_project`.

### Hint keys

| Key | Arguments | R | Python | Go |
|---|---|---|---|---|
| `overwrite` | | `pull_skills(overwrite = TRUE)` | `pull_skills(overwrite=True)` | `fw skills pull --overwrite` |
| `copy` | `from`, `to[]`, `pick` | `skills_copy(…)` per target | `skills_copy(…)` | `fw skills copy …` |
| `move` | `from`, `to` | `skills_move(from, to)` | `skills_move(from_, to)` | `fw skills move FROM TO` |
| `retarget` | `path`, `identity` | `skills_move(path, skill_id =, variant =)` | same | `fw skills move PATH --id --variant` |
| `force` | | `push_skills(force = TRUE)` | `push_skills(force=True)` | `fw skills push --force` |
| `sync` | `path` | `skills_sync(path)` | `skills_sync(path)` | `fw skills sync PATH` |
| `login` | | `cloud_login()` | `cloud_login()` | `fw login` |

`pull_all` and `push_all` render `overwrite` and `force` with their own
names. A `copy` hint uses folder names when both folders are assistant
folders, else directories. `pick: true` means the person chooses which copy
to keep; the prose names each alternative.

## Follow-up items

R (`framework`):

- **`overwrite` fills a new assistant folder with the shipped copy and
  replaces the edited one.** Kept as agreed. v2 applies it the same way to
  every identity (same identity, source not older). The edited copy is backed
  up and the row reason says so. See open question 2.
- **No way to switch a copy's identity or variant.** `skills_move()` with
  `skill_id`, `variant`, or `builtin`.
- **Inline setup content can replace a copy tracked as a `framework:` Cloud
  built-in.** Inline content is its own identity (`inline:<name>`), so the
  folder is `kept` (`other_identity`).
- **An offline pull leaves custom Cloud skills out of the report.** Unlisted
  entries are planned offline too and reported `unavailable` (`offline`).
- **`upgrade()` can write into a diverged skill.** Upgrade calls `plan_pull`,
  which judges an entry's copies together.

Python (`framework-py`):

- **A tracked skill's variant can switch from python to r.** Variant is part
  of the identity. The folder is `kept` (`other_variant`) with a `retarget`
  hint.
- **An offline pull leaves out personal skills.** As in R.
- **`upgrade()` can refill a diverged skill.** As in R. (Python main already
  checks entry problems before upgrading; v2 replaces that check.)
- **An inline skill has no baseline hash.** Inline skills get an `inline`
  entry with records.
- **A skill removed from the setup whose copies diverged is listed as removed
  with no hint.** `plan_unlisted` reports `diverged` with a `copy` hint.
- **`pull_all()` skips a metadata-only update.** It applies any plan with a
  non-`none` action; metadata updates are `record` steps.
- **The untracked row's adopt hint can't name a copy outside the assistant
  folders.** The `copy` hint carries paths; rendering uses `from_dir` and
  `to_dir` when either folder is not an assistant folder.
- **`push_all(dry_run=True)` leaves `failed` empty.** `failed` is built from
  the plan's rows, which are the same in a dry run. Command-level; one
  scenario covers it.

Go (`fw`):

- **An ordinary pull overwrites a local revert of a personal skill.** A
  tracked copy is unedited only when it equals its record. A revert to a known
  hash is `edited`.
- **An offline pull leaves personal Cloud skills out of its report.** As in R.
- **`--overwrite` with a new assistant folder replaces an edited package
  skill.** Kept as agreed (see R).
- **After an assistant switch, pull overwrites an independent same-named
  copy.** Already fixed on the copy branch. v2 keeps it: setup skills find
  entries by identity, and a folder another entry tracks is `kept`.
- **After `.claude` → `.agents`, push lists the moved copies as untracked with
  a bare `fw skills sync PATH` hint.** Push and pull detect an entry whose
  copies' folders are gone next to an untracked folder of the same name and
  give the `move` hint on both rows.

## Cloud API

v2 works with the current API. One addition is recommended, and the spec
schemas (`layer.v1.json`, `layers.v1.json`, `spec.v1.json`) already accept it
as an optional `sync.known_hashes` array of hashes:

- `sync.known_hashes` in each setup layer entry (`Skill::layerEntry()`) and
  `known_hashes` in the snapshot (`SkillSyncController::snapshot()`): the
  bundle hash of every version of the skill for that variant, oldest first.
  Today the setup carries only `sync.hash`, and only
  `GET /api/v1/skills/sync/{id}/history` (user token) lists older hashes. With
  the field, a project-token pull recognizes an older unedited copy that has
  no record (a project created before the lock, or a copy restored from git).
  Without it, such a copy is `edited` and the person runs pull with
  `overwrite`.

No other change. Push responses already include `skill_id`, `version`, and
`hash`, and a fork gets its new `skill_id` from the response.

## Scenarios

`inst/conformance/skills/` holds 88 language-neutral cases. Python and Go
copy them with their existing asset sync (`scripts/sync_assets.py`,
`tools/syncassets`), pinned to an R tag, beside the other conformance
fixtures. The README there defines the format.

## Errors

A command stops before writing anything with one of these codes:

| Code | When |
|---|---|
| `lock_schema_unsupported` | The lock's schema is above 2 |
| `lock_migrate_conflict` | Two v1 entries map to one identity with different versions |
| `paths_alias` | Two setup names are one folder on this volume (a case alias) |
| `copy_target_owned` | `skills_copy()` onto a folder another tracked skill owns |
| `copy_source_missing` | `skills_copy()` of a skill not in the source folder |
| `copy_source_unreadable` | `skills_copy()` of a source folder that isn't a valid skill |
| `copy_target_unreadable` | `skills_copy()` onto a folder that isn't a valid skill |
| `lock_changed` | The lock changed between a push's plan and its send (push and `push_all()`) |
| `move_target_exists` | `skills_move()` onto a folder that exists |
| `move_target_owned` | `skills_move()` onto a path the lock already tracks, in any entry |
| `move_nothing` | Neither the source nor the destination exists |
| `move_untracked` | The source isn't tracked |
| `move_identity_exists` | A retarget to an identity the lock already tracks |

These are rare states. Each stops rather than guess, and its message says
what to run.

## Accepted limits

- **A deleted or rewound lock loses provenance.** Without a lock, a copy
  whose bytes are a known version counts as unedited (`clean`), so a
  deliberate revert to a shipped version is updated, with a backup
  (`pull-adopt-known-before-lock`). A lock rewound to an older state does the
  same (`pull-rewound-lock-revert`).
- **A deleted copy is restored while its folder exists.** Pull treats a
  tracked copy that is absent beside its existing parent folder as missing,
  not removed, and installs it again (`restored`). To stop tracking a skill,
  remove it from the setup or the lock, not just its folder. A copy whose
  whole assistant folder is gone is never recreated.

## Open questions

Each question records the decision this design takes.

1. **A tracked copy absent next to clean siblings.** v1 calls this diverged.
   v2 restores it, since nothing edited would be lost. Recommendation:
   restore. An absent copy next to an edited one stays diverged.
2. **`overwrite` with an edited copy and a new folder.** Options: keep the
   agreed behavior (replace and fill), or fill the new folder from the edited
   copy. Recommendation: keep the agreed behavior. Revisit after v2 ships,
   when per-copy rows make the effect visible in dry runs.
3. **`overwrite` with copies that differ.** Recommendation: still diverged.
   The person picks a copy with `skills_copy()`. Overwrite never chooses
   between two edits.
4. **Automatic retarget of clean copies.** When the setup swaps a built-in
   for your fork and every copy is clean, pull could switch identity itself.
   Recommendation: no. Pull reports `kept` with a `retarget` hint. Only push
   (a fork) and `skills_move()` change an identity.
5. **Package and Cloud delivery of a built-in.** Recommendation: one
   identity, two channels. Cloud keeps some built-ins inline until clients
   ship them (`Skill::INLINE_PACKAGE_SKILLS`) and later sends `package: true`;
   one identity makes that switch a `record` step.
6. **When to rewrite a v1 lock.** Recommendation: only when a command changes
   the lock, which delays breaking older teammates.
7. **Size of `known`.** Package histories hold up to about ten hashes per
   skill. Recommendation: store all, no cap.
8. **Loose copies with known bytes.** A copy in a configured folder, untracked,
   beside tracked copies, whose bytes equal a known hash. Recommendation:
   `untracked`, never claimed. `skills_copy()` records it.
