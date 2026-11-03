# Generates the project spec JSON Schemas in inst/schema/ from one definition.
#
#   inst/schema/spec.v1.json   resolved spec: what project_create() accepts
#   inst/schema/layer.v1.json  partial spec: one layer before spec_resolve()
#
# The layer schema is derived from the resolved schema: required fields are
# dropped, and map entries may be null (null removes the key when merging).
# Run from the package root:  Rscript data-raw/spec_schema.R
#
# Both files are consumed by framework-cloud (opis/json-schema) and the fw CLI
# (ajv), pinned to a framework release tag. Edit this file, not the JSON.

SPEC_VERSION <- 1L
BASE_URL <- "https://framework.pub/schema"

# Assistant table: which skills folder and stub file each assistant gets.
# Keep in sync with .ai_assistant_table() in R/ai_skills.R.
ASSISTANTS <- c("claude", "codex", "copilot")

str <- function(...) list(type = "string", ...)
bool <- function(...) list(type = "boolean", ...)
nullable <- function(s) list(anyOf = list(s, list(type = "null")))
obj <- function(properties, required = NULL, additional = FALSE, ...) {
  out <- list(type = "object", properties = properties, additionalProperties = additional, ...)
  if (length(required)) out$required <- as.list(required)
  out
}
map_of <- function(value, key_pattern = NULL, ...) {
  out <- list(type = "object", additionalProperties = value, ...)
  if (!is.null(key_pattern)) out$propertyNames <- list(pattern = key_pattern)
  out
}
arr <- function(items, ...) list(type = "array", items = items, ...)

KEY <- "^[a-z][a-z0-9_]*$"
REL_PATH <- "^(?!/)(?!.*(^|/)\\.\\.(/|$))[^\\\\]+$"
SKILL_NAME <- "^[a-z0-9]+(-[a-z0-9]+)*$"
ENV_NAME <- "^[A-Za-z_][A-Za-z0-9_]*$"

definitions <- list(
  package = obj(
    list(
      # Each engine accepts its own sources: R cran/github/bioc, Python pypi/github
      source = str(enum = list("cran", "github", "bioc", "pypi")),
      version = nullable(str()),
      repo = nullable(str()),
      ref = nullable(str()),
      auto_attach = bool()
    ),
    required = c("source", "auto_attach")
  ),
  extra_directory = obj(
    list(label = str(), path = str(pattern = REL_PATH)),
    required = c("path")
  ),
  file = obj(
    list(
      content = str(),
      template = bool(description = "Replace {{project_name}}, {{author}}, {{author_email}}, {{affiliation}}, and {{date}}")
    ),
    required = c("content")
  ),
  skill = list(oneOf = list(
    obj(list(package = list(const = TRUE)), required = c("package")),
    obj(
      list(
        content = str(minLength = 1, description = "Full SKILL.md text, including frontmatter"),
        files = map_of(str(), key_pattern = REL_PATH),
        bundle = arr(obj(list(path = str(), content = str(), executable = bool()), required = c("path", "content", "executable")), maxItems = 256),
        sync = obj(list(skill_id = str(), version = list(type = "integer", minimum = 1),
                        hash = str(pattern = "^[a-f0-9]{64}$"), variant = str(enum = list("r", "python", "stata")), server = str()),
                   required = c("skill_id", "version", "hash", "variant", "server"))
      ),
      required = c("content")
    )
  )),
  connection = obj(list(driver = str(minLength = 1)), required = c("driver"), additional = TRUE)
)
ref <- function(name) list(`$ref` = paste0("#/definitions/", name))

