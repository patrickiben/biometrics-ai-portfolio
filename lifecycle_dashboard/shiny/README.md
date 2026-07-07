# Study Lifecycle Monitor - Shiny app

A runnable operational study-lifecycle console: portfolio RAG heatmap, ranked
early-warning signals, portfolio query trend, and a per-study detail (milestones,
TLF production funnel, deliverables). The risk scoring is transparent - pick a
study and nudge the what-if sliders to watch its score move. No PHI, no
participant-level data. Synthetic, deterministic.

## Run it

```r
install.packages(c("shiny", "bslib", "DT", "ggplot2"))   # once
shiny::runApp("lifecycle_dashboard/shiny")
```

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny app (a `bslib` layout + the reactive graph). |
| `R/logic.R` | The **pure scoring** - the four operational dimensions (Timeline, Data, TLF, Resource), the overall blend, the KPIs, and the signal rules, as plain functions. The Quarto docs and the unit tests call the same functions. |
| `R/gen_data.R` | The deterministic synthetic-portfolio generator. |
| `data/*.csv` | The portfolio (`studies`, `milestones`, `deliverables`, `query_trend`). |
| `../tests/test-logic.R` | Unit tests (run with `Rscript`). |

The scoring is deliberately transparent:

```
overall = 0.30*Timeline + 0.28*Data + 0.27*TLF + 0.15*Resource      (each 0..100)
RAG:  > 66 red   ·   34-66 amber   ·   <= 33 green
```

## Make it your own

`R/gen_data.R` writes the four CSVs so you can see the shape. On a real study you
replace them with a **read-only CTMS / EDC export** carrying the same columns
(`studies.csv`: id, phase, days_to_dbl, open_queries, clean_pct, sdv_pct, the TLF
counts, dbl_prog_pct, discrep; plus `milestones.csv`, `deliverables.csv`,
`query_trend.csv`). Nothing here writes back to a source system. To change what
"risk" means, edit `score_study()` in `R/logic.R`; nothing else changes.

## Other formats

The [visual guide](../quarto/lifecycle-guide.html), the shareable
[dashboard](../quarto/lifecycle-dashboard.html), and the
[run-and-build page](../quarto/lifecycle-build.html) are all built from this same
`R/logic.R`.

*A screening lens for operational health, never a reported clinical number.*
