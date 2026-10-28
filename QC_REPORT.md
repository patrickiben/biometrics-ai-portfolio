# Toolkit QC report

Review date: 28 October 2026. Scope: the complete repository, its published-page source, local tools and downloadable artifacts, with additional adversarial review of Open Study Tracker. All exercised datasets and accounts were synthetic. This is software and example-method QC, not regulatory validation or approval for a particular client, study or deployment.

## Runnable analysis follow-up

The TLF forms now use open-source R as the execution default, with native SAS reference exports. The same fixed runner executes mapped-CSV monitoring checks and independently recomputes aggregate interpretation facts. A generated revision pins input and source fingerprints; every attempt has a separate results folder. A nonzero exit, missing report, failed output or failed QC verdict makes the job fail. Reports retain warnings and software versions, and never mark scientific approval as granted.

Executed numerical QC includes 127 model assertions and 27 core known-answer, edge and metamorphic checks. All 221 R source programs execute on synthetic fixtures, including all 197 nonmodel programs and 24 model/PD/C-QTc programs. A second pass removes every input column outside each output's declared contract, exercising all 221 outputs again. This caught missing hidden requirements before the upload forms were finalized. Monitoring has 53 boundary, invalid-input and export checks across all eight routines.

Method corrections include actual numeric dose mappings, explicit Satterthwaite degrees of freedom for the supported nonreplicate 2×2 BE model, paired fixed-sequence comparisons, unique paired accumulation occasions, comparable AUC-interval confirmation, and descriptive trough trends without claiming steady state from a nonsignificant slope. PK exclusions are reported. AE summaries retain zero-event arms; missing lab/ADA classifications remain unknown. Quantitative contracts require units and reject incompatible mixtures. LINEAR/EMAX C-QTc fits remain exploratory diagnostics.

Report QC checks every printed component, 1,001-row pagination, CSV/RDS completeness, rtables conversion, actual PNG/PDF rendering, UTF-8 and formula-like text, HTML escaping, warning retention and removal of partial numeric outputs after failure. Runtime tests cover immutable revisions, distinct runs, fixed command arguments, installation consent, package tampering, source fingerprints, exact output-set reconciliation and diagnostic ZIPs. All 442 generated selections (221 per TLF entry point, both powered by R) execute through the complete report engine; repeat runs preserve prior results and duplicate analysis rows fail without partial numeric exports. Private input, configuration and run folders are excluded from public source copies and Pages builds. Browser QC exercises 13 scenarios, six actual R runs (including both TLF routes), and 30 generated HTML reports in light/dark themes at desktop/mobile widths. The site-wide pass covers all 68 source pages and six existing interaction workflows.

The legacy geometric-statistics gate follows actual shared helper calls, retains its 28-program floor and passes 95 seeded defect mutations plus 39 legitimate variants. All 221 R/SAS output identifiers match, and the existing C-QTc suite passes 38 of 38 checks.

No native SAS, real language model, live email or client dataset was executed. These are software and example-method checks; they do not establish independent double programming, CDISC conformance, regulatory qualification or approval of a particular study. Earlier follow-up sections below describe the evidence at those earlier stages; this section supersedes their parse-only description of the R library.

## Earlier guided template setup follow-up (superseded for R execution)

Five guided setups now replace code-editing for supported study configuration: paired SAS/R TLF libraries, monitoring checks, LOCALMIND findings and aggregate AE/PK interpretation. Forms select outputs, accept CSVs, map columns, check assumptions and generate immutable, versioned packages. Profiles can be reused without transferring inputs. The public site remains a catalog; private study setup runs through the downloaded toolkit on the user's computer.

QC covers all 442 TLF template selections and parsing of every generated R program, a generated R PK-summary execution with mapped synthetic data, AE and PK fact recomputation against the original R extractors, all eight monitoring checks, and unapproved LOCALMIND worklists. Browser tests exercise all five wizards, downloads, missing mappings, unsupported draft numbers, stale previews, profile isolation, desktop/mobile layouts and both themes. Generated HTML reports use the same toolkit theme tokens and saved preference. API/storage tests cover authentication, malformed input, linked-file boundaries, preview freshness, input backups, safe package paths and source/publication exclusions.

