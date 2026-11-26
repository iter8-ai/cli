---
name: reiterate
description: Use when working with Reiterate organization workflows, runs, web agents, tasks, members, integrations or month-end; Reiterate Accounting bookkeeping at os.reiterate.com (invoices, bills, bank, VAT, ledger, reports); or installing or logging in to the reiterate CLI or Reiterate plugin.
---

# Reiterate CLI

`reiterate` reads a Reiterate organization from the terminal. Most commands are read-only; the few that change data preview first and need `--confirm`. `reiterate accounting …` reads Reiterate Accounting (os.reiterate.com) and is read-only.

## Steps

1. Check the CLI: `reiterate version`. If it is missing, install it:

   - macOS or Linux: `curl -fsSL https://raw.githubusercontent.com/iter8-ai/cli/main/install.sh | sh`
   - Windows PowerShell 5.1 or PowerShell 7: `irm https://raw.githubusercontent.com/iter8-ai/cli/main/install.ps1 | iex`

   Windows installs AMD64 or ARM64 to `$env:LOCALAPPDATA\Programs\reiterate` and adds it to PATH. Set `REITERATE_INSTALL_DIR` or `REITERATE_VERSION` in the environment before installing to override the directory or version.
   On Linux, then run `reiterate configure set token_store file`.
   If `reiterate version` shows 0.1.0, rerun the install command; later versions update themselves daily. `reiterate update` installs a newer release at once, and `reiterate update --check` only reports one.
   To keep a specific installed version from 0.2.0 on, run `reiterate configure set auto_update off`.
2. Check the login: `reiterate status`. `logins` lists the organizations already available.
3. If the organization is missing or a non-accounting command exits 3, the user must log in. You cannot do this for them.
   - Same machine as their browser: ask them to run `reiterate login --company <name>`.
   - Remote or headless machine: run `reiterate login --remote --company <name>`, give the user the URL it prints, and when they paste back the one-time code run `reiterate login --remote --company <name> --code '<CODE>'`. The code expires after ten minutes and works once.
4. Pass `--company <name>` on every command. Never rely on the default profile when the user named an organization.
5. Read the command's own help before the first use of a group: `reiterate <group> --help`. It lists the typical sequence and every flag.
6. Answer from the JSON on stdout. Say which organization and which time range you read.

## Reiterate Accounting (os.reiterate.com)

The `accounting` group has its own login, separate from `reiterate login`. It needs CLI 0.3.0 or later (`reiterate version`; `reiterate update` installs it).

1. Check it: `reiterate accounting status`. If `logged_in` is false, or a command exits 3, the user must approve access in their browser. You cannot do this for them.
   - Same machine as their browser: run `reiterate accounting login`; their browser opens os.reiterate.com and they press "Luba".
   - Remote or headless machine: run `reiterate accounting login --remote`, give the user the `url` it prints, and when they paste back the `state:code` text the page shows, run `reiterate accounting login --remote --code '<state:code>'`.
2. `reiterate accounting companies list` shows the companies the user can read. Pass `--company` with the company's id, registry code or exact name on every command, or save a default with `reiterate configure set accounting_company <registry code>`.
3. Commands (read-only):

| Group | Commands |
|---|---|
| `accounting companies` | `list` |
| `accounting accounts` | `list` chart of accounts |
| `accounting reports` | `ledger --from --to`, `balance-sheet --date`, `income-statement --date` |
| `accounting sales-invoices` | `list`, `show <id>` |
| `accounting bills` | `list`, `show <id>` purchase invoices |
| `accounting bank` | `accounts`, `transactions --bank <id>` unconfirmed statement rows |
| `accounting vat-returns` | `list`, `show <id>` |
| `accounting documents` | `list`, `show <id>` inbox documents |

The user can see and revoke this access in os.reiterate.com under Seaded → Minu konto → Ühendatud AI-agendid. `reiterate accounting logout` revokes it from the terminal.

## Commands

| Group | Commands |
|---|---|
| `user companies` | `list` organizations the user can log in to |
| `workflows` | `list`, `get`, `status`, `runs list`, `runs get`, `runs node-results` |
| `web-agents` | `list`, `get`, `latest-run`, `run get`, `run activity`, `credentials list`, `credentials get` |
| `tasks` | `list`, `events` |
| `month-end` | `status`, `missing-docs get`, `invoices list`, `invoices get`, `invoices files`, `invoices decisions` |
| `integrations` | `list`, `get` |
| `company` | `list`, `get`, `current` |
| `members` | `list` |

## Output

- stdout is compact JSON: `{"data": ...}`. Lists add `next`, `total` and `truncated`.
- `truncated: true` means the page holds more rows than shown: repeat with a larger `--limit`. `next` is the next server page: pass it as `--page`.
- `--fields a,b.c` picks fields. `--full` returns every field. `--output table` is for showing a person, not for parsing.
- Secrets and tokens are redacted in every response. Do not try to recover them.
- Errors are one JSON object on stderr.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | Success | |
| 2 | Invalid arguments | Read `--help` and fix the command |
| 3 | Login required or wrong organization | Step 3, or Accounting step 1 for `reiterate accounting` commands |
| 4 | Permission denied | Tell the user; their role does not allow it |
| 5 | Not found | Check the id and the organization |
| 6 | Conflict | Read the error and resolve the conflict before retrying |
| 10 | Server or connection failure | Retry once, then report |

## Example: how did workflow runs go this week

```sh
reiterate workflows runs list --company <name> --page-size 100 --limit 100 --full
```

Runs come newest first. Request further pages with `--page 2`, `--page 3` until `created_at` passes the start of the range. Each run has `status`, `workflow_name`, `created_by`, `is_dry_run` and `variables`. For a failed run, the reason is in:

```sh
reiterate workflows runs node-results <run-id> --company <name> --full
```

Look for steps with `"status": "error"` and read `error_message`. Report real runs and dry runs separately, and check whether a failed run was followed by a completed run of the same workflow for the same date.
