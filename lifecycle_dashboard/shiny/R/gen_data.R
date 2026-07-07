# ---------------------------------------------------------------------------
# gen_data.R - deterministic synthetic study portfolio for the Lifecycle Monitor.
# No PHI, no participant-level data. Writes the CSVs the app reads, so on a real
# study you replace them with a read-only CTMS / EDC export (same columns).
# Run:  Rscript R/gen_data.R   (writes ../data/*.csv relative to shiny/)
# ---------------------------------------------------------------------------
gen_portfolio <- function(out_dir = "data", today = as.Date("2026-06-21"), seed = 20260621L) {
  set.seed(seed)
  phases  <- c("Startup", "Conduct", "DB Lock", "Reporting")
  designs <- c("Parallel SAD", "Parallel MAD", "2x2 Crossover BE",
               "Fixed-sequence DDI", "Food-effect", "Single-ascending FIH")
  ms_keys <- c("Protocol", "SAP", "FPFV", "LPLV", "DBL", "TLFs", "CSR")
  owners  <- c("A. Rivera", "J. Okafor", "M. Chen", "S. Patel", "L. Dubois", "K. Novak")
  offs    <- c(0, 18, 35, 150, 185, 215, 250)
  rf <- function(a, b) a + runif(1) * (b - a)
  ri <- function(a, b) as.integer(floor(a + runif(1) * (b - a + 1)))

  assigned <- c("Startup","Startup","Conduct","Conduct","DB Lock","DB Lock","Reporting","Reporting")
  studies <- list(); milestones <- list(); deliverables <- list(); qtrends <- list()

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
    q <- openQ + ri(0,40); qt <- integer(8)
    for (t in 1:8) { q <- max(0, round(q + if (phase=="Reporting") -q*.2 else rf(-8,10))); qt[t] <- q }
    qt[8] <- openQ
    clean_pct <- min(.999, prog*0.7 + rf(.2,.32))
    sdv_pct   <- min(.999, prog*0.6 + rf(.2,.35))

    planned <- sample(c(90,120,150,180,72), 1)
    rep_frac <- switch(phase, "Reporting" = rf(.6,1), "DB Lock" = rf(.15,.4),
                       "Conduct" = rf(0,.15), "Startup" = rf(0,.05))
    programmed <- round(planned * min(1, rep_frac + rf(.05,.2)))
    qcd <- round(programmed * rf(.55,.85)); finalized <- round(qcd * rf(.55,.95))
    dbl_prog_pct <- ri(40,85); discrep <- ri(0,18)

    # deliverables register (echoes Protocol->CSR, scaled), 4 phase buckets
    dtot <- c(Startup=14, Conduct=26, Analysis=34, Reporting=20)
    stagew <- c(1, .85, .55, .2)
    for (idx in seq_along(dtot)) {
      p <- names(dtot)[idx]; tot <- dtot[[idx]]
      done_n <- min(tot, round(tot * max(0, min(1, prog/stagew[idx] - (idx-1)*.15 + rf(-.05,.05)))))
      deliverables[[length(deliverables)+1]] <- data.frame(
        study_id=id, phase=p, done=as.integer(done_n), total=as.integer(tot), stringsAsFactors=FALSE)
    }
    for (j in 1:7) milestones[[length(milestones)+1]] <- data.frame(
      study_id=id, milestone=ms_keys[j], date=as.character(ms_date[j]), status=ms_status[j], stringsAsFactors=FALSE)
    for (t in 1:8) qtrends[[length(qtrends)+1]] <- data.frame(
      study_id=id, week=t, open_queries=as.integer(qt[t]), stringsAsFactors=FALSE)

    studies[[length(studies)+1]] <- data.frame(
      id=id, name=paste0(design, " study"), phase=phase, design=design, owner=sample(owners,1),
      target=target, enrolled=enrolled, sites=ri(1,4), days_to_dbl=days_to_dbl,
      open_queries=openQ, clean_pct=round(clean_pct,3), sdv_pct=round(sdv_pct,3),
      tlf_planned=planned, tlf_programmed=programmed, tlf_qcd=qcd, tlf_finalized=finalized,
      dbl_prog_pct=dbl_prog_pct, discrep=discrep, stringsAsFactors=FALSE)
  }
  studies <- do.call(rbind, studies)

  # force CP-108 to be clearly AT RISK so the red state + signals are exercised
  k <- studies$id == "CP-108"
  studies$phase[k] <- "Reporting"; studies$days_to_dbl[k] <- -24L
  studies$tlf_programmed[k] <- round(studies$tlf_planned[k]*0.45)
  studies$tlf_qcd[k] <- round(studies$tlf_planned[k]*0.22)
  studies$tlf_finalized[k] <- round(studies$tlf_planned[k]*0.10)
  studies$dbl_prog_pct[k] <- 42L; studies$discrep[k] <- 16L
  studies$open_queries[k] <- 7L; studies$clean_pct[k] <- 0.91; studies$sdv_pct[k] <- 0.86
  ms_all <- do.call(rbind, milestones)
  ms_all$status[ms_all$study_id=="CP-108" & ms_all$milestone %in% c("TLFs","CSR")] <- "risk"

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(studies, file.path(out_dir, "studies.csv"), row.names = FALSE)
  utils::write.csv(ms_all, file.path(out_dir, "milestones.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, deliverables), file.path(out_dir, "deliverables.csv"), row.names = FALSE)
  utils::write.csv(do.call(rbind, qtrends), file.path(out_dir, "query_trend.csv"), row.names = FALSE)
  invisible(studies)
}

if (sys.nframe() == 0) gen_portfolio(out_dir = file.path(dirname(getwd()), "data"))
