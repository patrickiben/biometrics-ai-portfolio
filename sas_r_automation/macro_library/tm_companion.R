# =====================================================================================
# tm_companion.R  -  TRIALMON R companion to tm_macros.sas (no AI).
# Same deterministic "ingest -> freshness -> guard -> checks -> report -> notify" loop.
# Schedule with cronR / taskscheduleR; pin packages with renv for byte-reproducibility.
# v2 - corrected after an independent review (strict Hy's-Law, NA-safe gate, %.0f,
#      lowercase columns, deferred de-dup commit, fail-loud assert/guard).
#
# Honest: these functions DETECT and EMAIL pre-specified deterministic flags. They do
# NOT triage or judge. A flag is a prompt for a human; the medical monitor decides.
# =====================================================================================
suppressPackageStartupMessages({
  library(dplyr); library(haven); library(gt); library(blastula)
})

# ---- FAIL LOUD: an unattended job must never let "no news" read as "good news" -------
tm_assert <- function(cond, msg, backup = NULL) {
  if (!isTRUE(cond)) {
    writeLines(sprintf("CP101 FAILED %s %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), msg), "out/heartbeat.txt")
    if (!is.null(backup)) try(tm_email(backup, paste("TRIALMON FAILURE -", msg),
                                       "The unattended monitor needs attention. Do not assume GREEN.", urgent = TRUE), silent = TRUE)
    stop("[TRIALMON] ASSERT FAILED: ", msg, call. = FALSE)
  }
}

# ---- read an extract and NORMALISE column names to lowercase (stable contract) -------
# haven::read_xpt preserves UPPERCASE CDISC names; lowercasing once means every check
# can reference alt_x / qtcf / usubjid regardless of the source casing.
tm_read <- function(path) {
  tm_assert(file.exists(path), paste("missing extract", path))
  read_xpt(path) |> rename_with(tolower)
}

# ---- GUARD: required columns exist, are numeric, and pass a range-sanity check -------
tm_guard <- function(df, numvars, sanity = NULL) {
  miss <- setdiff(numvars, names(df))
  tm_assert(length(miss) == 0, paste("missing columns:", paste(miss, collapse = ", ")))
  for (v in numvars) tm_assert(is.numeric(df[[v]]), paste(v, "is not numeric (unit/type change?)"))
  if (!is.null(sanity)) tm_assert(all(sanity(df), na.rm = TRUE), "failed range-sanity (possible unit error)")
  invisible(TRUE)
}

# ---- DATA-FRESHNESS GATE (run FIRST). NA-safe: a MISSING feed file is the worst case -
tm_freshness <- function(feeds, max_age_h = 26) {
  now <- Sys.time()
  out <- tibble::tibble(feed = names(feeds), path = unlist(feeds)) |>
    mutate(age_h = as.numeric(difftime(now, file.mtime(path), units = "hours")),
           stale = is.na(age_h) | age_h > max_age_h,                       # NA (absent file) -> stale
           sev   = ifelse(stale, "AMBER", "GREEN"))
  if (any(out$stale, na.rm = TRUE))
    message("WARNING [TRIALMON] STALE/MISSING FEED: ", paste(out$feed[out$stale], collapse = ", "),
            " -- GREEN on stale data is worse than RED")
  out
}

# ---- Hy's-Law / eDISH screening (CORRECTED): RED on ALT/AST>3 AND TBili>2, STRICT '>',
#      NEVER downgraded by ALP. R-ratio (ALT/ULN over ALP/ULN) is context only. --------
tm_chk_hyslaw <- function(df, altmult = 3, astmult = 3, bilmult = 2) {
  df |>
    mutate(hy = (alt_x > altmult | ast_x > astmult) & tbl_x > bilmult,
           r_ratio = alt_x / alp_x,
           pattern = case_when(r_ratio >= 5 ~ "hepatocellular", r_ratio <= 2 ~ "cholestatic", TRUE ~ "mixed")) |>
    filter(hy) |>
    transmute(usubjid, flag = sprintf("Hy's-Law pattern (%s, R=%.1f)", pattern, r_ratio), sev = "RED")
}

# ---- QTcF (ICH E14). Use %.0f, not %d (QTcF/dQTcF are doubles) -----------------------
tm_chk_qtcf <- function(df, abs_red = 500, dqt_red = 60, abs_amb = 480, dqt_amb = 30) {
  df |>
    mutate(sev = case_when(qtcf > abs_red | dqtcf > dqt_red ~ "RED",
                           qtcf > abs_amb | dqtcf > dqt_amb ~ "AMBER", TRUE ~ "GREEN")) |>
    filter(sev != "GREEN") |>
    transmute(usubjid, flag = sprintf("QTcF %.0f / dQTcF %.0f", qtcf, dqtcf), sev)
}

tm_chk_enroll <- function(n_enrolled, n_planned, kri = 0.80) {
  pct <- n_enrolled / n_planned
  tibble::tibble(flag = sprintf("Enrollment %.0f%% of plan (KRI %.0f%%)", 100*pct, 100*kri),
                 sev  = ifelse(pct < kri, "AMBER", "GREEN"))
}

tm_status <- function(...) {
  sevs <- unlist(lapply(list(...), function(d) d$sev))
  if (any(sevs == "RED")) "RED" else if (any(sevs == "AMBER")) "AMBER" else "GREEN"
}

# ---- de-dup: return fresh findings; COMMIT the seen-store only AFTER successful send -
tm_dedup <- function(new, key, store = "state/tm_seen.rds") {
  seen <- if (file.exists(store)) readRDS(store) else character(0)
  list(fresh = new[!new[[key]] %in% seen, , drop = FALSE], keys = unique(new[[key]]), store = store, seen = seen)
}
tm_commit_seen <- function(dd) saveRDS(union(dd$seen, dd$keys), dd$store)   # call ONLY after delivery succeeds

tm_email <- function(to, subject, body_md, attach = NULL, urgent = FALSE, smtp = creds_file("smtp_creds")) {
  em <- compose_email(body = md(body_md))
  if (!is.null(attach) && file.exists(attach)) em <- add_attachment(em, file = attach)
  smtp_send(em, to = to, from = "biostat-monitor@example.com",
            subject = paste0(if (urgent) "[URGENT] " else "", subject), credentials = smtp)
  message("NOTE [TRIALMON] emailed: ", subject)
}

# ---- per-RED-participant evidence packet: eDISH scatter + lab trajectory -> one PDF ------
tm_evidence <- function(red, lab, out = "out/evidence.pdf") {
  if (!nrow(red)) return(invisible(NULL))
  grDevices::pdf(out)
  with(lab, plot(alt_x, tbl_x, xlab = "peak ALT (x ULN)", ylab = "peak total bilirubin (x ULN)",
                 main = "eDISH evidence packet", pch = ifelse(lab$usubjid %in% red$usubjid, 19, 1)))
  abline(v = 3, h = 2, lty = 2)
  for (su in unique(red$usubjid)) {
    d <- lab[lab$usubjid == su, ]
    matplot(d$visitnum, d[, c("alt_x","ast_x","tbl_x","alp_x")], type = "b", pch = 1,
            xlab = "visit", ylab = "x ULN", main = paste("Participant", su, "- lab trajectory"))
  }
  grDevices::dev.off(); message("NOTE [TRIALMON] evidence -> ", out)
}

tm_heartbeat <- function(study, status, n, fresh_ok, file = "out/heartbeat.txt") {
  writeLines(sprintf("%s %s %s SYSCC=0 N=%d FRESH=%d", study, status,
                     format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), n, as.integer(fresh_ok)), file)
  invisible(TRUE)
}

# ---- example daily driver (schedule with cronR::cron_add / taskscheduleR) ------------
if (sys.nframe() == 0) {
  feeds  <- list(adlb = "/data/cp101/adam/adlb.xpt")
  fresh  <- tm_freshness(feeds)                                   # GATE first (NA-safe)
  adlb   <- tm_read(feeds$adlb)                                   # lowercased columns
  tm_guard(adlb, c("alt_x","ast_x","tbl_x","alp_x"), sanity = \(d) d$alt_x >= 0 & d$alt_x <= 400)
  hy     <- tm_chk_hyslaw(adlb)
  status <- tm_status(hy, fresh)
  dd     <- tm_dedup(filter(hy, sev == "RED"), key = "usubjid")
  if (nrow(dd$fresh)) {
    tm_evidence(dd$fresh, adlb)
    tm_email("biostat.cover@example.com", "RED ALERT - CP101 - safety threshold met",
             "A SCREENING flag met. Contact the medical monitor. Evidence attached.",
             attach = "out/evidence.pdf", urgent = TRUE)
    tm_commit_seen(dd)                                            # commit ONLY after the send
  }
  tm_heartbeat("CP101", status, n = nrow(adlb), fresh_ok = !any(fresh$stale, na.rm = TRUE))
}
