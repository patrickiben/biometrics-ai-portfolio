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
**Supported** (reviewed, contributed, or created or reviewed), **Tools built** (shown only by
independent work: code here or public drafts, not job experience), **Gap** (no job experience or no
worked artifact yet).

## What is here

| Folder | What it is | Status |
|---|---|---|
| [`sim_lifecycle/`](sim_lifecycle/index.html) | PK, NCA and bioequivalence sandbox: one synthetic 2x2 crossover in base R (eight ADaM-shaped domains, NCA, geometric mean ratio with 90% CI) | Runs (R 4.6.0) and regenerates its committed outputs byte for byte |
| [`study/`](study/index.html) | Flagship worked example: one synthetic 2x2 bioequivalence study taken from sample size and randomization through the SAP, ADaM (admiral), NCA (PKNCA), the ICH M13A analysis, rtables/tern tables, QC and CSR text | Runs from `study/run_all.R` (R 4.6.0; versions pinned in `study/renv.lock`); QC is same-author re-derivation; define.xml and ADRG not authored |
| [`sas_tlf_pseudocode/`](sas_tlf_pseudocode/index.html) | 217 SAS TLF programs across five early-phase designs | Not executed (no SAS license) |
| [`r_tlf_pseudocode/`](r_tlf_pseudocode/index.html) | The R twin: 217 scripts | Parse-checked (R 4.6.0); not run on data |
| [`validation_harness/`](validation_harness/index.html) | Eight-gate QC harness and evidence ledger | Structural checks plus a re-run of the sandbox (G1); G5 is a manual record; G7 is not signed; no gate signed yet |
| [`tlf_interpret/`](tlf_interpret/index.html) | Number-grounding check for drafted TLF text | Self-test runs without a model; the language-model step is a stub |
| [`sasr_onleave_wiki/`](sasr_onleave_wiki/Continuity_Toolkit.html) | Continuity and handoff toolkit, and the coverage playbook | Toolkit runs in the browser; the SAS/R macros are not executed |
| [`uat_irt/`](uat_irt/quarto/uat-guide.html) | IRT/RTSM acceptance-test library: workbook, Shiny tracker (local R or in the browser), static guide | Unit and `shiny::testServer()` tests pass locally; synthetic test data |
| [`biostat_pipeline/`](biostat_pipeline/EarlyPhase_Biostat_Pipeline.md) | Reference map of 132 Phase 1 biostatistics deliverables (document, register, one-page map) | A reference map, not a track record; an appendix holds a proposal for AI-assisted drafting under controls |
| [`sasr_monitoring_wiki/`](sasr_monitoring_wiki/index.html) | TRIALMON safety review: a Safety Review Committee packet, a Shiny console (Shinylive-ready) and the screening rules for a synthetic dose-escalation study, with the former `risk_monitor/` tiers merged in (that folder now redirects here) | Runs (R 4.6.0); testthat and `shiny::testServer()` tests pass; pages rendered with Quarto 1.10.19 |
| [`sas_r_automation/`](sas_r_automation/SAS_R_Trial_Monitoring_Automation.html) | Deterministic SAS/R monitoring macro library and wiki | Not executed (no SAS license) |
| [`smartsheet_sasr/`](smartsheet_sasr/Smartsheet_SASR.html) | Tracker updates from SAS/R through the Smartsheet API | R companion run against a local mock API; SAS not executed |
| [`lifecycle_dashboard/`](lifecycle_dashboard/quarto/lifecycle-guide.html) | Deliverable status report for a synthetic study portfolio, with a [field guide](lifecycle_dashboard/Study_Lifecycle_Monitor_FieldGuide.html) | Unit tests pass locally; static snapshots |
| `apps/` | Where the site serves three Shiny apps in the browser: TRIALMON, the UAT tracker and the lifecycle console. The Pages workflow (`.github/workflows/pages.yml`) builds them with Shinylive; the committed pages are placeholders, and the build output is not committed | Exported and checked in headless Chrome locally; Safari and Firefox not checked |
| [`budget_reconciliation/`](budget_reconciliation/quarto/hours-guide.html) | Effort (hours) reconciliation example | Illustration on synthetic data |

Research and teaching (six manuscripts and twelve educational editions) are on the
[research map](https://github.com/patrickiben/patrickiben/blob/main/RESEARCH_MAP.md).

## eCRF assist apps (separate repository)

Four Python apps on synthetic data: coding QC assist, de-identification review assist, participant
risk screening (rule-based default thresholds) and central statistical monitoring. Their evaluation
reports measured failures; for example, on held-out synthetic text the de-identification stand-in
left 108 of 308 identifiers readable (the full model path: 91 of 308). They run in the browser
from GitHub Pages on bundled synthetic data, with uploads disabled; GitHub Pages and jsDelivr,
which serve the page, see the visitor's IP address (about 30 MB on first visit):
[coding QC](https://patrickiben.github.io/ecrf-pipeline-apps/app/meddra.html) · [de-identification](https://patrickiben.github.io/ecrf-pipeline-apps/app/phi.html) ·
[risk screening](https://patrickiben.github.io/ecrf-pipeline-apps/app/risk.html) · [central monitoring](https://patrickiben.github.io/ecrf-pipeline-apps/app/anomaly.html)
([overview](https://patrickiben.github.io/ecrf-pipeline-apps/)). Result screenshots for the home page are in
`assets/ecrf/`. Not a validated or Part 11 system.

Source and evaluation: <https://github.com/patrickiben/ecrf-pipeline-apps>.

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
`lifecycle_dashboard/shiny`, `budget_reconciliation/shiny` and
`sasr_monitoring_wiki/trialmon_shiny`.

Three of them (TRIALMON, the UAT tracker and the lifecycle console) also run in the browser from
the site, built with Shinylive (webR) by `.github/workflows/pages.yml`. To build the whole site
locally, with shinylive 0.5.0 and the apps' packages installed (build outside the checkout, so
`package_qc.py` and the harness do not scan the build):

```sh
Rscript .github/pages/build_site.R ../portfolio-site             # static pages plus the three apps
python3 -m http.server 8000 --directory ../portfolio-site        # then open http://localhost:8000/apps/trialmon/
```

The SAS programs are written for SAS 9.4M8 or later (9.4M9, June 2025, is current) and have not been
executed here.

## Package check

`python3 package_qc.py` checks local links (HTML and Markdown), retired content, empty link cards,
navigation and this README's inventory, terminology, framing and count drift. It also reads the text
of every published spreadsheet, Word file, slide deck, PDF (with `pdftotext`) and JSON file for the
same framing, terminology and spelling checks. GitHub Actions runs it
on every push and pull request. Add `--external` to also request each external link once. It checks
the package, not the statistics.

## Contact

patrickiben@gmail.com · [github.com/patrickiben](https://github.com/patrickiben) ·
ORCID [0009-0005-2443-7973](https://orcid.org/0009-0005-2443-7973) · St. Petersburg, FL / Remote US

## License

MIT; see [`LICENSE`](LICENSE).
