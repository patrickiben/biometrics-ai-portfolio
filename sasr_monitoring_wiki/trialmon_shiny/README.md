# TRIALMON safety review console (Shiny app)

A Safety Review Committee style console for a synthetic dose-escalation study: a ranked worklist,
the eDISH plot (click a point to open that participant), QTcF categories, CTCAE lab shifts, adverse
events by SOC and PT, the DLT tally against an illustrative 3+3 rule, and a study tier of operational
indicators with a what-if. Every level rolls up worst-of, the QTcF watch level included, so one RED is
never averaged away.

**Synthetic data only.** Study CP-101 does not exist. The console flags positions for the medical
monitor and the committee; it does not adjudicate DLTs or Hy's Law cases and it makes no
dose-escalation decision. In a real study the numbers a committee relies on come from validated
programs on ADaM; this app is not one of them.

## Run it

```r
install.packages(c("shiny", "bslib", "DT", "ggplot2"))   # once
shiny::runApp("sasr_monitoring_wiki/trialmon_shiny")
```

The app is ready for Shinylive (webR): all data sit in `data/`, it uses only shiny, bslib, DT and
ggplot2, and the CSV download is built in the browser (a Blob sent through
`session$sendCustomMessage()`), not by a `downloadHandler`; the file is named
`SYNTHETIC_trialmon_worklist_CTCAEv6.0.csv` and its first column labels every row synthetic. The
site's Pages workflow (`.github/workflows/pages.yml`) exports it with shinylive 0.5.0 (assets
0.10.12) to `apps/trialmon/`, where it runs in the browser; a local export rendered and responded
in headless Chrome, and its CSV download worked.

## Files

| File | What it is |
|---|---|
| `app.R` | The UI and the reactive server. |
| `R/logic.R` | The screening rules in base R (no Shiny): potential Hy's Law with its timing window, the aminotransferase confirmation flag, eDISH quadrants, the R ratio, QTcF categories, CTCAE v6.0/v5.0 lab grades, the 3+3 rule reference, the study tier and the worst-of roll-up. The Quarto pages, the SRC packet and the tests call the same functions. |
| `R/gen_data.R` | Writes the synthetic ADaM-shaped CSVs from one seed. |
| `data/` | `adsl`, `adlb`, `adeg`, `adae`, `cohorts`, `study_kri` (operational indicators) and `notes` (teaching notes). |
| `../trialmon_tests/` | testthat tests: rule boundaries, the shipped study, and the server through `shiny::testServer()`. |

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
