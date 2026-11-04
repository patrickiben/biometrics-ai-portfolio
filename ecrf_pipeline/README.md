# eCRF review tools in the Trial Biostatistics Toolkit

Open the [eCRF workspace](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/) or the [toolkit setup page](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html). All four tools run directly in your browser with your own CSV files: no Python installation, toolkit download, account or command line is needed. Each starts blank; **Load synthetic example** is optional.

| Tool | Guided input | Browser result |
|---|---|---|
| [Coding QC assist](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/meddra.html) | Study CSVs, selected verbatim/identifier fields, and your dictionary CSV with mapped term, preferred-term and optional code/hierarchy/currency columns | Unreviewed lexical candidates, scores, input mapping and audit; complete review ZIP |
| [De-identification review assist](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/phi.html) | Selected CSV fields, identifier patterns and optional literal terms | Redacted field copies and audit in one ZIP; originals, matched spans and literal terms only in a separate sensitive-review download |
| [Participant risk screening](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/risk.html) | One study's safety CSVs, mapped fields/categories, units and configurable screening criteria | Rule-based scores, contributing signals, coverage and complete review ZIP |
| [Anomaly and drift screening](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/anomaly.html) | One wide CSV, participant/measurement mappings, units, optional site and explicit paired visits | Numeric outlier, drift, lab/site and text-isolation screens with audit and complete review ZIP |

The [User Guide](USER_GUIDE.md) walks through each form. Changing inputs or settings clears previous results and downloads. Download the complete package before resetting, closing or reloading the tab. Light/dark mode follows the toolkit preference, with a switch on each page.

## What runs in the browser

The browser runs these independent Python programs through pinned stlite/Streamlit and Pyodide. Browser intake is enabled only when the program is actually running on WebAssembly (`sys.platform == 'emscripten'`) and the reviewed loader sets `ECRF_BROWSER=1`. The app software loads from the site and its declared runtime sources; uploaded study files are processed in the tab and are not sent to a server by the app. Files and results remain session-only. Hosting/runtime providers receive ordinary asset requests, including the visitor's IP address.

Coding uses the existing lexical hashing and weighted review score. A threshold highlights suggestions; **every candidate remains unreviewed**, including exact matches. It does not auto-approve a code, resolve negation or infer semantic equivalence. User data requires a user-provided dictionary; the example dictionary is never substituted for an upload. MedDRA is not bundled. The synthetic example uses 99-prefixed placeholder codes, not MedDRA codes. Preserve your dictionary's version and licensing requirements.

De-identification uses the existing guarded patterns and co-occurring indirect-identifier rules, with user-selected literal matches added explicitly. The redacted package replaces the selected export fields in place and excludes original copies, flagged span text and custom literal terms. The separate sensitive-review package contains those originals. Neither missing flags nor a redacted export establishes complete anonymization: undetected identifiers and selected headers can remain.

Risk scores are capped, weighted screening indices, not probabilities or clinical determinations. Threshold starting values are illustrative; users confirm mappings, units and criteria. Missing domains are not assessed. Anomaly screening uses median/MAD robust z scores, the existing 200-point quantile-grid drift approximation and bag-of-words text isolation. Paired comparisons require complete matched visits, constant lab/site within each pair, and explicit measurement units. They are bounded screening methods, not a general longitudinal model or an exact optimal-transport analysis.

The optional native learned-model path—Needle3, Laya, hnswlib and trained XGBoost artifacts—is separate. The browser does not claim to execute those models. Risk has no trained-model path; anomaly's optional native Isolation Forest and Sinkhorn engines are not the browser algorithms.

## Inputs and exports

Browser inputs are UTF-8 CSV with a header, unique column names, consistent row widths and finite numeric values where required. Leading zeros in identifiers are preserved. Invalid replacements stop execution and clear stale outputs. Filenames cannot supply filesystem paths; exports use controlled names. The forms report applicable row, column and size limits.

Coding/PHI accept up to 10 study CSVs, 10 MiB per file and 20 MiB total, with 50,000 rows and 200 columns per file. Coding dictionaries allow up to 100,000 rows within the same 10 MiB file limit; a coding run is bounded to 10,000 nonblank rows and 1,000 distinct verbatims. PHI runs are bounded to 100,000 selected cells and 10,000 distinct values. Risk/anomaly use smaller screening batches: 2 MiB per CSV, 8 MiB total and 5,000 rows / 100 columns per file; anomaly takes one wide CSV per run.

CSV downloads escape text that could execute as a spreadsheet formula. Coding's JSON files preserve the original selected strings. Unmapped study columns are excluded from its package. PHI's sensitive-review JSON preserves selected originals separately from redacted output. Audits record effective settings, mappings, input hashes and the algorithm used. These are ordinary review artifacts, not access-controlled audit trails or electronic signatures.

## Evaluation and QC evidence

The [evaluation](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/evaluation.html) and [worked case study](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/case-study.html) preserve the original synthetic/native evidence. Their historical automatic-commit labels and original side-by-side PHI exports describe that evaluated implementation, not the current browser output contract.

Those historical results include coding rank-1 accuracy of 78% for the native learned path versus 54% for the lexical path on the held-out synthetic set, and 91 versus 108 of 308 identifiers left readable. They do not estimate performance on a user's study, licensed dictionary or adapted settings. Risk and anomaly have known-answer QC, not measured clinical accuracy. The within-sibling evaluation is a separate test of the original lexical implementation.

Software QC covers native compatibility, strict browser intake, guided mapping, known answers, exports, stale state, reset, privacy boundaries and actual browser execution. Reproduction sources remain in [`tests/qc_test.py`](tests/qc_test.py), [`eval/README.md`](eval/README.md) and the toolkit's build checks. The four programs retain independent algorithms and audit records; consolidation does not merge their scientific scopes.

## Optional local/native use

Local operation remains available for users who need filesystem input, SAS `.sas7bdat`, licensed ASCII dictionary releases or the optional learned models. From this `ecrf_pipeline/` directory, macOS users can double-click a `Launch … .command` file; Windows users can use the corresponding `.bat`. The launchers create a local environment and open Streamlit. This optional route installs software and is separate from the browser workflow above.

The existing `run_meddra.sh`, `run_phi.sh`, `run_risk.sh` and `run_anomaly.sh` commands and [`requirements.txt`](requirements.txt) remain available. The native model setup is documented in [`eval/README.md`](eval/README.md). Native coding can emit its historical automatic-commit status, and native PHI retains original columns beside `SAN_<field>`; treat those exports according to their documented scope. Browser-specific review labels and clean/sensitive download separation do not silently change the native algorithm.

A server operator may deliberately enable `ECRF_HOSTED=1` for the locked synthetic demo. That switch remains fail-closed and takes precedence over browser intake. It is not how the integrated own-data browser workspace is launched. A server deployment has different upload/privacy requirements; see the native comments and [`USER_GUIDE.md`](USER_GUIDE.md).

## Maintenance and license

The canonical sources are the four `*_app.py` files. `tools/sync_browser_apps.py` creates the byte-identical app/data copies under `docs/app/` and the pinned browser shells. Keep that build synchronized when changing sources; the toolkit build and QC check it. `docs/theme.js` and `docs/theme.css` use the toolkit theme preference without persisting study data.

Apache-2.0 applies to this imported module. Retain [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE), including bundled third-party wheel notices. The original repository history and evaluation artifacts were imported with the module. Current source and issue handling belong to [the Trial Biostatistics Toolkit](https://github.com/patrickiben/biometrics-ai-portfolio/tree/main/ecrf_pipeline).
