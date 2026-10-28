# TRIALMON safety review console (Shiny app)

For a graphical start, follow the [point-and-click toolkit setup](../../TOOLKIT_SETUP.html), create a private project, then choose the TRIALMON card to check packages, upload the listed inputs and start the app. Save supported app downloads before closing; the terminal instructions below are an optional interface.

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

## Run it locally for evaluation

Install R 4.1 or later and keep the complete repository checkout. In a terminal at
the repository root, run:

```sh
Rscript launch_app.R trialmon --install   # first run: install missing packages in a user library
Rscript launch_app.R trialmon             # later runs: no package downloads
```

The launcher opens your browser and binds Shiny to `127.0.0.1`. Stop it with
Ctrl+C. `Rscript launch_app.R --check trialmon` checks packages without starting a
server. Packages go into an R-version-specific user cache; set
`BIOMETRICS_R_LIB` to choose a separate user library. System/site libraries are
never installation targets. This evaluation environment reports package versions;
it is not a frozen study environment.

From another working directory, pass the quoted absolute path to the launcher,
for example `Rscript "/path/to/biometrics-ai-portfolio/launch_app.R" trialmon`.
In an R console that is already inside this app folder, use `shiny::runApp()`
after checking dependencies with the launcher.

Interactive changes are local to the running app session. Keep separate input
copies for each client/study and save the supported downloads before closing;
this example does not provide a shared, persistent study database.

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
mean, and four things to try (the same four as the launch page). The color legend is built from the
list of screening rules in `R/logic.R` (`WORKLIST_RULES`), so it names every rule that can put a row
on the worklist, and the tests fail if a worklist row matches no legend entry of its level. The card
is open on a visitor's first visit and folded on a phone, and it starts folded on later visits (the
choice is kept in that browser only); one click opens or folds it. With the card open, a 1440 x 900
screen shows the seven value boxes in one row and the top of the worklist; on a 1280 x 800 laptop
the worklist starts just below the first screen until the card is folded. Every value box, the
worklist and the participant packet have content on first load, and each tab fills when it is
opened. A panel that cannot show anything says why and what to do (for example "Pick a participant
in the sidebar"), and an R error names the panel that failed (`guard()`); the tests check both.

Each "Try this" step changes something a visitor can see, and the tests replay them: the packet
opens with CP101-014, the worst participant, whose first worklist row is highlighted, so step 1
(CP101-004's row) switches the packet; step 2 names both points in the shaded eDISH box
(CP101-014, a potential Hy's Law case, and CP101-004, whose bilirubin peaked before its
aminotransferase elevation). Every click says what it did:

- The line above the worklist names the participant in the sidebar. Their row stays highlighted
  however they were chosen (worklist, sidebar or eDISH plot); a participant with no flag is said to
  have no row.
- The line under the eDISH plot names the ringed participant and the points in the shaded box, and
  after a click says which participant it opened, that the one clicked is already open, or that no
  point was near enough.
- A Cohort or Study row is explained (the packet shows participants only) with a link to its tab,
  above the worklist and in a short notice at the edge of the screen; on a phone, a Participant row
  also gets a notice with a "Show the packet" link, because the packet is below the console.

On a phone (under 576 px) the worklist and the DLT table turn into one small card per row, and any
table wider than its card fades at the edge it continues and says "scroll the table sideways". The
three plots place every word in inches and pick the longest wording that fits the device (a phone,
the eDISH column on a laptop, a wide screen); the tests draw them at five widths and fail if any
text leaves the device or covers another label.

### Why it starts fast in the browser

The app's own computation is small: in webR, on a fast laptop, loading the data and the convention
grid takes under 0.1 s and the first roll-up about 0.1 s (measured 2026-10-25). The start is
dominated by R and its packages loading, so the app avoids the two costs it controls:

- **No Sass in the browser.** A custom bslib theme is compiled with Sass each time the app starts
  (about 0.6 s). The app uses Bootstrap's precompiled theme and takes the site's tokens
  (`assets/theme/tokens.css`, through `bp_theme_head()` in the shared helper) as CSS variables,
  light and dark; its four review levels and the liver tests are site tones (`R/app_view.R`), and
  it follows the site's light or dark choice (input `bp_theme`).
- **No ggplot2.** Loading it takes about 0.65 s, and each ggplot draws in about 0.3 s; the eDISH
  plot, the liver trajectory and the dose ladder are base graphics, which R has loaded already.

Results that depend on no input (QTcF screen, DLT tally, AE table, convention grid) are computed
once at startup. Measured on 2026-10-25 from a full local export (the same steps as the Pages
workflow) in headless Chrome with a fresh profile, served locally on one fast laptop: every visible
output had content 6.9 to 7.3 s after the launch page opened (8.3 to 8.5 s before these changes),
6.5 to 6.7 s on a reload (7.9 to 8.3 s before), and each tab filled 0.1 to 0.2 s after a click
(the Liver tab took 0.9 s before), with no output error in light, dark or phone-width runs. After
the status lines, notices and text-fitting plots were added, three runs of the deploy smoke test
(`smoke.mjs`, 2026-10-25) read 6.7 to 6.9 s to ready and 6.3 to 6.5 s on a reload; after the move
to the site's tokens, 6.7 s and 6.2 to 6.3 s in two runs, and eight more first visits at 1280 and
390 px, light and dark, 6.6 to 7.0 s. A slower laptop and a real network add to these
numbers; the launch page reports each step meanwhile.

## Files

| File | What it is |
|---|---|
| `app.R` | The UI and the reactive server. |
| `R/app_view.R` | How the console looks: the level colors (WCAG AA in light and dark), the site tokens as CSS, a few lines of JavaScript (the scroll cues, the Start here card's memory), the level chips, the Start here card, the phone card tables and the three plots in base graphics, with their text-fitting helpers. No screening rule lives here. |
| `R/logic.R` | The screening rules in base R (no Shiny): potential Hy's Law with its timing window, the aminotransferase confirmation flag, eDISH quadrants, the R ratio, QTcF categories, CTCAE v6.0/v5.0 lab grades, the 3+3 rule reference, the study tier and the worst-of roll-up. The Quarto pages, the SRC packet and the tests call the same functions. |
| `R/hyslaw_grid.R` | The Hy's Law convention grid in base R: 12 cells (window 14, 30 or 60 days; ALT or AST, or ALT only; ALP < 2x ULN at the aminotransferase draw, or not applied), the peak-versus-peak reference column and the verdict rule. |
| `R/gen_data.R` | Writes the synthetic ADaM-shaped CSVs from one seed, plus `labs_long.csv` (no random draws). |
| `data/` | `adsl`, `adlb`, `adeg`, `adae`, `cohorts`, `study_kri` (operational indicators) and `notes` (teaching notes); `labs_long` (liver tests for seven planted known-answer cases, CP101-901 to -907, used only by the grid) and `narrative_flags` (written by hand: the grid verdict each narrative implies). |
| `../trialmon_tests/` | testthat tests: rule boundaries, the shipped study, the server through `shiny::testServer()`, and the first screen (`test-app.R`: every output has content, empty states explain themselves, the legend covers every worklist rule, each "Try this" step and click does what it says, the plots' text fits at five widths, the launch page's smoke-test values match the server). |

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