No SAS program, real language model or external mail service was executed in this follow-up. Generated drivers consume the configured data, but existing pseudocode methods and unfinished report shells remain explicitly unvalidated. The forms do not turn a configured template into a completed study analysis. Empty event inputs are permitted only where the selected provider supports them; missing denominator data and monitoring feeds still fail validation. Evidence uses synthetic data and is retained outside the repository.

## Earlier point-and-click toolkit follow-up

The [setup guide](TOOLKIT_SETUP.html) now provides a desktop entry point for all 22 catalog modules. The local control panel creates separate private project copies, checks runtimes, installs supported R dependencies on request, manages input replacement and backups, saves configuration, supervises fixed workflows, and downloads outputs. Its browser-only preview does not attempt local API access. SAS and model-dependent modules provide preparation and editor workflows; pseudocode still requires implementation and study-specific review.

Verification includes the local API and process lifecycle, invalid inputs and path boundaries, source-copy/publication exclusions, persisted job history, both light/dark themes, desktop/mobile layout, 13 browser contract scenarios, 10 real-server browser scenarios with actual R execution, and startup of all five Shiny apps from private projects. The worked-study adapter verifies the exact R version and all 151 package versions in its lockfile. CI repeats the desktop and browser checks on Windows and Linux and exercises the private-library study restore and rebuild.

The portable QC runners use Python and R directly, so their launch buttons do not require Bash or rsync. Gate states remain explicit: a completed process is not an all-green QC verdict, and manual review/sign-off gates remain manual. Synthetic QC does not validate an untested study or client deployment. Shared tracker data/settings have their own backup workflow and are not included in the toolkit project ZIP.

The portable QC adapters passed six focused regression tests and a complete 18-case seeded-defect run on macOS with R 4.6.0: **15 caught, zero survived, one equivalent and two not applicable; 18 of 18 as predicted**. Every defect class and catcher set matched the committed Bash-run reference. A fresh harness run then reported **8 of 8 automated gates green**, with G5 still manual and G7 still unsigned; G10 became green only after the native runner and deterministic-profile hashes were recorded. The JSON ledger matched its embedded HTML copy. The job adapter installed the missing test dependencies in a private library and ran the real workflows. Evidence was retained outside the repository; no committed example evidence was overwritten. These native-run results are from macOS, not an executed Windows run.

## Changes resulting from the review

- Replaced the proprietary tracker module with the MIT-licensed Open Study Tracker: standalone browser workspace, Python/SQLite import/export, optional individual accounts, and a queued SMTP notification worker. SMTP previews do not send mail.
- Added a task-based [start guide](GET_STARTED.html) and a portable R launcher for TRIALMON, lifecycle, UAT, risk and hours. Setup docs now distinguish browser demos, local tools, configuration templates and pseudocode, including what each export actually preserves.
- Standardized light/dark behavior around the existing toolkit tokens and `bp-theme` preference. Older self-contained pages embed the adapter to retain portability; scientific images retain their original colors. The tracker uses the same palette and typography. Generated-copy checks prevent theme drift.
- Hardened tracker input limits, Unicode/date parsing, monotonic row versions, atomic authorization checks, host validation, local-only HTTP enforcement, and export destination protection. Local draft identity, cross-tab conflicts, canceled saves and sign-out races have browser regressions.
- Corrected notification cancellation/revival and overlapping-worker races; preserved at-least-once delivery semantics. Successful SMTP acceptance is not proof of inbox receipt, and an in-flight message cannot be recalled.
- Corrected risk-weight and lifecycle-count validation, hours estimates/reserve handling, fractional shortfalls, a risk-table column mismatch, and UAT traceability/input checks. Existing hours overruns now consume contingency before a new request is called absorbable, and edited contingency survives CSV export. Explicitly supplied missing input paths now fail instead of silently substituting demonstration data.
- Linux CI exposed a missing libuv development dependency in the current `fs` source package. The launcher and CI now request its bundled libuv build; CI fails immediately if required packages did not install.
- Excluded local databases, recovery files, environment files and email previews from repository publication, including a second filter in the Pages build.
- Corrected stale pipeline-document framing/navigation and reviewed downloadable workbook gates and PDF layout. The detailed artifact results are below.

