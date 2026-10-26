# ===========================================================================
# app.R: TRIALMON safety review console (Shiny), on SYNTHETIC data.
#
# One screen for a Safety Review Committee style review of a dose-escalation study:
# a ranked worklist, the eDISH plot (click a point to open that participant), QTcF
# categories, CTCAE lab shifts, adverse events by SOC and PT, the DLT tally against an
# illustrative 3+3 rule, a study tier of operational indicators with a what-if, and a
# convention grid that shows whether each potential Hy's Law flag holds under every
# combination of three SAP conventions. Every level rolls up worst-of, watch included. The
# console flags; the medical monitor and the committee decide, and it never makes a
# dose-escalation decision.
#
# A visitor can always tell what is open and what a click did: the line above the worklist names
# the participant in the sidebar (whose row stays highlighted, however it was chosen), the line under
# the eDISH plot says what each click found, and a short notice explains a click whose effect is out
# of view (a Cohort or Study row; on a phone, the packet below the console).
#
# Shinylive-ready: all data sit in data/, the packages are shiny, bslib and DT (the plots are
# base graphics), and the CSV download is built in the browser (a Blob), not by a
# downloadHandler. The look comes from the site's color tokens on the precompiled Bootstrap
# theme (R/app_view.R), so the browser compiles no Sass. Results that never change while the
# app runs are computed once at startup; on a fast laptop all of app.R's own computation takes
# about 0.3 s in the browser, and the rest of the start is R and its packages loading.
# Run:  shiny::runApp("sasr_monitoring_wiki/trialmon_shiny")
# ===========================================================================
suppressPackageStartupMessages({ library(shiny); library(bslib); library(DT) })
source(if (file.exists("portfolio_app.R")) "portfolio_app.R" else "../../apps/_shared/portfolio_app.R")  # status, error cards
warm_up_graphics()   # in the browser, load the plot fonts while the launch page still shows its status
source("R/logic.R")
source("R/hyslaw_grid.R")
source("R/app_view.R")
if (!file.exists("data/adsl.csv") || !file.exists("data/labs_long.csv")) { source("R/gen_data.R"); gen_trialmon("data") }
tm <- trialmon_load("data")
HL <- hyslaw_load("data")                               # planted grid cases + narrative assertions
GRID0 <- hyslaw_app_grid(tm, HL)
GRID_CHECK <- hyslaw_check_narrative(GRID0, HL$flags)
STUDY0 <- study_signals(tm)
KRI0 <- STUDY0$ID[STUDY0$LEVEL != "GREEN"][1]          # first firing indicator opens selected
LEVELS <- c("GREEN", "AMBER", "RED")
# results that depend on no input: computed once here, not in every reactive that needs them
QTC <- qtc_screen(tm$adeg)
DLT <- dlt_state(tm)
AE <- ae_soc_pt(tm)
DOSED <- DLT[DLT$N > 0, ]
COHORT_TEXT <- sprintf("%d cohorts, %g to %g mg", nrow(DOSED), min(DOSED$DOSEMG), max(DOSED$DOSEMG))
WINDOW_DEFAULT <- 30
E6R3 <- paste("ICH E6(R3) (Step 4 6 Jan 2025; EU effective 23 Jul 2025; FDA final guidance Sep 2025);",
              "Annex 2 Step 4 3 Jun 2026 (CHMP 25 Jun 2026, EU effective 15 Jan 2027; FDA: draft guidance Dec 2024, not final)")

# a few lines of JavaScript: turn a CSV string sent from R into a file the browser saves
DOWNLOAD_JS <- "
Shiny.addCustomMessageHandler('trialmon-download', function(m) {
  var url = URL.createObjectURL(new Blob([m.content], {type: m.type}));
  var a = document.createElement('a');
  a.href = url; a.download = m.filename; document.body.appendChild(a); a.click();
  setTimeout(function () { URL.revokeObjectURL(url); a.remove(); }, 1000);
});"

