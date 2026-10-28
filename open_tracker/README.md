# Open Study Tracker

An MIT-licensed tracker for study deliverables, owners, deadlines, and operational exceptions. The offline workflow needs only **Python 3.10+ and its standard library**, with no account, API token, cloud service, or package installation. R and SAS jobs can produce the same plain CSV input. Optional shared mode adds individual logins, viewer/editor permissions, conflict detection, and automatic email alerts through your SMTP server.

**Reusable evaluation tool:** for consultants and in-house teams adapting study operations. The browser demo works immediately. A guided launcher sets up individual accounts, private storage and automatic local email previews; the same setup can run on your chosen host with your chosen SMTP service. No client workspace or provider account is preconfigured.

[Open the browser workspace](index.html) · [Shared accounts and email setup](SHARED.md) · [Synthetic CSV example](examples/status.csv) · [Source code](tracker.py) · [MIT license](../LICENSE)

## Try it

Open `index.html` directly in a browser. It includes fictional tasks. Search, filter, add a task, or edit its status. Browser edits are saved locally when browser storage is available. Download JSON to keep a portable copy. No upload or network request is made by the workspace.

For scheduled jobs and a durable change history, run these commands from the repository root:

```sh
mkdir -p open_tracker/out
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite upsert --csv open_tracker/examples/status.csv --dry-run
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite upsert --csv open_tracker/examples/status.csv --actor nightly-demo
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite export --html open_tracker/out/tracker.html
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite export --json open_tracker/out/tracker.json
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite check --stale-hours 24
```

Open `open_tracker/out/tracker.html` to review the database snapshot offline. The demo intentionally has blocked and at-risk tasks, so the final command returns **2**, meaning attention is needed. Due-date checks use UTC.

## Start shared access with one command

From a complete checkout, with Python 3.10+ installed:

```sh
python3 open_tracker/manage.py
```

On Windows, use `py -3 open_tracker/manage.py`. The launcher checks dependencies, creates an isolated environment if needed, asks you to create the first account, and starts the shared server and email-preview worker together. Open `http://127.0.0.1:8080` and sign in. The first setup needs internet access to install packages; subsequent starts reuse the installed environment.

Your database and configuration are kept in `~/.open-study-tracker`, outside the checkout. The workspace starts empty unless you choose the synthetic example. No default password is supplied. Press **Ctrl+C** to stop both services; run the same command to resume.

```sh
python3 open_tracker/manage.py email
python3 open_tracker/manage.py email-test
python3 open_tracker/manage.py doctor
```

`email` guides you through disabled, local-preview or live-SMTP mode. `email-test` creates a local sample message, even for an empty tracker. `doctor` checks local setup and reports actionable problems without sending email. See the [shared setup guide](SHARED.md) for team hosting with automatic HTTPS, account commands, backups and separate workspaces.

## How the pieces fit

```text
SAS / R / any CSV-producing job
              |
              v
        tracker.py upsert --> local SQLite + recorded change history
                                      |
                         +------------+-------------+
                         v                          v
                  HTML/JSON snapshot         tracker.py check
                         |                   scheduler exit code
                         v
              offline browser workspace
                         |
                 edited JSON download
                         |
                 tracker.py upsert
```

The browser is a **snapshot editor**, not a live database connection. Its edits do not reach SQLite until you import the downloaded JSON. Then export a fresh HTML snapshot. Each embedded snapshot has its own browser-storage identity so an older saved copy cannot silently replace a newly generated snapshot. File movement, private browsing, and browser-specific `file://` storage behavior can affect local persistence; the visible save indicator and JSON downloads are the fallback.

```sh
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite upsert --json /path/to/downloaded-tracker.json --dry-run
python3 open_tracker/tracker.py --db open_tracker/out/tracker.sqlite upsert --json /path/to/downloaded-tracker.json --actor reviewer
```

Imports merge rows by `task_id`; missing rows never delete existing tasks. Repeated identical imports add no change events. A successful no-change import still refreshes the import heartbeat, while a dry run or failed import does not. This heartbeat proves the tracker import ran, **not** that an upstream extract is current. Check upstream freshness in the producing job.

**Concurrent edits:** SQLite serializes file imports, and the last successful file import wins for fields supplied by that import. Offline file imports have no conflict detection. Review a fresh snapshot before editing and avoid importing an old full snapshot over newer work. The optional shared web mode compares row versions and rejects stale edits. For automated jobs, send only the fields the job owns. Task IDs are permanent; changing one creates a separate task. Deletion is intentionally not part of the interface.

## Data contract