## Executed checks

| Area | Evidence and result |
| --- | --- |
| Tracker storage, accounts and notifications | 104 Python tests passed, including invalid/oversized imports, transaction rollback, parallel writes, permissions, session revocation, CSRF, stale saves, host/origin checks, notification concurrency, retries and crash recovery. |
| Tracker browser workflows | 21 Chromium scenarios passed: standalone/offline edits and export, validation, persistence, cross-tab conflicts, shared sign-in/out and roles, stale edits, cancellation races, and theme switching/persistence. No external email sent. |
| R app startup | All five apps launched from an unrelated working directory, connected a Shiny websocket, and rendered their first output without JavaScript or Shiny output errors. All five apps also passed theme switching, surface changes and saved preference on reload; risk/hours had additional mobile and KPI contrast checks. Three launcher subprocess tests passed. |
| R logic and server checks | TRIALMON: 653 expectations in 69 tests; lifecycle, UAT, risk and hours logic/server suites passed, including added invalid-input regressions. |
| Method-specific examples | C-QTc known-answer suite: 38/38; carryover suite: 21 PASS, two informational cases and zero failures (PKNCA relative error 3.11e-15); TLF drafter self-test passed. These test the examples' stated scope. |
| Worked bioequivalence study | R 4.6.0 and all 151 package versions matched `study/renv.lock`. Two baseline isolated runs regenerated all 104 tracked study files byte-identically. After the report-theme source fix, the report was regenerated; all numerical outputs remained unchanged. Numerical QC: 40/40 checks, 5,100 values compared; CSR consistency: 10/10, DRAFT_OK. |
| Validation harness | Isolated baseline produced seven automated green gates, a manual G5, unsigned G7 and stale G10. All 18 seeded cases behaved as predicted: 15 caught, one equivalent mutation, two not applicable, zero survived. G10 remained stale because the package checker changed during the final run; no fresh hash-coverage claim is made. Committed evidence/ledger files were not overwritten to manufacture green results. |
| Published and freshly built R apps | Read-only checks of all three deployed Shinylive apps passed. A fresh 151 MB site build also passed all three app smoke tests against the new source: launch, output values, theme propagation into R, interactive controls, mobile views and reload. First readiness was 8.4–9.3 seconds, reload 7.8–8.5 seconds on the local QC machine. |
| Download structure | Seven PDFs parsed cleanly with Poppler; four workbook packages, three Word packages and one presentation package passed structural checks. Structure alone does not establish content correctness or visual quality. |
| Workbook calculations | 19 synthetic hours/UAT scenarios passed in both artifact-tool and native LibreOffice, with no formula errors. Original sheet order, merges, dropdown validation, widths and formula locations were preserved and renders reviewed. The hours gate rejects invalid estimates and accounts for existing overruns; UAT now labels its limited automated checks and mandatory manual review. |
| Documents | Re-rendered and inspected the pipeline Word/PDF after correcting stale framing and navigation. Updated the register workbook introduction while preserving its three filters, frozen panes, widths and other cell values. Repaired the UAT one-page PDF's two-page overflow and aligned its gate description with the R implementation. |
| Package and generator regressions | Eight theme-injection/launcher/publication tests and 11 G2 geometric-statistics tests passed. Package QC reported zero issues; legacy document punctuation warnings remain stylistic. |

The final source-site browser sweep passed **64/64 HTML pages and all six interaction groups**, with both theme directions and saved-preference persistence, sampled text contrast in both palettes, zero desktop/mobile document overflow, no JavaScript runtime errors, no broken local links or missing anchors, and no external runtime requests. Visual review covered 52 light/dark desktop/mobile screenshots across 13 representative pages, with targeted checks after corrections. The launch template is counted separately by the package scanner (65 HTML files including that template).

