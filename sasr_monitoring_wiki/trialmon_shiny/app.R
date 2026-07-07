# ===========================================================================
# app.R - TRIALMON participant-safety SCREENING console (Shiny).
#
# The signature eDISH / Hy's-Law scatter, the QTcF and 3+3 screens, an AE grid,
# and a per-participant evidence packet. Click a point on the eDISH plot (or pick
# a participant) to open the packet. Every panel is a SCREENING lens: it flags a
# position for the medical monitor / SRC, it never reports a number or adjudicates.
# Synthetic, no PHI (values are xULN multiples / ms, not measurements).
#
# Run:  shiny::runApp("sasr_monitoring_wiki/trialmon_shiny")
# ===========================================================================
library(shiny); library(bslib); library(ggplot2)
source("R/logic.R")
if (!file.exists("data/participants.csv")) { source("R/gen_data.R"); gen_trialmon("data") }
tm <- trialmon_load("data")
P  <- score_participants(tm$participants)
DARK <- theme_minimal(base_size = 12) + theme(
  legend.position = "top", plot.background = element_rect(fill="#141925", colour=NA),
  panel.background = element_rect(fill="#141925", colour=NA), text = element_text(colour="#e9edf7"),
  axis.text = element_text(colour="#c5cee4"), panel.grid = element_line(colour="#2a3242"),
  legend.text = element_text(colour="#c5cee4"), plot.title = element_text(colour="#e9edf7", size=12))

ui <- page_sidebar(
  title = "TRIALMON - Participant-Safety Screening",
  theme = bs_theme(version = 5, bootswatch = "darkly", primary = "#5b8cff"),
  sidebar = sidebar(
    width = 320,
    div(class = "small text-muted",
        "A screening lens across the safety database. It flags positions; the medical ",
        "monitor / SRC / DSMB decide. Values are xULN multiples, synthetic, no PHI. ",
        "Click a point on the eDISH plot or pick a participant to open the evidence packet."),
    selectInput("pid", "Participant", choices = sort(P$id), selected = "CP101-014"),
    hr(),
    uiOutput("packet")
  ),
  layout_columns(
    col_widths = c(2,2,2,2,2,2),
    value_box("Safety status", uiOutput("v_status"), theme = "secondary"),
    value_box("Participants", textOutput("v_n"), theme = "secondary"),
    value_box("RED flags", textOutput("v_red"), theme = "danger"),
    value_box("AMBER flags", textOutput("v_amber"), theme = "warning"),
    value_box("Grade >=3 AE", textOutput("v_g3"), theme = "secondary"),
    value_box("SAEs", textOutput("v_sae"), theme = "secondary")
  ),
  layout_columns(
    col_widths = c(7,5),
    card(card_header("eDISH / Hy's-Law screen (click a point)"), plotOutput("edish", height="360px", click="edish_click")),
    card(card_header("Screening worklist (ranked)"), uiOutput("worklist"))
  ),
  layout_columns(
    col_widths = c(4,4,4),
    card(card_header("3+3 DLT ladder"), plotOutput("ladder", height="240px")),
    card(card_header("AE by SOC x max grade"), plotOutput("aegrid", height="240px")),
    card(card_header(textOutput("traj_hdr")), plotOutput("traj", height="240px"))
  )
)

