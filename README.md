# Trial biostatistics toolkit

Open-source tools, templates and worked examples for **biostatistics consultants and employees** across study planning, programming, operations and reporting. The worked examples focus on **early-phase clinical pharmacology**; each tool can be adapted where its methods and input contract fit the study.

**[Choose your task and get started](https://patrickiben.github.io/biometrics-ai-portfolio/GET_STARTED.html)** · [Home](https://patrickiben.github.io/biometrics-ai-portfolio/index.html) · [Full library](https://patrickiben.github.io/biometrics-ai-portfolio/START_HERE.html)

**[Point-and-click setup for the whole toolkit](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html)** · [Control panel and module catalog](https://patrickiben.github.io/biometrics-ai-portfolio/toolkit_launcher/index.html) · [Download the complete ZIP](https://github.com/patrickiben/biometrics-ai-portfolio/archive/refs/heads/main.zip)

Download and extract the ZIP, then double-click **Start Toolkit.command** (macOS) or **Start Toolkit.cmd** (Windows). The local browser control panel covers all five Shiny apps, the reproducible R examples, QC checks, browser workspaces, paired SAS/R libraries and configuration templates. Create a **private project from examples** for each study or engagement, check dependencies, install supported R packages, open apps, upload documented inputs and export the project through the GUI. Python 3.10+ starts the control panel; each card identifies any additional runtime installer. The Linux launcher is **Start Toolkit.sh**.

The [`toolkit_launcher/`](https://patrickiben.github.io/biometrics-ai-portfolio/toolkit_launcher/index.html) catalog distinguishes runnable examples from templates and references. The three published Shinylive apps and browser-only workspaces can still be tried without local installation. The external eCRF apps remain a separate repository. The [shared tracker setup](https://patrickiben.github.io/biometrics-ai-portfolio/open_tracker/SETUP.html) handles its accounts, hosting and optional email.

**Guided template setup:** choose study design and outputs, upload and map CSV inputs, preview requirements, then generate a versioned study package. Forms cover the SAS/R TLF libraries, monitoring checks, LOCALMIND findings and AE/PK draft reports. Save or import setup profiles to reuse choices across projects. Supported study settings no longer require code edits; unfinished analysis methods and shells remain explicitly identified for implementation and review.

**This is a general-purpose toolkit, not a deployment for a specific client.** A new private project contains fictional starter data, not an empty or already configured production study. Source files, generated results and logs are retained in that project. Export app/session data before closing; a project ZIP does not capture unsaved Shiny state or browser storage. The shared tracker’s database and settings live outside that workspace ZIP; use its separate backup controls. SAS pseudocode and model templates still require implementation and review in your licensed/approved tools. See [the setup guide](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html) for inputs, persistence, runtime installation and all 22 module paths, and [QC_REPORT.md](QC_REPORT.md) for the October 2026 QC scope.

<details>
<summary>Optional terminal interface for R users</summary>

```sh
Rscript launch_app.R --list
Rscript launch_app.R --check
Rscript launch_app.R trialmon --install
# Also: lifecycle, uat, risk, hours.
```

The R launcher finds the complete checkout from another working directory. Package downloads happen only with `--install` and target a user library.

</details>

**Site:** <https://patrickiben.github.io/biometrics-ai-portfolio/>

**Author:** Patrick Iben

---

## What's inside

**Statistical programming (SAS + R)**
- **ADaM-based TLF pseudocode libraries:** 221 Table/Listing/Figure programs **each** in SAS and R
  (pharmaverse: `dplyr` + `rtables` + `ggplot2` + `emmeans`), across every early-phase design
  (parallel, crossover, single/fixed-sequence, SAD, MAD). Geometric PK on the log scale, distinct-participant
  counts, period denominators. The SAS programs have not been executed (no SAS license); the R programs
  parse but have not been run on data.
  → [`sas_tlf_pseudocode/`](sas_tlf_pseudocode/index.html) · [`r_tlf_pseudocode/`](r_tlf_pseudocode/index.html)
- **Worked bioequivalence study:** one 2x2 crossover taken from PowerTOST sample size and a blockrand schedule
  through an ICH E9(R1) estimand and SAP excerpt, admiral ADaM with a Pinnacle 21-layout specification and XPT
  files, PKNCA, the ICH M13A analysis, rtables/tern tables with RTF, a QC re-derivation by a second method and
  CSR section 11-style text. One script (`study/run_all.R`) regenerates every output and CI reruns it. QC is a
  same-author re-derivation, not independent double programming. → [`study/`](study/index.html)
- **Synthetic ADaM generator + study-lifecycle sandbox:** a self-contained R generator (one-compartment oral
  PK + NCA, a 2x2 bioequivalence crossover, per-period safety domains) that emits 8 ADaM domains and runs
  demographics, PK/NCA and the bioequivalence ANOVA end to end. → [`sim_lifecycle/`](sim_lifecycle/index.html)
- **Operating-characteristics studies:** residual carryover and the ICH M13A 5% pre-dose rule
  ([`sim_lifecycle/carryover_oc/`](sim_lifecycle/carryover_oc/index.html)), and a prespecified C-QTc hysteresis
  check with its size and power ([`cqtc_hysteresis/`](cqtc_hysteresis/index.html)).
- **Protocol→CSR deliverables pipeline** and a **TLF-interpretation drafter** (a small-model skeleton that
  never sources a number; the model step is a stub and the number validator runs).
  → [`biostat_pipeline/`](biostat_pipeline/EarlyPhase_Biostat_Pipeline.pdf) · [`tlf_interpret/`](tlf_interpret/index.html)
- **eCRF pipeline apps** (separate repo): four independent Python (Streamlit) apps for clinical eCRF extracts:
  MedDRA-style auto-coding, PII/PHI redaction, participant risk scoring, and anomaly and drift detection. They
  run in the browser (stlite), so nothing is sent to a server; the demos use synthetic data and placeholder
  codes, not MedDRA.
  → [overview](https://patrickiben.github.io/ecrf-pipeline-apps/) · [coding](https://patrickiben.github.io/ecrf-pipeline-apps/app/meddra.html) ·
  [PHI](https://patrickiben.github.io/ecrf-pipeline-apps/app/phi.html) · [risk](https://patrickiben.github.io/ecrf-pipeline-apps/app/risk.html) ·
  [anomaly](https://patrickiben.github.io/ecrf-pipeline-apps/app/anomaly.html) · [source](https://github.com/patrickiben/ecrf-pipeline-apps)

**Operational tooling (no AI required)**
- **Deterministic SAS/R monitoring + coverage for leave and handoffs:** configuration templates for scheduled
  checks, evidence packets and notifications. Paths, schedules and recipients require local configuration;
  the templates do not detect sensitive content or enforce an organization's data-sharing policy.
  → [`sas_r_automation/`](sas_r_automation/SAS_R_Trial_Monitoring_Automation.html) · [`sasr_monitoring_wiki/`](sasr_monitoring_wiki/SASR_Monitoring_Coverage_Wiki.html)
- **Coverage and continuity toolkit:** the leave playbook generalized to five scenarios (planned leave,
  unplanned absence, role handoff or departure, a new owner taking over, bus-factor review), plus an interactive
  single-file page: enter or import the recurring jobs you run for a client (owner, backups, schedule, inputs,
  outputs, criticality, last run, runbook) and get a coverage matrix, uncovered and single-owner risks, a
  checklist per job, and a printable or downloadable handoff packet. Data stays in the browser (localStorage +
  JSON/CSV export); no network requests; ships with a clearly fictional example.
  → [`sasr_onleave_wiki/`](sasr_onleave_wiki/Continuity_Toolkit.html) · [playbook](sasr_onleave_wiki/On_Leave_Coverage_Playbook.html) · [CSV template](sasr_onleave_wiki/continuity_jobs_template.csv)
- **Open Study Tracker:** an MIT-licensed deliverables tracker with local SQLite storage, keyed CSV/JSON
  imports, dry runs and change history. Use the offline browser workspace to review and edit status, then
  exchange files with scheduled R/SAS jobs. The offline version needs no account or API key. Optional
  self-hosted shared mode adds individual logins, viewer/editor permissions, conflicting-edit protection,
  and queued SMTP alerts with retries and daily exception digests.
  → [`open_tracker/`](open_tracker/index.html) · [file workflow](open_tracker/README.md) · [shared accounts and email](open_tracker/SHARED.md)
- **IRT / RTSM user acceptance testing:** UAT of the randomization and supply system from the biostatistics
  lens: a test-script library, traceability matrix, defect log, and execution checks for human review.
  The workbook and Shiny app have separate checks; neither authorizes go-live.
  → **[fillable Excel workbook](uat_irt/UAT_IRT_RTSM_Workbook.xlsx)** · [`uat_irt/`](uat_irt/quarto/uat-guide.html)
- **Hours "find-hours" reconciliation:** where the hours come from when out-of-scope work lands: a
  planned-vs-actual-vs-EAC effort reconciliation + decision tree (slack → contingency → defer → change order),
  with an interactive worksheet. Hours and effort only, no dollars.
  → **[fillable Excel workbook](budget_reconciliation/Hours_Budget_Reconciliation_Workbook.xlsx)** · [`budget_reconciliation/`](budget_reconciliation/quarto/hours-guide.html)
- **LOCALMIND macro library:** deterministic SAS/R macros that call a local, offline small language model for
  the text layer only (classify, extract, draft); SAS/R owns every number. → [`slm_wiki/`](slm_wiki/macro_library/README.md)

**Interactive dashboards** (synthetic example data)
- Participant-safety monitoring (**TRIALMON**, with a Safety Review Committee packet), trial-risk early warning
  (participant and study tiers), and a study-lifecycle monitor.
  → [`sasr_monitoring_wiki/TRIALMON_Dashboard.html`](sasr_monitoring_wiki/TRIALMON_Dashboard.html) · [`risk_monitor/`](risk_monitor/quarto/risk-guide.html) · [`lifecycle_dashboard/`](lifecycle_dashboard/quarto/lifecycle-guide.html)
- The TRIALMON, UAT and lifecycle R Shiny apps also run in the browser with Shinylive:
  [`apps/`](apps/trialmon/) (TRIALMON) · [UAT tracker](apps/uat_irt/) · [lifecycle monitor](apps/lifecycle_dashboard/).

**Validation & QC**
- **Trial-Management Validation Harness:** ten gates (reproducibility, PK and count conventions, data structure
  and integrity, SAS/R twin structural parity, an adversarial QC panel, reporting conventions, AI-use
  documentation, package consistency, an independent recomputation of the sandbox results, and a seeded-defect
  test of what the gates catch). The checks run on this repo's own libraries and synthetic data and write an
  evidence ledger: 8 of 10 green, the QC panel is a manual record, and the AI-use record awaits sign-off.
  → [`validation_harness/`](validation_harness/index.html)

---

## Principles the work is built on

- **Validated tools own every reported number** (Phoenix WinNonlin, Pinnacle 21, the EDC): a language model
  never produces a regulated number; AI drafts the words *around* a number, behind a human gate.
- **Operations only:** no PHI, no participant-level data and no unblinded assignments leave the client's systems.
- **"Participant," not "subject"** in prose; CDISC variables (`USUBJID`/`SUBJID`) preserved exactly.
- **A named statistician signs every deliverable.** Automation drafts and checks; it never decides.
- **Run locally where confidentiality and reproducibility matter**; a pinned, frozen model for anything regulated.

---

## Notes

- **Synthetic example data.** The generator's *design structure* is informed by public early-phase registration
  patterns on ClinicalTrials.gov; all participant-level data is simulated from generic domain priors. Nothing
  here is real trial data.
- These are working templates and tools to adapt and validate for each client study, not validated
  production systems.

## Design

The original pages (home, Operations, Biostatistics, the full library and the module pages) keep their
layouts and use a shared light/dark adapter with `site.css`, `site.js`, `_mc-topbar.html` and `_quarto-mc.scss`. The newer pages (the worked study, the
method studies, the harness page and the app launch pages) are built by `build_pages.py` from
`assets/theme/tokens.css` into [`assets/`](assets/theme/tokens.css) (`toolkit.css`, `ui.js`) and `_partials/`;
`python3 build_pages.py --check` confirms they are current.

## Hosting and package checks

GitHub Pages builds the site with GitHub Actions (`.github/workflows/pages.yml`): it copies the static files,
exports the three R apps with Shinylive, and opens every app in headless Chrome before deploying; nothing is
published unless every app passes.

Run `python3 package_qc.py` from a complete checkout to check navigation, local links, retired content,
terminology and documented counts. GitHub Actions runs it, `python3 build_pages.py --check` and the worked
study (`study/run_all.R`) on pushes and pull requests. These check the package, not the statistics.

Reusable launcher checks live in `tools/tests/`. Theme sources are `assets/theme/tokens.css` and `assets/legacy-theme.css/js`; run `python3 build_pages.py` after changing them or re-rendering a legacy page. The build inlines the theme into portable pages, and `--check` detects drift.

## License

MIT; see [`LICENSE`](LICENSE).
