# ===========================================================================
# app.R: TRIALMON safety review console (Shiny), on SYNTHETIC data.
#
# One screen for a Safety Review Committee style review of a dose-escalation study:
# a ranked worklist, the eDISH plot (click a point to open that participant), QTcF
# categories, CTCAE lab shifts, adverse events by SOC and PT, the DLT tally against an
# illustrative 3+3 rule, and a study tier of operational indicators with a what-if.
# Every level rolls up worst-of. The console flags; the medical monitor and the
# committee decide, and it never makes a dose-escalation decision.
#
# Shinylive-ready: all data sit in data/, the packages are shiny, bslib, DT and ggplot2,
# and the CSV download is built in the browser (a Blob), not by a downloadHandler.
# Run:  shiny::runApp("sasr_monitoring_wiki/trialmon_shiny")
# ===========================================================================
suppressPackageStartupMessages({ library(shiny); library(bslib); library(DT); library(ggplot2) })
source("R/logic.R")
if (!file.exists("data/adsl.csv")) { source("R/gen_data.R"); gen_trialmon("data") }
tm <- trialmon_load("data")
STUDY0 <- study_signals(tm)
KRI0 <- STUDY0$ID[STUDY0$LEVEL != "GREEN"][1]          # first firing indicator opens selected
LEVELS <- c("GREEN", "AMBER", "RED")

# a few lines of JavaScript: turn a CSV string sent from R into a file the browser saves
DOWNLOAD_JS <- "
Shiny.addCustomMessageHandler('trialmon-download', function(m) {
  var url = URL.createObjectURL(new Blob([m.content], {type: m.type}));
  var a = document.createElement('a');
  a.href = url; a.download = m.filename; document.body.appendChild(a); a.click();
  setTimeout(function () { URL.revokeObjectURL(url); a.remove(); }, 1000);
});"

