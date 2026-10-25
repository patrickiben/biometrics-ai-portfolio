# TRIALMON safety review console (Shiny app)

A Safety Review Committee style console for a synthetic dose-escalation study: a ranked worklist,
the eDISH plot (click a point to open that participant), QTcF categories, CTCAE lab shifts, adverse
events by SOC and PT, the DLT tally against an illustrative 3+3 rule, a study tier of operational
indicators with a what-if, and a convention grid that shows whether each potential Hy's Law flag holds
under every combination of three SAP conventions. Every level rolls up worst-of, the QTcF watch level included, so one RED is
never averaged away.

**Synthetic data only.** Study CP-101 does not exist. The console flags positions for the medical
monitor and the committee; it does not adjudicate DLTs or Hy's Law cases and it makes no
dose-escalation decision. In a real study the numbers a committee relies on come from validated
programs on ADaM; this app is not one of them.

## Run it

```r
install.packages(c("shiny", "bslib", "DT"))   # once
shiny::runApp("sasr_monitoring_wiki/trialmon_shiny")
```

The app is ready for Shinylive (webR): all data sit in `data/`, it uses only shiny, bslib and DT (the
three plots are base graphics), and the CSV download is built in the browser (a Blob sent through
`session$sendCustomMessage()`), not by a `downloadHandler`; the file is named
`SYNTHETIC_trialmon_worklist_CTCAEv6.0.csv` and its first column labels every row synthetic. The
site's Pages workflow (`.github/workflows/pages.yml`) exports it with shinylive 0.5.0 (assets
0.10.12) to `apps/trialmon/`, where it runs in the browser. `app.R` sources the shared status and
error helpers, [`apps/_shared/portfolio_app.R`](../../apps/_shared/portfolio_app.R) (from the
repository in local R; the Pages build copies the file next to `app.R` for the browser), and the
site opens the app behind a launch page that reports each step of starting R
([how it works](../../apps/_shared/README.md)).

### What a visitor sees first

