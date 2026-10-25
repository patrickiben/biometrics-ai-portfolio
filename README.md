# Patrick Iben: clinical trial biostatistics portfolio

Independent biostatistician: seven years of clinical trial work (Emmes, Syneos Health), including
lead biostatistician on early-phase clinical pharmacology studies, shown here through worked examples
and tools on synthetic data across the clinical trial lifecycle.

**Site:** <https://patrickiben.github.io/biometrics-ai-portfolio/>. Start at the home page: it carries
the lifecycle snapshot, labels each stage, and states the gaps (define.xml and ADRG authoring,
submission packages, DMC charters, group-sequential interim design).

Every dataset here is **synthetic**. Nothing is real trial data, and nothing here is a validated or
regulatory deliverable.

## Status labels

Each module states what was actually executed:

| Label | Meaning |
|---|---|
| **Runs** | Executed here; the page says how and when |
| **Parse-checked** | The code parses; it has not been run on data |
| **Not executed** | Written for a tool that was not available (SAS: no license) |
| **Structural check** | Inventories, pattern scans or counts, not a numeric comparison |
| **Manual record** | Entered by hand, not computed |
| **Under revision** | Known issues are listed on the page; fixes come in the next revision |

The home page's lifecycle labels are narrower still: **Led** (owned, wrote or led the work in a job),
**Supported** (reviewed, contributed, or created or reviewed), **Tools built** (shown only by code
here), **Gap** (no job experience or no worked artifact yet).

## What is here

| Folder | What it is | Status |
|---|---|---|
| [`sim_lifecycle/`](sim_lifecycle/index.html) | PK, NCA and bioequivalence sandbox: one synthetic 2x2 crossover in base R (eight ADaM-shaped domains, NCA, geometric mean ratio with 90% CI) | Runs (R 4.6.0) and regenerates its committed outputs byte for byte |
| [`sas_tlf_pseudocode/`](sas_tlf_pseudocode/index.html) | 217 SAS TLF programs across five early-phase designs | Not executed (no SAS license) |
| [`r_tlf_pseudocode/`](r_tlf_pseudocode/index.html) | The R twin: 217 scripts | Parse-checked (R 4.6.0); not run on data |
| [`validation_harness/`](validation_harness/index.html) | Eight-gate QC harness and evidence ledger | Structural checks plus a re-run of the sandbox (G1); G5 is a manual record; no gate signed yet |
| [`tlf_interpret/`](tlf_interpret/index.html) | Number-grounding check for drafted TLF text | Self-test runs without a model; the language-model step is a stub |
| [`sasr_onleave_wiki/`](sasr_onleave_wiki/Continuity_Toolkit.html) | Continuity and handoff toolkit, and the coverage playbook | Toolkit runs in the browser; the SAS/R macros are not executed |
| [`uat_irt/`](uat_irt/quarto/uat-guide.html) | IRT/RTSM acceptance-test library: workbook, Shiny tracker, static guide | Unit tests pass locally; synthetic test data |
| [`biostat_pipeline/`](biostat_pipeline/EarlyPhase_Biostat_Pipeline.md) | Reference map of 136 Phase 1 biostatistics deliverables (document, register, one-page map) | A reference map, not a track record; the AI-routing overlay is a proposal |
| [`sasr_monitoring_wiki/`](sasr_monitoring_wiki/SASR_Monitoring_Coverage_Wiki.html) | TRIALMON participant-safety screening demo and the SAS/R monitoring wiki | Under revision: CP101-009 lacks a repeat-testing flag (see the page) |
| [`risk_monitor/`](risk_monitor/quarto/risk-guide.html) | Two-tier trial early-warning console (Shiny and Quarto) | Under revision: the averaging roll-up dilutes a red signal (see the page) |
| [`sas_r_automation/`](sas_r_automation/SAS_R_Trial_Monitoring_Automation.html) | Deterministic SAS/R monitoring macro library and wiki | Not executed (no SAS license) |
| [`smartsheet_sasr/`](smartsheet_sasr/Smartsheet_SASR.html) | Tracker updates from SAS/R through the Smartsheet API | R companion run against a local mock API; SAS not executed |
| [`lifecycle_dashboard/`](lifecycle_dashboard/quarto/lifecycle-guide.html) | Deliverable status report for a synthetic study portfolio, with a [field guide](lifecycle_dashboard/Study_Lifecycle_Monitor_FieldGuide.html) | Unit tests pass locally; static snapshots |
| [`budget_reconciliation/`](budget_reconciliation/quarto/hours-guide.html) | Effort (hours) reconciliation example | Illustration on synthetic data |