SEV_CSS <- "
.sev{font-weight:700;white-space:nowrap}
.sev-RED{color:#b42318}.sev-AMBER{color:#8a5300}.sev-watch{color:#2f5f8a}.sev-GREEN{color:#1d6b3a}
[data-bs-theme=dark] .sev-RED{color:#ff9b8f}[data-bs-theme=dark] .sev-AMBER{color:#f3c169}
[data-bs-theme=dark] .sev-watch{color:#9cc3ea}[data-bs-theme=dark] .sev-GREEN{color:#8fd8a8}
.packet dt{font-weight:600;margin-top:.4rem}.packet dd{margin:0}
.foot{font-size:.85rem;color:var(--bs-secondary-color)}
.tm-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(128px,1fr));gap:.5rem;margin:.5rem 0 .9rem}
.tm-kpi{border:1px solid var(--bs-border-color);border-radius:.5rem;padding:.45rem .75rem;background:var(--bs-body-bg)}
.tm-kpi .k{font-size:.8rem;color:var(--bs-secondary-color);line-height:1.2}
.tm-kpi .v{font-size:1.35rem;font-weight:700;line-height:1.4}"

sev_span <- function(s) span(class = paste0("sev sev-", s), s)
kpi <- function(label, value) div(class = "tm-kpi", div(class = "k", label), div(class = "v", value))

ui <- page_sidebar(
  title = div(class = "d-flex flex-wrap align-items-center gap-2 w-100",
              span("TRIALMON: safety review console"),
              span(class = "badge text-bg-warning", "synthetic data"),
              div(class = "ms-auto", input_dark_mode(id = "mode"))),
  theme = bs_theme(version = 5, primary = "#0757BF"),
  fillable = FALSE,
  sidebar = sidebar(
    width = 340,
    selectInput("pid", "Participant", choices = tm$adsl$USUBJID, selected = "CP101-014"),
    uiOutput("packet"),
    hr(),
    h6("SAP settings"),
    radioButtons("ctcae", "Lab grading", choices = c("NCI CTCAE v6.0" = "6.0", "v5.0 (per protocol)" = "5.0"),
                 selected = "6.0"),
    numericInput("window", "Potential Hy's Law: days after the AT elevation", value = 30, min = 1, max = 90),
    checkboxInput("alp", "Also require ALP < 2x ULN (an SAP convention)", value = FALSE),
    textInput("meddra", "MedDRA version (label)", value = "29.1")
  ),
  tags$head(tags$link(rel = "icon", href = "data:,"), tags$script(HTML(DOWNLOAD_JS)), tags$style(HTML(SEV_CSS))),
  p(class = "small mb-2",
    "Synthetic study CP-101: a first-in-human multiple ascending dose study at the Cohort 4 (120 mg) data cut. ",
    "The console flags positions for the medical monitor and the Safety Review Committee; it does not adjudicate ",
    "DLTs or Hy's Law cases and makes no dose-escalation decision. Every tier rolls up worst-of."),
  div(class = "tm-kpis",
    kpi("Overall (worst-of)", uiOutput("v_overall", inline = TRUE)),
    kpi("Participants and cohorts", uiOutput("v_part", inline = TRUE)),
    kpi("Study tier", uiOutput("v_study", inline = TRUE)),
    kpi("RED flags", textOutput("v_red", inline = TRUE)),
    kpi("AMBER flags", textOutput("v_amber", inline = TRUE)),
    kpi("Dosed participants", textOutput("v_n", inline = TRUE))
  ),
  navset_card_tab(
    id = "tabs",
    nav_panel("Worklist",
      div(class = "d-flex flex-wrap gap-2 align-items-center mb-2",
          actionButton("dl", "Download the worklist (CSV)", class = "btn-sm btn-outline-primary"),
          span(class = "foot", "Ranked RED, then AMBER. The file is built in your browser.")),
      DTOutput("worklist")),
    nav_panel("Liver (eDISH)",
      plotOutput("edish", height = "420px", click = "edish_click"),
      p(class = "foot", "Peak post-baseline ALT or AST against peak total bilirubin (TBL), as multiples of ULN, log scales. ",
        "Peaks need not be concurrent: a point in the upper-right quadrant is a potential Hy's Law case only when ",
        "TBL > 2x ULN came on or after the aminotransferase elevation within the window. Click a point to open it."),
      plotOutput("traj", height = "260px"),
      DTOutput("liver_tbl")),
    nav_panel("QTcF",
      tableOutput("qtc_cat"),
      p(class = "foot", "Categorical analysis per ICH E14 and the E14/S7B Q&As: maximum post-baseline QTcF > 450, > 480 and ",
        "> 500 ms; maximum change from baseline > 30 and > 60 ms. Categories are cumulative."),
      DTOutput("qtc_tbl")),
    nav_panel("Labs (CTCAE)",
      tableOutput("shift"),
      uiOutput("shift_note")),
    nav_panel("Adverse events",
      tableOutput("ae_tbl"),
      uiOutput("ae_note")),
    nav_panel("Dose escalation",
      tableOutput("dlt_tbl"),
      plotOutput("ladder", height = "260px"),
      p(class = "foot", "3+3 appears only as an illustrative rule reference: 0 of 3 or 1 of 6 is escalation-eligible, ",
        "1 of 3 means expand to 6, and 2 or more DLTs mean the dose exceeds the MTD (which needs 6 treated). ",
        "Model-assisted designs such as BOIN (FDA fit-for-purpose determination, December 2021) are the current ",
        "alternative; this demo does not implement them. The committee adjudicates DLTs and decides.")),
    nav_panel("Study tier",
      p(class = "small", "Study-level indicators from the operational feed, plus two computed from the data. ",
        "Exceeding a pre-specified range triggers evaluation, not an automatic stop (ICH E6(R3) 3.10.1.3). ",
        "Try a what-if: pick an indicator and set its level; the tiers re-roll worst-of."),
      div(class = "d-flex flex-wrap gap-3 align-items-end",
          selectInput("kri", "Indicator", choices = setNames(STUDY0$ID, paste(STUDY0$ID, STUDY0$INDICATOR, sep = ": ")),
                      selected = KRI0, width = "360px"),
          radioButtons("kri_level", "Level (what-if)", choices = LEVELS, inline = TRUE,
                       selected = STUDY0$LEVEL[STUDY0$ID == KRI0]),
          actionButton("kri_reset", "Reset to the feed", class = "btn-sm btn-outline-secondary mb-3")),
      DTOutput("study_tbl"))
  )
)

server <- function(input, output, session) {
  settings <- reactive({
    w <- input$window
    if (is.null(w) || is.na(w) || w < 1) w <- 30
    trialmon_settings(if (is.null(input$ctcae)) "6.0" else input$ctcae, w, isTRUE(input$alp),
                      if (is.null(input$meddra) || !nzchar(input$meddra)) "29.1" else input$meddra)
  })
  study <- reactiveVal(STUDY0)
  roll <- reactive(trialmon_rollup(tm, settings(), study()))
  liver <- reactive(hys_screen(tm$adlb, settings()$hys_window, settings()$alp_convention))
  pstat <- reactive({
    wl <- roll()$worklist; q <- qtc_screen(tm$adeg)
    vapply(tm$adsl$USUBJID, function(i) worst(c(wl$sev[wl$tier == "Participant" & wl$id == i],
                                                q$sev[q$USUBJID == i])), character(1))
  })
  dark <- reactive(identical(input$mode, "dark"))
  gtheme <- reactive({
    fg <- if (dark()) "#E6EAEE" else "#18212B"; grid <- if (dark()) "#323C47" else "#D5DBE1"
    theme_minimal(base_size = 12) + theme(
      text = element_text(colour = fg), axis.text = element_text(colour = fg),
      panel.grid = element_line(colour = grid), legend.position = "top",
      plot.background = element_rect(fill = "transparent", colour = NA),
      panel.background = element_rect(fill = "transparent", colour = NA))
  })
  pal <- reactive(if (dark()) c(GREEN = "#8fd8a8", watch = "#9cc3ea", AMBER = "#f3c169", RED = "#ff9b8f")
                  else c(GREEN = "#1d6b3a", watch = "#2f5f8a", AMBER = "#a86400", RED = "#b42318"))

  output$v_overall <- renderUI(sev_span(roll()$overall))
  output$v_part <- renderUI(sev_span(roll()$participant))
  output$v_study <- renderUI(sev_span(roll()$study))
  output$v_red <- renderText(roll()$red)
  output$v_amber <- renderText(roll()$amber)
  output$v_n <- renderText(nrow(tm$adsl))

  output$worklist <- renderDT({
    wl <- roll()$worklist
    datatable(wl, rownames = FALSE, selection = "single",
              colnames = c("Tier", "Participant, cohort or indicator", "Level", "Screen", "Value", "Rule"),
              options = list(pageLength = 15, dom = "tp", scrollX = TRUE))
  })
  observeEvent(input$worklist_rows_selected, {
    r <- roll()$worklist[input$worklist_rows_selected, ]
    if (nrow(r) && r$tier == "Participant") updateSelectInput(session, "pid", selected = r$id)
  })

  # client-side download: R builds the CSV text, the browser saves it (works under Shinylive)
  dl_payload <- reactiveVal(NULL)
  observeEvent(input$dl, {
    p <- list(filename = sprintf("trialmon_worklist_CTCAEv%s.csv", settings()$ctcae),
              type = "text/csv", content = as_csv_text(roll()$worklist))
    dl_payload(p)
    session$sendCustomMessage("trialmon-download", p)
  })

  output$edish <- renderPlot({
    h <- liver()
    h$screen <- factor(ifelse(h$hys, "Potential Hy's Law", ifelse(!is.na(h$at3x_day), "AT > 3x ULN: confirm", "No hepatic flag")),
                       levels = c("Potential Hy's Law", "AT > 3x ULN: confirm", "No hepatic flag"))
    lab <- h[h$peak_at >= 2.5 | h$peak_tbl > 1.5, ]
    ggplot(h, aes(peak_at, peak_tbl, colour = screen)) +
      annotate("rect", xmin = 3, xmax = Inf, ymin = 2, ymax = Inf, alpha = .10, fill = pal()[["RED"]]) +
      geom_vline(xintercept = 3, linetype = 2, colour = pal()[["AMBER"]]) +
      geom_hline(yintercept = 2, linetype = 2, colour = pal()[["AMBER"]]) +
      geom_point(size = 3.2) +
      geom_text(data = lab, aes(label = USUBJID), vjust = -1, size = 3.4, show.legend = FALSE) +
      annotate("text", x = 9.5, y = 6, label = "upper right: check timing", hjust = 1, size = 3.4, colour = pal()[["RED"]]) +
      annotate("text", x = 9.5, y = 0.22, label = "lower right: AT >= 3x, TBL <= 2x", hjust = 1, size = 3.4, colour = pal()[["AMBER"]]) +
      scale_x_log10(limits = c(.2, 10)) + scale_y_log10(limits = c(.2, 6)) +
      scale_colour_manual(values = setNames(pal()[c("RED", "AMBER", "GREEN")], levels(h$screen)), drop = FALSE,
                          name = "Hepatic screen") +
      labs(x = "Peak ALT or AST (x ULN, log scale)", y = "Peak total bilirubin (x ULN, log scale)") + gtheme()
  }, bg = "transparent", res = 96)
  observeEvent(input$edish_click, {
    np <- nearPoints(liver(), input$edish_click, xvar = "peak_at", yvar = "peak_tbl", maxpoints = 1)
    if (nrow(np)) updateSelectInput(session, "pid", selected = np$USUBJID[1])
  })
  output$traj <- renderPlot({
    d <- liver_trajectory(tm, input$pid)
    ggplot(d, aes(ADY, xuln, colour = test)) +
      geom_hline(yintercept = c(2, 3), linetype = 3, colour = pal()[["AMBER"]]) +
      geom_line(linewidth = .9) + geom_point(size = 2) +
      scale_colour_manual(values = c(ALT = "#c0392b", AST = "#d98a1a", ALP = "#6b7c8f", TBL = "#2f6fb5")) +
      labs(x = "Study day", y = "x ULN", colour = NULL, title = paste(input$pid, "liver tests by study day")) + gtheme()
  }, bg = "transparent", res = 96)
  output$liver_tbl <- renderDT({
    h <- liver()
    h <- h[h$peak_at >= 3 | h$peak_tbl > 2 | h$sev != "GREEN", ]
    d <- data.frame(Participant = h$USUBJID, Level = h$sev, `Peak AT` = round(h$peak_at, 1),
                    `Peak TBL` = round(h$peak_tbl, 1), `AT >= 3x ULN (day)` = h$at3_day,
                    `ALP at that draw` = round(h$alp_at3, 1), `R ratio` = round(h$r_at3, 1), Pattern = h$pattern,
                    `TBL > 2x on day` = h$tbl_day, `Potential Hy's Law` = ifelse(h$hys, "Yes", "No"),
                    Quadrant = h$quadrant, `First repeat (days)` = h$repeat_gap, check.names = FALSE)
    datatable(d, rownames = FALSE, options = list(dom = "t", scrollX = TRUE))
  })

  output$qtc_cat <- renderTable({
    q <- qtc_screen(tm$adeg); q$COHORT <- tm$adsl$COHORT[match(q$USUBJID, tm$adsl$USUBJID)]
    cats <- c(`QTcF > 450 ms` = "gt450", `QTcF > 480 ms` = "gt480", `QTcF > 500 ms` = "gt500",
              `Change > 30 ms` = "chg30", `Change > 60 ms` = "chg60", `Baseline > 450 ms` = "base450")
    grp <- c(split(q, q$COHORT), list(Total = q))
    out <- data.frame(Category = names(cats), check.names = FALSE)
    for (g in names(grp)) out[[sprintf("%s (N=%d)", g, nrow(grp[[g]]))]] <- vapply(cats, function(cc) {
      n <- sum(grp[[g]][[cc]]); sprintf("%d (%.0f%%)", n, 100 * n / nrow(grp[[g]]))
    }, character(1))
    out
  }, striped = TRUE, spacing = "s")
  output$qtc_tbl <- renderDT({
    q <- qtc_screen(tm$adeg); q <- q[q$sev != "GREEN", ]
    datatable(data.frame(Participant = q$USUBJID, Level = q$sev, Baseline = q$base, `Max QTcF` = q$max_qtcf,
                         Day = q$max_day, `Max change` = q$max_chg, check.names = FALSE),
              rownames = FALSE, options = list(dom = "t"))
  })

  output$shift <- renderTable({
    s <- lab_shift(tm$adlb, settings()$ctcae)
    data.frame(Test = s$TERM, `Baseline grade` = s$BGRADE, N = s$N, `Worst 0` = s$G0, `1` = s$G1, `2` = s$G2,
               `3` = s$G3, `4` = s$G4, check.names = FALSE)
  }, striped = TRUE, spacing = "s", digits = 0)
  output$shift_note <- renderUI(p(class = "foot", sprintf(paste0(
    "Shift from baseline grade to worst post-baseline grade, participants. Lab grades: NCI CTCAE v%s. ",
    "Creatinine is graded on x ULN and fold over baseline (v5.0: the worse of the two; v6.0: fold over baseline ",
    "only when the baseline is below the LLN), never on mg/dL alone."), settings()$ctcae)))

  output$ae_tbl <- renderTable({
    a <- ae_soc_pt(tm); N <- attr(a, "N")
    lab <- ifelse(a$PT == "", a$SOC, paste0("   ", a$PT))
    out <- data.frame(`SOC / Preferred term` = lab, check.names = FALSE)
    for (g in names(N)) out[[sprintf("%s (N=%d)", g, N[[g]])]] <- sprintf("%d (%.0f%%)", a[[g]], 100 * a[[g]] / N[[g]])
    out
  }, striped = TRUE, spacing = "s")
  output$ae_note <- renderUI(p(class = "foot", sprintf(paste0(
    "Treatment-emergent AEs, participants counted once per row; N = dosed participants. Coded with MedDRA v%s ",
    "(primary SOC). Grades as recorded (NCI CTCAE v6.0)."), settings()$meddra)))

  output$dlt_tbl <- renderTable({
    d <- dlt_state(tm)
    data.frame(Cohort = d$COHORT, `Dose (mg)` = d$DOSEMG, Status = d$STATUS, Dosed = d$N, `DLT-evaluable` = d$EVALUABLE,
               `Confirmed DLTs` = d$DLT, Pending = d$PENDING, `Rule reference (3+3, illustrative)` = d$text,
               check.names = FALSE)
  }, striped = TRUE, spacing = "s", digits = 0)
  output$ladder <- renderPlot({
    d <- dlt_state(tm); d <- d[d$N > 0, ]; d$COHORT <- factor(d$COHORT, levels = d$COHORT)
    ggplot(d, aes(COHORT, DOSEMG, fill = sev)) + geom_col(width = .65) +
      geom_text(aes(label = sprintf("%d of %d%s", DLT, EVALUABLE, ifelse(PENDING > 0, sprintf(" (+%d pending)", PENDING), ""))),
                vjust = -.4, colour = if (dark()) "#E6EAEE" else "#18212B") +
      scale_fill_manual(values = pal(), name = NULL) + scale_y_continuous(expand = expansion(mult = c(0, .15))) +
      labs(x = NULL, y = "Dose (mg)") + gtheme()
  }, bg = "transparent", res = 96)

  # study tier what-if. The radio starts on the selected indicator's level and its observer
  # ignores the initial value, so opening the app never rewrites an indicator (no flicker).
  observeEvent(input$kri, {
    updateRadioButtons(session, "kri_level", selected = study()$LEVEL[study()$ID == input$kri])
  }, ignoreInit = TRUE)
  observeEvent(input$kri_level, {
    s <- study(); i <- which(s$ID == input$kri)
    if (length(i) == 1 && s$LEVEL[i] != input$kri_level) { s$LEVEL[i] <- input$kri_level; study(s) }
  }, ignoreInit = TRUE)
  observeEvent(input$kri_reset, {
    study(STUDY0)
    updateRadioButtons(session, "kri_level", selected = STUDY0$LEVEL[STUDY0$ID == input$kri])
  })
  output$study_tbl <- renderDT({
    s <- study(); s$CHANGED <- ifelse(s$LEVEL != STUDY0$LEVEL, "what-if", "")
    datatable(s[, c("ID", "INDICATOR", "VALUE", "UNIT", "LEVEL", "CHANGED", "RULE", "DETAIL", "SOURCE")],
              rownames = FALSE, colnames = c("ID", "Indicator", "Value", "Unit", "Level", "", "Rule", "Detail", "Source"),
              options = list(dom = "t", scrollX = TRUE))
  })

  output$packet <- renderUI({
    id <- input$pid; s <- tm$adsl[tm$adsl$USUBJID == id, ]
    h <- liver()[liver()$USUBJID == id, ]; q <- qtc_screen(tm$adeg); q <- q[q$USUBJID == id, ]
    g <- lab_grades(tm$adlb[tm$adlb$USUBJID == id, ], settings()$ctcae); g <- g[!is.na(g$WGRADE) & g$WGRADE >= 2, ]
    ae <- tm$adae[tm$adae$USUBJID == id, ]; nt <- tm$notes$NOTE[tm$notes$USUBJID == id]
    hep <- if (h$hys) sprintf("Potential Hy's Law: AT %.1fx ULN on Day %d, TBL %.1fx ULN on Day %d", h$at3_value, h$at3_day, h$tbl_at_hit, h$tbl_day)
      else if (!is.na(h$at3x_day)) sprintf("AT %.1fx ULN on Day %d: confirm (repeat within 48 to 72 h); TBL peak %.1fx", h$at3x_value, h$at3x_day, h$peak_tbl)
      else sprintf("Peak AT %.1fx, TBL %.1fx ULN: no hepatic flag", h$peak_at, h$peak_tbl)
    div(class = "packet small",
      div(class = "fw-bold", sprintf("%s: %s, %g mg", id, s$COHORT, s$DOSEMG), " ", sev_span(pstat()[[id]])),
      tags$dl(
        tags$dt("Disposition"), tags$dd(sprintf("Treatment %s%s; study %s", tolower(s$EOTSTT),
          if (nzchar(s$DCTREAS)) paste0(" (", tolower(s$DCTREAS), ")") else "", tolower(s$EOSSTT))),
        tags$dt("DLT"), tags$dd(if (s$DLTADJ == "Pending") paste("Pending adjudication:", s$DLTDESC)
                                else if (s$DLTFL == "Y") s$DLTDESC else "No DLT"),
        tags$dt("Liver"), tags$dd(hep, if (!is.na(h$r_at3)) sprintf(" (R %.1f, %s)", h$r_at3, h$pattern)),
        tags$dt("QTcF"), tags$dd(sprintf("max %d ms (baseline %d, change %d): ", q$max_qtcf, q$base, q$max_chg), sev_span(q$sev)),
        tags$dt(sprintf("Lab grades 2 or higher (CTCAE v%s)", settings()$ctcae)),
        tags$dd(if (nrow(g)) paste(sprintf("%s G%d", g$TERM, g$WGRADE), collapse = "; ") else "none"),
        tags$dt(sprintf("Adverse events (%d)", nrow(ae))),
        tags$dd(if (nrow(ae)) paste(sprintf("%s G%d%s", ae$AEDECOD, ae$AETOXGR, ifelse(ae$AESER == "Y", " (serious)", "")),
                                    collapse = "; ") else "none")),
      if (length(nt)) p(class = "fst-italic mb-0", "Synthetic teaching note: ", nt)
    )
  })
}

shinyApp(ui, server)
