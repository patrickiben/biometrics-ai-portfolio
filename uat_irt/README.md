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
| [`quarto/uat-dashboard.html`](quarto/uat-dashboard.html) and [`shiny/`](shiny/README.md) | A shareable snapshot and the runnable R Shiny tracker (local R, or in the browser on the site at `apps/uat_irt/`): KPIs, execution by area, a searchable test-script table (click a row for its steps and expected result), the defect log, and a **live go-live sign-off gate** that stays blocked until every critical test passes, no critical or major defect is open and every fix has passed its retest, and every requirement has a test that has been run. |
| [`templates/test_scripts.csv`](templates/test_scripts.csv) | Test-script library (29 example cases across randomization, dose-escalation cohorts, enrollment, dispensing, resupply, unblinding, notifications, EDC integration). |
| [`templates/traceability_matrix.csv`](templates/traceability_matrix.csv) | Requirement → test mapping; surfaces any URS requirement with no test (the demo has one gap, `URS-SUP-005`). |
| [`templates/defect_log.csv`](templates/defect_log.csv) | Defect log (severity, status, source test, resolution). |

## The go-live sign-off gate

Deterministic and pre-specified: the study does not go live until **all three** hold:

1. every **critical** test is **Pass**;
2. **zero** open critical or major defects, and every fix **retested**: a defect closes only after
   the test it was found in passes on retest, and a failing test needs an open defect logged
   against it (open **minor** defects do not block; the signer fixes them or waives them with a
   rationale);
3. **100%** requirement traceability: every URS requirement has a test, and every test has been
   **run** (Pass or Fail; none Not Run, In Progress or Blocked, including a draft test added to
   close a gap).

The Excel workbook's Execution Summary computes the original three counts (critical tests not
passing, open critical/major defects, requirements without a test); its Instructions sheet asks for
the retest and for an executed test per requirement, which the app's gate checks.

The gate packages the evidence; the **sign-off is a named human decision** (the tester / accountable
biostatistician), never the tool's.

## Governance

Synthetic test data only: UAT runs on test participants in a test environment; **no PHI**.
Part 11 / ALCOA++ audit trail; the frozen URS and test-script set are version-controlled. Automation
packages and checks; a human approves.
