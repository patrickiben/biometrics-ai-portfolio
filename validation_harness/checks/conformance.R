#!/usr/bin/env Rscript
###############################################################################
# G3 — Data conformance & integrity checker (Trial-Management Validation Harness)
# Dogfoods on the repository's synthetic ADaM (sim_lifecycle/out/*.csv).
# Prints one "CHECK <name>: PASS|FAIL (detail)" line per check + a G3 verdict.
# 100% synthetic data; no PHI. Usage: Rscript conformance.R [out_dir]
###############################################################################
args <- commandArgs(trailingOnly = TRUE)
out  <- if (length(args) >= 1) args[1] else "sim_lifecycle/out"
dom  <- c("adsl","adex","adpc","adpp","adae","advs","adlb","adeg")
pass <- TRUE
chk  <- function(name, ok, detail = "") {
  cat(sprintf("CHECK %-34s %s%s\n", name, if (ok) "PASS" else "FAIL",
              if (nzchar(detail)) paste0("  (", detail, ")") else ""))
  if (!ok) pass <<- FALSE
}
rd <- function(d) {
  f <- file.path(out, paste0(d, ".csv"))
  if (!file.exists(f)) return(NULL)
  read.csv(f, stringsAsFactors = FALSE, check.names = FALSE)
}

# --- 1. all 8 ADaM domains present ------------------------------------------
present <- vapply(dom, function(d) file.exists(file.path(out, paste0(d,".csv"))), logical(1))
chk("all 8 ADaM domains present", all(present),
    if (all(present)) "adsl adex adpc adpp adae advs adlb adeg"
    else paste("missing:", paste(dom[!present], collapse=",")))
D <- setNames(lapply(dom, rd), dom)

# --- 2. USUBJID present in every domain -------------------------------------
hasid <- vapply(D, function(x) !is.null(x) && "USUBJID" %in% names(x), logical(1))
chk("USUBJID present in every domain", all(hasid),
    if (!all(hasid)) paste("no USUBJID:", paste(dom[!hasid], collapse=",")) else "CDISC key")

# --- 3. cross-domain referential integrity (all USUBJID subset of ADSL) ------
if (!is.null(D$adsl)) {
  ref <- unique(D$adsl$USUBJID)
  orphans <- vapply(dom[-1], function(d)
    if (is.null(D[[d]])) 0L else sum(!unique(D[[d]]$USUBJID) %in% ref), integer(1))
  chk("referential integrity (USUBJID in ADSL)", all(orphans == 0),
      if (any(orphans>0)) paste0(sum(orphans)," orphan keys in ",
        paste(names(orphans)[orphans>0],collapse=",")) else paste(length(ref),"participants"))
}

# --- 4. PARAMCD well-formed (no name-leak / malformed codes) -----------------
badpc <- character(0)
for (d in c("adpp","adpc","advs","adlb","adeg")) {
  x <- D[[d]]; if (is.null(x) || !"PARAMCD" %in% names(x)) next
  bad <- unique(x$PARAMCD[!grepl("^[A-Z0-9_]+$", x$PARAMCD)])
  if (length(bad)) badpc <- c(badpc, paste0(d,":",bad))
}
chk("PARAMCD well-formed (^[A-Z0-9_]+$)", length(badpc)==0,
    if (length(badpc)) paste(head(badpc,3),collapse=" ") else "no malformed codes")

# --- 5. crossover TRT01A tracks TRTSEQP (TR->Test, RT->Reference) ------------
a <- D$adsl
if (!is.null(a) && all(c("TRT01A","TRTSEQP") %in% names(a))) {
  ok <- all((a$TRTSEQP=="TR" & a$TRT01A=="Test") | (a$TRTSEQP=="RT" & a$TRT01A=="Reference"))
  tab <- paste(capture.output(print(table(a$TRTSEQP, a$TRT01A))), collapse=" | ")
  chk("TRT01A tracks TRTSEQP (period-1)", ok, if (ok) "no sequence/treatment mixing" else tab)
} else chk("TRT01A tracks TRTSEQP (period-1)", TRUE, "not a crossover design (n/a)")

# --- 6. ADPP derived params populated (AUCIFO/CL-F/Vz-F not silently NA) -----
pp <- D$adpp
if (!is.null(pp) && all(c("PARAMCD","AVAL") %in% names(pp))) {
  want <- c("AUCIFO","CLFO","VZFO")
  bad <- want[vapply(want, function(k){
    v <- pp$AVAL[pp$PARAMCD==k]; length(v)==0 || all(is.na(v)) || all(v==0)}, logical(1))]
  chk("derived PK params populated (AUCIFO/CL/Vz)", length(bad)==0,
      if (length(bad)) paste("empty:",paste(bad,collapse=",")) else "all non-missing")
}

# --- 7. participant terminology (no 'subject' column-name misuse) ------------
subj <- unlist(lapply(D, function(x) if (is.null(x)) character(0)
                      else grep("^SUBJECT", names(x), ignore.case=TRUE, value=TRUE)))
chk("no non-CDISC 'SUBJECT*' variables", length(subj)==0,
    if (length(subj)) paste(subj,collapse=",") else "USUBJID/SUBJID only")

cat(sprintf("\nG3_VERDICT: %s\n", if (pass) "PASS" else "FAIL"))
quit(status = if (pass) 0 else 1)