server <- function(input, output, session) {
  st <- trialmon_status(tm); k <- trialmon_kpis(tm)
  output$v_status <- renderUI({
    col <- c(GREEN="#43c47d", watch="#5f8aa8", AMBER="#e0a64c", RED="#e8657a")[st]
    span(style = sprintf("color:%s;font-weight:700;white-space:nowrap", col), st)
  })
  output$v_n <- renderText(as.character(k$n)); output$v_red <- renderText(as.character(k$red))
  output$v_amber <- renderText(as.character(k$amber)); output$v_g3 <- renderText(as.character(k$g3ae))
  output$v_sae <- renderText(as.character(k$sae))

  output$edish <- renderPlot({
    P$flag <- ifelse(P$hys, "Hy's-Law (RED)", ifelse(P$alt > 3 & P$tbl <= 2, "ALT-only (near-miss)", "within limits"))
    ggplot(P, aes(alt, tbl, colour = flag)) +
      annotate("rect", xmin=3, xmax=Inf, ymin=2, ymax=Inf, fill="#e8657a", alpha=.08) +
      geom_hline(yintercept=2, linetype=2, colour="#e0a64c") +
      geom_vline(xintercept=3, linetype=2, colour="#e0a64c") +
      geom_point(size=3) +
      geom_text(data=P[P$hys | P$alt>3, ], aes(label=id), colour="#c5cee4", size=3, vjust=-1) +
      scale_x_log10() + scale_y_log10() +
      scale_colour_manual(values=c("Hy's-Law (RED)"="#e8657a","ALT-only (near-miss)"="#e0a64c","within limits"="#43c47d")) +
      labs(x="peak ALT (x ULN, log)", y="peak TBili (x ULN, log)", colour=NULL,
           title="Upper-right quadrant = Hy's-Law screening position") + DARK
  })
  observeEvent(input$edish_click, {
    np <- nearPoints(P, input$edish_click, xvar="alt", yvar="tbl", maxpoints=1)
    if (nrow(np)) updateSelectInput(session, "pid", selected = np$id[1])
  })

  output$worklist <- renderUI({
    wl <- trialmon_worklist(tm)
    if (!nrow(wl)) return(div(class="text-muted small", "No screening flags - all within limits."))
    tagList(lapply(seq_len(nrow(wl)), function(j) {
      r <- wl[j, ]; col <- if (r$sev=="RED") "#e8657a" else "#e0a64c"
      div(class="d-flex gap-2 py-1", style="border-bottom:1px solid #2a3242",
        div(style=sprintf("flex:0 0 8px;height:8px;border-radius:50%%;background:%s;margin-top:6px",col)),
        div(div(class="small", tags$b(r$id), " · ", r$check),
            div(class="small text-muted", r$value, " — ", tags$code(r$rule))))
    }))
  })

  output$ladder <- renderPlot({
    ds <- dlt_state(tm); ds$cohort <- factor(ds$cohort, levels=ds$cohort)
    ds$col <- c(GREEN="#43c47d", AMBER="#e0a64c", RED="#e8657a")[ds$sev]
    ggplot(ds, aes(cohort, dose_mg, fill=sev)) + geom_col(width=.7) +
      geom_text(aes(label=sprintf("%d/%d DLT", dlt, evaluable)), vjust=-0.5, colour="#e9edf7", size=3.3) +
      scale_fill_manual(values=c(GREEN="#43c47d", AMBER="#e0a64c", RED="#e8657a")) +
      labs(x=NULL, y="dose (mg)", fill=NULL, title="Dose escalation vs 3+3") + DARK
  })

  output$aegrid <- renderPlot({
    ae <- tm$aes; ae$soc <- sub(" disorders","", ae$soc)
    g <- aggregate(list(n=ae$grade), by=list(soc=ae$soc, grade=factor(ae$grade, levels=1:4)), length)
    ggplot(g, aes(grade, soc, fill=n)) + geom_tile(colour="#141925") +
      geom_text(aes(label=n), colour="#0b1020", fontface="bold", size=3.6) +
      scale_fill_gradient(low="#3a4157", high="#e8657a") +
      labs(x="CTCAE grade", y=NULL, fill=NULL, title="Treatment-emergent AEs") + DARK +
      theme(legend.position="none")
  })

  sel <- reactive(P[P$id == input$pid, ])
  output$traj_hdr <- renderText(sprintf("%s trajectory (x ULN)", input$pid))
  output$traj <- renderPlot({
    s <- sel()
    d <- rbind(cbind(trajectory(1.0, s$alt), analyte="ALT"),
               cbind(trajectory(0.9, s$ast), analyte="AST"),
               cbind(trajectory(0.7, s$tbl), analyte="TBili"))
    ggplot(d, aes(visit, value, colour=analyte, group=analyte)) +
      geom_hline(yintercept=c(2,3), linetype=3, colour="#e0a64c") +
      geom_line(linewidth=1) + geom_point(size=2) +
      scale_colour_manual(values=c(ALT="#e8657a", AST="#e0a64c", TBili="#5b8cff")) +
      labs(x=NULL, y="x ULN", colour=NULL) + DARK +
      theme(axis.text.x=element_text(angle=40, hjust=1))
  })

  output$packet <- renderUI({
    s <- sel(); ae <- tm$aes[tm$aes$id == input$pid, ]
    scol <- c(GREEN="#43c47d", watch="#5f8aa8", AMBER="#e0a64c", RED="#e8657a")
    tagList(
      div(class="fw-bold", sprintf("%s — %s (%d mg)", s$id, s$cohort, s$dose_mg)),
      div(class="small text-muted mb-1", s$disposition),
      div(class="small", tags$b("eDISH: "),
          if (s$hys) span(style="color:#e8657a;font-weight:700", sprintf("Hy's-Law position — ALT %.1fx & TBili %.1fx (R %.1f, %s)", s$alt, s$tbl, s$rratio, s$pattern))
          else sprintf("ALT %.1fx / TBili %.1fx — not a Hy's position", s$alt, s$tbl)),
      div(class="small", tags$b("QTcF: "), span(style=sprintf("color:%s;font-weight:700", scol[s$qsev]),
          sprintf("%d ms (d%d) — %s", s$qt, s$dqt, s$qsev))),
      if (nrow(ae)) div(class="small mt-1", tags$b(sprintf("AEs (%d): ", nrow(ae))),
          paste(sprintf("%s G%d%s", ae$pt, ae$grade, ifelse(ae$serious=="Y"," SAE","")), collapse="; ")),
      if (nzchar(s$note)) div(class="small text-muted mt-1", tags$em(s$note))
    )
  })
}

shinyApp(ui, server)
