# Trial-Termination Early-Warning - Shiny app

A runnable 2-tier early-termination-risk console. Participant and Study signals
roll up to a tier RAG and an overall termination-risk index. Select a
signal and change its level to watch the tier and overall risk move - the roll-up
is transparent. The console flags and drafts; the SRC / DSMB / medical monitor / PM
decide. Synthetic, no PHI, no participant records.

## Run it

```r
install.packages(c("shiny", "bslib", "DT"))   # once
shiny::runApp("risk_monitor/shiny")
```

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny console (value boxes + signals table + early-warning feed). |
| `R/logic.R` | The **pure roll-up** - severity-weighted `tier_score()`, `risk_overall()`, the `risk_feed()`, and the counts. The Quarto docs and unit tests call the same functions. |
| `data/signals.csv` | A representative signal set. Swap in your KRI feed with the same columns. |
| `../tests/test-logic.R` | Unit tests (run with `Rscript`). |

The roll-up:

```
severity: green 0, amber 50, red 100
tier score  = sum(severity * weight) / sum(weight)        (per tier)
overall     = weighted mean of tier scores (Participant .625, Study .375)
RAG:  > 55 red   ·   26-55 amber   ·   <= 25 green
```

## Make it your own

`data/signals.csv` carries `tier, id, signal, category, engine, level, weight,
advanced, detail`. Replace the rows with your KRIs and stopping-rule states; each
tier re-rolls automatically. The `advanced` flag marks illustrative placeholder signals;
the optimal-transport and active-inference engine they describe is not implemented.

**Known issue:** the severity-weighted average can dilute a single red safety signal
(the red Hy's-Law candidate rolls up to an amber Participant tier). The next revision
replaces it with a worst-of roll-up. To change what a tier RAG means, edit `rag_of()` /
the weights in `R/logic.R`.

## Other formats

The [visual guide](../quarto/risk-guide.html), the shareable
[dashboard](../quarto/risk-dashboard.html), and the
[run-and-build page](../quarto/risk-build.html) are built from this same `R/logic.R`.

*The console flags; validated tools and humans decide. Reported safety numbers come from the validated safety database, never from a model.*