ui <- page_sidebar(
  title = div(class = "d-flex flex-wrap align-items-center gap-2 w-100",
              span("TRIALMON: safety review console"),
              span(class = "badge text-bg-warning", "synthetic data"),
              div(class = "ms-auto", input_dark_mode(id = "mode"))),
  theme = bs_theme(version = 5),                        # precompiled; the site colors come from tm_css()
  fillable = FALSE,
  sidebar = sidebar(
    width = 340,
    selectInput("pid", "Participant", choices = tm$adsl$USUBJID, selected = "CP101-014"),
    uiOutput("packet"),
    hr(),
    h6("SAP settings"),
    radioButtons("ctcae", "Lab grading (derived from the lab values)", choices = c("NCI CTCAE v6.0" = "6.0", "v5.0 (per protocol)" = "5.0"),
                 selected = "6.0"),
    p(class = "foot", sprintf(paste("This setting re-derives lab grades only. AE grades stay as the investigator",
                                    "recorded them (NCI CTCAE v%s in these data)."), trialmon_settings()$ae_ctcae)),
    numericInput("window", "Potential Hy's Law: days after the AT elevation", value = WINDOW_DEFAULT, min = 1, max = 90),
    p(class = "foot", textOutput("window_note", inline = TRUE)),
    checkboxInput("alp", "Also require ALP < 2x ULN (an SAP convention)", value = FALSE),
    textInput("meddra", "MedDRA version (label)", value = "29.1")
  ),
  tags$head(tags$link(rel = "icon", href = "data:,"), tags$script(HTML(DOWNLOAD_JS)), tags$script(HTML(TM_JS)),
            tags$style(HTML(tm_css()))),
  app_status_ui("the worst-of safety roll-up, the ranked worklist and the participant packet"),
  start_here_ui(nrow(tm$adsl), COHORT_TEXT),
  div(class = "tm-kpis-wrap", div(class = "tm-kpis",         # 7 in a row when wide, 3 + 4, or 1 + 2 + 2 + 2 on a phone
    kpi(tagList("Overall ", span(class = "nw", "(worst-of)")), uiOutput("v_overall", inline = TRUE), "worst of both tiers", tier = TRUE),
    kpi("Participants and cohorts", uiOutput("v_part", inline = TRUE), "worst participant or cohort", tier = TRUE),
    kpi("Study tier", uiOutput("v_study", inline = TRUE), "worst study indicator", tier = TRUE),
    kpi("RED flags", textOutput("v_red", inline = TRUE), "worklist rows", "RED"),
    kpi("AMBER flags", textOutput("v_amber", inline = TRUE), "worklist rows", "AMBER"),
    kpi("Watch", textOutput("v_watch", inline = TRUE), "worklist rows", "watch"),
    kpi("Dosed participants", textOutput("v_n", inline = TRUE), COHORT_TEXT)
  )),
  navset_card_tab(
    id = "tabs",
    nav_panel("Worklist",
      div(class = "d-flex flex-wrap gap-2 align-items-start justify-content-between mb-1",
          div(class = "flex-grow-1", style = "min-width:14rem;flex-basis:20rem", uiOutput("wl_status")),
          actionButton("dl", "Download the worklist (CSV)", class = "btn-sm btn-outline-primary")),
      tm_wide(tm_xscroll(DTOutput("worklist", fill = FALSE))),
      p(class = "foot mt-2", "Ranked RED, then AMBER, then watch. The CSV file is built in your browser; its first",
        "column labels every row synthetic.")),
    nav_panel("Liver (eDISH)",
      layout_columns(
        col_widths = breakpoints(sm = 12, lg = c(7, 5)),
        div(plotOutput("edish", height = "430px", click = "edish_click"),
            uiOutput("edish_msg"),
            p(class = "tm-plot-note", "Shaded box: peak ALT or AST >= 3x ULN and peak TBL > 2x ULN. A point there is a ",
              "potential Hy's Law case only when the timing fits; the table below says which.")),
        div(plotOutput("traj", height = "300px"),
            p(class = "tm-plot-note", "ALT, AST, ALP and TBL by study day for the participant in the sidebar, as ",
              "multiples of ULN. Pick another participant in the sidebar or on the eDISH plot."))),
      p(class = "foot", "Peak post-baseline ALT or AST against peak total bilirubin (TBL), as multiples of ULN, log scales. ",
        "Peaks need not be concurrent: a point in the upper-right quadrant is a potential Hy's Law case only when ",
        "TBL > 2x ULN came on or after an aminotransferase elevation (ALT or AST >= 3x ULN) within the window. ",
        "Every such draw opens its own window. The axes widen so that no participant falls off."),
      tm_wide(DTOutput("liver_tbl", fill = FALSE))),
    nav_panel("Convention grid",
      p(class = "small", HYS_GRID_LABEL),
      p(class = "tm-hint", "One row per participant, one column per combination; ", tags$strong("scroll the table sideways"),
        " for the verdict, what the narrative states and whether the two agree."),
      tm_wide(tm_xscroll(DTOutput("grid_tbl", fill = FALSE)), hint = FALSE),
      uiOutput("grid_note")),
    nav_panel("QTcF",
      tm_wide(tm_xscroll(tableOutput("qtc_cat"))),
      p(class = "foot", "Categorical analysis per ICH E14 and the E14/S7B Q&As: maximum post-baseline QTcF > 450, > 480 and ",
        "> 500 ms; maximum change from baseline > 30 and > 60 ms. Categories are cumulative."),
      tm_wide(DTOutput("qtc_tbl", fill = FALSE))),
    nav_panel("Labs (CTCAE)",
      tm_wide(tm_xscroll(tableOutput("shift"))),
      uiOutput("shift_note")),
    nav_panel("Adverse events",
      tm_wide(tm_xscroll(tableOutput("ae_tbl"))),
      uiOutput("ae_note")),
    nav_panel("Dose escalation",
      tm_wide(tm_xscroll(uiOutput("dlt_tbl"))),            # one card per cohort on a phone
      plotOutput("ladder", height = "300px"),
      p(class = "foot", "3+3 appears only as an illustrative rule reference: 0 of 3 or 1 of 6 is escalation-eligible, ",
        "1 of 3 means expand to 6, and 2 or more DLTs mean the dose exceeds the MTD (which needs 6 treated). ",
        "A cohort with a DLT pending adjudication takes the worse of its two possible outcomes. ",
        "Model-assisted designs such as BOIN (FDA fit-for-purpose determination, December 2021) are the current ",
        "alternative; this demo does not implement them. The committee adjudicates DLTs and decides.")),
    nav_panel("Study tier",
      p(class = "small", "Study-level indicators from the operational feed, plus two computed from the data. ",
        "Exceeding a pre-specified range triggers evaluation, not an automatic stop (ICH E6(R3) section 3.10.1.3). ",
        "Try a what-if: pick an indicator and set its level; the tiers re-roll worst-of."),
      div(class = "d-flex flex-wrap gap-3 align-items-end",
          selectInput("kri", "Indicator", choices = setNames(STUDY0$ID, paste(STUDY0$ID, STUDY0$INDICATOR, sep = ": ")),
                      selected = KRI0, width = "360px"),
          radioButtons("kri_level", "Level (what-if)", choices = LEVELS, inline = TRUE,
                       selected = STUDY0$LEVEL[STUDY0$ID == KRI0]),
          actionButton("kri_reset", "Reset to the feed", class = "btn-sm btn-outline-secondary mb-3")),
      tm_wide(DTOutput("study_tbl", fill = FALSE)),
      p(class = "foot mt-2", paste0("Guidance: ", E6R3, ".")))
  ),
  p(class = "tm-footer", "Synthetic data only: study CP-101 and every participant in it are invented. TRIALMON flags ",
    "positions for a human reviewer; in a real study the numbers a committee relies on come from validated programs.")
)

