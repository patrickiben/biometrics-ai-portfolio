# Operational browser workspaces

TRIALMON, Study Lifecycle, IRT/RTSM UAT, Operational Risk and Hours Reconciliation use the same point-and-click data drawer. Each starts without an active study. **Load fictional example** is an explicit demonstration action; it never silently fills missing study inputs.

1. Download the blank CSV templates, or select your existing CSVs.
2. Choose a source file for each feed and map its columns. Required fields show their expected types; the module’s setup note gives its value conventions.
3. Review the mapping and study assumptions, confirm, and open the workspace. TRIALMON also requires the planned visit schedule, operational thresholds, grading versions and liver-screening conventions.
4. Use the module’s existing controls. **Save complete workspace** downloads a ZIP containing input CSVs, a restorable workspace JSON, computed tables, review notes, software versions and the analysis/validation sources. UAT saves all three editable registers; hours saves the ledger, reserve and requested hours.
5. To resume, select the workspace JSON from that ZIP. Review its mapping before opening it. Reset and browser reload clear active data; they do not delete files already downloaded.

Browser releases process inputs in browser memory. Selecting replacement files immediately hides previous results and disables exports. A failed, incomplete or stale upload cannot reactivate a previous study. Imports are validated as one complete feed set. IDs remain text, including leading zeros. Extra or missing CSV fields, duplicate headers, nonfinite numbers and duplicate source-column mappings are rejected rather than silently repaired.

CSV limits are 16 MiB and 100,000 rows per file, 32 MiB for the combined input set. Saved workspace JSON can be up to 96 MiB; complete result ZIPs can be up to 128 MiB. These larger export/restore limits account for the readable input CSVs also being embedded in the JSON. Spreadsheet-formula-like text is escaped in derived CSV outputs; mapped input CSVs retain the stored source values.

TRIALMON supports the documented eight laboratory parameters and units, one study at a time, and the `SAFFL=Y` safety population. Excluded records remain in saved source inputs and appear in a population audit. The implemented laboratory screens define post-baseline as study day greater than 1; baseline flags must occur on or before day 1. ECG post-baseline is a nonbaseline draw on day 1 or later. Complete supported baseline/post-baseline measurements are required; missing measurements cannot become reassuring green results. The 3+3 display is an illustrative rule reference, not a general dose-finding engine. Medical review and study-specific analysis approval remain necessary.

The scoring and analysis functions remain in each module’s canonical `R/logic.R`. `browser_workspace.R` handles bounded intake, mapping, atomic activation and export; `browser_workspace.js` reads files and constructs downloads without an upload service; CSS follows the toolkit’s theme tokens. `browser_setup.R` holds each module’s input contract.

Maintainer checks: `browser_modules/tests/test-operational.R` verifies editable-state round trips and invalid/stale upload behavior; `test-stub-profile.R` verifies native/browser launcher scoping; `operational-browser.mjs` drives actual webR apps through file selection, mapping, downloads, restoration and rejected replacements. Existing per-module statistical and server suites remain in place.
