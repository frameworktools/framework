# Framework docs sites: the common format (v1)

The R package, framework-py, fw, and the Stata package each publish a docs site from the same
input. framework-cloud renders them in one style at:

- `r.framework.pub` (product `r`)
- `py.framework.pub` (product `py`)
- `cli.framework.pub` (product `cli`)
- `stata.framework.pub` (product `stata`)

Each repository keeps its docs in `docs/site/`. A release attaches
`docs-site.tar.gz` to its GitHub release, and framework-cloud imports it.
`docs-reference.v1.json` is canonical in the R repository's
`inst/schema/` and is copied by the other repositories' asset syncs.

## The folder

```
docs/site/
  site.yml          # written by hand
  guides/*.md       # written by hand
  images/           # optional: png, jpg, svg, webp, or gif
  reference.json    # generated at release; not committed
```

### site.yml

```yaml
product: py                      # r, py, cli, or stata
title: Framework for Python
tagline: Structured data science projects in Python
repository: https://github.com/frameworktools/framework-py
install: uv add framework-py     # shown on the home page
sections:                        # in order: top-bar dropdowns and sidebar groups
  - id: getting_started
    title: Getting Started
  - id: features
    title: Features
  - id: reference
    title: Reference
    reference: true              # lists reference.json's categories
```

Every section is a dropdown in the top bar and a group in the sidebar. A
guides section lists its guides by `position`. Each item shows its title
with its `description` under it. The reference section lists the
categories from `reference.json`, each with its description. The product
switcher (R, Python, CLI, Stata) is the cloud's and needs nothing here.

### Guides

`guides/<id>.md` is CommonMark with GFM tables, plus front matter:

```markdown
---
id: data-management                 # URL-safe, unique in the product: /guides/{id}
title: Data Management
description: Managing data files with the declarative data catalog   # one line
section: features                   # a section id from site.yml
position: 3                         # order within the section
---
```

- Write h2 (`##`) and h3 (`###`) headings in the body. They build "On this
  page". The page title comes from the front matter, so the body has no h1.
- Every code fence names a language (`python`, `r`, `sh`, `yaml`, and so on).
- Callouts use GitHub alert syntax: `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`.
- Previous and next links follow the sections and positions.

### Links

Link targets use these forms in guides, in Markdown fields in
`reference.json`, and as `see_also` strings:

| Target | Form |
|--------|------|
| A guide in the same product | `guide:data-management` |
| A reference entry in the same product | `ref:data_read` |
| A heading on that page | `guide:data-management#saving-data` |
| Another product | `r:guide:setup`, `py:ref:data_read`, `cli:ref:project-bootstrap`, `stata:ref:fw_use` |
| Anything else | a full `https://` URL |

`ref:` takes the entry's `id`. framework-cloud rewrites these into URLs and
reports any target it can't find when it imports the archive. A plain
`see_also` string with no prefix is an entry name in the same product.

### Images

Images live in `docs/site/images/` and are linked relative to the guide:
`![The data catalog](images/catalog.png)`. Always write alt text.
framework-cloud serves them under `/images/`. Reference text may link them
the same way.

### reference.json

`reference.json` is generated at release time. It must validate against
`docs-reference.v1.json`, and it contains public entries only.

- Top level: `schema` (`"docs-reference.v1"`), `product`, `version`,
  `categories`, and `entries`.
- `categories`: `id`, `title`, `description` (one line), `position`, and
  `common` (entry names listed first).
- `entries`: `id`, `name`, `kind` (`function`, `class`, or `command`),
  `category`, and a one-line `summary` are required. The optional fields
  are:
  - `title`, `usage`, `description`, `details`, `returns`, and `note`
  - `parameters` (`name`, `type`, `default`, `required`, `env`, and
    `description`)
  - `sections` (with `subsections`)
  - `examples` (`title`, `code`, and `runnable`)
  - `see_also` (strings, or `{title, url}`)
  - `aliases`, `lifecycle` (`stable`, `deprecated`, or `experimental`),
    `replaced_by`, and `since`
- Text fields hold Markdown.

How each product fills `reference.json`:

- **R** fills it from roxygen through `docs_export()`:
  - `@description` goes to `description` and `@details` to `details`.
  - `\section` and `\subsection` go to `sections`.
  - `\dontrun` makes `runnable: false`.
  - Defaults come from the usage line, and there are no types.
- **Python** fills it from the exported functions and classes:
  - Google-style docstrings give `description` and `details`, and `Args:`
    gives `parameters`.
  - Type hints give `type`, and the signature gives `default`.
- **fw** fills it from its command tree:
  - Each command is an entry with `kind: command`. Its `id` replaces
    spaces with `-`, so `project bootstrap` becomes `project-bootstrap`.
  - Flags go to `parameters`, with `env` set when an environment variable
    sets the flag.

## The archive

`docs-site.tar.gz` has a single top folder, `docs-site/`, with `site.yml`,
`guides/`, `images/`, and the generated `reference.json`. The release
workflow builds it, checks `reference.json` against the schema, and
attaches it to the GitHub release. framework-cloud imports the newest
release of each product and builds the ⌘K search index from guide titles,
descriptions, and headings, and from reference names, summaries, and
parameters. Docs for older versions can come later.
