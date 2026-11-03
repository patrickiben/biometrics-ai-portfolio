# ===========================================================================
# app.R - Operational risk signals console (Shiny), 2 tiers.
#
# Participant and study signals roll up to a tier RAG and an overall
# termination-risk index. Select a signal and change its level to watch the
# tier and overall risk move - the roll-up is transparent. The AI flags; the
# SRC, the DSMB and the medical monitor decide. Synthetic, no PHI.
#
# Run:  shiny::runApp("risk_monitor/shiny")
# Data: data/signals.csv (a representative subset; swap in your KRI feed).
# ===========================================================================
library(shiny); library(bslib); library(DT)
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")
source("R/logic.R")
seed <- risk_load("data")
source(if (file.exists("browser_workspace.R")) "browser_workspace.R" else "../../browser_modules/shared/browser_workspace.R")
source("browser_setup.R", local = TRUE)
RAG_THEME <- c(green = "success", amber = "warning", red = "danger")

ui <- page_sidebar(
  title = div(class = "d-flex flex-wrap align-items-center gap-3", "Operational risk signals", bp_theme_toggle()),
  theme = bp_theme(),
  app_status_ui("the operational signal scores and ranked feed"),
  tags$style(HTML(".bslib-page-sidebar>.navbar{background:var(--surface);border-bottom:1px solid var(--line-2)}
    .bslib-sidebar-layout{--_sidebar-bg:var(--surface);--bslib-sidebar-bg:var(--surface)}
    html .bslib-value-box{background:var(--surface)!important;color:var(--ink)!important;border:1px solid var(--line-2)}
    .value-box-title{color:var(--muted)}")),
  sidebar = sidebar(
    width = 320,
    div(class = "small text-muted",
        "Two tiers of early-warning risk, participant and study. The console flags and drafts; ",
        "the SRC, the DSMB and the medical monitor decide. Operational signal summaries; no prediction of trial termination is supplied."),
    selectInput("tier", "Show tier", choices = c("All", TIERS), selected = "All"),
    hr(),
    div(class = "small fw-bold text-muted", "Set a signal's level (what-if)"),
    selectInput("sig", "Signal", choices = setNames(seed$id, paste0(seed$id, " - ", seed$signal))),
    radioButtons("level", NULL, choices = c("green","amber","red"), selected = as.character(seed$level[1]), inline = TRUE),
    actionButton("reset", "Reset to feed", class = "btn-sm btn-outline-warning")
  ),
  layout_columns(
    col_widths = c(4,4,4),
    value_box("Overall risk", uiOutput("v_overall"), theme = "secondary"),
    value_box("Participant tier", uiOutput("v_part"), theme = "secondary"),
    value_box("Study tier", uiOutput("v_study"), theme = "secondary")
  ),
  layout_columns(
    col_widths = c(7,5),
    card(card_header("Signals (select a row, then set its level at left)"), DTOutput("signals")),
    card(card_header("Early-warning feed (firing, ranked)"), uiOutput("feed"))
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(signals = seed)
  pending_signal <- reactiveVal(NULL)
  observe({ wanted <- pending_signal(); if (!is.null(wanted) && identical(input$sig, wanted$id) && identical(input$level, wanted$level)) pending_signal(NULL) })

  observeEvent(input$sig, {
    lvl <- as.character(rv$signals$level[rv$signals$id == input$sig])
    if (length(lvl) == 1) updateRadioButtons(session, "level", selected = lvl)
  })
  observeEvent(input$level, {
    wanted <- pending_signal()
    if (!is.null(wanted)) {
      if (!identical(input$sig, wanted$id) || !identical(input$level, wanted$level)) return()
      pending_signal(NULL)
    }
    i <- which(rv$signals$id == input$sig)
    if (length(i) == 1 && length(input$level) == 1 && input$level %in% names(SEVERITY) && as.character(rv$signals$level[i]) != input$level)
      rv$signals$level[i] <- factor(input$level, levels = c("green","amber","red"))
  })
  observeEvent(input$signals_rows_selected, {
    r <- input$signals_rows_selected
    view <- if (input$tier == "All") rv$signals else rv$signals[rv$signals$tier == input$tier, ]
    if (length(r) == 1 && is.numeric(r) && is.finite(r) && r == as.integer(r) && r >= 1 && r <= nrow(view))
      updateSelectInput(session, "sig", selected = view$id[r])
  })
  observeEvent(input$reset, { rv$signals <- seed
    updateRadioButtons(session, "level",
      selected = as.character(seed$level[seed$id == input$sig])) })

  ov <- reactive({ req(bw$active()); risk_overall(rv$signals) })

  vb <- function(id, tier) {
    o <- ov(); ts <- if (tier == "overall") list(score=o$score, rag=o$rag) else o$tiers[[tier]]
    col <- sprintf("var(--%s)", ts$rag)
    span(style = sprintf("color:%s", col), sprintf("%d  ·  %s", ts$score, toupper(ts$rag)))
  }
  output$v_overall <- renderUI(vb("overall","overall"))
  output$v_part    <- renderUI(vb("part","Participant"))
  output$v_study   <- renderUI(vb("study","Study"))

  output$signals <- renderDT({
    v <- if (input$tier == "All") rv$signals else rv$signals[rv$signals$tier == input$tier, ]
    d <- v[, c("tier","id","signal","category","level","weight","advanced")]
    d$advanced <- ifelse(as.logical(d$advanced), "ADV", "")
    datatable(d, rownames = FALSE, selection = "single",
              colnames = c("Tier","ID","Signal","Category","Level","Wt","Adv"),
              options = list(pageLength = 12, dom = "tp", scrollX = TRUE)) |>
      formatStyle("level", fontWeight = "bold",
        color = styleEqual(c("green","amber","red"), c("var(--green)","var(--amber)","var(--red)")))
  }, server = TRUE)

  output$feed <- renderUI({
    req(bw$active()); f <- risk_feed(rv$signals)
    if (!nrow(f)) return(div(class="text-muted small","No signals firing - all within limits."))
    tagList(lapply(seq_len(nrow(f)), function(j) {
      r <- f[j, ]; col <- if (r$level == "red") "var(--red)" else "var(--amber)"
      adv <- if (as.logical(r$advanced)) span(class="badge bg-secondary ms-1", "ADV") else NULL
      div(class = "d-flex gap-2 py-1", style = "border-bottom:1px solid var(--line-2)",
        div(style = sprintf("flex:0 0 8px;height:8px;border-radius:50%%;background:%s;margin-top:6px", col)),
        div(div(class="small", tags$b(r$tier), " · ", tags$code(r$id), " ", r$signal, adv),
            div(class="small text-muted", r$detail)))
    }))
  })
  baseline_example <- seed
  source_data <- reactiveVal(NULL)
  bw <- bw_server(input, output, session, "risk", BW_TEMPLATES,
    example = function() lapply(BW_TEMPLATES, `[[`, "data"), validate = bw_risk_validate,
    apply = function(value, settings) {
      source_data(value); rv$signals <- value
      pending_signal(list(id = value$id[[1]], level = as.character(value$level[[1]])))
      updateSelectInput(session, "sig", choices = setNames(value$id, paste0(value$id, " - ", value$signal)), selected = value$id[[1]])
      updateRadioButtons(session, "level", selected = as.character(value$level[[1]]))
    }, clear = function() { source_data(NULL); rv$signals <- bw_empty(baseline_example) },
    export = function() list(inputs = list("signals.csv" = rv$signals), settings = list(),
      outputs = list(overall = bw_scalar_table(ov()), tiers = do.call(rbind, lapply(names(ov()$tiers), function(tier) cbind(tier = tier, bw_scalar_table(ov()$tiers[[tier]])))), signals = rv$signals, firing = risk_feed(rv$signals)),
      notes = "Operational heuristic scores; these are not probabilities of trial termination or clinical decisions."))
  bw_binding("seed", function() { value <- source_data(); req(value); value }, environment())
  rv$signals <- bw_empty(baseline_example)
}

ui <- bw_ui(ui, "Operational risk signals", BW_TEMPLATES, note = "Use tier Participant or Study; level green, amber or red; positive numeric weights; and TRUE/FALSE for advanced. Include both tiers. Scores are transparent operational heuristics, not calibrated outcome probabilities.")
shinyApp(ui, server)