A **Start here** card at the top of the console says what it shows, what RED, AMBER, watch and GREEN
mean, and three things to try; it folds away with one click. Below it, every value box, the
worklist and the participant packet have content on the first screen, and each tab fills when it is
opened. A panel that cannot show anything says why and what to do (for example "Pick a participant
in the sidebar"), and an R error names the panel that failed (`guard()`); the tests check both.

### Why it starts fast in the browser

The app's own computation is small: in webR, on a fast laptop, loading the data and the convention
grid takes under 0.1 s and the first roll-up about 0.1 s (measured 2026-10-25). The start is
dominated by R and its packages loading, so the app avoids the two costs it controls:

- **No Sass in the browser.** A custom bslib theme is compiled with Sass each time the app starts
  (about 0.6 s). The app uses Bootstrap's precompiled theme and sets the site's color tokens
  (`site.css`, through `PORTFOLIO_TOKENS`) as CSS variables, light and dark (`R/app_view.R`).
- **No ggplot2.** Loading it takes about 0.65 s, and each ggplot draws in about 0.3 s; the eDISH
  plot, the liver trajectory and the dose ladder are base graphics, which R has loaded already.

Results that depend on no input (QTcF screen, DLT tally, AE table, convention grid) are computed
once at startup. Measured on 2026-10-25 from a full local export (the same steps as the Pages
workflow) in headless Chrome with a fresh profile, served locally on one fast laptop: every visible
output had content 6.9 to 7.3 s after the launch page opened (8.3 to 8.5 s before these changes),
6.5 to 6.7 s on a reload (7.9 to 8.3 s before), and each tab filled 0.1 to 0.2 s after a click
(the Liver tab took 0.9 s before), with no output error in light, dark or phone-width runs. A
slower laptop and a real network add to these numbers; the launch page reports each step meanwhile.

## Files

| File | What it is |
|---|---|
| `app.R` | The UI and the reactive server. |
| `R/app_view.R` | How the console looks: the level colors (WCAG AA in light and dark), the site tokens as CSS, the level chips, the Start here card and the three plots in base graphics. No screening rule lives here. |
| `R/logic.R` | The screening rules in base R (no Shiny): potential Hy's Law with its timing window, the aminotransferase confirmation flag, eDISH quadrants, the R ratio, QTcF categories, CTCAE v6.0/v5.0 lab grades, the 3+3 rule reference, the study tier and the worst-of roll-up. The Quarto pages, the SRC packet and the tests call the same functions. |
| `R/hyslaw_grid.R` | The Hy's Law convention grid in base R: 12 cells (window 14, 30 or 60 days; ALT or AST, or ALT only; ALP < 2x ULN at the aminotransferase draw, or not applied), the peak-versus-peak reference column and the verdict rule. |
| `R/gen_data.R` | Writes the synthetic ADaM-shaped CSVs from one seed, plus `labs_long.csv` (no random draws). |
| `data/` | `adsl`, `adlb`, `adeg`, `adae`, `cohorts`, `study_kri` (operational indicators) and `notes` (teaching notes); `labs_long` (liver tests for seven planted known-answer cases, CP101-901 to -907, used only by the grid) and `narrative_flags` (written by hand: the grid verdict each narrative implies). |
| `../trialmon_tests/` | testthat tests: rule boundaries, the shipped study, the server through `shiny::testServer()`, and the first screen (`test-app.R`: every output has content, empty states explain themselves, the launch page's smoke-test values match the server). |

## The rules

```
Potential Hy's Law  ALT or AST >= 3x ULN, and TBL > 2x ULN on or after that draw within 30 days of
                    it (an SAP convention). Every such draw opens its own window. ALP shown;
                    "ALP < 2x ULN" in that draw only as a labeled SAP option.
                    FDA, Drug-Induced Liver Injury: Premarketing Clinical Evaluation (July 2009).
Confirm             ALT or AST > 3x ULN: repeat ALT, AST, ALP and TBL within 48 to 72 hours.
eDISH               peak ALT or AST vs peak TBL (x ULN); lines at 3x and 2x; peaks need not be concurrent;
                    the axes widen so that no participant falls off.
R ratio             (ALT/ULN)/(ALP/ULN) at the reported ALT or AST >= 3x ULN draw: >= 5 hepatocellular,
                    2 < R < 5 mixed, <= 2 cholestatic.
QTcF                > 450, > 480, > 500 ms; change > 30, > 60 ms (ICH E14; E14/S7B Q&As).
                    RED > 500 or > 60; AMBER > 480 or > 30; watch > 450 (a worklist row).
Lab grades          NCI CTCAE v6.0 by default, v5.0 per protocol; creatinine on x ULN and fold over
                    baseline (v5.0: the worse of the two; v6.0: baseline fold only below the LLN).
                    AE grades stay as the investigator recorded them (v6.0 in these data).
3+3 (illustrative)  0 of 3 or 1 of 6: escalation-eligible; 1 of 3: expand to 6; 2 or more: the dose
                    exceeds the MTD. BOIN is the model-assisted alternative; not implemented here.
Roll-up             worst-of at participant (watch included), cohort, study tier and overall.
                    Never an average.
Convention grid     potential Hy's Law in each of 12 cells: window W in {14, 30, 60} days after the
                    ALT or AST >= 3x ULN draw (TBL > 2x ULN on day t to t + W, both ends included),
                    aminotransferase = ALT or AST, or ALT only; ALP < 2x ULN at that draw, or not
                    applied. Reference column (not a cell): peak AT >= 3x and peak TBL > 2x ULN.
                    Verdict: Robust (12 of 12); Convention-dependent (names each factor for which two
                    cells differing only in that factor disagree); Not flagged; Peak-only artifact
                    (0 of 12 but flagged on peaks). A structured sensitivity analysis of SAP
                    conventions; the tests fail if a status in data/narrative_flags.csv disagrees.
```

The CTCAE v6.0 cut points follow admiral 1.5.0's `atoxgr_criteria_ctcv6`; they were not re-checked
against the NCI v6.0 workbook here. The v5.0 cut points follow the NCI v5.0 workbook (2017-11-27).

## Tests

```sh
Rscript sasr_monitoring_wiki/trialmon_tests/run-tests.R   # needs testthat (>= 3.0)
```

## Moved pages

The hand-built pages `TRIALMON_Dashboard.html` and `TRIALMON_Dashboard_Wiki.html` were retired. Small
redirect stubs at those paths in `sasr_monitoring_wiki/` send old links to the
[TRIALMON landing page](../index.html).

The [visual guide](../trialmon_quarto/trialmon-guide.html), the [snapshot](../trialmon_quarto/trialmon-dashboard.html),
the [run-and-build page](../trialmon_quarto/trialmon-build.html) and the
[SRC safety packet](../trialmon_quarto/trialmon-src-packet.html) are rendered from this same code.
