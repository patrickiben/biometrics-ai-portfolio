BW_TM_FILES <- c("adsl.csv", "adlb.csv", "adeg.csv", "adae.csv", "cohorts.csv", "study_kri.csv", "notes.csv", "labs_long.csv", "narrative_flags.csv")
BW_TEMPLATES <- setNames(lapply(BW_TM_FILES, function(file) list(data = read.csv(file.path("data", file), check.names = FALSE, stringsAsFactors = FALSE), required = !file %in% c("notes.csv", "labs_long.csv", "narrative_flags.csv"))), BW_TM_FILES)
BW_TM_EXAMPLE_SETTINGS <- list(schedule = trialmon_schedule(), sae_limits = c(10, 20), missing_limits = c(2, 5), ctcae = "6.0", hys_window = 30, alp_convention = FALSE, meddra = "29.1", ae_ctcae = "6.0")
bw_tm_settings <- function(settings) {
  bw_need(is.list(settings), "Enter the study schedule, thresholds and coding/assay conventions before loading study data.")
  schedule <- settings$schedule
  if (is.character(schedule) && length(schedule) == 1L) {
    lines <- trimws(strsplit(schedule, "\n", fixed = TRUE)[[1]]); lines <- lines[nzchar(lines)]
    parts <- strsplit(lines, "=", fixed = TRUE)
    bw_need(length(parts) > 0 && all(lengths(parts) == 2L), "Enter each planned lab visit as Visit label = study day, one per line.")
    schedule <- setNames(suppressWarnings(as.numeric(vapply(parts, function(x) trimws(x[[2]]), ""))), vapply(parts, function(x) trimws(x[[1]]), ""))
  } else if (is.list(schedule)) schedule <- unlist(schedule)
  bw_need(is.numeric(schedule) && length(schedule) > 0 && all(is.finite(schedule)) && !is.null(names(schedule)) && bw_nonblank(names(schedule)) && !anyDuplicated(names(schedule)), "Planned visits require unique labels and finite study days.")
  settings$schedule <- schedule
  for (key in c("sae_limits", "missing_limits")) {
    value <- unlist(settings[[key]])
    bw_need(is.numeric(value) && length(value) == 2L && all(is.finite(value)) && all(value >= 0 & value <= 100) && value[1] < value[2], "Operational percentages require 0 <= amber < red <= 100.")
    settings[[key]] <- value
  }
  bw_need(settings$ctcae %in% c("5.0", "6.0") && settings$ae_ctcae %in% c("5.0", "6.0"), "Choose the prespecified lab and recorded-AE CTCAE versions.")
  bw_need(is.numeric(settings$hys_window) && length(settings$hys_window) == 1L && is.finite(settings$hys_window) && settings$hys_window >= 1 && settings$hys_window <= 90, "The Hy's Law screening window must be between 1 and 90 days.")
  bw_need(is.logical(settings$alp_convention) && length(settings$alp_convention) == 1L && !is.na(settings$alp_convention), "Confirm the ALP convention.")
  bw_need(is.character(settings$meddra) && length(settings$meddra) == 1L && nzchar(trimws(settings$meddra)) && nchar(settings$meddra) <= 80, "Enter the MedDRA version used for the data.")
  settings
}
bw_tm_settings_input <- function(input) list(schedule = input$bw_schedule, sae_limits = c(input$bw_sae_amber, input$bw_sae_red), missing_limits = c(input$bw_missing_amber, input$bw_missing_red), ctcae = input$bw_lab_ctcae, hys_window = input$bw_window, alp_convention = isTRUE(input$bw_alp), meddra = input$bw_meddra, ae_ctcae = input$bw_ae_ctcae)
bw_tm_controls <- function() div(class = "bw-feed", h3("Study-specific screening conventions"),
  p("SAFFL=Y defines the included dosed safety population; excluded participant rows remain in the saved source inputs. This console requires complete baseline/post-baseline measurements for its supported screens; missing measurements are not interpreted as normal. The implemented lab screens use study day > 1 as post-baseline; baseline draws must be flagged Y on or before day 1. ECG post-baseline uses non-baseline draws on day 1 or later. Use these study-day conventions only when they match your analysis specification."),
  textAreaInput("bw_schedule", "Planned safety-lab visits (Visit label = study day, one per line)", value = "", placeholder = "Baseline = 1\nFollow-up = 15", rows = 5),
  div(class = "bw-map-grid",
    numericInput("bw_sae_amber", "SAE percentage: amber above", value = NA, min = 0, max = 100), numericInput("bw_sae_red", "SAE percentage: red above", value = NA, min = 0, max = 100),
    numericInput("bw_missing_amber", "Missing lab visits: amber above (%)", value = NA, min = 0, max = 100), numericInput("bw_missing_red", "Missing lab visits: red above (%)", value = NA, min = 0, max = 100),
    selectInput("bw_lab_ctcae", "Lab grading version", c("Choose version" = "", "CTCAE 6.0" = "6.0", "CTCAE 5.0" = "5.0"), selectize = FALSE),
    selectInput("bw_ae_ctcae", "Recorded AE grading version", c("Choose version" = "", "CTCAE 6.0" = "6.0", "CTCAE 5.0" = "5.0"), selectize = FALSE),
    numericInput("bw_window", "Potential Hy's Law window (days)", value = NA, min = 1, max = 90), textInput("bw_meddra", "MedDRA version used for coding", value = "")),
  checkboxInput("bw_alp", "Require ALP < 2 × ULN at the qualifying draw (SAP convention)", FALSE),
  actionButton("bw_settings_apply", "Revalidate these settings for the loaded data", class = "btn-outline-secondary"))
