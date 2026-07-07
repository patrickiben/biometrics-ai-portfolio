# Find Hours - Hours Budget Reconciliation Shiny app

A runnable, editable version of the find-hours worksheet. Edit the effort
ledger, type an out-of-scope ask, and watch net-findable and the
absorbable-vs-change-order verdict recompute live. **Hours / effort only**, no
dollars, rates, ROI, or headcount. Synthetic data.

## Run it

From the package root:

```r
install.packages(c("shiny", "bslib", "DT", "ggplot2"))   # once
shiny::runApp("budget_reconciliation/shiny")
```

Or from inside this folder: `setwd("budget_reconciliation/shiny"); shiny::runApp()`.

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny app: UI + reactive server. |
| `R/logic.R` | The **pure logic** - `hours_metrics()` (the net-findable roll-up) and `find_hours()` (the sourcing + verdict), plus `change_order_text()`. The Quarto docs and the unit tests call the same functions. |
| `../templates/project_hours_ledger.csv` | The seed effort ledger (the editable template). |
| `../tests/test-logic.R` | Unit tests (run with `Rscript`). |

The one equation the whole tool is about:

```
NET FINDABLE = (Σ Planned + Contingency) − Σ EAC
```

## Make it your own

1. Replace the rows in `../templates/project_hours_ledger.csv` with your
   project's deliverables and hours (keep the `CONTINGENCY` and `TOTAL` rows and
   the column names). Planned comes from your SOW/budget grid, Actual from the
   timesheet system, EAC is your forecast.
2. Re-run the app. Type an ask, or use the quick-pick buttons, and read the
   verdict. Download the change-order draft when there's a shortfall.

## How it maps to the other formats

- **Excel workbook** (`../Hours_Budget_Reconciliation_Workbook.xlsx`) - the fillable version for real reconciliations.
- **Quarto guide / dashboard / slides** (`../quarto/`) - the read/share/present views, built from the same `R/logic.R`.

*Hours/effort only. Pricing the effort is the PM's / project finance's job, downstream of this tool. Nothing here connects to a real budget or timesheet.*
