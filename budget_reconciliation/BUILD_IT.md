# Build the find-hours app yourself (R Shiny)

This app is even smaller than the UAT tracker, and it uses the exact same
pattern: **a logic core, editable state in `reactiveValues`, reactive rules, and
outputs that read them.** Own the pattern once and you can build the next tool in
an afternoon. Hours / effort only throughout: no dollars, rates, or headcount.

The one equation:

```
NET FINDABLE = (Σ Planned + Contingency) − Σ EAC
```

---

## Step 1 — the logic core (`R/logic.R`)

Plain functions, no Shiny. The roll-up and the sourcing decision:

```r
hours_metrics <- function(ledger, contingency = 40) {
  planned <- sum(ledger$planned); eac <- sum(ledger$eac)
  net_slack <- max(0, planned - eac)             # under-run, floored at zero
  list(planned = planned, eac = eac, net_slack = net_slack,
       contingency = contingency, findable = net_slack + contingency)
}

find_hours <- function(need, ledger, contingency = 40) {
  m <- hours_metrics(ledger, contingency)
  from_slack <- min(need, m$net_slack)           # spend slack first ...
  from_cont  <- min(need - from_slack, contingency)  # ... then contingency ...
  shortfall  <- need - from_slack - from_cont    # ... the rest is a change order
  list(from_slack = from_slack, from_cont = from_cont, shortfall = shortfall,
       absorbable = shortfall <= 0, metrics = m)
}
```

## Step 2 — test it in the console first

```r
source("R/logic.R"); d <- hours_load()
hours_metrics(d$ledger, d$contingency)$findable    # 59
find_hours(90, d$ledger, d$contingency)$shortfall  # 31  -> change order
```

Get the arithmetic right here and every surface (app, Quarto, Excel) agrees.

## Step 3 — the app skeleton

```r
library(shiny); library(bslib); library(DT); library(ggplot2)
source("R/logic.R")
seed <- hours_load()

ui <- page_sidebar(
  title = "Find Hours — Hours Budget Reconciliation",
  theme = bs_theme(version = 5, bootswatch = "darkly"),
  sidebar = sidebar( numericInput("need", "Out-of-scope ask (hours)", 45, min = 0), ... ),
  # value boxes, editable ledger, verdict, plot ...
)
server <- function(input, output, session) { ... }
shinyApp(ui, server)
```

## Step 4 — editable state + reactive rules

```r
  rv <- reactiveValues(ledger = withVar(seed$ledger))          # planned/actual/pct/eac/variance
  metrics <- reactive(hours_metrics(rv$ledger, input$contingency))
  fh      <- reactive(find_hours(input$need, rv$ledger, input$contingency))
```

`metrics` and `fh` re-run whenever the ledger **or** the ask input changes. The
value boxes and the verdict just read them.

## Step 5 — an editable table with a `dataTableProxy`

The ledger is editable inline. On a cell edit, coerce the value, update the
state, recompute the derived `variance`, and push the data back with a proxy so
you do not lose the user's place:

```r
  output$ledger <- renderDT(
    datatable(disp(rv$ledger), rownames = FALSE,
              editable = list(target = "cell", disable = list(columns = c(0, 5)))),
    server = TRUE)
  proxy <- dataTableProxy("ledger")

  observeEvent(input$ledger_cell_edit, {
    info <- input$ledger_cell_edit; j <- info$col + 1L
    num <- suppressWarnings(as.numeric(info$value))
    if (j %in% 2:5 && !is.na(num)) {
      rv$ledger[info$row, j] <- num
      rv$ledger$variance <- rv$ledger$planned - rv$ledger$eac
      replaceData(proxy, disp(rv$ledger), resetPaging = FALSE, rownames = FALSE)
    }
  })
```

## Step 6 — the verdict output

```r
  output$verdict <- renderUI({
    f <- fh()
    if (f$absorbable)
      div(class = "alert alert-success", "Absorbable internally",
          sprintf(" — %d h slack + %d h contingency", f$from_slack, f$from_cont))
    else
      div(class = "alert alert-danger", sprintf("Change order needed: %d h", f$shortfall))
  })
```

## Step 7 — quick-pick buttons and a download

`actionButton`s call `updateNumericInput(session, "need", value = 90)`; a
`downloadHandler` writes the change-order draft from `change_order_text(fh())`.

---

## Run it and verify headless

```r
shiny::runApp("budget_reconciliation/shiny")

shiny::testServer("budget_reconciliation/shiny", {
  session$setInputs(need = 90, contingency = 40)
  fh()$shortfall            # 31
})
```

## Make it yours

- **Change the data:** edit `../templates/project_hours_ledger.csv`.
- **Change the rule:** edit `hours_metrics()`/`find_hours()` (for example, hold back part of the contingency as untouchable).
- **Add a source step:** insert it into the sourcing order in `find_hours()`.

Same skeleton as the UAT tracker (`uat_irt/BUILD_IT.md`): logic core →
`reactiveValues` → reactive rules → outputs.
