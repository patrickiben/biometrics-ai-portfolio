# Find Hours - Hours Budget Reconciliation Shiny app

For a graphical start, follow the [point-and-click toolkit setup](../../TOOLKIT_SETUP.html), create a private project, then choose the Hours card to check packages, upload the listed inputs and start the app. Save supported app downloads before closing; the terminal instructions below are an optional interface.

A runnable, editable version of the find-hours worksheet. Edit the effort
ledger, type an out-of-scope ask, and watch net-findable and the
absorbable-vs-change-order verdict recompute live. **Hours / effort only**, no
dollars, rates, ROI, or headcount. Synthetic data.

## Run it locally for evaluation

Install R 4.1 or later and keep the complete repository checkout. In a terminal at
the repository root, run:

```sh
Rscript launch_app.R hours --install   # first run: install missing packages in a user library
Rscript launch_app.R hours             # later runs: no package downloads
```

The launcher opens your browser and binds Shiny to `127.0.0.1`. Stop it with
Ctrl+C. `Rscript launch_app.R --check hours` checks packages without starting a
server. Packages go into an R-version-specific user cache; set
`BIOMETRICS_R_LIB` to choose a separate user library. System/site libraries are
never installation targets. This evaluation environment reports package versions;
it is not a frozen study environment.

From another working directory, pass the quoted absolute path to the launcher,
for example `Rscript "/path/to/biometrics-ai-portfolio/launch_app.R" hours`.
In an R console that is already inside this app folder, use `shiny::runApp()`
after checking dependencies with the launcher.

Interactive changes are local to the running app session. Keep separate input
copies for each client/study and save the supported downloads before closing;
this example does not provide a shared, persistent study database.

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
