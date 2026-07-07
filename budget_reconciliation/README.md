# Hours Budget Reconciliation — "Find Hours"

When an out-of-scope deliverable suddenly needs doing, where do the hours come from? This component
reconciles a project's **planned vs actual vs forecast (EAC) hours**, computes the net headroom, and
sources a new ask from under-run slack and contingency — flagging any shortfall that is genuinely
additional scope and needs a change order.

> **Effort in HOURS only** — no dollars, no rates, no headcount. This is how the team stewards its own
> effort budget; cost is finance's. Synthetic project data throughout.

## Contents

| File | What it is |
|---|---|
| [`FindHours_Playbook.html`](FindHours_Playbook.html) | The playbook — the problem (silent absorption), the reconciliation (`net findable = (Σ planned + contingency) − Σ EAC`), the 4-step decision tree (reallocate slack → contingency → defer → change order), when it's genuinely out-of-scope, and governance. |
| [`Hours_Reconciliation_Worksheet.html`](Hours_Reconciliation_Worksheet.html) | Interactive worksheet — a synthetic project effort ledger + a "find hours" input: enter the new deliverable's estimated hours and it sources them (under-run slack → contingency), showing whether it's **absorbable internally** or needs a **change order** for the shortfall. |
| [`templates/project_hours_ledger.csv`](templates/project_hours_ledger.csv) | The effort ledger (deliverable × planned / actual / % / EAC / variance) with a contingency row. |
| [`templates/change_order.md`](templates/change_order.md) | A change-order (effort) request template for the shortfall hours. |

## The method in one line

`net findable = (Σ planned hours + contingency) − Σ EAC` — the honest headroom, netting every under-run
against every over-run. If a new ask exceeds it, the excess is real added scope: raise a change order
rather than absorbing a silent over-run.

## Governance

Hours/effort only (no $). Every reallocation, contingency draw, deferral, and change order is
**recorded, not silent**. The worksheet is decision support; the PM and lead biostatistician decide and
own the call.
