# IRT / RTSM: User Acceptance Testing

UAT of the **Interactive Response Technology** (IRT) / **Randomization & Trial Supply Management**
(RTSM) system before go-live, from the biostatistics lens: does the vendor-built system implement
the study's randomization and supply logic exactly? The randomization schedule is produced and owned by
biostatistics, so validating that the IRT allocates, stratifies, blocks, and conceals per that list is
a biostatistician's responsibility. This module is UAT test-design support from the randomization
owner's side, on synthetic test data; it is not a record of leading IRT UAT execution.

## Contents

| File | What it is |
|---|---|
| **[`UAT_IRT_RTSM_Workbook.xlsx`](UAT_IRT_RTSM_Workbook.xlsx)** | **The working tool: download and fill in.** A formula-driven Excel workbook (Instructions · Test Scripts · Traceability · Defect Log · Execution Summary) pre-filled for a **parallel-group** study. Execute each test in the IRT test environment and record the result; the go-live sign-off gate computes automatically. Shareable and signable for the eTMF. |
| [`quarto/uat-guide.html`](quarto/uat-guide.html) | The visual guide: what UAT for IRT/RTSM is, the biostatistician's role, the process (URS → scripts → execute → defects → trace → sign-off), coverage areas, the go-live gate, governance. |
| [`quarto/uat-dashboard.html`](quarto/uat-dashboard.html) and [`shiny/`](shiny/README.md) | A shareable snapshot and the runnable R Shiny tracker (local R, or in the browser on the site at `apps/uat_irt/`): KPIs, execution by area, a filterable test-script table (click for steps/expected/actual), the defect log, and a **live go-live sign-off gate** that stays blocked until every critical test passes and every critical/major defect closes. |
| [`templates/test_scripts.csv`](templates/test_scripts.csv) | Test-script library (29 example cases across randomization, dose-escalation cohorts, enrollment, dispensing, resupply, unblinding, notifications, EDC integration). |
| [`templates/traceability_matrix.csv`](templates/traceability_matrix.csv) | Requirement → test mapping; surfaces any URS requirement with no test (the demo has one gap, `URS-SUP-005`). |
| [`templates/defect_log.csv`](templates/defect_log.csv) | Defect log (severity, status, source test, resolution). |

## The go-live sign-off gate

Deterministic and pre-specified: the study does not go live until **all three** hold:

1. every **critical** test is **Pass**;
2. **zero** open critical or major defects;
3. **100%** requirement traceability (no URS requirement without a test).

The gate packages the evidence; the **sign-off is a named human decision** (the tester / accountable
biostatistician), never the tool's.

## Governance

Synthetic test data only: UAT runs on test participants in a test environment; **no PHI**.
Part 11 / ALCOA++ audit trail; the frozen URS and test-script set are version-controlled. Automation
packages and checks; a human approves.
