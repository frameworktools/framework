---
id: setup
title: Setup
section: getting_started
position: 2
description: 'Framework Cloud sign-in, project tokens, and user-wide settings'
---
## Framework Cloud sign-in

Framework Cloud ([framework.pub](https://framework.pub)) holds your defaults for new projects. Sign in once per computer:

```r
framework::cloud_login()
```

`cloud_login()` lists what connecting shares and asks for confirmation. It then opens the server's approval page in your browser. Sign in, or create a free account, and approve this computer. The token comes back to R and is stored in the macOS Keychain, Windows Credential Manager, or Linux Secret Service. Without a credential store, it goes in a permission-restricted file in the config folder.

To use a token from the Framework Cloud token page instead:

```r
framework::cloud_login("fw_...")
```

For a self-hosted server, pass its URL. Plain `http` works only for `localhost` and `127.0.0.1`.

```r
framework::cloud_login(url = "https://framework.example.edu")
```

The server you last signed in to becomes the default. The `FW_CLOUD_URL` environment variable overrides it. `cloud_status()` shows the server in use and the account. `cloud_logout()` revokes the stored token and removes it from this computer.

Nothing contacts Framework Cloud until you sign in.

## Project defaults

Edit your defaults on Framework Cloud under **Default settings**. Signed in, `new_project()` sends your choices to Framework Cloud and builds the project it resolves. Framework caches your defaults after each online creation. When Framework Cloud can't be reached, a project with no choices beyond its name uses the cached defaults.

`cloud_sync()` mirrors your Cloud settings document to `cloud-settings.yml` in the config folder. Edit that file and run `cloud_sync()` again to push the changes.

Signed out, or with `offline = TRUE`, new projects use Framework's built-in defaults. See [New projects](guide:new-project).

## Project tokens

A project created on Framework Cloud has a project token. Create the project locally from it:

```r
framework::setup("fw_...")
```

`setup()` fetches the project's definition and asks `Create the project here (<path>)? [y/n]` for a folder named for the project in the current directory. Answer `n` to type another folder; the project folder goes inside it. Pass `location` to skip the prompt. Non-interactive sessions must pass `location`. Pass `url` for a self-hosted server. The token and server are saved in the project's `.env` file as `FW_PROJECT_TOKEN` and `FW_CLOUD_URL`, so publishing and the data ledger go back to that server. `new(key = "fw_...")` does the same.

## Settings storage

User-wide settings live in the folder `fw_config_dir()` returns. The default is `tools::R_user_dir("framework", "config")`. Set `FW_CONFIG_HOME` to use another folder.

```text
<config folder>/
├── settings.yml        # User-wide settings
├── projects.yml        # Registry of your Framework projects
├── templates/          # Your notebook, script, and slide templates
├── cloud.yml           # The saved Framework Cloud server
├── cloud-settings.yml  # Mirror of your Cloud settings (cloud_sync())
└── cache/defaults/     # Cached Framework Cloud defaults
```

- **settings.yml**: read and updated with `configure_global()`.
- **projects.yml**: projects you've created, listed by `project_list()`.
- **templates/**: starter files for `make_notebook()`, `make_script()`, and `make_revealjs()`. Edit them with `write_framework_template()`. A project's own `stubs/` folder comes first.
- **cloud.yml**, **cloud-settings.yml**, and **cache/**: written by the cloud functions.

Framework creates `settings.yml` and `projects.yml` the first time they are needed.

## Settings from Python and fw

The Python package and the `fw` command-line tool keep their settings in `~/.config/framework`. `config_sync()` copies user settings, the saved server, and token files from that folder into R's when they are missing or newer there. R never writes to their folder.

```r
framework::config_sync(dry_run = TRUE)
framework::config_sync()
```

---

<div style="display: flex; justify-content: space-between">

[← Installation](guide:installation)

[Conventions →](guide:conventions)

</div>
