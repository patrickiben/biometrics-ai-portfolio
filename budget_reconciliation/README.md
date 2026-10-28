# Hours Budget Reconciliation: "Find Hours"

Use the [point-and-click toolkit setup](../TOOLKIT_SETUP.html) to create a private project, upload the documented hours ledger and launch Find Hours. Save the ledger and change-order downloads before closing the app.

When an out-of-scope deliverable suddenly needs doing, where do the hours come from? This component
reconciles a project's **planned vs actual vs forecast (EAC) hours**, computes the net headroom, and
sources a new ask from under-run slack and contingency: flagging any shortfall that is genuinely
additional scope and needs a change order.

> **Effort in hours only:** no dollars, no rates, no headcount. An illustration of effort stewardship on a
> synthetic project; budget ownership is not claimed. Synthetic project data throughout.

## Contents

| File | What it is |
|---|---|
| **[`Hours_Budget_Reconciliation_Workbook.xlsx`](Hours_Budget_Reconciliation_Workbook.xlsx)** | **The working tool: download and fill in.** A formula-driven Excel workbook (Instructions · Effort Ledger · Find Hours · Change Order). Enter your deliverables and planned/actual/EAC hours; net findable and the find-hours verdict compute automatically. Hours/effort only, no dollars. |
| [`quarto/hours-guide.html`](quarto/hours-guide.html) | The visual guide: the problem (silent absorption), the reconciliation (`net findable = (Σ planned + contingency) − Σ EAC`), the 4-step decision tree (reallocate slack, then contingency, then defer, then change order) and a live roll-up from the ledger. |
| [`quarto/hours-dashboard.html`](quarto/hours-dashboard.html) | A shareable snapshot computed from the ledger. |
| [`shiny/`](shiny/README.md) | The runnable R Shiny app (local R; see its README) with unit tests in `tests/`. |
| [`templates/project_hours_ledger.csv`](templates/project_hours_ledger.csv) | The effort ledger (deliverable × planned / actual / % / EAC / variance) with a contingency row. |
| [`templates/change_order.md`](templates/change_order.md) | A change-order (effort) request template for the shortfall hours. |

## The method in one line

`net findable = (Σ planned hours + contingency) − Σ EAC` the honest headroom, netting every under-run
against every over-run. If a new ask exceeds it, the excess is real added scope: raise a change order
rather than absorbing a silent over-run.

## Governance

Hours/effort only (no $). Every reallocation, contingency draw, deferral, and change order is
**recorded, not silent**. The worksheet is decision support; the PM and lead biostatistician decide and
own the call.
