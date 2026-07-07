# IRT / RTSM UAT Tracker - Shiny app

A runnable, editable version of the UAT execution & sign-off tracker. Select a
test, mark it Pass/Fail, close a defect, and the KPIs and the go-live sign-off
gate recompute live. Operations-only, synthetic data, no PHI.

## Run it

From the package root (needs R and a few packages):

```r
install.packages(c("shiny", "bslib", "DT", "ggplot2"))   # once
shiny::runApp("uat_irt/shiny")
```

Or from inside this folder: `setwd("uat_irt/shiny"); shiny::runApp()`.

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny app: UI (a `bslib` sidebar layout) + server (the reactive graph). |
| `R/logic.R` | The **pure logic** - the go-live gate and the KPI math, as plain functions with no Shiny dependency. The Quarto guide and the unit tests call the *same* functions. |
| `../templates/*.csv` | The seed data (test scripts, defect log, traceability matrix). These are the editable templates. |
| `../tests/test-logic.R` | Unit tests for the gate/KPI logic (run with `Rscript`). |

## Make it your own

1. Replace the rows in `../templates/test_scripts.csv`, `defect_log.csv`, and
   `traceability_matrix.csv` with your study's tests, defects, and requirements
   (keep the column names).
2. Re-run the app. The gate rule (every Critical test passing, zero open
   Critical/Major defects, 100% traceability) applies to your data automatically.
3. Download your results to CSV from the sidebar and drop them into the Excel
   workbook and the eTMF.

The logic is deliberately separated from the UI so you can change *what the gate
means* (in `R/logic.R`) without touching the app, or change *how it looks* (in
`app.R`) without touching the logic. See [`../quarto/uat-build.html`](../quarto/uat-build.html) to
build the app from scratch.

## How it maps to the other formats

- **Excel workbook** (`../UAT_IRT_RTSM_Workbook.xlsx`) - the fillable record you sign and file.
- **Quarto guide / dashboard / slides** (`../quarto/`) - the read/share/present views, built from the same `R/logic.R`.

*The gate packages the evidence; a named human signs UAT off. Nothing here connects to a live IRT system.*