properties <- list(
  spec_version = list(const = SPEC_VERSION),
  name = str(minLength = 1),
  type = str(
    pattern = KEY,
    description = "A label for the blueprint the project came from. Framework's own are project, project_sensitive, course, presentation, and bare. Behavior follows settings, tools, and core_files, not this label."
  ),
  core_files = bool(description = "Whether the structure writes Framework's core files (starter scripts and .env). false for bare structures. Missing means true."),
  settings_layout = str(
    enum = list("split", "flat"),
    description = "split: connections, packages, and data in settings/*.yml. flat: everything in settings.yml. Missing means split for Framework's project and project_sensitive structures and flat for the rest."
  ),
  tools = map_of(bool(), key_pattern = KEY,
                 description = "Tool id -> on. Missing means off. Framework's tools are defined in inst/features/<id>.json. In a layer, later layers override earlier ones key by key."),
  language = str(
    enum = list("r", "python", "stata"),
    description = "Primary language. The R package builds r, the Python package builds python, and fw builds stata (scaffolding only). A layers file with no language means r."
  ),
  # orcid, url, and affiliations follow Quarto's author schema. affiliation
  # stays the plain-string summary (the first affiliation's name).
  author = obj(list(
    name = str(), email = str(), affiliation = str(),
    orcid = str(), url = str(),
    affiliations = arr(obj(
      list(name = str(minLength = 1), department = str(), city = str(), country = str()),
      required = "name"
    ))
  ), required = c("name", "email", "affiliation")),
  directories = map_of(str(pattern = REL_PATH), key_pattern = KEY),
  extra_directories = map_of(ref("extra_directory"), key_pattern = KEY),
  render_dirs = map_of(str(pattern = REL_PATH), key_pattern = KEY),
  packages = obj(
    list(
      use_renv = bool(),
      default_packages = map_of(ref("package"), key_pattern = "^[A-Za-z0-9][A-Za-z0-9._-]*$",
                                description = "Package name -> spec. JSON object key order is not kept (Postgres JSONB sorts keys).")
    ),
    required = c("default_packages")
  ),
  git = obj(
    list(
      use_git = bool(),
      hooks = map_of(bool(), key_pattern = KEY),
      gitignore_content = str()
    ),
    required = c("use_git", "hooks", "gitignore_content")
  ),
  ai = obj(
    list(
      enabled = bool(),
      assistants = list(
        type = "object",
        propertyNames = list(enum = as.list(ASSISTANTS)),
        additionalProperties = bool(),
        description = "Assistant -> true to include. In a layer, false or null removes it."
      ),
      agents_md = str(enum = list("stub", "none"))
    ),
    required = c("enabled", "assistants", "agents_md")
  ),
  scaffold = obj(
    list(
      seed_on_scaffold = bool(),
      seed = str(),
      set_theme_on_scaffold = bool(),
      ggplot_theme = str(),
      source_all_functions = bool(),
      notebook_format = str(enum = list("quarto", "rmarkdown", "jupyter", "script")),
      workflow = str(
        enum = list("quarto", "jupyter", "scripts"),
        description = "How notebooks are written. quarto allows notebook_format quarto (or rmarkdown in R), jupyter allows jupyter, and scripts allows script."
      ),
      ide = str(enum = list("vscode", "positron", "rstudio", "both", "none"))
    ),
    required = c("seed_on_scaffold", "seed")
  ),
  quarto = list(type = "object", description = "Passed through to _quarto.yml generation"),
  connections = obj(
    list(
      default_database = nullable(str()),
      default_storage_bucket = nullable(str()),
      databases = map_of(ref("connection"), key_pattern = KEY),
      storage_buckets = map_of(ref("connection"), key_pattern = KEY)
    ),
    required = c("databases", "storage_buckets")
  ),
  security = obj(list(sensitive = bool()), required = c("sensitive")),
  env = map_of(str(), key_pattern = ENV_NAME,
               description = "Variables written to .env. Secret-looking names must be empty."),
  data_hooks = map_of(str(pattern = "^[^:]+\\.(R|py)::[A-Za-z_.][A-Za-z0-9._]*$"), key_pattern = KEY,
                      description = "Directory key -> 'path/to/file.R::function'"),
  files = map_of(ref("file"), key_pattern = REL_PATH),
  skills = map_of(ref("skill"), key_pattern = SKILL_NAME),
  source = obj(
    list(
      origin = str(enum = list("cloud", "cli", "r", "python")),
      fragments = arr(obj(
        list(kind = str(enum = list("base", "facet", "blueprint")), key = str(), version = list(type = "integer")),
        required = c("kind", "key")
      )),
      blueprint = obj(list(key = str(), version = list(type = "integer")), required = c("key")),
      study_plan = obj(list(id = str(), version = list(type = "integer")), required = c("id")),
      adopted = bool(description = "True when adopt() made an existing folder a project, mapping its folders in place"),
      framework_version = str(description = "Version of the R or Python package that created the project"),
      fw_version = str(description = "Version of fw that created the project (Stata scaffolding)")
    ),
    required = c("origin")
  )
)

