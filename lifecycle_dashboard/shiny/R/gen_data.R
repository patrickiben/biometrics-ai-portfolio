# ---------------------------------------------------------------------------
# gen_data.R - deterministic synthetic study portfolio for the Lifecycle Monitor.
# No PHI, no participant-level data. Writes the CSVs the app reads, so on a real
# study you replace them with a read-only CTMS / EDC export (same columns).
# Run:  Rscript R/gen_data.R   (writes ../data/*.csv relative to shiny/)
#
# The portfolio is internally consistent, so no panel contradicts another:
# - each study's query trend ends on its open-query count (the snapshot week) and
#   follows its phase: rising in Startup and Conduct, burning down in DB Lock and
#   Reporting;
# - the TLFs milestone is done only when every planned TLF is finalized, and the CSR
#   only after the TLFs; a past-due milestone that is not done is "risk" (overdue);
# - the deliverables register fills in phase order: Startup and Conduct follow the
#   study's progress, Analysis follows TLF programming and Reporting follows TLF
#   finalization;
# - days_to_dbl is the DB lock milestone's date minus the snapshot date.
# The random draws are taken in the same order as in earlier versions, so the
# studies' inputs (and so the risk scores) stay the same.
# ---------------------------------------------------------------------------
gen_portfolio <- function(out_dir = "data", today = as.Date("2026-06-21"), seed = 20260621L) {
  set.seed(seed)
  designs <- c("Parallel SAD", "Parallel MAD", "2x2 Crossover BE",
               "Fixed-sequence DDI", "Food-effect", "Single-ascending FIH")
  ms_keys <- c("Protocol", "SAP", "FPFV", "LPLV", "DBL", "TLFs", "CSR")
  owners  <- c("A. Rivera", "J. Okafor", "M. Chen", "S. Patel", "L. Dubois", "K. Novak")
  offs    <- c(0, 18, 35, 150, 185, 215, 250)
  rf <- function(a, b) a + runif(1) * (b - a)
  ri <- function(a, b) as.integer(floor(a + runif(1) * (b - a + 1)))
  status_for <- function(date, done)
    if (done) "done" else if (date < today) "risk" else if (date < today + 14) "wip" else "todo"

  assigned <- c("Startup","Startup","Conduct","Conduct","DB Lock","DB Lock","Reporting","Reporting")
  studies <- list(); milestones <- list(); progress <- list(); steps <- list(); noise <- list()

  for (i in 0:7) {
    id <- paste0("CP-", 101 + i)
    phase <- assigned[i + 1]
    prog <- switch(phase, "Startup" = rf(.05,.25), "Conduct" = rf(.3,.6),
                   "DB Lock" = rf(.6,.8), "Reporting" = rf(.8,.98))
    design <- designs[(i %% length(designs)) + 1]
    target <- sample(c(24,32,40,48,60,16), 1)
    enrolled <- if (phase=="Startup") ri(0, round(target*.4))
                else if (phase=="Conduct") ri(round(target*.5), target) else target
    base <- today - (round(prog*240) + 30)

    ms_status <- character(7); ms_date <- as.Date(rep(NA, 7))
    for (j in 1:7) {
      d <- base + offs[j]; ms_date[j] <- d
      done <- d < today && runif(1) < .92
      s <- if (done) "done" else if (d < today + 14 && d >= today) "wip" else if (d < today) "risk" else "todo"
      if (prog > 0.9 && j < 6) s <- "done"
      ms_status[j] <- s
    }
    days_to_dbl <- as.integer(ms_date[5] - today)

    openQ <- switch(phase, "Startup" = ri(0,6), "Conduct" = ri(25,120),
                    "DB Lock" = ri(10,48), "Reporting" = ri(0,8))
    invisible(ri(0, 40))   # an earlier version's trend offset: still drawn, so later draws do not move
    steps[[id]] <- if (phase == "Reporting") rep(NA_real_, 8) else vapply(1:8, function(t) rf(-8, 10), numeric(1))
    clean_pct <- min(.999, prog*0.7 + rf(.2,.32))
    sdv_pct   <- min(.999, prog*0.6 + rf(.2,.35))

    planned <- sample(c(90,120,150,180,72), 1)
    rep_frac <- switch(phase, "Reporting" = rf(.6,1), "DB Lock" = rf(.15,.4),
                       "Conduct" = rf(0,.15), "Startup" = rf(0,.05))
    programmed <- round(planned * min(1, rep_frac + rf(.05,.2)))
    qcd <- round(programmed * rf(.55,.85)); finalized <- round(qcd * rf(.55,.95))
    dbl_prog_pct <- ri(40,85); discrep <- ri(0,18)
    noise[[id]] <- vapply(1:4, function(k) rf(-.05, .05), numeric(1))   # deliverables register
    progress[[id]] <- prog

    for (j in 1:7) milestones[[length(milestones)+1]] <- data.frame(
      study_id=id, milestone=ms_keys[j], date=as.character(ms_date[j]), status=ms_status[j], stringsAsFactors=FALSE)

    studies[[length(studies)+1]] <- data.frame(
      id=id, name=paste0(design, " study"), phase=phase, design=design, owner=sample(owners,1),
      target=target, enrolled=enrolled, sites=ri(1,4), days_to_dbl=days_to_dbl,
      open_queries=openQ, clean_pct=round(clean_pct,3), sdv_pct=round(sdv_pct,3),
      tlf_planned=planned, tlf_programmed=programmed, tlf_qcd=qcd, tlf_finalized=finalized,
      dbl_prog_pct=dbl_prog_pct, discrep=discrep, stringsAsFactors=FALSE)
  }
  studies <- do.call(rbind, studies)
  ms_all <- do.call(rbind, milestones)

  # force CP-108 to be clearly AT RISK so the red state + signals are exercised: in Reporting,
  # TLF production far behind, double programming low
  k <- studies$id == "CP-108"
  studies$phase[k] <- "Reporting"
  studies$tlf_programmed[k] <- round(studies$tlf_planned[k]*0.45)
  studies$tlf_qcd[k] <- round(studies$tlf_planned[k]*0.22)
  studies$tlf_finalized[k] <- round(studies$tlf_planned[k]*0.10)
  studies$dbl_prog_pct[k] <- 42L; studies$discrep[k] <- 16L
  studies$open_queries[k] <- 7L; studies$clean_pct[k] <- 0.91; studies$sdv_pct[k] <- 0.86

  # TLFs are done only when every planned TLF is finalized; the CSR only after the TLFs
  for (r in seq_len(nrow(studies))) {
    s <- studies[r, ]; m <- ms_all$study_id == s$id
    tlf <- m & ms_all$milestone == "TLFs"; csr <- m & ms_all$milestone == "CSR"
    tlf_done <- s$tlf_finalized >= s$tlf_planned
    ms_all$status[tlf] <- status_for(as.Date(ms_all$date[tlf]), tlf_done)
    ms_all$status[csr] <- status_for(as.Date(ms_all$date[csr]), tlf_done && ms_all$status[csr] == "done")
    studies$days_to_dbl[r] <- as.integer(as.Date(ms_all$date[m & ms_all$milestone == "DBL"]) - today)
  }

  # query trend: 8 weeks ending on the snapshot week, whose value is the study's open queries
  qtrends <- lapply(seq_len(nrow(studies)), function(r) {
    s <- studies[r, ]; st <- steps[[s$id]]; q <- numeric(8); q[8] <- s$open_queries
    for (t in 8:2) q[t - 1] <- switch(s$phase,
      "Startup"   = s$open_queries * (t - 1) / 8,       # queries start with the first participants
      "Conduct"   = max(0, q[t] - st[t]),               # a random walk that drifts upward
      "DB Lock"   = q[t] + abs(st[t]),                  # burning down toward the lock
      "Reporting" = q[t] * 1.25)                        # the last queries closing, 20% a week
    data.frame(study_id = s$id, week = 1:8, open_queries = as.integer(round(q)), stringsAsFactors = FALSE)
  })

  # deliverables register, 4 phase buckets that fill in order
  dtot <- c(Startup = 14, Conduct = 26, Analysis = 34, Reporting = 20)
  deliverables <- lapply(seq_len(nrow(studies)), function(r) {
    s <- studies[r, ]; prog <- progress[[s$id]]
    csr_done <- ms_all$status[ms_all$study_id == s$id & ms_all$milestone == "CSR"] == "done"
    frac <- c(prog / .15, (prog - .15) / .45, s$tlf_programmed / s$tlf_planned,
              s$tlf_finalized / s$tlf_planned) + noise[[s$id]]
    if (csr_done) frac[4] <- 1
    data.frame(study_id = s$id, phase = names(dtot),
               done = as.integer(round(dtot * pmin(1, pmax(0, frac)))), total = as.integer(dtot),
               stringsAsFactors = FALSE)
  })

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(studies, file.path(out_dir, "studies.csv"), row.names = FALSE)
  utils::write.csv(ms_all, file.path(out_dir, "milestones.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, deliverables), file.path(out_dir, "deliverables.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, qtrends), file.path(out_dir, "query_trend.csv"), row.names = FALSE)
  invisible(studies)
}

if (sys.nframe() == 0) gen_portfolio(out_dir = file.path(dirname(getwd()), "data"))
