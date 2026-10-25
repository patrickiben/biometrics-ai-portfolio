# TRIALMON - Participant-Safety Screening (Shiny app)

A runnable safety-monitoring console: the signature eDISH / Hy's-Law scatter, the
QTcF (ICH E14) and 3+3 DLT screens, an AE-by-SOC grid, and a per-participant
evidence packet. Click a point on the eDISH plot (or pick a participant) to open
the packet. Synthetic, no PHI - values are xULN multiples / ms, not measurements.

**Every panel is a SCREENING lens.** It flags a position for the medical monitor /
SRC / DSMB. It never reports a clinical number and never adjudicates a DLT or a
Hy's-Law case. Reported safety numbers come from the validated safety database.

## Run it

```r
install.packages(c("shiny", "bslib", "ggplot2"))   # once
shiny::runApp("sasr_monitoring_wiki/trialmon_shiny")
```

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny console (eDISH scatter + worklist + 3+3 ladder + AE grid + trajectory + packet). |
| `R/logic.R` | The **pure screening logic** - the eDISH AND-gate, the QTcF tiers, the 3+3 DLT roll-up, the worklist, and the overall status. The Quarto docs and unit tests call the same functions. |
| `R/gen_data.R` | The deterministic synthetic-cohort generator (values are xULN multiples). |
| `data/*.csv` | participants, aes, cohorts. Swap in a read-only export from your validated safety DB / ADaM (same columns). |
| `../trialmon_tests/test-logic.R` | Unit tests (run with `Rscript`). |

The screening rules (illustrative thresholds):

```
eDISH / Hy's-Law : (ALT or AST >= 3x ULN) AND TBili > 2x ULN           -> RED
                   R = (ALT/ULN)/(ALP/ULN): >= 5 hepatocellular, 2 < R < 5 mixed, <= 2 cholestatic
QTcF (ICH E14)   : QTcF > 500 ms or dQTcF > 60 ms -> RED ; > 480/> 30  -> AMBER
3+3 DLT          : >= 2 adjudicated DLT in a cohort -> RED (MTD exceeded);
                   1 DLT with fewer than 6 evaluable -> AMBER (expand to 6);
                   1 of 6 -> GREEN (escalation-eligible; the SRC decides)
```

The **AND-gate** is the point: CP101-009 has ALT 4.2x but TBili 1.6x, so it is *not*
a Hy's-Law position and stays green: a high transaminase alone does not fire the Hy's-Law gate.
Known issue: there is no separate flag for ALT or AST above 3x ULN, which FDA's DILI guidance (2009)
says needs repeat liver tests within 48 to 72 hours; the next revision adds it.

## Make it your own

`R/gen_data.R` writes the CSVs so you can see the shape. On a real study you replace
them with a read-only export from the validated safety database / ADaM (ADLB, ADEG,
ADAE), same columns. Nothing writes back, and the dashboard never becomes the source
of a number - it points a reviewer at a position. To change a threshold, edit the
rule in `R/logic.R`.

## Other formats

The [visual guide](../trialmon_quarto/trialmon-guide.html), the shareable
[dashboard](../trialmon_quarto/trialmon-dashboard.html), and the
[run-and-build page](../trialmon_quarto/trialmon-build.html) are built from this same
`R/logic.R`.

*The AI/tool flags; the medical monitor / SRC / DSMB decide.*