server <- function(input, output, session) {
  win <- reactive({
    w <- input$window
    ok <- !is.null(w) && length(w) == 1 && !is.na(w) && w >= 1 && w <= 90
    list(value = if (ok) as.numeric(w) else WINDOW_DEFAULT, ok = ok)
  })
  settings <- reactive({
    trialmon_settings(if (is.null(input$ctcae)) "6.0" else input$ctcae, win()$value, isTRUE(input$alp),
                      if (is.null(input$meddra) || !nzchar(input$meddra)) "29.1" else input$meddra)
  })
  study <- reactiveVal(STUDY0)
  roll <- reactive(trialmon_rollup(tm, settings(), study()))
  liver <- reactive(hys_screen(tm$adlb, settings()$hys_window, settings()$alp_convention))
  pstat <- reactive({
    wl <- roll()$worklist
    vapply(tm$adsl$USUBJID, function(i) worst(c(wl$sev[wl$tier == "Participant" & wl$id == i],
                                                QTC$sev[QTC$USUBJID == i])), character(1))
  })
  pid <- reactive(if (!is.null(input$pid) && input$pid %in% tm$adsl$USUBJID) input$pid else NA_character_)
  dark <- reactive(identical(input$mode, "dark"))
  pal <- reactive(tm_palette(dark()))

  output$window_note <- renderText({
    if (win()$ok) sprintf("In use: TBL within %g days of the AT elevation.", win()$value)
    else sprintf("Enter a number of days from 1 to 90; until then the default of %d days is used.", WINDOW_DEFAULT)
  })

  output$v_overall <- renderUI(guard("the overall level", sev_span(roll()$overall)))
  output$v_part <- renderUI(guard("the participant and cohort tier", sev_span(roll()$participant)))
  output$v_study <- renderUI(guard("the study tier", sev_span(roll()$study)))
  output$v_red <- renderText(guard("the RED count", roll()$red))
  output$v_amber <- renderText(guard("the AMBER count", roll()$amber))
  output$v_watch <- renderText(guard("the watch count", roll()$watch))
  output$v_n <- renderText(nrow(tm$adsl))

  # Opening a participant, from a worklist row or an eDISH point: the sidebar's select input changes
  # in the browser and pid() follows. `asked` keeps the last request (the tests read it).
  asked <- reactiveVal(NULL)
  open_participant <- function(id) {
    asked(id)
    if (!identical(id, pid())) updateSelectInput(session, "pid", selected = id)
  }

  # the worklist: the row highlighted is always the sidebar's participant (its first row), or the
  # Cohort or Study row just clicked, which the status line above the table explains
  wl_pick <- reactiveVal(NULL)
  pid_row <- reactive({
    wl <- roll()$worklist
    i <- which(wl$tier == "Participant" & wl$id %in% pid())
    if (length(i)) i[1] else integer(0)
  })
  output$worklist <- renderDT(guard("the worklist", {
    wl <- roll()$worklist
    explain_empty(nrow(wl) > 0, paste("No participant, cohort or study indicator is flagged under these settings, so",
                                      "every level is GREEN. Change an SAP setting, or set a study indicator on Study tier."))
    d <- data.frame(Tier = tm_esc(wl$tier), ID = tm_esc(wl$id), Level = sev_html(wl$sev),
                    `Screen and rule` = sprintf('<span class="tm-check">%s</span><span class="tm-rule">%s</span>',
                                                tm_esc(wl$check), tm_esc(wl$rule)),
                    Finding = tm_esc(wl$value), check.names = FALSE)
    sel <- isolate(pid_row())
    datatable(d, rownames = FALSE, escape = FALSE, class = "compact stripe hover",
              selection = list(mode = "single", target = "row", selected = if (length(sel)) sel else NULL),
              options = list(pageLength = 15, dom = "tp", ordering = FALSE, autoWidth = FALSE,
                             columnDefs = list(list(width = "6rem", targets = c(0, 2)), list(width = "7.5rem", targets = 1),
                                               list(width = "30%", targets = 3))))
  }))
  wl_proxy <- dataTableProxy("worklist")
  observeEvent(roll(), wl_pick(NULL), ignoreInit = TRUE)   # a re-ranked worklist starts on the sidebar's participant
  # a short notice at the edge of the screen for a click whose effect is out of view: a Cohort or
  # Study row (the packet shows participants only) and, on a phone, a Participant row (the packet
  # is below the console). `told` keeps the last one (the tests read it).
  told <- reactiveVal(NULL)
  tell <- function(msg, action = NULL) {
    told(msg)
    showNotification(HTML(msg), action = action, duration = 8, id = "tm-notice", type = "message")
  }
  observeEvent(input$worklist_rows_selected, {
    r <- roll()$worklist[input$worklist_rows_selected, ]
    if (!nrow(r) || is.na(r$tier[1])) return()
    if (r$tier == "Participant") {
      # the open participant's own row is selected by the table's first draw and by selectRows()
      # below; that is not a tap, so it opens nothing and says nothing
      if (identical(r$id, pid())) { wl_pick(NULL); return() }
      wl_pick(NULL); open_participant(r$id)
      if (isTRUE(session$clientData$output_worklist_width < 540))
        tell(sprintf("Opened <strong>%s</strong>: its packet is below the console.", tm_esc(r$id)),
             tags$a(href = "#", onclick = "tmShowPacket(); return false;", "Show the packet"))
    } else {
      k <- list(tier = r$tier, label = if (r$tier == "Cohort") paste("Cohort", r$id) else sprintf("%s (%s)", r$id, r$check),
                tab = if (r$tier == "Cohort") "Dose escalation" else "Study tier")
      wl_pick(k)
      tell(sprintf("<strong>%s</strong> is a %s, not a participant, so the packet still shows %s.", tm_esc(k$label),
                   if (r$tier == "Cohort") "cohort flag" else "study indicator", if (is.na(pid())) "no one" else tm_esc(pid())),
           actionLink("note_goto", paste("Open", k$tab)))
    }
  })
  observeEvent(input$note_goto, { k <- wl_pick(); removeNotification("tm-notice"); if (!is.null(k)) nav_select("tabs", k$tab) })
  observeEvent(pid(), {                                    # chosen in the sidebar or on the eDISH plot
    cur <- input$worklist_rows_selected; wl <- roll()$worklist
    on_pid <- length(cur) == 1 && cur <= nrow(wl) && wl$tier[cur] == "Participant" && identical(wl$id[cur], pid())
    if (!on_pid) { wl_pick(NULL); selectRows(wl_proxy, if (length(pid_row())) pid_row() else NULL) }
  }, ignoreInit = TRUE)
  observeEvent(input$wl_goto, { k <- wl_pick(); if (!is.null(k)) nav_select("tabs", k$tab) })
  who <- function(i) sprintf("<strong>%s</strong> %s", tm_esc(i), sev_html(pstat()[[i]]))   # "CP101-014 RED"
  output$wl_status <- renderUI(guard("the worklist status", {
    id <- pid(); k <- wl_pick()
    txt <- if (!is.null(k)) paste0(
      "<strong>", tm_esc(k$label), "</strong> is a ", if (k$tier == "Cohort") "cohort flag" else "study indicator",
      ", not a participant, so the sidebar packet still shows ", if (is.na(id)) "no one" else tm_esc(id), ". ",
      if (k$tier == "Cohort") paste0("Its DLT tally is on ", actionLink("wl_goto", k$tab), ".")
      else paste0("It is on ", actionLink("wl_goto", k$tab), ", where a what-if can change its level."))
    else paste0(
      "<strong>Click a Participant row</strong> to open that participant's packet in the sidebar. ",
      if (is.na(id)) "No participant is open." else paste0(
        "Open now: ", who(id), if (length(pid_row())) ", highlighted below." else ", which has no flag, so no row is highlighted.",
        '<span class="d-sm-none"> On a phone the packet is below the console: <button type="button" class="btn btn-link" ',
        'onclick="tmShowPacket()">show the packet</button>.</span>'))
    p(class = "tm-status", role = "status", HTML(txt))
  }))

  # client-side download: R builds the CSV text, the browser saves it (works under Shinylive)
  dl_payload <- reactiveVal(NULL)
  observeEvent(input$dl, {
    p <- list(filename = sprintf("SYNTHETIC_trialmon_worklist_CTCAEv%s.csv", settings()$ctcae),
              type = "text/csv", content = as_csv_text(cbind(data_source = SYNTHETIC_LABEL, roll()$worklist)))
    dl_payload(p)
    session$sendCustomMessage("trialmon-download", p)
  })

  output$edish <- renderPlot(guard("the eDISH plot", {
    h <- liver()
    explain_empty(nrow(h) > 0, "No participant has post-baseline liver tests, so there is nothing to plot.")
    tm_plot_edish(h, edish_limits(h), pal(), pid())
  }), bg = "transparent", res = 96,
  alt = reactive(paste("eDISH plot: peak ALT or AST against peak total bilirubin for each participant, as multiples of ULN;",
                       "ringed:", if (is.na(pid())) "none" else pid())))
  # every click on the eDISH plot says what it did: opened a participant, found the one already
  # open, or found no point near enough
  edish_last <- reactiveVal(NULL)
  observeEvent(input$edish_click, {
    np <- nearPoints(liver(), input$edish_click, xvar = "peak_at", yvar = "peak_tbl", maxpoints = 1, threshold = 14)
    id <- if (nrow(np)) np$USUBJID[1] else NA_character_
    n <- if (is.null(edish_last())) 1 else edish_last()$n + 1
    edish_last(list(id = id, before = pid(), n = n))
    if (!is.na(id)) open_participant(id)
  })
  output$edish_msg <- renderUI(guard("the eDISH note", {
    h <- liver(); id <- pid(); e <- edish_last()
    inbox <- h$USUBJID[grepl("^Upper right", h$quadrant)]
    box <- if (!length(inbox)) "No point sits in the shaded box."
      else sprintf("%s in the shaded box: %s.", if (length(inbox) == 1) "One point sits" else sprintf("%d points sit", length(inbox)),
                   paste(vapply(inbox, who, ""), collapse = ", "))
    if (length(inbox) > 1) box <- sub(", (?=[^,]*\\.$)", " and ", box, perl = TRUE)
    ringed <- if (is.na(id)) "No participant is open in the sidebar. " else paste0("Ringed: ", who(id), ", the participant in the sidebar. ")
    expect <- if (is.null(e)) NULL else if (is.na(e$id)) e$before else e$id
    txt <- if (is.null(e) || !identical(expect, id)) paste0("<strong>Click a point</strong> to open that participant. ", ringed, box)
      else if (is.na(e$id)) paste0("<strong>No point within reach of that click.</strong> Click on a point. ", ringed)
      else if (identical(e$id, e$before)) paste0(who(id), " is already the participant in the sidebar (ringed). ",
                                                 "Click another point to compare. ", box)
      else paste0("Now showing ", who(id), ": ringed here, with its liver tests by study day and its packet in the sidebar.")
    p(class = "tm-plot-note", role = "status", HTML(txt))
  }))
  output$traj <- renderPlot(guard("the liver trajectory", {
    explain_empty(!is.na(pid()), "Pick a participant in the sidebar to see their liver tests by study day.")
    d <- liver_trajectory(tm, pid())
    explain_empty(nrow(d) > 0, sprintf("%s has no ALT, AST, ALP or TBL results in this data cut.", pid()))
    tm_plot_traj(d, pid(), pal())
  }), bg = "transparent", res = 96,
  alt = reactive(paste("ALT, AST, ALP and total bilirubin by study day, as multiples of ULN, for", pid())))
  liver_view <- reactive({                                 # the liver table's rows (the tests read them)
    h <- liver()
    h <- h[h$peak_at >= 3 | h$peak_tbl > 2 | h$sev != "GREEN", ]
    h <- h[order(-sev_rank(h$sev), h$USUBJID), ]
    data.frame(Participant = h$USUBJID, Level = sev_html(h$sev), `Peak AT` = tm_f1(h$peak_at),
               `Peak TBL` = tm_f1(h$peak_tbl), `AT >= 3x (day)` = h$at3_day,
               `ALP then` = tm_f1(h$alp_at3), `R ratio` = tm_f1(h$r_at3), Pattern = h$pattern,
               `TBL > 2x (day)` = h$tbl_day, `Potential Hy's Law` = ifelse(h$hys, "Yes", "No"),
               Quadrant = h$quadrant, `First repeat (days later)` = h$repeat_gap, check.names = FALSE)
  })
  output$liver_tbl <- renderDT(guard("the liver table", {
    d <- liver_view()
    explain_empty(nrow(d) > 0, paste("No participant reached ALT or AST >= 3x ULN or TBL > 2x ULN, and none has a",
                                     "hepatic flag, so this table is empty. The eDISH plot above still shows everyone."))
    datatable(d, rownames = FALSE, escape = -2, selection = "none", class = "compact stripe",
              caption = "Participants with a liver finding: peaks as x ULN; days are study days.",
              options = list(dom = "t", scrollX = TRUE, ordering = FALSE,
                             columnDefs = list(list(className = "dt-right", targets = c(2, 3, 5, 6)))))
  }))

  output$grid_tbl <- renderDT(guard("the convention grid", {
    g <- GRID0; chk <- GRID_CHECK
    asserted <- chk$ASSERTED[match(g$USUBJID, chk$USUBJID)]
    agree <- chk$AGREE[match(g$USUBJID, chk$USUBJID)]
    d <- data.frame(Participant = g$USUBJID, Source = g$SOURCE, g[HYS_GRID$code], `Peak vs peak` = g$REF,
                    `Cells flagged` = sprintf("%d of 12", g$N_FLAGGED), Verdict = g$VERDICT,
                    `Narrative states` = ifelse(is.na(asserted), "", asserted),
                    `Agrees` = ifelse(is.na(agree), "", ifelse(agree, "yes", "NO")),
                    `ALP at the AT draw (x ULN)` = tm_f1(g$ALP_AT3), check.names = FALSE)
    leaf <- c("AT + ALP", "AT", "ALT + ALP", "ALT")
    head2 <- tags$table(class = "display", tags$thead(
      tags$tr(tags$th(rowspan = 2, "Participant"), tags$th(rowspan = 2, "Source"),
        lapply(c(14, 30, 60), function(w) tags$th(colspan = 4, class = "dt-center", sprintf("Window %d days", w))),
        tags$th(rowspan = 2, class = "tm-ref", "Peak vs peak (screening display, not a grid cell)"),
        lapply(c("Cells flagged", "Verdict", "Narrative states", "Agrees", "ALP at the AT draw (x ULN)"),
               function(x) tags$th(rowspan = 2, x))),
      tags$tr(lapply(rep(leaf, 3), tags$th))))
    refcol <- which(names(d) == "Peak vs peak") - 1
    dt <- datatable(d, container = head2, rownames = FALSE, selection = "none", class = "compact stripe",
              options = list(dom = "t", ordering = FALSE, pageLength = 50, autoWidth = FALSE,
                             columnDefs = list(list(className = "tm-ref", targets = refcol),
                                               list(className = "dt-center", targets = seq(2, refcol)),
                                               list(className = "dt-right", targets = ncol(d) - 1))))
    formatStyle(dt, c(HYS_GRID$code, "Peak vs peak"), fontWeight = styleEqual(1, "700"))
  }), server = FALSE)                                   # ten rows: sent whole to the browser
  output$grid_note <- renderUI({
    s <- settings(); w <- s$hys_window
    col <- if (w %in% c(14, 30, 60)) sprintf("the column \"Window %g days, %s\"", w,
                                             if (s$alp_convention) "AT + ALP" else "AT")
           else sprintf("no grid column (the grid uses 14, 30 and 60 days; the sidebar says %g)", w)
    p(class = "foot mt-2", paste0(
      "1 = flagged as potential Hy's Law in that cell. AT = ALT or AST; ALT = ALT only; + ALP = ALP < 2x ULN ",
      "required at the aminotransferase draw. The sidebar's settings match ", col, ". ",
      "Verdicts: Robust (12 of 12 cells); Convention-dependent (names each factor for which two cells that differ ",
      "only in that factor disagree); Not flagged; Peak-only artifact (0 of 12, but in the upper-right eDISH ",
      "quadrant on peak values). The peak-versus-peak column is the eDISH screen and is not part of the verdict. ",
      "CP101-901 to -907 are planted known-answer cases from data/labs_long.csv: they are not among the 18 dosed ",
      "participants and enter no other tab. The statuses the narratives imply are in data/narrative_flags.csv; ",
      "the tests fail if any disagrees with the computed verdict."))
  })

  output$qtc_cat <- renderTable(guard("the QTcF categories", {
    q <- QTC; q$COHORT <- tm$adsl$COHORT[match(q$USUBJID, tm$adsl$USUBJID)]
    cats <- c(`QTcF > 450 ms` = "gt450", `QTcF > 480 ms` = "gt480", `QTcF > 500 ms` = "gt500",
              `Change > 30 ms` = "chg30", `Change > 60 ms` = "chg60", `Baseline > 450 ms` = "base450")
    grp <- c(split(q, q$COHORT), list(Total = q))
    out <- data.frame(Category = names(cats), check.names = FALSE)
    for (g in names(grp)) out[[sprintf("%s (N=%d)", g, nrow(grp[[g]]))]] <- vapply(cats, function(cc) {
      n <- sum(grp[[g]][[cc]]); sprintf("%d (%.0f%%)", n, 100 * n / nrow(grp[[g]]))
    }, character(1))
    out
  }), striped = TRUE, hover = TRUE, spacing = "s")
  output$qtc_tbl <- renderDT(guard("the QTcF listing", {
    q <- QTC[QTC$sev != "GREEN", ]
    explain_empty(nrow(q) > 0, "No participant's QTcF went above 450 ms or rose more than 30 ms from baseline.")
    q <- q[order(-sev_rank(q$sev), q$USUBJID), ]
    datatable(data.frame(Participant = q$USUBJID, Level = sev_html(q$sev), `Baseline (ms)` = q$base,
                         `Max QTcF (ms)` = q$max_qtcf, `On day` = q$max_day, `Max change (ms)` = q$max_chg,
                         check.names = FALSE),
              rownames = FALSE, escape = -2, selection = "none", class = "compact stripe",
              caption = "Participants above a QTcF category, worst first.",
              options = list(dom = "t", ordering = FALSE, scrollX = TRUE))
  }))

  output$shift <- renderTable(guard("the lab shift table", {
    s <- lab_shift(tm$adlb, settings()$ctcae)
    data.frame(Test = s$TERM, `Baseline grade` = s$BGRADE, N = s$N, `Worst 0` = s$G0, `1` = s$G1, `2` = s$G2,
               `3` = s$G3, `4` = s$G4, check.names = FALSE)
  }), striped = TRUE, hover = TRUE, spacing = "s", digits = 0)
  output$shift_note <- renderUI(p(class = "foot", sprintf(paste0(
    "Shift from baseline grade (rows) to worst post-baseline grade (columns 0 to 4), participants. Lab grades: NCI CTCAE v%s. ",
    "Creatinine is graded on x ULN and fold over baseline (v5.0: the worse of the two; v6.0: fold over baseline ",
    "only when the baseline is below the LLN), never on mg/dL alone."), settings()$ctcae)))

  output$ae_tbl <- renderTable(guard("the adverse event table", {
    a <- AE; N <- attr(a, "N")
    explain_empty(nrow(a) > 1, "No treatment-emergent adverse events are recorded in this data cut.")
    lab <- ifelse(a$PT == "", sprintf('<span class="tm-soc">%s</span>', tm_esc(a$SOC)),
                  sprintf('<span class="tm-pt">%s</span>', tm_esc(a$PT)))
    out <- data.frame(`SOC / Preferred term` = lab, check.names = FALSE)
    for (g in names(N)) out[[sprintf("%s (N=%d)", g, N[[g]])]] <- sprintf("%d (%.0f%%)", a[[g]], 100 * a[[g]] / N[[g]])
    out
  }), striped = TRUE, hover = TRUE, spacing = "s", sanitize.text.function = function(x) x)
  output$ae_note <- renderUI(p(class = "foot", sprintf(paste0(
    "Treatment-emergent AEs, participants counted once per row; N = dosed participants. Coded with MedDRA v%s ",
    "(primary SOC). AE grades as recorded by the investigator (NCI CTCAE v%s); the lab-grade setting ",
    "(now v%s) re-derives lab grades only and does not change a recorded AE grade."),
    settings()$meddra, settings()$ae_ctcae, settings()$ctcae)))

  output$dlt_tbl <- renderUI(guard("the DLT table", {
    d <- DLT
    lvl <- ifelse(d$N > 0, sev_html(d$sev), "")
    head <- sprintf('%s<span class="tm-stack-only">, %g mg %s</span>', tm_esc(d$COHORT), d$DOSEMG, lvl)
    tm_stack_table(data.frame(Cohort = head, `Dose (mg)` = d$DOSEMG, Status = d$STATUS, Dosed = d$N,
                              `DLT-evaluable` = d$EVALUABLE, `Confirmed DLTs` = d$DLT, Pending = d$PENDING, Level = lvl,
                              `Rule reference (3+3, illustrative)` = d$text, check.names = FALSE),
                   html = c("Cohort", "Level"), head = "Cohort", wide = c("Status", "Rule reference (3+3, illustrative)"),
                   hide = c("Dose (mg)", "Level"), cols = 2,
                   labels = c(`DLT-evaluable` = "Evaluable", `Confirmed DLTs` = "Confirmed"))
  }))
  output$ladder <- renderPlot(guard("the dose ladder", tm_plot_ladder(DLT, pal())), bg = "transparent", res = 96,
                              alt = "Dose ladder: one bar per cohort at its dose, colored by its level under the illustrative 3+3 rule")

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
  study_view <- reactive({                                 # the study table's rows (the tests read them)
    s <- study()
    lvl <- paste0(sev_html(s$LEVEL), ifelse(s$LEVEL != STUDY0$LEVEL,
                  sprintf('<span class="tm-whatif" title="feed: %s">what-if</span>', STUDY0$LEVEL), ""))
    data.frame(ID = s$ID, Indicator = s$INDICATOR, Value = s$VALUE, Unit = s$UNIT, Level = lvl,
               Rule = s$RULE, Detail = s$DETAIL, Source = s$SOURCE, check.names = FALSE)
  })
  output$study_tbl <- renderDT(guard("the study tier", {
    datatable(study_view(), rownames = FALSE, escape = -5, selection = "none", class = "compact stripe",
              options = list(dom = "t", scrollX = TRUE, pageLength = 50, ordering = FALSE))
  }))

  output$packet <- renderUI(guard("the participant packet", {
    id <- pid()
    if (is.na(id)) return(empty_state("Pick a participant above to see their packet: disposition, DLT, liver, QTcF, lab grades and AEs."))
    s <- tm$adsl[tm$adsl$USUBJID == id, ]
    h <- liver()[liver()$USUBJID == id, ]; q <- QTC[QTC$USUBJID == id, ]
    g <- lab_grades(tm$adlb[tm$adlb$USUBJID == id, ], settings()$ctcae); g <- g[!is.na(g$WGRADE) & g$WGRADE >= 2, ]
    ae <- tm$adae[tm$adae$USUBJID == id, ]; nt <- tm$notes$NOTE[tm$notes$USUBJID == id]
    hep <- if (!nrow(h)) "no post-baseline liver tests"
      else if (h$hys) sprintf("Potential Hy's Law: AT %.1fx ULN on Day %d, TBL %.1fx ULN on Day %d", h$at3_value, h$at3_day, h$tbl_at_hit, h$tbl_day)
      else if (!is.na(h$at3x_day)) sprintf("AT %.1fx ULN on Day %d: confirm (repeat within 48 to 72 h); TBL peak %.1fx", h$at3x_value, h$at3x_day, h$peak_tbl)
      else sprintf("Peak AT %.1fx, TBL %.1fx ULN: no hepatic flag", h$peak_at, h$peak_tbl)
    div(class = "packet small",
      div(class = "packet-head", sprintf("%s: %s, %g mg ", id, s$COHORT, s$DOSEMG), sev_span(pstat()[[id]])),
      tags$dl(
        tags$dt("Disposition"), tags$dd(sprintf("Treatment %s%s; study %s", tolower(s$EOTSTT),
          if (!is.na(s$DCTREAS) && nzchar(s$DCTREAS)) paste0(" (", tolower(s$DCTREAS), ")") else "", tolower(s$EOSSTT))),
        tags$dt("DLT"), tags$dd(if (s$DLTADJ == "Pending") paste("Pending adjudication:", s$DLTDESC)
                                else if (s$DLTFL == "Y") s$DLTDESC else "No DLT"),
        tags$dt("Liver"), tags$dd(hep, if (nrow(h) && !is.na(h$r_at3)) sprintf(" (R %.1f, %s)", h$r_at3, h$pattern)),
        tags$dt("QTcF"), tags$dd(if (nrow(q)) list(sprintf("max %d ms (baseline %d, change %d) ", q$max_qtcf, q$base, q$max_chg), sev_span(q$sev))
                                 else "no post-baseline ECG"),
        tags$dt(sprintf("Lab grades 2 or higher (CTCAE v%s)", settings()$ctcae)),
        tags$dd(if (nrow(g)) paste(sprintf("%s G%d", g$TERM, g$WGRADE), collapse = "; ") else "none"),
        tags$dt(sprintf("Adverse events (%d)", nrow(ae))),
        tags$dd(if (nrow(ae)) paste(sprintf("%s G%d%s", ae$AEDECOD, ae$AETOXGR, ifelse(ae$AESER == "Y", " (serious)", "")),
                                    collapse = "; ") else "none")),
      if (length(nt)) p(class = "note", "Synthetic teaching note: ", nt)
    )
  }))
}

shinyApp(ui, server)
