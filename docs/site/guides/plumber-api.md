---
id: plumber-api
title: Plumber API
section: project_types
position: 16
description: 'Plumber HTTP API blueprint with plumber.R endpoints and R/ logic'
---
## Blueprint overview

The Plumber API blueprint (`plumber`) scaffolds an HTTP API powered by `plumber`. Because the blueprint is hosted on Framework Cloud, sign in with `cloud_login()` before creating one.

## Project creation

Create the project from R after signing in:

```r
framework::cloud_login()
framework::new_project("my-api", type = "plumber")
```

You can also open **Blueprints** on Framework Cloud, select **Plumber API**, and click **Create project**. When signed out, `type = "plumber"` emits a warning and builds a layout with only the core project files, without the blueprint's folders or starter files.

## Starter files

```text
my-api/
├── plumber.R      # Endpoint definitions
├── run.R          # Launches the API on port 8000
├── R/             # Functions called by endpoints
├── tests/
├── data/
├── scripts/
├── README.md
└── settings.yml
```

Starter `plumber.R`:

```r
#* @apiTitle my-api

# The logic lives in R/, so tests can call it without the API
for (file in list.files("R", pattern = "[.][Rr]$", full.names = TRUE)) source(file)

#* Check that the API is running
#* @get /health
function() {
  list(status = "ok")
}

#* Return the message sent
#* @param msg The message
#* @get /echo
function(msg = "") {
  list(msg = msg)
}
```

## Default packages

The blueprint includes the `plumber-r` package set (`plumber`, `jsonlite`, `httr2`, and `logger`). Add the same set to an existing project with:

```r
framework::package_set_add("plumber-r")
```

## Running the API

Start the server from the project root:

```sh
Rscript run.R
```

The API listens at `http://127.0.0.1:8000` and serves interactive OpenAPI documentation at `http://127.0.0.1:8000/__docs__/`. Keep business logic in `R/` so tests can invoke functions directly without starting the server.
