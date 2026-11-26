# Reiterate CLI

`reiterate` reads your Reiterate organization from the terminal: workflows and their runs, web agents, tasks, members, integrations and month-end status. It is built for people and for coding agents: every command prints JSON and documents itself with `--help`.

Most commands are read-only; the few that change data preview first and need `--confirm`.

## Install

### macOS and Linux

Intel or ARM:

```sh
curl -fsSL https://raw.githubusercontent.com/iter8-ai/cli/main/install.sh | sh
```

The script downloads the binary for your machine from the [latest release](https://github.com/iter8-ai/cli/releases/latest), verifies its SHA-256 checksum and installs it to `~/.local/bin/reiterate`. Set `REITERATE_INSTALL_DIR` to install elsewhere, or `REITERATE_VERSION=0.1.0` to install a specific version.

### Windows

AMD64 or ARM64, in Windows PowerShell 5.1 or PowerShell 7. Windows binaries are available from v0.2.2.

```powershell
irm https://raw.githubusercontent.com/iter8-ai/cli/main/install.ps1 | iex
```

The script downloads the binary, verifies its SHA-256 checksum and installs it to `$env:LOCALAPPDATA\Programs\reiterate\reiterate.exe`. It adds the install directory to your user PATH and the current session's PATH. Set `$env:REITERATE_INSTALL_DIR` to install elsewhere, or `$env:REITERATE_VERSION = '0.2.2'` to install a specific version (`v0.2.2` also works).

## Log in

```sh
reiterate login
reiterate status
```

Your browser opens the Reiterate login and you pick the organization. On a remote machine use `reiterate login --remote`: open the URL it prints, then finish with `reiterate login --remote --code '<CODE>'`.

On macOS the login is stored in the Keychain. Linux has no Keychain, so opt in to file storage first:

```sh
reiterate configure set token_store file
```

## Use

```sh
reiterate user companies list --output table
reiterate workflows list --company <name> --output table
reiterate workflows runs list --company <name> --page-size 50 --limit 50
reiterate workflows runs node-results <run-id> --company <name>
reiterate --help
```

## Reiterate Accounting

From 0.3.0, `reiterate accounting …` reads your bookkeeping in Reiterate Accounting (os.reiterate.com): companies, chart of accounts, sales invoices, purchase bills, bank rows, VAT returns, inbox documents, the ledger, the balance sheet and the income statement. It is read-only and has its own login: you approve access on os.reiterate.com, and you can revoke it there under Minu konto → Ühendatud AI-agendid.

```sh
reiterate accounting login            # or --remote on another machine
reiterate accounting companies list --output table
reiterate accounting bills list --company <registry code> --output table
reiterate accounting reports balance-sheet --date 2026-10-31 --company <registry code>
reiterate accounting --help
```

## Use with coding agents

The repository is also a plugin marketplace for Claude Code and Codex. The plugin adds a skill that teaches the agent to install the CLI, handle login and read your organization.

Claude Code:

```sh
claude plugin marketplace add iter8-ai/cli
claude plugin install reiterate@reiterate
```

Codex:

```sh
codex plugin marketplace add iter8-ai/cli
codex plugin add reiterate@reiterate
```

Any other agent: point it at [skills/reiterate/SKILL.md](skills/reiterate/SKILL.md).

## Updating

From 0.2.0 on, the CLI keeps itself up to date. Once a day a command checks the [latest release](https://github.com/iter8-ai/cli/releases/latest) in the background and, when the install directory is writable, installs a newer version after verifying its SHA-256 checksum. Update checks need no login and send no credentials.

To keep a specific installed version from 0.2.0 on, run `reiterate configure set auto_update off`.

```sh
reiterate update --check   # is a newer release out?
reiterate update           # install it now
reiterate configure set auto_update off   # only report new releases
reiterate configure set update_check off  # no background checks at all
```

Version 0.1.0 has no `update` command: run the install command once more to move to the current release.

## License

All rights reserved; no open-source license is granted. The source code is not published here.