## Reproduce the checks

Run from a complete checkout. Python tracker tests use only synthetic temporary state; install the optional server dependencies first to exercise shared mode.

```sh
python3 -m pip install -r open_tracker/requirements-shared.txt
python3 -m unittest discover -s open_tracker/tests -v
python3 -m unittest discover -s tools/tests -v
python3 package_qc.py
python3 build_pages.py --check
python3 validation_harness/checks/tests/test_g2_geo.py -v
```

Browser checks have development-only dependencies; they do not add a runtime download to portable toolkit pages:

```sh
npm ci --prefix tools/browser-qc
tools/browser-qc/node_modules/.bin/playwright install chromium
NODE_PATH="$PWD/tools/browser-qc/node_modules" node .github/pages/smoke/site_qc.cjs
NODE_PATH="$PWD/tools/browser-qc/node_modules" node open_tracker/tests/browser_qc.cjs
```

Use `TRACKER_PYTHON` to select a Python environment with Flask installed, and `CHROME_PATH` if using an existing Chromium executable. `QA_OUTPUT_DIR` retains JSON reports and screenshots at a chosen location. Both browser scripts use ephemeral local servers and clean up their test processes. The [package workflow](.github/workflows/package-check.yml) repeats Python, browser and R regression checks; the [study workflow](.github/workflows/study.yml) rebuilds the worked example independently.

For numerical reproduction, follow [study/README.md](study/README.md), and run each module's documented test command. Restore the worked-study environment before running `Rscript study/run_all.R`; the launcher does not substitute for that pinned analysis environment. Harness runs should use disposable copies so synthetic tests do not replace retained study evidence. Inspect the generated ledger statuses: `run_harness.sh` returns a process-success code even when a reported gate is red, manual or unsigned. Its exit status alone is not a validation verdict.

## Practical limits

- No real client data, hosting account, production identity provider or live external SMTP service was configured. Shared tracker use requires a host; live email requires SMTP configuration. Local browser use and notification previews work without those services.
- The shared tracker is an evaluation tool with individual accounts. It has no MFA/SSO, per-study access partitioning or external penetration-test certification. All accounts can read their service's entire tracker. Separate access boundaries require separate databases/services.
- Browser persistence is not a backup. Download portable files; use documented export/import paths. UAT's app export covers test scripts, not a complete defect and traceability archive.
- SAS programs were not executed because no licensed SAS runtime was available. The 221 SAS files remain unexecuted reference templates. The R library now has synthetic execution QC as described above; this is not validation on a new study dataset. Local-model examples need a separately obtained runtime/model, and the TLF interpretation model step remains a stub.
- C-QTc and carryover known-answer tests do not replace rerunning every Monte Carlo experiment for a new design. The carryover comparison against an old full-precision Git baseline was unavailable in the disposable copy and is reported as informational. The worked study's same-author alternative derivation is not independent double programming.
- The Shinylive build reported host/WebAssembly version warnings for knitr, rmarkdown, tinytex and xfun. All three exported apps passed their runtime smoke tests; the build warnings remain recorded rather than presented as a version-exact analysis environment.
- A clean package/browser check does not certify every scientific claim, regulatory reference, third-party destination or future dependency version. Reference standards and method assumptions still need review for the intended use.
- The optional external-link scan encountered HTTP 403 responses at three DOI destinations and two official Flask documentation pages. Those destinations could not be confirmed by that scanner; a 403 is not evidence that a reference is broken. Local navigation is checked independently.
- The unchanged ADaM specification workbook could not be rendered through artifact-tool; its review was limited to XML/package structure, not full visual verification. The repaired UAT workbook still requires manual retest evidence, failed-test links and signatures.

Retained evidence for this review was produced outside the repository; generated screenshots, test accounts, databases and mail previews are not published as toolkit data.
