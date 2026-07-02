# Smartsheet tracker — the no-GUI version (Windows, API-only)

Smartsheet was already mostly code-first (the SHEETLINK `%ss_*` SAS / `ss_companion.R` helpers drive
the REST API). This adds a **self-contained Windows companion** and removes the last GUI hunting, so
the only thing you ever do in the Smartsheet UI is **generate the token, once**.

## The one (and only) Smartsheet GUI step
Account ▸ **Apps & Integrations** ▸ **API Access** ▸ **Generate new access token** → copy it once:
```bat
setx SMARTSHEET_TOKEN "paste-token-here"
```
Open a fresh terminal afterward. (Never hard-code or log the token; the script reads it from the env
and only ever puts it in the auth header.) This screen is stable across Smartsheet versions/devices —
it's the one irreducible click.

## Everything else is code (no IDs to copy from the UI)
[`Update-Smartsheet.ps1`](Update-Smartsheet.ps1) resolves the **sheet by name** (`GET /sheets`),
maps **columns by title** (`GET /sheets/{id}`), and does an **idempotent upsert by a key column**
(`PUT` existing / `POST` new, ≤500/batch) — so you never copy a sheet ID from the URL or a column ID
from the GUI. Run it:
```powershell
.\Update-Smartsheet.ps1 -SheetName "CP-101 Deliverables" -CsvPath .\status.csv `
    -KeyColumn "Deliverable" -AllowColumns "Deliverable","Status","% Complete","Owner","Due"
```
The **CSV** is whatever your scheduled SAS/R monitoring already writes — headers must equal the
Smartsheet column titles; one of them is the `-KeyColumn` (a **text** column, for exact matching).
"Code owns the data; Smartsheet owns the alerts": this writes truthful operational cells; a Smartsheet
Automation a PM set up once decides who gets notified.

## Schedule it (CLI, not the Task Scheduler GUI)
To dodge quoting headaches, put your real arguments in a 2-line wrapper `run_tracker.ps1`:
```powershell
& "$PSScriptRoot\Update-Smartsheet.ps1" -SheetName "CP-101 Deliverables" `
  -CsvPath "C:\Users\you\monitoring\status.csv" -KeyColumn "Deliverable" `
  -AllowColumns "Deliverable","Status","% Complete","Owner","Due"
```
then schedule the wrapper:
```bat
schtasks /Create /TN "Smartsheet Tracker" /SC HOURLY /F ^
  /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\Users\you\smartsheet\run_tracker.ps1\""
```

## Guarantees (mirror the SHEETLINK %ss_* library)
- **Idempotent** — re-running with the same data updates rows in place; never duplicates (match on the text key).
- **Ops-only allowlist guard (the PHI boundary)** — the script **refuses** any CSV column not in
  `-AllowColumns`, and requires each allowlisted column to exist on the sheet. Only push non-sensitive
  operational fields (status, % complete, milestone/QC state, ownership, dates, aggregate counts).
  **Never** participant-level / unblinded / PHI / reported clinical numbers.
- **Token never logged**, read from `$env:SMARTSHEET_TOKEN`.
- **Rate-limit aware** — backs off on HTTP 429 (300 req/min) and 5xx.

## What stays GUI (honest)
- **Notifications**: Smartsheet's automation/workflow builder is GUI-only (the API can't fully create
  workflows). That's a **one-time** setup by a PM — and it's the design on purpose (don't email from
  code). If you want *zero* Smartsheet GUI, you can instead send alerts from your SAS/R/PowerShell side
  (e.g., a Teams webhook) and skip Automations — but then you own the alert logic.
- Token generation (above) — one screen, once.

## Use the SAS/R helpers instead when…
…the update runs **inside** an existing pipeline: `%ss_*` (SAS, EG/Azure) and `ss_companion.R` (R)
already do the same API upsert with the same guarantees. This PowerShell version is for the
**standalone Windows laptop** case and to match the Outlook KB script.

## Honest caveat
API endpoints verified against the Smartsheet 2.0 docs (list sheets / get sheet / add+update rows /
Bearer auth / 429). The script was **structure-verified, not executed** here (no PowerShell on the dev
box) — run/parse it on your Windows machine first. Not validated software.