Research and teaching (six manuscripts and twelve educational editions) are on the
[research map](https://github.com/patrickiben/patrickiben/blob/main/RESEARCH_MAP.md).

## In-browser eCRF apps (separate repository)

Four Python apps that run in the browser on synthetic data. Files you load are processed on your
device and are not uploaded by the app; GitHub Pages, jsDelivr and PyPI serve the page and see your IP
address. The first visit downloads about 30 MB. Not a validated or Part 11 system.

- [Coding QC assist](https://patrickiben.github.io/ecrf-pipeline-apps/app/meddra.html)
- [De-identification review assist](https://patrickiben.github.io/ecrf-pipeline-apps/app/phi.html)
- [Protocol-criteria safety listing](https://patrickiben.github.io/ecrf-pipeline-apps/app/risk.html)
- [Central statistical monitoring](https://patrickiben.github.io/ecrf-pipeline-apps/app/anomaly.html)

Overview: <https://patrickiben.github.io/ecrf-pipeline-apps/>. Source:
<https://github.com/patrickiben/ecrf-pipeline-apps>.

## How I work

Validated systems own reported numbers, a named statistician signs every deliverable, and this site
uses synthetic data only. In a study, reported numbers come from validated, double-programmed SAS/R
TLF programs on ADaM; NCA from Phoenix WinNonlin (version per the ADRG, currently 8.8) or PKNCA; CDISC
conformance is checked with Pinnacle 21, which produces no reported numbers. AI tools may draft or
check text; they never produce a reported number. Several modules were drafted with AI assistance;
where an AI-agent review panel was used, the page says so, and human sign-off is recorded only where
it was given (none yet in the validation ledger).

## Run it locally

The site is static HTML with relative links.

```sh
git clone https://github.com/patrickiben/biometrics-ai-portfolio.git
cd biometrics-ai-portfolio
python3 -m http.server 8000      # then open http://localhost:8000/index.html
```

R (R >= 4.4.0; tested on 4.6.x):

```sh
Rscript sim_lifecycle/run_lifecycle.R                          # the sandbox; base R only
Rscript validation_harness/checks/conformance.R sim_lifecycle/out
bash validation_harness/run_harness.sh                          # rewrites the evidence ledger (R and python3)
Rscript uat_irt/tests/test-logic.R                              # each Shiny module has tests/test-logic.R
```

The Shiny apps run in local R, for example `shiny::runApp("uat_irt/shiny")` after
`install.packages(c("shiny", "bslib", "DT", "ggplot2"))`. The same pattern works for
`lifecycle_dashboard/shiny`, `budget_reconciliation/shiny`, `risk_monitor/shiny` and
`sasr_monitoring_wiki/trialmon_shiny`.

The SAS programs are written for SAS 9.4M8 or later (9.4M9, June 2025, is current) and have not been
executed here.

## Package check

`python3 package_qc.py` checks local links (HTML and Markdown), retired content, empty link cards,
navigation and this README's inventory, terminology, framing and count drift. GitHub Actions runs it
on every push and pull request. Add `--external` to also request each external link once. It checks
the package, not the statistics.

## Contact

patrickiben@gmail.com · [github.com/patrickiben](https://github.com/patrickiben) ·
ORCID [0009-0005-2443-7973](https://orcid.org/0009-0005-2443-7973) · St. Petersburg, FL / Remote US

## License

MIT; see [`LICENSE`](LICENSE).