| Field | Meaning and validation |
| --- | --- |
| `task_id` | Required stable text key, 1–80 characters, without surrounding whitespace or line breaks. `007` stays `007`. |
| `title` | Required on creation, nonblank text, up to 160 characters. |
| `status` | `Not started`, `In progress`, `At risk`, `Blocked`, or `Done`. Defaults to `Not started`. |
| `owner` | Team or role, up to 120 characters. Defaults to empty. |
| `due` | Real calendar date in `YYYY-MM-DD`, or empty. Defaults to empty. |
| `progress` | Integer percentage from 0 to 100. Defaults to 0. |
| `notes` | Operational note, up to 1,000 characters. Defaults to empty. |

CSV headers must exactly match these names. Only `task_id` is required in every batch; a new row also needs `title`. Omitted columns and empty CSV cells leave an existing value unchanged. A CSV percentage is an integer such as `70`, not `0.7` or `70%`.

JSON accepts a document with `schema_version: 1` and a nonempty `rows` array. It also accepts the exported metadata `exported_at`, `last_import_at`, and `events`. Use explicit empty strings to clear `owner`, `due`, or `notes`; `null` is rejected. Row `updated_at` values and document metadata do not control the database's timestamps or history. For example:

```json
{"schema_version": 1, "rows": [{"task_id": "DEMO-TLF", "status": "In progress", "notes": ""}]}
```

Unknown columns, duplicate IDs within a batch, duplicate CSV headers/JSON properties, invalid dates, and invalid field values fail the whole CLI import. Input files are limited to 5 MiB and 10,000 rows per batch. The database can accumulate more rows and history than fit in one browser workspace or import: for large databases, omit `events` and send smaller row batches when importing changes. Exports include the full history and are not size-limited. No database changes occur during dry runs. JSON is the lossless interchange format. Browser CSV downloads prefix formula-like text with an apostrophe to reduce spreadsheet formula execution; that prefix is literal text on reimport.

The field allowlist is a schema check, **not a sensitive-data detector**. Free text can still contain sensitive information. Keep this workspace to operational information and use synthetic data for public examples. It is not a clinical data repository or a validated regulatory system.

## R and SAS

The [base-R example](bridges/update_tracker.R) writes a synthetic CSV, invokes the Python importer, checks its return code, and exports HTML. No R packages are needed:

```sh
Rscript open_tracker/bridges/update_tracker.R /absolute/path/to/biometrics-ai-portfolio/open_tracker/out
```

The [SAS example](bridges/export_tracker.sas) uses `PROC EXPORT` to write the same schema. Set its output directory, run it in your SAS environment, then let your existing scheduler execute the Python commands. SAS does not need shell execution enabled. The SAS source is an example and has not been executed here because a SAS runtime is unavailable.

## Scheduling and exceptions

Schedule your producer, then `upsert`, then `export`, then `check`, using absolute paths in cron, Task Scheduler, or your existing job runner. Stop the sequence on a failed producer/import; do not publish a successful-looking snapshot after an error. The script prints machine-readable JSON on success and an error to stderr on failure.

| Exit status | Meaning |
| --- | --- |
| `0` | Command succeeded; for `check`, no configured exceptions were found. |
| `1` | Input, storage, or export error. CLI usage errors from argparse return `2`. |
| `2` from `check` | Valid check found at-risk/blocked tasks, overdue unfinished tasks, or an import heartbeat older than the threshold. |

`check` evaluates all tasks; browser filters do not change it. This command does not send messages. Use the optional [email worker](SHARED.md) for queued SMTP status alerts and daily overdue/stale digests, or connect the check's exit code to your scheduler. Shared accounts and role-based editing are available through the self-hosted web server. Approval workflows, attachments, and mobile push are outside the current scope.

## Storage and development

Keep the database on a local disk, outside the published site and source control. `open_tracker/out/`, `*.sqlite`, and `*.db` are ignored inside this module. Exported snapshots contain their rows and change history, so review them before sharing. Back up the SQLite file when no writer is active, or use SQLite's backup facility. The history records local changes and a caller-supplied actor; it is editable by anyone with database access and is not a tamper-evident audit trail or authenticated signature.

Run the behavioral tests:

```sh
python3 -m unittest discover -s open_tracker/tests -p 'test_tracker.py' -v
```

These offline tests exercise idempotency, rollback, input validation, dry runs, snapshot exports, history integrity, and scheduler checks. The [shared-mode guide](SHARED.md) includes the full account, concurrency, and email test suite. The browser is self-contained HTML/CSS/JavaScript; the offline CLI is one Python file. All components use the repository's [MIT license](../LICENSE).
