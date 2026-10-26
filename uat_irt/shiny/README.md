# IRT / RTSM UAT Tracker - Shiny app

A runnable, editable version of the UAT execution & sign-off tracker. Select a test, record its
result, close a defect once its test passes a retest, add a draft test for the untraced
requirement, and the KPIs and the go-live sign-off gate recompute live. Operations-only, synthetic
data, no PHI.

## What a visitor sees on first load

Every panel has content as soon as R is ready; nothing waits for a click:

- a header with a **Synthetic data** badge, a change counter ("Seed data, no changes yet"), the
  CSV download, Reset to seed and, in a standalone run, the site's light/dark switch (it starts
  from the site's saved theme, then the system setting; on the site's launch page the toggle in the
  top bar sets it);
- a **Start here** card (collapsible, closed on phones): what the app shows, what each color means,
  three things to try;
- five KPI boxes, each with a one-line explanation (for example "92% of the 24 executed");
- the **test-script table** (ID and Status first, so a phone shows both), searchable, with
  **RAND-04** selected (a failing critical test with an open critical defect), so the **Selected
  test** card shows its steps, buttons to record its result and its defect. Rows open with a click,
  or from the keyboard (Tab to a row, then Enter or Space);
- the **go-live gate**: the verdict, then each criterion as met or blocking with the items that
  block it. Each ID opens that test (and pages the table to it, clearing a search that hides it);
  "Add a draft test" covers the untraced requirement. On one-column screens the gate comes first;
- the execution-by-area plot and the defect log, whose Status cell opens an editor on a
  double-click anywhere in it.

## The gate, and the way to READY

The gate is conjunctive and strict enough for a computerized-system-validation reviewer:

1. every critical test passes;
2. no critical or major defect is open, and every fix was retested: a defect closes only after the
   test it was found in passes (the app keeps the Close button disabled until then, and refuses a
   typed "Closed"), a closed defect whose test fails again blocks the gate, and a failing test
   needs an open defect logged against it. Open minor defects do not block; at READY the gate
   names them for the person who signs, who fixes or waives them with a rationale;
3. every requirement has a test, and every test has been run (Pass or Fail). A draft test added
   for the untraced requirement starts as Not Run, so it keeps the gate blocked until it is run.

From the seed: record RAND-04's retest as Pass and close DEF-01; pass COH-03; retest SUP-03 and
close DEF-03; run ENR-03, DISP-03, UNBL-03 and NOT-02; add the draft test SUP-05 for URS-SUP-005
and run it. The gate then reads READY, with DEF-04 (minor, cosmetic) named for the signer.

Each empty state says why it is empty and what to do (no selected test, a search that matches
nothing, no tests or defects loaded). Colors are the portfolio site's tokens (`site.css`) in light
and dark: green Pass/Closed, red Fail/Critical, amber Blocked/Open/Major, blue In Progress, grey
Not Run/Minor. Each change shows a short confirmation that says what it means for the test's
defects and where the gate now stands; on phones it spans the screen.

## Run it

From the package root (needs R and a few packages):

```r
install.packages(c("shiny", "bslib", "DT", "ggplot2"))   # once
shiny::runApp("uat_irt/shiny")
```

Or from inside this folder: `setwd("uat_irt/shiny"); shiny::runApp()`.

It also runs in the browser with Shinylive (webR): the site's Pages workflow exports this folder to
`apps/uat_irt/`. Shinylive exports only the app folder, so the folder carries a copy of the three
seed CSVs in `templates/`, and the CSV download is built in the browser (a Blob sent through
`session$sendCustomMessage()`) rather than by a `downloadHandler`. `app.R` sources the shared status and error helpers, [`apps/_shared/portfolio_app.R`](../../apps/_shared/portfolio_app.R)
(from the repository in local R; the Pages build copies the file next to `app.R` for the browser), and
the site opens the app behind a launch page that reports each step of starting R
([how it works](../../apps/_shared/README.md)).

Two details matter only in the browser:

