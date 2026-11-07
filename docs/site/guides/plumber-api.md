---
id: plumber-api
title: Plumber API
section: project_types
position: 16
description: 'A Plumber API with endpoints in plumber.R and the logic in R/'
---
## Overview

The Plumber API type (`plumber`) starts a web API built with Plumber. It
comes from Framework Cloud, so you need to be signed in to create one.

## Creating the project

Sign in once, then create the project from R:

```r
framework::cloud_login()
framework::new_project("my-api", type = "plumber")
```

You can also open **Blueprints** on Framework Cloud, choose **Plumber API**,
and select **New project**. Signed out, `type = "plumber"` builds Framework's
default layout with a warning.

## Starter files

```text
my-api/
├── plumber.R      # the endpoints
├── run.R          # starts the API on port 8000
├── R/             # the logic the endpoints call
├── tests/
├── data/
├── scripts/
├── README.md
└── settings.yml
```

`plumber.R` loads the functions in `R/` and defines two endpoints:

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

## Packages

The project starts with the **Plumber API** package set: plumber, jsonlite,
httr2, and logger. To add the same set to an existing project:

```r
framework::package_set_add("plumber-r")
```

## Running the API

From the project folder:

```sh
Rscript run.R
```

The API answers at `http://127.0.0.1:8000`, and its interactive docs are at
`http://127.0.0.1:8000/__docs__/`.