bw_tm_validate <- function(frames, settings = NULL) {
  cfg <- bw_tm_settings(settings)
  s <- frames[["adsl.csv"]]; bw_key(s, "USUBJID", "Participants")
  bw_need(length(unique(s$STUDYID)) == 1 && bw_nonblank(s$STUDYID), "Load one study at a time and supply its study identifier.")
  for (field in c("SAFFL", "DLTEVLFL")) bw_need(all(s[[field]] %in% c("Y", "N")), paste(field, "requires Y or N."))
  bw_need(all(s$DLTFL %in% c("Y", "N", "")), "DLTFL requires Y, N or blank for not evaluable.")
  bw_need(all(is.finite(s$LSTVISDY)) && all(is.finite(s$DOSEMG) & s$DOSEMG >= 0), "Follow-up days and doses must be finite, with nonnegative dose.")
  bw_need(all(s$DLTADJ %in% c("Final", "Pending")), "DLT adjudication requires Final or Pending; unknown states cannot be treated as resolved.")
  bw_need(all(s$DLTFL != "Y" | s$DLTEVLFL == "Y"), "A confirmed DLT requires an evaluable participant.")
  for (file in c("adlb.csv", "adeg.csv", "adae.csv", "notes.csv")) {
    d <- frames[[file]]; bw_need(all(d$USUBJID %in% s$USUBJID), paste(file, "contains participants absent from ADSL."))
    if ("STUDYID" %in% names(d)) bw_need(all(d$STUDYID == s$STUDYID[[1]]), paste(file, "contains a different study identifier."))
  }
  cohort <- frames[["cohorts.csv"]]; bw_key(cohort, "COHORT", "Cohorts")
  bw_need(all(s$COHORT %in% cohort$COHORT), "ADSL references a cohort absent from cohorts.csv.")
  bw_need(all(is.finite(cohort$DOSEMG) & cohort$DOSEMG >= 0) && all(is.finite(cohort$DLTWIN) & cohort$DLTWIN > 0), "Cohort dose and DLT window must be valid numbers.")
  bw_need(all(s$DOSEMG == cohort$DOSEMG[match(s$COHORT, cohort$COHORT)]), "Participant and cohort doses disagree.")
  tm <- setNames(frames[seq_len(7)], c("adsl", "adlb", "adeg", "adae", "cohorts", "kri", "notes"))
  tm$adsl <- tm$adsl[tm$adsl$SAFFL == "Y", , drop = FALSE]; bw_need(nrow(tm$adsl) > 0, "No SAFFL=Y participants are available for safety review.")
  for (name in c("adlb", "adeg", "adae", "notes")) tm[[name]] <- tm[[name]][tm[[name]]$USUBJID %in% tm$adsl$USUBJID, , drop = FALSE]
  labs <- tm$adlb; bw_key(labs, c("USUBJID", "PARAMCD", "ADY", "AVISIT"), "Labs")
  expected_units <- c(ALP = "U/L", ALT = "U/L", AST = "U/L", BILI = "mg/dL", CREAT = "mg/dL", HGB = "g/dL", NEUT = "10^9/L", PLAT = "10^9/L")
  bw_need(all(labs$PARAMCD %in% names(expected_units)), "ADLB contains unsupported lab parameters; this console supports ALT, AST, ALP, BILI, CREAT, HGB, NEUT and PLAT.")
  bw_need(all(labs$AVALU == expected_units[labs$PARAMCD]), "Lab units do not match the documented grading units; convert units before importing.")
  for (field in c("ADY", "AVAL", "ANRLO", "ANRHI", "BASE")) bw_need(all(is.finite(labs[[field]])), paste("Labs require complete finite", field, "values for these screens."))
  bw_need(all(labs$AVAL >= 0 & labs$BASE >= 0 & labs$ANRLO >= 0 & labs$ANRHI > 0 & labs$ANRHI >= labs$ANRLO), "Lab values and reference ranges are invalid.")
  bw_need(all(labs$ABLFL %in% c("Y", "N", "")), "Lab baseline flags require Y or N/blank.")
  bw_need(all(labs$ADY[labs$ABLFL == "Y"] <= 1), "Baseline labs must occur on or before study day 1 for the implemented screening convention.")
  keys <- expand.grid(USUBJID = tm$adsl$USUBJID, PARAMCD = names(expected_units), stringsAsFactors = FALSE)
  for (i in seq_len(nrow(keys))) {
    rows <- labs[labs$USUBJID == keys$USUBJID[i] & labs$PARAMCD == keys$PARAMCD[i], ]
    bw_need(sum(rows$ABLFL == "Y") == 1L && any(rows$ADY > 1), "Every included participant/parameter needs one baseline and at least one post-baseline measurement; missingness cannot be labeled normal.")
  }
  for (id in tm$adsl$USUBJID) {
    rows <- labs[labs$USUBJID == id & labs$PARAMCD %in% c("ALT", "AST", "ALP", "BILI") & labs$ADY > 1, ]
    counts <- table(interaction(rows$ADY, rows$AVISIT, drop = TRUE))
    bw_need(all(counts == 4L), "Each post-baseline liver draw needs ALT, AST, ALP and BILI; incomplete panels require separate review.")
  }
  ecg <- tm$adeg; bw_key(ecg, c("USUBJID", "ADY", "AVISIT", "ATPT"), "ECGs")
  bw_need(all(ecg$PARAMCD == "QTCF") && all(is.finite(ecg$ADY) & is.finite(ecg$AVAL) & is.finite(ecg$BASE) & ecg$AVAL > 0 & ecg$BASE > 0), "ECG inputs require QTcF in milliseconds and valid baseline/current values.")
  bw_need(all(ecg$ABLFL %in% c("Y", "N", "")), "ECG baseline flags require Y or N/blank.")
  post <- ecg[ecg$ABLFL != "Y" & ecg$ADY >= 1, ]
  bw_need(all(tm$adsl$USUBJID %in% post$USUBJID) && all(is.finite(post$CHG)) && all(abs(post$CHG - (post$AVAL - post$BASE)) < 1e-6), "Every included participant requires post-baseline QTcF with change equal to current minus baseline.")
  ae <- tm$adae
  for (field in c("AESER", "TRTEMFL")) bw_need(all(ae[[field]] %in% c("Y", "N")), paste("AE", field, "requires Y or N."))
  bw_need(all(is.finite(ae$AETOXGR) & ae$AETOXGR >= 0 & ae$AETOXGR <= 5 & ae$AETOXGR == floor(ae$AETOXGR)), "AE grades must be recorded integers from 0 through 5.")
  k <- tm$kri; bw_key(k, "ID", "Study indicators")
  bw_need(!any(k$ID %in% c("QTL-SAE", "MISS-LAB")), "The study indicator IDs QTL-SAE and MISS-LAB are reserved for derived indicators.")
  bw_need(all(is.finite(k$VALUE) & is.finite(k$AMBER) & is.finite(k$RED)) && all(k$WORSE %in% c("higher", "lower")), "Study indicators require finite values and higher/lower direction.")
  bw_need(all(ifelse(k$WORSE == "higher", k$AMBER < k$RED, k$AMBER > k$RED)), "Study indicator thresholds disagree with their direction.")
  hl <- list(labs_long = frames[["labs_long.csv"]], flags = frames[["narrative_flags.csv"]])
  if (nrow(hl$labs_long)) { bw_key(hl$labs_long, c("USUBJID", "PARAMCD", "ADY", "AVISIT"), "Comparison labs"); bw_need(!any(hl$labs_long$USUBJID %in% tm$adsl$USUBJID), "Comparison-case identifiers must be distinct from study participants.") }
  if (nrow(hl$labs_long)) {
    d <- hl$labs_long
    bw_need(all(d$PARAMCD %in% c("ALT", "AST", "ALP", "BILI")) && all(d$AVALU == expected_units[d$PARAMCD]), "Comparison liver labs require supported parameters and units.")
    bw_need(all(is.finite(d$ADY) & is.finite(d$AVAL) & is.finite(d$ANRHI) & d$AVAL >= 0 & d$ANRHI > 0), "Comparison liver labs require finite nonnegative results and positive ULNs.")
    post_comparison <- d[d$ADY > 1, ]
    bw_need(all(unique(d$USUBJID) %in% post_comparison$USUBJID), "Each comparison case requires post-baseline liver draws.")
    bw_need(all(table(interaction(post_comparison$USUBJID, post_comparison$ADY, post_comparison$AVISIT, drop = TRUE)) == 4L), "Comparison liver draws require complete four-parameter panels.")
  }
  if (nrow(hl$flags)) bw_key(hl$flags, "USUBJID", "Narrative assertions")
  bw_need(all(hl$flags$USUBJID %in% c(tm$adsl$USUBJID, hl$labs_long$USUBJID)), "Narrative assertions reference an unknown participant or comparison case.")
  st <- study_signals(tm, cfg$schedule, cfg$sae_limits, cfg$missing_limits)
  if (!is.null(cfg$study_levels)) {
    levels <- unlist(cfg$study_levels)
    bw_need(setequal(names(levels), st$ID) && all(levels %in% c("GREEN", "AMBER", "RED")), "Saved study what-if levels are invalid.")
  }
  trialmon_rollup(tm, trialmon_settings(cfg$ctcae, cfg$hys_window, cfg$alp_convention, cfg$meddra, cfg$ae_ctcae), st)
  list(tm = tm, hl = hl, inputs = frames, config = cfg, population_audit = data.frame(USUBJID = s$USUBJID, included = s$SAFFL == "Y", reason = ifelse(s$SAFFL == "Y", "SAFFL=Y", "Outside safety population")))
}
