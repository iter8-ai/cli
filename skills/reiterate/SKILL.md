---
name: reiterate
description: Use when the user asks about their Reiterate organization - workflows and workflow runs, failed runs, web agents, tasks, members, integrations or month-end status - or asks to install or log in to the reiterate CLI.
---

# Reiterate CLI

`reiterate` reads a Reiterate organization from the terminal. This version is read-only: no command changes client data.

## Steps

1. Check the CLI: `reiterate version`. If it is missing, install it:
   `curl -fsSL https://raw.githubusercontent.com/iter8-ai/cli/main/install.sh | sh`
   On Linux, then run `reiterate configure set token_store file`.
   If `reiterate version` shows 0.1.0, rerun the install command; later versions update themselves daily. `reiterate update` installs a newer release at once, and `reiterate update --check` only reports one.
2. Check the login: `reiterate status`. `logins` lists the organizations already available.
3. If the organization is missing or a command exits 3, the user must log in. You cannot do this for them.
   - Same machine as their browser: ask them to run `reiterate login --company <name>`.
   - Remote or headless machine: run `reiterate login --remote --company <name>`, give the user the URL it prints, and when they paste back the one-time code run `reiterate login --remote --company <name> --code '<CODE>'`. The code expires after ten minutes and works once.
4. Pass `--company <name>` on every command. Never rely on the default profile when the user named an organization.
5. Read the command's own help before the first use of a group: `reiterate <group> --help`. It lists the typical sequence and every flag.
6. Answer from the JSON on stdout. Say which organization and which time range you read.

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
| 3 | Login required or wrong organization | Step 3 |
| 4 | Permission denied | Tell the user; their role does not allow it |
| 5 | Not found | Check the id and the organization |
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
