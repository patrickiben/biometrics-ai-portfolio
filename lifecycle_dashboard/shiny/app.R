# ===========================================================================
# app.R - Study Lifecycle Monitor (Shiny)
#
# A runnable, editable operational study-lifecycle console. Portfolio RAG
# heatmap, ranked early-warning signals, portfolio query trend, and a per-study
# detail (milestones, TLF funnel, deliverables). The scoring is transparent:
# nudge a study's open queries or double-programming and watch its risk move.
# No PHI, no participant-level data. Synthetic, deterministic.
#
# Run:  shiny::runApp("lifecycle_dashboard/shiny")
# Data: data/*.csv (regenerate with Rscript R/gen_data.R, or swap in a CTMS export).
# ===========================================================================
library(shiny); library(bslib); library(DT); library(ggplot2)
source("R/logic.R")
if (!file.exists("data/studies.csv")) { source("R/gen_data.R"); gen_portfolio("data") }
seed <- lifecycle_load("data")
MS_ORDER <- c("Protocol","SAP","FPFV","LPLV","DBL","TLFs","CSR")
DARK <- theme_minimal(base_size = 12) + theme(
  legend.position = "none", plot.background = element_rect(fill="#222630", colour=NA),
  panel.background = element_rect(fill="#222630", colour=NA), text = element_text(colour="#e9edf7"),
  axis.text = element_text(colour="#c5cee4"), panel.grid = element_line(colour="#3a4157"),
  plot.title = element_text(colour="#e9edf7", size=12))