resolved_required <- c(
  "spec_version", "name", "type", "language", "author", "directories", "extra_directories",
  "git", "ai", "security", "env", "data_hooks", "files", "skills"
)

# Sections only the R and Python engines use. A Stata spec (fw scaffolding)
# may leave them out.
runtime_required <- c("render_dirs", "packages", "scaffold", "connections")

spec_schema <- c(
  list(
    `$schema` = "http://json-schema.org/draft-07/schema#",
    `$id` = sprintf("%s/spec/v%d.json", BASE_URL, SPEC_VERSION),
    title = "Framework project spec (resolved)",
    description = "A complete project spec, produced by spec_resolve() and accepted by project_create()."
  ),
  obj(properties, required = resolved_required),
  list(
    allOf = list(list(
      `if` = list(properties = list(language = list(enum = list("r", "python")))),
      then = list(required = as.list(runtime_required))
    )),
    definitions = definitions
  )
)

# Layer schema: same shape, nothing required, and map entries may be null.
as_layer <- function(s) {
  if (!is.list(s)) return(s)
  s$required <- NULL
  if (identical(s$type, "object") && is.list(s$additionalProperties)) {
    s$additionalProperties <- nullable(as_layer(s$additionalProperties))
  }
  if (!is.null(s$properties)) s$properties <- lapply(s$properties, as_layer)
  if (!is.null(s$items)) s$items <- as_layer(s$items)
  if (!is.null(s$oneOf)) s$oneOf <- lapply(s$oneOf, as_layer)
  if (!is.null(s$anyOf)) s$anyOf <- lapply(s$anyOf, as_layer)
  s
}

layer_schema <- spec_schema
layer_schema$`$id` <- sprintf("%s/layer/v%d.json", BASE_URL, SPEC_VERSION)
layer_schema$title <- "Framework project spec layer"
layer_schema$description <- paste(
  "One unmerged layer of a project spec. Every field is optional, and a null",
  "map entry removes that key when spec_resolve() merges layers."
)
layer_schema$required <- NULL
layer_schema$allOf <- NULL
layer_schema$properties <- lapply(layer_schema$properties, as_layer)
# Definitions keep their required fields: a package, file, or skill entry must
# still be complete inside a layer. Only the top-level spec is partial.

layer_body <- layer_schema[setdiff(names(layer_schema), c("$schema", "$id", "definitions"))]

# Layers envelope: the body of pull v2 and of .framework/layers.json. Layers
# are listed bottom to top; package defaults are not included because R adds
# them from the installed package.
layers_schema <- list(
  `$schema` = "http://json-schema.org/draft-07/schema#",
  `$id` = sprintf("%s/layers/v%d.json", BASE_URL, SPEC_VERSION),
  title = "Framework project layers",
  description = paste(
    "Unmerged layers for one project, bottom to top, excluding package",
    "defaults. Read by project_create_from_layers() and returned by pull v2."
  ),
  type = "object",
  properties = list(
    spec_version = list(const = SPEC_VERSION),
    name = str(minLength = 1),
    author = properties$author,
    layers = arr(obj(
      list(
        kind = str(
          enum = list("settings", "base", "facet", "blueprint", "project"),
          description = "Labels the layer in conflicts and gitignore blocks. Without it the label is 'layer N' (1-based)."
        ),
        key = str(),
        version = list(type = "integer"),
        layer = ref("layer")
      ),
      required = c("layer")
    )),
    source = properties$source
  ),
  required = list("spec_version", "name", "layers"),
  additionalProperties = FALSE,
  # The layer schema is inlined so this file validates on its own. Its
  # internal refs (#/definitions/package and so on) resolve against the
  # definitions below, which are the same as the layer schema's.
  definitions = c(definitions, list(layer = layer_body))
)

write_schema <- function(schema, path) {
  json <- jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = 2, null = "null")
  writeLines(json, path)
  message("Wrote ", path)
}

out_dir <- Sys.getenv("FW_SCHEMA_OUT", "inst/schema")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
write_schema(spec_schema, file.path(out_dir, "spec.v1.json"))
write_schema(layer_schema, file.path(out_dir, "layer.v1.json"))
write_schema(layers_schema, file.path(out_dir, "layers.v1.json"))
