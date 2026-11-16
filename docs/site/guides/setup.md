---
id: setup
title: Setup
section: getting_started
position: 2
description: 'Framework Cloud sign-in, project tokens, and user-wide settings'
---
## Framework Cloud sign-in

Framework Cloud ([framework.pub](https://framework.pub)) stores project defaults, blueprints, and skills. Sign in once per computer:

```r
framework::cloud_login()
```

`cloud_login()` lists the metadata shared with the server, asks for confirmation, and opens the browser approval page. Sign in or create an account and approve the computer. R receives the device token and saves it in the macOS Keychain, Windows Credential Manager, or Linux Secret Service. When no credential store is available, R writes the token to a permission-restricted file in the configuration directory.

To authenticate directly with a token created under **Account > Computers & API tokens**:

```r
framework::cloud_login("fw_...")
```

For a self-hosted server, pass `url`. Unencrypted `http` URLs are restricted to `localhost` and `127.0.0.1`.

```r
framework::cloud_login(url = "https://framework.example.edu")
```

The most recent server becomes the default. Set `FW_CLOUD_URL` to override it. `cloud_status()` displays the active server and account. `cloud_logout()` revokes the token and removes local credentials.

### Server resolution

Account calls (`cloud_status()`, `cloud_sync()`, `new_project()`, `setup("fw_...")`) use the first of:

1. `url` argument
2. `FW_CLOUD_URL` environment variable
3. Last server saved by `cloud_login()`, `fw login`, or the Python package

Project calls (`publish()`, `pull_all()`, `push_all()`, the data ledger) use the first of:

1. `FW_CLOUD_URL` in the project's `.env`
2. `FW_CLOUD_URL` environment variable
3. Saved login server. When saved logins name different servers, the call stops and asks for `FW_CLOUD_URL` in `.env`.

With none of these set, the call stops with an error. Framework never falls back to `https://framework.pub`. `cloud_login()` without `url`, `FW_CLOUD_URL`, or a saved login names `https://framework.pub` in its notice and asks before connecting.

Framework makes no network requests to Framework Cloud until you sign in or pass a project token.

## Project defaults

Configure your defaults on Framework Cloud under **Settings > Project defaults** (and author details under **Settings > Personal data**). When signed in, `new_project()` sends your selections to Framework Cloud, builds the resolved specification, and caches your defaults locally. If Framework Cloud is unreachable, `new_project()` falls back to the cached defaults when called without custom options.

`cloud_sync()` mirrors your Cloud settings document to `cloud-settings.yml` in the local configuration directory. Edit that file and run `cloud_sync()` again to upload changes.

When signed out or called with `offline = TRUE`, `new_project()` uses Framework's built-in defaults. See [New projects](guide:new-project).

## Project tokens

Each project on Framework Cloud can issue a project token. Create the local project directory from that token:

```r
framework::setup("fw_...")
```

`setup()` downloads the project specification and prompts `Create the project here (<path>)? [y/n]` for a subdirectory of the current working directory. If a Projects folder is set in Framework Cloud Settings, `setup()` prompts `Create the project in <path>? [y/n]` inside that folder instead. The project owner's Projects folder takes precedence when present, followed by your own. Enter `n` to type another parent directory. Pass `location` to skip the prompt (required in non-interactive sessions) and `url` for a self-hosted server.

`setup()` writes `FW_PROJECT_TOKEN` and `FW_CLOUD_URL` to the project's `.env` file so `publish()`, `pull_all()`, `push_all()`, and the data ledger use that server. `new_project(key = "fw_...")` performs the same setup.

## Local configuration storage

User-wide configuration files live in the directory returned by `fw_config_dir()` (by default `tools::R_user_dir("framework", "config")`). Set `FW_CONFIG_HOME` to override the location.

```text
<config folder>/
├── settings.yml        # User-wide settings
├── projects.yml        # Local project registry
├── templates/          # User notebook, script, and slide templates
├── cloud.yml           # Default Framework Cloud server URL
├── cloud-settings.yml  # Local mirror for cloud_sync()
└── cache/defaults/     # Cached Framework Cloud defaults
```

- `settings.yml`: read and updated by `configure_global()`.
- `projects.yml`: local project list read by `project_list()`.
- `templates/`: starter files for `make_notebook()`, `make_script()`, and `make_revealjs()`, managed with `write_framework_template()`. Project-level `stubs/` directories take precedence.
- `cloud.yml`, `cloud-settings.yml`, and `cache/`: managed by the Cloud functions.

Framework creates `settings.yml` and `projects.yml` on first use.

## Cross-tool configuration sync

Framework for Python and the `fw` CLI store user settings in `~/.config/framework`. `config_sync()` copies user settings, the saved Cloud server, and fallback token files from `~/.config/framework` into R's configuration directory when those files are missing or newer. R does not modify `~/.config/framework`.

```r
framework::config_sync(dry_run = TRUE)
framework::config_sync()
```
