# Browser workflows

[Open the module catalog](https://patrickiben.github.io/biometrics-ai-portfolio/toolkit_launcher/index.html) or the [point-and-click guide](../TOOLKIT_SETUP.html). Core workflows require no local R, Python, toolkit download or account. Study identifiers, column mappings and assumptions belong to the user; no client is preconfigured.

| Workspace | Browser scope |
|---|---|
| Five operational R apps | TRIALMON, lifecycle, UAT, risk and hours: blank startup, explicit synthetic example, validated complete CSV import, study mappings and full workspace export. |
| Vaccine | All six existing canonical R analyses; mapped inputs, study settings, reports, complete results and configured SAS reference. |
| TLF libraries | All 221 R programs across parallel, crossover, fixed sequence, SAD and MAD; guided study forms and configured SAS references. Inputs must already contain documented analysis-ready variables. |
| Monitoring | All eight canonical R checks, reviewed thresholds/data cut and configured SAS references. No automated clinical decisions. |
| Interpretation | Canonical R recomputation and deterministic factual drafting for the documented aggregate AE/PK contracts; editable prose and number/claim checks. |
| Methods | Configurable sandbox, carryover and C-QTc simulations; the worked study reproduces its fixed synthetic six-stage analysis. It is not a general uploaded-study workflow. |
| Validation | Original ten gates and eighteen frozen seeded defects, run against a reviewed toolkit snapshot. Manual, unsigned, stale and partial-evidence states remain distinct. Arbitrary uploaded code is not executed. |
| LOCALMIND | Editable manual findings worklist; optional browser-local WebGPU inference returns controlled suggestions that are neither applied nor approved automatically. |
| Deliverables register | Blank workspace or full 132-row reference; every field editable, JSON/CSV/print, complete exports even when filtering. |
| Existing browser tools/references | Tracker, continuity, coverage wiki, playbook and vaccine learning companion retain their browser workflows. External eCRF/evaluation links remain separately maintained public demos with their stated upload restrictions. |

Shared accounts, schedules, connected feeds and email are optional service connections. They need a chosen host or provider; opening this toolkit does not provision a client deployment or send messages. The desktop toolkit remains an optional reproduction path.

## Data and persistence

The new analysis, method, operational-app and register workspaces use session memory. Reset, reload and closing discard unsaved work. Download complete outputs and workspace/profile files to retain work. Profiles transfer settings; they do not establish scientific approval. Existing tracker/continuity storage is described on those pages.

The analysis workbench accepts UTF-8 CSVs up to 16 MiB and 100,000 rows per input and exports at most 256 MiB of results. It validates complete rows, unique headers, column mappings and canonical analysis contracts. Rejected replacements remove the previous input. Settings changes invalidate earlier validation/results. Complete files are retained even where previews are paginated or shortened. Choose scientifically prespecified subsets or output batches; never discard eligible records to meet a software limit. Each Shiny workspace documents its own limits.

Reviewed source and runtime files are downloaded to the browser. Study files are not uploaded to an analysis server. Validation runs the reviewed public source snapshot, not uploaded arbitrary R/Python code. Runtime downloads reveal ordinary web-request metadata to the site host.

LOCALMIND model loading is a separate explicit action. WebLLM 0.2.87 is bundled with its Apache-2.0 license; Qwen2.5-0.5B-Instruct model files and the compiled MLC library are downloaded from their public hosts only on request. WebGPU and approximately 1.1 GB graphics memory are required. Model assets may be cached; finding text and review records remain in memory. Unsupported devices retain the manual review workflow. Model output is not evidence of scientific validity or validated model performance.

## Scientific and software boundaries

Canonical R/Python providers and numerical functions are reused. The browser adapters handle inputs, execution and export; they do not replace the statistical methods with JavaScript approximations. Method scenarios and their stated exploratory scope remain intact. Full reports retain assumptions, missingness, exclusions, diagnostics and software versions. Native SAS code remains unexecuted reference material.

Browser QC includes real Chromium/WebAssembly execution, native-versus-browser numerical comparisons, invalid inputs, reset/stale-result behavior, exports, themes and responsive layouts. The [QC report](../QC_REPORT.md) records the completed release evidence and limitations. Desktop Chromium is the main tested R path. Existing launch pages retain explicit Safari/WebKit startup failure handling. Large simulation and seeded-defect runs can take many minutes; computation requires an open tab.

## Implementation

- `workbench/`: reviewed guided-provider Python worker, direct webR execution and optional WebLLM worker.
- `methods/`: Shiny interface over canonical method and worked-study sources.
- `shared/`: atomic mapped-input and complete-workspace export controls for the five operational apps.
- `validation/`: asynchronous scheduling adapter over the original gates and defect registry.
- `register/`: session-only editable deliverables register.
- `engine/`: build-only declaration of browser R package dependencies; not a user-facing app.

The Pages build verifies runtime locks, packages reviewed source archives with SHA-256 inventories, and exports the registered Shiny apps. Browser test evidence and screenshots are generated outside the source checkout. Upstream runtimes retain their own licenses; toolkit code is MIT licensed.
