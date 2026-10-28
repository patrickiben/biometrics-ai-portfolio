# Trial-Termination Early-Warning - Shiny app

For a graphical start, follow the [point-and-click toolkit setup](../../TOOLKIT_SETUP.html), create a private project, then choose the Risk card to check packages, upload the listed inputs and start the app. Save supported app downloads before closing; the terminal instructions below are an optional interface.

A runnable two-tier early-termination-risk console. Participant and study
signals roll up to a tier RAG and an overall termination-risk index. Select a
signal and change its level to watch the tier and overall risk move - the roll-up
is transparent. The console flags and drafts; the SRC, the DSMB and the medical monitor
decide. Synthetic, no PHI, no participant records.

## Run it locally for evaluation

Install R 4.1 or later and keep the complete repository checkout. In a terminal at
the repository root, run:

```sh
Rscript launch_app.R risk --install   # first run: install missing packages in a user library
Rscript launch_app.R risk             # later runs: no package downloads
```

The launcher opens your browser and binds Shiny to `127.0.0.1`. Stop it with
Ctrl+C. `Rscript launch_app.R --check risk` checks packages without starting a
server. Packages go into an R-version-specific user cache; set
`BIOMETRICS_R_LIB` to choose a separate user library. System/site libraries are
never installation targets. This evaluation environment reports package versions;
it is not a frozen study environment.

From another working directory, pass the quoted absolute path to the launcher,
for example `Rscript "/path/to/biometrics-ai-portfolio/launch_app.R" risk`.
In an R console that is already inside this app folder, use `shiny::runApp()`
after checking dependencies with the launcher.

Interactive changes are local to the running app session. Keep separate input
copies for each client/study and save the supported downloads before closing;
this example does not provide a shared, persistent study database. The risk
sliders are what-ifs only: they do not write back to `data/signals.csv`, and this
app has no session export.

## What's here

| File | What it is |
|---|---|
| `app.R` | The Shiny console (value boxes + signals table + early-warning feed). |
| `R/logic.R` | The **pure roll-up** - severity-weighted `tier_score()`, `risk_overall()`, the `risk_feed()`, and the counts. The Quarto docs and unit tests call the same functions. |
| `data/signals.csv` | A representative signal set (a subset of the 65-signal catalog; the full catalog is documented in the dashboard wiki). Swap in your KRI feed with the same columns. |
| `../tests/test-logic.R` | Unit tests (run with `Rscript`). |

The roll-up:

```
severity: green 0, amber 50, red 100
tier score  = sum(severity * weight) / sum(weight)        (per tier)
overall     = weighted mean of tier scores (Participant .6, Study .4)
RAG:  > 55 red   ·   26-55 amber   ·   <= 25 green
```

## Make it your own

`data/signals.csv` carries `tier, id, signal, category, level, weight,
advanced, detail`. Replace the rows with your KRIs and stopping-rule states; each
tier re-rolls automatically. The `advanced` flag marks the continuous / anticipatory
signals from the published-method engine (Optimal Transport / Wasserstein drift,
Active Inference / free-energy). To change what a tier RAG means, edit `rag_of()` /
the weights in `R/logic.R`.

## Other formats

The [visual guide](../quarto/risk-guide.html), the shareable
[dashboard](../quarto/risk-dashboard.html), and the
[run-and-build page](../quarto/risk-build.html) are built from this same `R/logic.R`.

*The AI flags; validated tools and humans decide. Reported safety numbers come from the validated safety database, never from a model.*