- **DataTables loads with the page.** Its scripts normally arrive with the first table's value.
  When both tables arrive in the same update, Shiny loads the scripts for one and lets the other
  start without waiting, so under Shinylive one table stayed empty ("$table.DataTable is not a
  function"). `app.R` attaches the same dependency (`dt-core-bootstrap5`, same version) to the
  page, so both tables find DataTables ready.
- **Nothing heavy runs at startup.** The app reads three small CSVs; every panel is computed from
  them in well under a second, and the theme is Bootstrap's precompiled one with the site's tokens
  as CSS variables (`bp_theme()` and `bp_theme_head()` in the shared helper), so no Sass is
  compiled in the browser. In a local Shinylive build every panel had content 7.0 to 7.3 s after
  the page opened on a first visit and 6.7 to 6.9 s after a reload (2026-10-25; 7.7 to 8.4 s while the app
  still compiled a custom theme), almost all of it R and its packages starting. The startup card
  stays until both tables have drawn their rows.
- **What only a browser shows** is checked by the deploy smoke test's `smoke.interactions` in
  [`apps/uat_irt/launch.json`](../../apps/uat_irt/launch.json), with real mouse events: a
  double-click on a defect's Status pill opens the editor (the pill lets the pointer through to its
  cell, since DataTables ignores a double-click aimed at anything inside the cell), DEF-01 cannot
  close before its retest, adding the draft test from page 1 pages the table to its highlighted
  row, and on a 390 px phone the confirmation lies inside the screen.

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny app: UI (a `bslib` page in the site theme, with the Start here card) + server (the reactive graph). |
| `R/logic.R` | The **pure logic** - the go-live gate, the KPI math, what blocks the gate (criterion by criterion), whether a defect may close, covering a traceability gap and counting changes, as plain functions with no Shiny dependency. The Quarto guide and the unit tests call the *same* functions. |
| `../templates/*.csv` | The seed data (test scripts, defect log, traceability matrix). These are the editable templates. |
| `templates/*.csv` | A byte-for-byte copy of the seed data, so the app folder is complete for the browser build. Local R reads `../templates/` first. |
| `../tests/test-logic.R` | Unit tests for the gate/KPI logic (including the retest rule, failures with no defect, tests not run, and that the earlier five-step shortcut no longer reaches READY), plus a check that the two copies of the CSVs match (run with `Rscript`). |
| `../tests/test-server.R` | The server driven headless with `shiny::testServer()`: first-load content, the download, recording results, closing defects (button and typed edit, refused before the retest), a fix that fails again, the draft test and the full path to READY, the table paging to a new or searched-away row, the empty state, the dark plot, reset. |

## Make it your own

1. Replace the rows in `../templates/test_scripts.csv`, `defect_log.csv`, and
   `traceability_matrix.csv` with your study's tests, defects, and requirements
   (keep the column names). Copy them into `templates/` here too, or the browser build
   keeps the old rows and the unit test fails.
2. Re-run the app. The gate rule (every Critical test passing; zero open Critical/Major defects,
   every fix retested; every requirement traced to a test that has been run) applies to your data
   automatically. If your data
   has no test called RAND-04, change `DEFAULT_TEST` in `app.R` to the test you want selected on
   first load, and update `smoke.expect` in [`apps/uat_irt/launch.json`](../../apps/uat_irt/launch.json),
   which pins the first-load numbers the deploy smoke test checks.
3. Download your results to CSV from the header and drop them into the Excel
   workbook and the eTMF.

The logic is deliberately separated from the UI so you can change *what the gate
means* (in `R/logic.R`) without touching the app, or change *how it looks* (in
`app.R`) without touching the logic. See [`../quarto/uat-build.html`](../quarto/uat-build.html) to
build the app from scratch.

## How it maps to the other formats

- **Excel workbook** (`../UAT_IRT_RTSM_Workbook.xlsx`) - the fillable record you sign and file.
- **Quarto guide / dashboard / slides** (`../quarto/`) - the read/share/present views, built from the same `R/logic.R`.

*The gate packages the evidence; a named human signs UAT off. Nothing here connects to a live IRT system.*
