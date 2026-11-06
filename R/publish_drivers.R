.fw_bundle_copy <- function(from, to, recursive = FALSE) {
  if (length(from) && !all(file.copy(from, to, recursive = recursive))) {
    stop("Could not copy all published files.", call. = FALSE)
  }
  invisible(TRUE)
}

.fw_publish_visibility <- function(destination, visibility = NULL) {
  visibility %||% destination$visibility %||% if (isTRUE(destination$private)) "private" else NULL
}

.fw_publish_assert_secrets <- function(value, path = "publish.destinations") {
  if (!is.list(value)) return(invisible(TRUE))
  for (key in names(value)) {
    entry <- value[[key]]
    field <- paste(path, key, sep = ".")
    if (is.list(entry)) {
      .fw_publish_assert_secrets(entry, field)
    } else if (.fw_secret_name(key) && length(entry) &&
               (!is.character(entry) || length(entry) != 1L || anyNA(entry) ||
                (nzchar(entry) && !grepl("^env\\(['\"][A-Za-z_][A-Za-z0-9_]*['\"]\\)$", entry)))) {
      stop(field, ": credentials must use env(\"VARIABLE\") references.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

# Destination resolution, bundle construction, and delivery share one pipeline.
.fw_publish_destination <- function(to = NULL, connection = NULL) {
  settings <- tryCatch(settings_read(), error = function(e) list())
  publishing <- settings$publish %||% list()
  .fw_publish_assert_secrets(publishing$destinations)
  selected <- to %||% publishing$default
  if (is.null(selected)) return(list(driver = .fw_publish_target(connection), legacy = TRUE))
  checkmate::assert_string(selected, min.chars = 1)
  destination <- publishing$destinations[[selected]]
  if (is.null(destination)) {
    if (!selected %in% c("cloud", "github", "folder", "s3", "bucket")) {
      stop("Unknown publishing destination: ", selected, ". Use cloud, github, folder, s3, or a named destination.", call. = FALSE)
    }
    destination <- list(driver = if (selected == "bucket") "s3" else selected)
  }
  if (!is.list(destination) || is.null(destination$driver) || length(destination$driver) != 1L || !destination$driver %in% c("cloud", "github", "folder", "s3")) {
    stop("Invalid publishing driver for destination: ", selected, call. = FALSE)
  }
  destination$name <- selected
  destination$legacy <- selected %in% c("bucket", "s3") && is.null(publishing$destinations[[selected]])
  destination
}

.fw_bundle_slug <- function(value) {
  value <- gsub("^-+|-+$", "", gsub("[^a-z0-9]+", "-", tolower(value)))
  if (!nzchar(value)) stop("Artifact slug needs a letter or digit.", call. = FALSE)
  value
}

.fw_publish_capabilities <- function(destination, visibility = NULL, password = NULL, collection = NULL) {
  driver <- destination$driver
  visibility <- .fw_publish_visibility(destination, visibility)
  if (!is.null(visibility)) checkmate::assert_choice(visibility, c("public", "unlisted", "private"))
  if (driver == "cloud") return(invisible(TRUE))
  if (!is.null(password)) stop("Password protection requires Framework Cloud.", call. = FALSE)
  if (!is.null(collection)) stop("Collections require publishing to Framework Cloud.", call. = FALSE)
  if (identical(visibility, "unlisted")) stop("Unlisted links require Framework Cloud.", call. = FALSE)
  if (driver == "folder") {
    if (!is.character(destination$path) || length(destination$path) != 1L || is.na(destination$path) || !nzchar(destination$path)) {
      stop("Folder publishing needs a named destination with a path, such as:\n\n",
           "publish:\n  default: site\n  destinations:\n    site:\n      driver: folder\n      path: ~/site",
           call. = FALSE)
    }
    if (identical(visibility, "private") && !isTRUE(destination$private) && !identical(destination$visibility, "private")) {
      stop("Private folder publishing requires visibility: private and access controls on the destination folder.", call. = FALSE)
    }
  }
  if (driver == "github" && identical(visibility, "private")) {
    root <- tryCatch(.find_project_root(getwd()), error = function(e) NULL) %||% getwd()
    top <- .fw_git(root, "rev-parse", "--show-toplevel")
    remote <- if (.fw_git_ok(top)) .fw_pages_remote(top[1]) else NULL
    gh <- Sys.which("gh")
    public <- if (!is.null(remote) && nzchar(gh)) {
      suppressWarnings(system2(gh, c("api", paste0("repos/", remote$owner, "/", remote$repo, "/pages"), "--jq", ".public"), stdout = TRUE, stderr = FALSE))
    } else character()
    if (!identical(public, "false")) stop("GitHub has not confirmed private Pages access for this repository.", call. = FALSE)
  }
  invisible(TRUE)
}

.fw_bundle_escape <- function(value) {
  value <- gsub("&", "&amp;", value, fixed = TRUE)
  value <- gsub("<", "&lt;", value, fixed = TRUE)
  value <- gsub(">", "&gt;", value, fixed = TRUE)
  gsub('"', "&quot;", value, fixed = TRUE)
}

.fw_bundle_reader <- function(manifest, representation) {
  template <- system.file("static-reader", "reader.html", package = "framework")
  if (!nzchar(template)) stop("The packaged static reader is missing.", call. = FALSE)
  html <- paste(readLines(template, warn = FALSE), collapse = "\n")
  payload <- jsonlite::toJSON(list(manifest = manifest, representation = representation), auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  for (pair in list(c("&", "\\u0026"), c("<", "\\u003c"), c(">", "\\u003e"), c("\u2028", "\\u2028"), c("\u2029", "\\u2029"))) {
    payload <- gsub(pair[1], pair[2], payload, fixed = TRUE)
  }
  html <- gsub("__FRAMEWORK_TITLE__", .fw_bundle_escape(manifest$title), html, fixed = TRUE)
  gsub("__FRAMEWORK_ARTIFACT__", payload, html, fixed = TRUE)
}

# Refuse symlinks and reserved paths before reading or copying a render tree.
.fw_bundle_safe_files <- function(source) {
  root <- normalizePath(source, winslash = "/", mustWork = TRUE)
  paths <- c(source, if (dir.exists(source)) list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE, include.dirs = TRUE))
  links <- Sys.readlink(paths)
  if (any(!is.na(links) & nzchar(links))) stop("Published sources cannot contain symbolic links.", call. = FALSE)
  if (dir.exists(source)) {
    relative <- substring(paths[-1], nchar(root) + 2L)
    if (any(grepl("(^|/)(\\.\\.?|v)(/|$)", relative)) || any(relative %in% c("artifact.json", "representation.json"))) {
      stop("Published sources contain reserved bundle paths.", call. = FALSE)
    }
  }
  invisible(root)
}

.fw_bundle_build <- function(source, slug = NULL, title = NULL, description = NULL, kind = NULL, self_contained = TRUE, include_private = FALSE) {
  directory <- tempfile("fw_bundle_")
  dir.create(directory)
  complete <- FALSE
  on.exit(if (!complete) unlink(directory, recursive = TRUE), add = TRUE)
  representation <- NULL
  object <- !is.character(source) || !is.null(dim(source))
  if (object) {
    classes <- class(source)
    frame <- .fw_artifact_frame(source)
    original <- .fw_artifact_file(source, directory, cloud = TRUE)
    if (!is.null(frame)) utils::write.csv(frame, file.path(directory, "data.csv"), row.names = FALSE)
    name <- basename(original)
  } else {
    .fw_bundle_safe_files(source)
    classes <- NULL
    name <- tools::file_path_sans_ext(basename(sub("/+$", "", source)))
    ext <- tolower(tools::file_ext(source))
    if (dir.exists(source)) {
      .fw_bundle_copy(list.files(source, full.names = TRUE, all.files = TRUE, no.. = TRUE), directory, recursive = TRUE)
      files <- list.files(directory, recursive = TRUE, all.files = TRUE, no.. = TRUE)
      if (!length(files)) stop("Nothing to publish in source directory.", call. = FALSE)
      original <- file.path(directory, if ("index.html" %in% files) "index.html" else files[1])
    } else if (ext %in% c("qmd", "rmd")) {
      staged <- .fw_github_stage(source, self_contained)
      on.exit(unlink(staged, recursive = TRUE), add = TRUE)
      .fw_bundle_copy(list.files(staged, full.names = TRUE, all.files = TRUE, no.. = TRUE), directory, recursive = TRUE)
      original <- file.path(directory, "index.html")
    } else {
      if (basename(source) %in% c("artifact.json", "representation.json")) stop("Source uses a reserved bundle filename.", call. = FALSE)
      original <- file.path(directory, basename(source))
      if (!.fw_bundle_copy(source, original)) stop("Could not copy the published source.", call. = FALSE)
      assets <- paste0(tools::file_path_sans_ext(source), "_files")
      if (ext %in% c("html", "htm") && dir.exists(assets)) {
        .fw_bundle_safe_files(assets)
        .fw_confirm_private(assets, include_private = include_private)
        .fw_bundle_copy(assets, directory, recursive = TRUE)
      }
    }
  }
  ext <- tolower(tools::file_ext(original))
  if (ext == "json") {
    value <- tryCatch(jsonlite::read_json(original, simplifyVector = FALSE), error = function(e) NULL)
    if (identical(value$schema, "framework.artifact/v1")) representation <- value
  }
  kind <- kind %||% representation$kind %||% if (ext %in% c("png", "jpg", "jpeg", "svg", "gif", "webp")) "image" else if (ext %in% c("html", "htm")) "html" else "file"
  slug <- .fw_bundle_slug(if (is.character(slug)) slug else tools::file_path_sans_ext(name))
  manifest <- list(schema = "framework.bundle/v1", slug = slug, title = title %||% name,
                   description = description, kind = kind, entrypoint = "index.html",
                   representation = if (!is.null(representation)) "representation.json" else NULL,
                   original = substring(original, nchar(directory) + 2L), source = list(language = "r", class = unname(as.list(classes))),
                   created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                   generator = paste("framework", utils::packageVersion("framework")))
  if (!is.null(representation)) jsonlite::write_json(representation, file.path(directory, "representation.json"), auto_unbox = TRUE, null = "null", digits = NA)
  # Rendered documents keep their relative asset paths and become the front page.
  if (ext %in% c("html", "htm")) {
    if (original != file.path(directory, "index.html")) .fw_bundle_copy(original, file.path(directory, "index.html"))
  } else {
    writeLines(.fw_bundle_reader(manifest, representation), file.path(directory, "index.html"), useBytes = TRUE)
  }
  paths <- sort(list.files(directory, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  manifest$files <- lapply(paths, function(path) list(path = path, bytes = unname(file.info(file.path(directory, path))$size), sha256 = digest::digest(file = file.path(directory, path), algo = "sha256")))
  jsonlite::write_json(manifest, file.path(directory, "artifact.json"), auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
  complete <- TRUE
  list(path = directory, manifest = manifest)
}

.fw_site_index <- function(path) {
  slugs <- list.dirs(path, recursive = FALSE, full.names = TRUE)
  artifacts <- lapply(slugs, function(dir) {
    file <- file.path(dir, "artifact.json")
    if (file.exists(file)) jsonlite::read_json(file, simplifyVector = FALSE) else NULL
  })
  artifacts <- Filter(function(x) !is.null(x) && identical(x$schema, "framework.bundle/v1") &&
                        is.character(x$slug) && grepl("^[a-z0-9]+(-[a-z0-9]+)*$", x$slug), artifacts)
  jsonlite::write_json(list(schema = "framework.site/v1", artifacts = artifacts), file.path(path, "index.json"), auto_unbox = TRUE, null = "null", pretty = TRUE)
  rows <- vapply(artifacts, function(x) paste0('<li><a href="', x$slug, '/">', .fw_bundle_escape(x$title), '</a></li>'), character(1))
  writeLines(paste0('<!doctype html><html><head><meta charset="utf-8"><title>Artifacts</title></head><body><h1>Artifacts</h1><ul>', paste(rows, collapse = ""), '</ul></body></html>'), file.path(path, "index.html"))
}

.fw_folder_deliver <- function(bundle, destination, overwrite = TRUE) {
  root <- path.expand(destination$path)
  slug <- bundle$manifest$slug
  candidates <- c(root, file.path(root, slug))
  parent <- dirname(root)
  while (!identical(parent, dirname(parent))) {
    if (!parent %in% c("/tmp", "/var", "/etc")) candidates <- c(candidates, parent)
    parent <- dirname(parent)
  }
  links <- Sys.readlink(candidates)
  if (any(!is.na(links) & nzchar(links))) stop("Destination cannot be a symbolic link.", call. = FALSE)
  if (file.exists(file.path(root, "index.html")) && !file.exists(file.path(root, "index.json"))) {
    stop("Destination contains an unmanaged index.html.", call. = FALSE)
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  lock <- file.path(root, ".framework-publish.lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("Another publish is using this folder.", call. = FALSE)
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  target <- file.path(root, slug)
  if (dir.exists(target) && !overwrite) stop("Artifact already exists: ", slug, call. = FALSE)
  other_manifests <- file.path(list.dirs(root, recursive = FALSE, full.names = TRUE), "artifact.json")
  for (file in other_manifests[file.exists(other_manifests)]) jsonlite::read_json(file)
  old_file <- file.path(target, "artifact.json")
  previous <- if (file.exists(old_file)) jsonlite::read_json(old_file) else NULL
  if (dir.exists(target) && is.null(previous)) stop("Destination already contains an unmanaged artifact: ", slug, call. = FALSE)
  if (!is.null(previous) && (!identical(previous$schema, "framework.bundle/v1") ||
      !is.numeric(previous$version %||% 1L) || (previous$version %||% 1L) < 1)) {
    stop("Invalid published artifact manifest.", call. = FALSE)
  }
  version <- if (is.null(previous)) 1L else as.integer(previous$version %||% 1L) + 1L
  staging <- tempfile(".framework-", tmpdir = root)
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  .fw_bundle_copy(list.files(bundle$path, full.names = TRUE, all.files = TRUE, no.. = TRUE), staging, recursive = TRUE)
  if (!is.null(previous)) {
    archive <- file.path(staging, "v")
    dir.create(archive)
    if (dir.exists(file.path(target, "v"))) .fw_bundle_copy(list.files(file.path(target, "v"), full.names = TRUE, all.files = TRUE, no.. = TRUE), archive, recursive = TRUE)
    dir.create(file.path(archive, version - 1L), showWarnings = FALSE)
    .fw_bundle_copy(list.files(target, full.names = TRUE, all.files = TRUE, no.. = TRUE)[list.files(target, all.files = TRUE, no.. = TRUE) != "v"], file.path(archive, version - 1L), recursive = TRUE)
  }
  manifest <- bundle$manifest
  manifest$version <- version
  jsonlite::write_json(manifest, file.path(staging, "artifact.json"), auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
  current_archive <- file.path(staging, "v", version)
  dir.create(current_archive, recursive = TRUE)
  .fw_bundle_copy(list.files(staging, full.names = TRUE, all.files = TRUE, no.. = TRUE)[list.files(staging, all.files = TRUE, no.. = TRUE) != "v"], current_archive, recursive = TRUE)
  backup <- tempfile(".framework-old-", tmpdir = root)
  if (dir.exists(target) && !file.rename(target, backup)) stop("Could not archive the previous artifact.", call. = FALSE)
  if (!file.rename(staging, target)) {
    if (dir.exists(backup)) file.rename(backup, target)
    stop("Could not replace the published artifact.", call. = FALSE)
  }
  unlink(backup, recursive = TRUE)
  .fw_site_index(root)
  url <- if (!is.null(destination$url)) paste0(sub("/+$", "", destination$url), "/", slug, "/") else NULL
  list(driver = "folder", url = url, version = version,
       version_url = if (!is.null(url)) paste0(url, "v/", version, "/") else NULL, location = target, commit = NULL,
       sha256 = digest::digest(file = file.path(target, "artifact.json"), algo = "sha256"))
}

.fw_track_external <- function(bundle, receipt, visibility = NULL) {
  token <- .fw_project_token()
  if (is.null(token)) return(invisible(NULL))
  tryCatch({
    url <- .fw_project_cloud_url()
    me <- .fw_api("/api/v1/me", token, url = url)
    project <- if (is.character(me$project)) me$project else me$project$slug
    project <- project %||% me$project_slug %||% me$slug
    if (is.null(project)) stop("Project slug is missing from the project token response.")
    manifest <- bundle$manifest
    body <- list(slug = manifest$slug, title = manifest$title, description = manifest$description,
                 kind = manifest$kind, driver = receipt$driver, url = receipt$url,
                 version_url = receipt$version_url, version = receipt$version,
                 size_bytes = sum(vapply(manifest$files, function(x) x$bytes, numeric(1))),
                 sha256 = receipt$sha256 %||% digest::digest(file = file.path(bundle$path, "artifact.json"), algo = "sha256"),
                 visibility = visibility %||% "public", published_at = manifest$created_at, source = manifest$source)
    .fw_api(paste0("/api/v1/projects/", utils::URLencode(project, reserved = TRUE), "/artifacts/external"), token, method = "POST", body = body, url = url)
  }, error = function(e) warning("Published successfully; Cloud metadata tracking failed: ", conditionMessage(e), call. = FALSE))
  invisible(NULL)
}

.fw_publish_bundle <- function(source, destination, dest = NULL, connection = NULL,
                               overwrite = TRUE, self_contained = TRUE, slug = NULL,
                               include_private = FALSE, title = NULL, description = NULL,
                               kind = NULL, password = NULL, visibility = NULL, collection = NULL) {
  visibility <- .fw_publish_visibility(destination, visibility)
  .fw_publish_capabilities(destination, visibility, password, collection)
  if (destination$driver == "folder" && !is.null(dest)) stop("Folder destinations use slug instead of dest.", call. = FALSE)
  if (is.character(source) && is.null(dim(source))) {
    if (!file.exists(source)) stop("Source not found: ", source, call. = FALSE)
    .fw_confirm_private(source, include_private)
  }
  if (!is.null(destination$url) && !grepl("^https?://", destination$url)) stop("Publishing URL must use HTTP or HTTPS.", call. = FALSE)
  if (destination$driver == "github") {
    .fw_pages_reject(dest, connection, slug)
    if (is.character(source) && dir.exists(source) && !file.exists(file.path(source, "index.html"))) {
      stop("A folder published to GitHub Pages needs an index.html at its top.", call. = FALSE)
    }
  }
  if (destination$driver == "s3") {
    s3 <- .resolve_s3_connection(destination$bucket %||% connection)
    if (identical(visibility, "private")) {
      .fw_s3_confirm_private(s3)
      s3$private <- TRUE
    }
  }
  bundle <- .fw_bundle_build(source, slug, title, description, kind, self_contained, include_private)
  on.exit(unlink(bundle$path, recursive = TRUE), add = TRUE)
  receipt <- switch(destination$driver,
    folder = .fw_folder_deliver(bundle, destination, overwrite),
    github = {
      url <- .fw_github_publish(bundle$path, slug = bundle$manifest$slug, self_contained = self_contained, bundle = bundle, visibility = visibility)
      attr(url, "receipt")
    },
    s3 = .fw_s3_bundle_deliver(bundle, destination, s3, dest, overwrite)
  )
  .fw_track_external(bundle, receipt, visibility)
  value <- receipt$url %||% receipt$location
  # Keep the historical character return value.
  invisible(value)
}

.fw_s3_bundle_deliver <- function(bundle, destination, s3, dest = NULL, overwrite = TRUE) {
  # Read the current manifest before uploading. Authentication and network failures
  # must not be mistaken for an empty destination.
  prefix <- dest %||% bundle$manifest$slug
  if (grepl("(^|/)\\.\\.?(/|$)|^/|\\\\", prefix)) stop("Unsafe S3 destination path.", call. = FALSE)
  withr::local_envvar(AWS_ACCESS_KEY_ID = s3$access_key, AWS_SECRET_ACCESS_KEY = s3$secret_key,
                     AWS_DEFAULT_REGION = s3$region, AWS_SESSION_TOKEN = s3$session_token)
  key <- paste(c(s3$prefix, prefix, "artifact.json")[nzchar(c(s3$prefix, prefix, "artifact.json"))], collapse = "/")
  args <- list(object = key, bucket = s3$bucket, base_url = s3$endpoint %||% "s3.amazonaws.com",
               region = if (!is.null(s3$endpoint)) "" else s3$region, use_https = s3$use_https %||% TRUE)
  # aws.s3 prints "Client error: (404) Not Found" for a first publish
  exists <- .fw_s3_quiet(do.call(aws.s3::object_exists, args))
  previous <- if (isTRUE(exists)) jsonlite::fromJSON(rawToChar(do.call(aws.s3::get_object, args)), simplifyVector = FALSE) else NULL
  if (!is.null(previous) && !overwrite) stop("Artifact already exists: ", prefix, call. = FALSE)
  if (!is.null(previous) && (!identical(previous$schema, "framework.bundle/v1") ||
      !is.numeric(previous$version %||% 1L) || (previous$version %||% 1L) < 1)) {
    stop("Invalid published artifact manifest.", call. = FALSE)
  }
  version <- if (is.null(previous)) 1L else as.integer(previous$version %||% 1L) + 1L
  manifest <- bundle$manifest
  manifest$version <- version
  jsonlite::write_json(manifest, file.path(bundle$path, "artifact.json"), auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
  # Every version has an immutable folder, including the current one. Upload the
  # front page last so a failed asset upload cannot expose a partial new reader.
  files <- list.files(bundle$path, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  files <- c(setdiff(files, c("artifact.json", "index.html")), "artifact.json", "index.html")
  for (base in c(paste0(prefix, "/v/", version), prefix)) {
    for (file in files) .s3_upload_file(file.path(bundle$path, file), paste0(base, "/", file), s3)
  }
  url <- if (isTRUE(s3$private)) NULL else paste0(sub("/index.html$", "/", .s3_public_url(paste(c(s3$prefix, prefix, "index.html")[nzchar(c(s3$prefix, prefix, "index.html"))], collapse = "/"), s3)))
  list(driver = "s3", url = url, version = version,
       version_url = if (!is.null(url)) paste0(url, "v/", version, "/") else NULL,
       location = paste0("s3://", s3$bucket, "/", prefix), commit = NULL)
}


.fw_s3_confirm_private <- function(s3) {
  # aws.s3 prints the raw error, with the access key ID and request
  # signature, before it fails. Keep that out of the console.
  request <- function(query) .fw_s3_quiet(aws.s3::s3HTTP(
    verb = "GET", bucket = s3$bucket, query = query,
    base_url = s3$endpoint %||% "s3.amazonaws.com",
    region = if (!is.null(s3$endpoint)) "" else s3$region,
    key = s3$access_key, secret = s3$secret_key, session_token = s3$session_token,
    use_https = s3$use_https %||% TRUE
  ))
  confirmed <- tryCatch({
    block <- unlist(request(list(publicAccessBlock = "")))
    status <- unlist(request(list(policyStatus = "")))
    truth <- function(values, name, expected) {
      found <- values[grepl(paste0("(^|\\.)", name, "$"), names(values))]
      # aws.s3 simplifies the single IsPublic XML element to an unnamed scalar.
      if (identical(name, "IsPublic") && is.null(names(values)) && length(values) == 1L) found <- values
      length(found) == 1L && identical(tolower(as.character(unname(found))), expected)
    }
    all(vapply(c("BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets"),
               function(name) truth(block, name, "true"), logical(1))) && truth(status, "IsPublic", "false")
  }, error = function(e) FALSE)
  if (!confirmed) stop("S3 could not confirm private access. Enable bucket Public Access Block and a non-public bucket policy.", call. = FALSE)
  invisible(TRUE)
}

# Run an aws.s3 call without its printed output and messages. Errors and the
# return value pass through.
.fw_s3_quiet <- function(expr) {
  value <- NULL
  utils::capture.output(value <- suppressMessages(expr))
  value
}