ui <- page_sidebar(
  title = "Study Lifecycle Monitor",
  theme = bs_theme(version = 5, bootswatch = "darkly", primary = "#5b8cff"),
  sidebar = sidebar(
    width = 300,
    div(class = "small text-muted", "Operational health, protocol to CSR. Synthetic, no PHI. ",
        "Pick a study, then nudge the what-if sliders to see the transparent score move."),
    selectInput("study", "Study", choices = sort(seed$studies$id), selected = "CP-108"),
    hr(),
    div(class = "small fw-bold text-muted", "What-if on the selected study"),
    sliderInput("openq", "Open queries", min = 0, max = 150, value = 0),
    sliderInput("dblprog", "Double-programmed %", min = 0, max = 100, value = 50),
    actionButton("reset", "Reset to data", class = "btn-sm btn-outline-warning")
  ),
  layout_columns(
    col_widths = c(2,2,2,2,2,2),
    value_box("Active studies", textOutput("k_n"), theme="secondary"),
    value_box("At risk", textOutput("k_risk"), theme="danger"),
    value_box("On watch", textOutput("k_watch"), theme="warning"),
    value_box("Open queries", textOutput("k_q"), theme="secondary"),
    value_box("Avg deliv.", textOutput("k_del"), theme="info"),
    value_box("Next DB lock", textOutput("k_dbl"), theme="secondary")
  ),
  layout_columns(
    col_widths = c(7,5),
    card(card_header("Portfolio risk heatmap (click a row to select)"), plotOutput("heat", height="300px", click="heat_click")),
    card(card_header("Early-warning signals (ranked)"), uiOutput("signals"))
  ),
  layout_columns(
    col_widths = c(5,7),
    card(card_header("Portfolio open-query trend (8 weeks)"), plotOutput("trend", height="240px")),
    card(card_header(textOutput("detail_hdr")),
         layout_columns(col_widths = c(6,6),
           plotOutput("milestones", height="220px"), plotOutput("funnel", height="220px")))
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(studies = seed$studies)

  # keep the what-if sliders in sync with the selected study's data
  observeEvent(input$study, {
    s <- rv$studies[rv$studies$id == input$study, ]
    updateSliderInput(session, "openq", value = s$open_queries,
                      max = max(150, s$open_queries))
    updateSliderInput(session, "dblprog", value = s$dbl_prog_pct)
  })
  observeEvent(list(input$openq, input$dblprog), {
    i <- which(rv$studies$id == input$study)
    if (length(i) == 1) { rv$studies$open_queries[i] <- input$openq
      rv$studies$dbl_prog_pct[i] <- input$dblprog }
  })
  observeEvent(input$reset, {
    rv$studies <- seed$studies
    s <- seed$studies[seed$studies$id == input$study, ]
    updateSliderInput(session, "openq", value = s$open_queries)
    updateSliderInput(session, "dblprog", value = s$dbl_prog_pct)
  })

  data_now <- reactive(list(studies = rv$studies, milestones = seed$milestones,
                            deliverables = seed$deliverables, query_trend = seed$query_trend))
  st  <- reactive(score_portfolio(data_now()))
  kpi <- reactive(lifecycle_kpis(st(), data_now()))

  output$k_n     <- renderText(as.character(kpi()$n))
  output$k_risk  <- renderText(as.character(kpi()$at_risk))
  output$k_watch <- renderText(as.character(kpi()$watch))
  output$k_q     <- renderText(as.character(kpi()$open_q))
  output$k_del   <- renderText(sprintf("%d%%", kpi()$avg_del))
  output$k_dbl   <- renderText(if (is.na(kpi()$next_dbl_days)) "-" else sprintf("%dd", kpi()$next_dbl_days))

  heat_long <- reactive({
    x <- st(); dims <- c("Timeline","Data","TLF","Resource")
    do.call(rbind, lapply(dims, function(dm) data.frame(
      id = x$id, dim = dm, value = x[[dm]], stringsAsFactors = FALSE)))
  })
  output$heat <- renderPlot({
    x <- st(); hl <- heat_long()
    hl$id  <- factor(hl$id, levels = rev(x$id))
    hl$dim <- factor(hl$dim, levels = c("Timeline","Data","TLF","Resource"))
    ggplot(hl, aes(dim, id, fill = value)) +
      geom_tile(colour = "#222630", linewidth = 1.5) +
      geom_text(aes(label = value), colour = "#0b1020", fontface = "bold", size = 4) +
      scale_fill_gradientn(colours = c("#43c47d","#e0a64c","#e8657a"), limits = c(0,100)) +
      labs(x = NULL, y = NULL) + DARK + theme(panel.grid = element_blank())
  })
  observeEvent(input$heat_click, {
    x <- st(); lv <- rev(x$id)
    idx <- round(input$heat_click$y)
    if (!is.na(idx) && idx >= 1 && idx <= length(lv))
      updateSelectInput(session, "study", selected = as.character(lv[idx]))
  })

  output$signals <- renderUI({
    sg <- lifecycle_signals(st(), data_now())
    if (!nrow(sg)) return(div(class="text-muted small","No operational signals above threshold."))
    rows <- lapply(seq_len(min(9, nrow(sg))), function(j) {
      r <- sg[j, ]; col <- if (r$sev == "red") "#e8657a" else "#e0a64c"
      div(class = "d-flex gap-2 py-1", style="border-bottom:1px solid #2b3350",
        div(style = sprintf("flex:0 0 8px;height:8px;border-radius:50%%;background:%s;margin-top:6px", col)),
        div(div(class="small", tags$b(r$who), " - ", r$title),
            div(class="small text-muted", r$msg)))
    })
    tagList(rows)
  })

  output$trend <- renderPlot({
    qt <- seed$query_trend
    agg <- aggregate(open_queries ~ week, qt, sum)
    ggplot(agg, aes(week, open_queries)) +
      geom_line(colour = "#5b8cff", linewidth = 1.2) + geom_point(colour = "#5b8cff", size = 2) +
      labs(x = "Week", y = "Open queries (portfolio)") + DARK
  })

  output$detail_hdr <- renderText({ s <- rv$studies[rv$studies$id == input$study, ]
    sprintf("%s - %s (%s)  ·  %d%% deliverables complete", s$id, s$name, s$phase,
            deliverables_pct(data_now(), s$id)) })

  output$milestones <- renderPlot({
    m <- seed$milestones[seed$milestones$study_id == input$study, ]
    m$milestone <- factor(m$milestone, levels = rev(MS_ORDER))
    m$date <- as.Date(m$date)
    cols <- c(done="#43c47d", wip="#5b8cff", risk="#e8657a", todo="#6b7794")
    ggplot(m, aes(date, milestone, colour = status)) +
      geom_point(size = 5) + geom_text(aes(label = milestone), colour="#c5cee4", hjust=-0.25, size=3.3) +
      scale_colour_manual(values = cols) +
      labs(x = NULL, y = NULL, title = "Milestone track") + DARK +
      theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())
  })
  output$funnel <- renderPlot({
    s <- rv$studies[rv$studies$id == input$study, ]
    f <- data.frame(stage = factor(c("Planned","Programmed","QC'd","Finalized"),
                    levels = rev(c("Planned","Programmed","QC'd","Finalized"))),
                    n = c(s$tlf_planned, s$tlf_programmed, s$tlf_qcd, s$tlf_finalized))
    ggplot(f, aes(n, stage)) + geom_col(fill = "#3fd0c9", width = 0.7) +
      geom_text(aes(label = n), hjust = -0.2, colour = "#e9edf7", size = 3.5) +
      labs(x = NULL, y = NULL, title = "TLF production funnel") + DARK +
      xlim(0, max(s$tlf_planned) * 1.15)
  })
}

shinyApp(ui, server)
