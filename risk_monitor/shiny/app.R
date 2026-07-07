# ===========================================================================
# app.R - Trial-Termination Early-Warning console (Shiny), 3 tiers.
#
# Participant / Study / Client signals roll up to a tier RAG and an overall
# termination-risk index. Select a signal and change its level to watch the
# tier and overall risk move - the roll-up is transparent. The AI flags; the
# SRC / DSMB / medical monitor / PM / account lead decide. Synthetic, no PHI.
#
# Run:  shiny::runApp("risk_monitor/shiny")
# Data: data/signals.csv (a representative subset; swap in your KRI feed).
# ===========================================================================
library(shiny); library(bslib); library(DT)
source("R/logic.R")
seed <- risk_load("data")
RAG_THEME <- c(green = "success", amber = "warning", red = "danger")

ui <- page_sidebar(
  title = "Trial-Termination Early-Warning",
  theme = bs_theme(version = 5, bootswatch = "darkly", primary = "#5b8cff"),
  sidebar = sidebar(
    width = 320,
    div(class = "small text-muted",
        "3 tiers of early-termination risk. The AI flags and drafts; the SRC / DSMB / ",
        "medical monitor / PM / account lead decide. Synthetic, no PHI, no participant records."),
    selectInput("tier", "Show tier", choices = c("All", TIERS), selected = "All"),
    hr(),
    div(class = "small fw-bold text-muted", "Set a signal's level (what-if)"),
    selectInput("sig", "Signal", choices = setNames(seed$id, paste0(seed$id, " - ", seed$signal))),
    radioButtons("level", NULL, choices = c("green","amber","red"), inline = TRUE),
    actionButton("reset", "Reset to feed", class = "btn-sm btn-outline-warning")
  ),
  layout_columns(
    col_widths = c(3,3,3,3),
    value_box("Overall termination risk", uiOutput("v_overall"), theme = "secondary"),
    value_box("Participant tier", uiOutput("v_part"), theme = "secondary"),
    value_box("Study tier", uiOutput("v_study"), theme = "secondary"),
    value_box("Client tier", uiOutput("v_client"), theme = "secondary")
  ),
  layout_columns(
    col_widths = c(7,5),
    card(card_header("Signals (select a row, then set its level at left)"), DTOutput("signals")),
    card(card_header("Early-warning feed (firing, ranked)"), uiOutput("feed"))
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(signals = seed)

  observeEvent(input$sig, {
    lvl <- as.character(rv$signals$level[rv$signals$id == input$sig])
    updateRadioButtons(session, "level", selected = lvl)
  })
  observeEvent(input$level, {
    i <- which(rv$signals$id == input$sig)
    if (length(i) == 1 && as.character(rv$signals$level[i]) != input$level)
      rv$signals$level[i] <- factor(input$level, levels = c("green","amber","red"))
  })
  observeEvent(input$signals_rows_selected, {
    r <- input$signals_rows_selected
    view <- if (input$tier == "All") rv$signals else rv$signals[rv$signals$tier == input$tier, ]
    if (length(r) == 1) updateSelectInput(session, "sig", selected = view$id[r])
  })
  observeEvent(input$reset, { rv$signals <- seed
    updateRadioButtons(session, "level",
      selected = as.character(seed$level[seed$id == input$sig])) })

  ov <- reactive(risk_overall(rv$signals))

  vb <- function(id, tier) {
    o <- ov(); ts <- if (tier == "overall") list(score=o$score, rag=o$rag) else o$tiers[[tier]]
    col <- c(green="#43c47d", amber="#e0a64c", red="#e8657a")[ts$rag]
    span(style = sprintf("color:%s", col), sprintf("%d  ·  %s", ts$score, toupper(ts$rag)))
  }
  output$v_overall <- renderUI(vb("overall","overall"))
  output$v_part    <- renderUI(vb("part","Participant"))
  output$v_study   <- renderUI(vb("study","Study"))
  output$v_client  <- renderUI(vb("client","Client"))

  output$signals <- renderDT({
    v <- if (input$tier == "All") rv$signals else rv$signals[rv$signals$tier == input$tier, ]
    d <- v[, c("tier","id","signal","category","engine","level","weight","advanced")]
    d$advanced <- ifelse(as.logical(d$advanced), "ADV", "")
    datatable(d, rownames = FALSE, selection = "single",
              colnames = c("Tier","ID","Signal","Category","Engine","Level","Wt","Adv"),
              options = list(pageLength = 12, dom = "tp", scrollX = TRUE)) |>
      formatStyle("level", fontWeight = "bold",
        color = styleEqual(c("green","amber","red"), c("#43c47d","#e0a64c","#e8657a")))
  }, server = TRUE)

  output$feed <- renderUI({
    f <- risk_feed(rv$signals)
    if (!nrow(f)) return(div(class="text-muted small","No signals firing - all within limits."))
    tagList(lapply(seq_len(nrow(f)), function(j) {
      r <- f[j, ]; col <- if (r$level == "red") "#e8657a" else "#e0a64c"
      adv <- if (as.logical(r$advanced)) span(class="badge bg-secondary ms-1", "ADV") else NULL
      div(class = "d-flex gap-2 py-1", style = "border-bottom:1px solid #2b3350",
        div(style = sprintf("flex:0 0 8px;height:8px;border-radius:50%%;background:%s;margin-top:6px", col)),
        div(div(class="small", tags$b(r$tier), " · ", tags$code(r$id), " ", r$signal, adv),
            div(class="small text-muted", r$detail)))
    }))
  })
}

shinyApp(ui, server)
