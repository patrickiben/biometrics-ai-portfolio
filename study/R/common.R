################################################################################
# common.R: shared settings and helpers for the flagship worked example (study/).
# SYNTHETIC DATA ONLY. Nothing here is real trial data or a regulatory deliverable.
#
# Sourced by study/run_all.R before any stage script. The working directory is the
# repository root, so paths such as "sim_lifecycle/priors.R" resolve.
################################################################################

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

invisible(Sys.setlocale("LC_COLLATE", "C"))   # base-R string sorting is the same on macOS and Linux
options(
  formatters_default_hsep = "-",   # rtables/formatters rule character (ASCII, not an em dash)
  stringsAsFactors = FALSE,
  dplyr.summarise.inform = FALSE,
  warn = 1,
  scipen = 0
)

## --- study constants (the protocol's fixed design facts) ---------------------
STUDY <- list(
  studyid   = "SIMBE01",
  title     = "A randomized, open-label, single-dose, two-period, two-sequence (2x2) crossover bioequivalence study of SIMDRUG 100 mg tablets in healthy adults (synthetic)",
  siteid    = "101",
  seed      = 2026L,            # master seed; same seed as sim_lifecycle/
  n_enrolled = 40L,
  dose_mg   = 100,
  washout_d = 14L,              # days between the two single doses (Day 1 and Day 15)
  lloq      = 0.50,             # ng/mL
  cutoff    = "2026-05-29",     # synthetic database lock, used as a fixed date everywhere
  ## MedDRA: the version current when the synthetic study started (consent from Feb 2026,
  ## first dose 2026-03-02), per the SAP rule "version set at study start". v28.1 is the
  ## September 2025 release; v29.1 (September 2026) came out after this study's lock.
  ## Every output that names the dictionary reads these two values.
  meddra_version = "28.1",
  dict_meddra = "MedDRA v28.1 (synthetic coding)",
  sequences = c("TR", "RT"),
  trt_levels = c("Test", "Reference")
)

stopifnot(grepl(STUDY$meddra_version, STUDY$dict_meddra, fixed = TRUE))

## Package version as CRAN and renv.lock write it ("1.5-7"); utils::packageVersion()
## normalizes the dash to a dot ("1.5.7"), so displayed versions use the DESCRIPTION string.
pkg_version <- function(p) utils::packageDescription(p, fields = "Version")

SYNTHETIC_NOTE <- "Synthetic data only: simulated for this worked example; not real trial data and not a regulatory deliverable."

## --- paths -------------------------------------------------------------------
sp <- function(...) file.path("study", ...)

## --- deterministic writers ---------------------------------------------------
## Numbers are rounded to 10 significant digits before writing, so a rerun on the
## same platform is byte-identical and cross-platform last-digit noise is unlikely.
round_df <- function(df, digits = 10) {
  for (nm in names(df)) {
    x <- df[[nm]]
    if (is.double(x) && !inherits(x, c("POSIXt", "Date"))) df[[nm]] <- signif(x, digits)
  }
  df
}

## ADaM numerics (not dates or times) are rounded to 10 significant digits when each dataset
## is built, so the NCA, the QC, the XPT, CSV and Dataset-JSON files all see the same values.
num_round <- function(d) {
  for (nm in names(d)) if (is.double(d[[nm]]) && !inherits(d[[nm]], c("POSIXt", "Date", "difftime"))) d[[nm]] <- signif(d[[nm]], 10)
  d
}

write_csv_det <- function(df, path) {
  df <- as.data.frame(df)
  for (nm in names(df)) {
    x <- df[[nm]]
    if (inherits(x, "POSIXt")) df[[nm]] <- format(x, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
    if (inherits(x, "Date"))   df[[nm]] <- format(x, "%Y-%m-%d")
  }
  df <- round_df(df)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(path)
}

write_json_det <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")
  writeLines(txt, path, useBytes = TRUE)
  invisible(path)
}

write_text <- function(txt, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(paste(txt, collapse = "\n"), "\n"))), con)
  invisible(path)
}

## Binary containers (XPT, XLSX) carry write timestamps, so a byte comparison would
## change on every run. Write to a temporary file and replace the committed copy only
## when its CONTENT differs (compare() returns TRUE when the two files are equivalent).
write_if_changed <- function(path, writer, compare) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- file.path(tempfile("wic"), basename(path))   # same file name (XPT names the member after it)
  dir.create(dirname(tmp))
  writer(tmp)
  if (file.exists(path) && isTRUE(compare(tmp, path))) {
    unlink(tmp)
    return(invisible(FALSE))
  }
  file.copy(tmp, path, overwrite = TRUE)
  unlink(tmp)
  invisible(TRUE)
}

## SDTM-like CSVs are read as text, then the numeric SDTM variables are converted, so
## identifiers such as SUBJID "001" keep their leading zeros.
SDTM_NUM <- c("AGE", "EXDOSE", "VISITNUM", "VISITDY", "EXSEQ", "PCSTRESN", "PCLLOQ", "PCTPTNUM", "PCSEQ",
              "AESEQ", "VSSTRESN", "VSSEQ", "DSSEQ", "PPSTRESN", "PPSEQ")
read_sdtm <- function(nm) {
  x <- utils::read.csv(sp("03_adam", "sdtm", paste0(nm, ".csv")), colClasses = "character", na.strings = "")
  for (v in intersect(names(x), SDTM_NUM)) x[[v]] <- as.numeric(x[[v]])
  admiral::convert_blanks_to_na(tibble::as_tibble(x))
}

## ADPP.NCAEXRSN terms for the SAP parameter rules (used by 03_adam/05_adpp.R and the
## specification, so the data and the codelist cannot disagree)
nca_rule_terms <- function(sap) c(
  r2   = sprintf("ADJUSTED R-SQUARED BELOW %.2f", sap$nca$min_hl_adj_r_squared),
  pext = sprintf("AUC(0-INF) EXTRAPOLATED ABOVE %g%%", sap$nca$max_aucinf_pext_pct))

## --- small statistics helpers (conventions from the verified baseline) -----------
geomean <- function(x) exp(mean(log(x)))
geocv   <- function(x) 100 * sqrt(exp(stats::var(log(x))) - 1)

## --- HTML helpers --------------------------------------------------------------
esc <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

## Markdown to HTML for prose blocks (commonmark; no raw HTML passes through unescaped
## because every input string is authored in this repository).
md <- function(...) commonmark::markdown_html(paste(c(...), collapse = "\n"), extensions = "table")

## A chip whose text starts with Led, Supported, Tools built or Gap is a lifecycle label (.lab);
## anything else ("Runs: ...", "Executed: ...", "Synthetic data") is an execution status (.st).
lab <- function(kind, text) {
  if (grepl("^(Led|Supported|Tools built|Gap)\\b", text))
    return(sprintf('<span class="lab %s">%s</span>', kind, esc(text)))
  st <- if (grepl("^Synthetic", text)) "synthetic" else if (grepl("^(Runs|Executed)", text)) "runs" else "note"
  sprintf('<span class="st st-%s">%s</span>', st, esc(text))
}

## The site's head and top bar, read unchanged from the partials that build_pages.py writes
## (the working directory is the repository root).
partial <- function(name) paste(readLines(file.path("_partials", name), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

html_table <- function(df, caption = NULL, cls = "data", digits = NULL) {
  df <- as.data.frame(df, check.names = FALSE)
  head <- paste0("<tr>", paste0("<th scope=\"col\">", esc(names(df)), "</th>", collapse = ""), "</tr>")
  rows <- apply(df, 1, function(r) paste0("<tr>", paste0("<td>", esc(ifelse(is.na(r), "", r)), "</td>", collapse = ""), "</tr>"))
  paste0('<div class="tblwrap"><table class="', cls, '">',
         if (!is.null(caption)) paste0("<caption>", esc(caption), "</caption>") else "",
         "<thead>", head, "</thead><tbody>", paste(rows, collapse = "\n"), "</tbody></table></div>")
}

## One page template for every generated page in study/. depth = folders below study/
## (0 for study/index.html, 1 for study/0X_stage/, 2 for study/0X_stage/sub/).
page_html <- function(title, kicker, h1, body, depth = 1, description = NULL, labels = NULL) {
  up <- paste(rep("../", depth + 1), collapse = "")      # to the repository root
  st <- paste(rep("../", depth), collapse = "")          # to study/
  desc <- description %||% paste(h1, "(synthetic worked example).")
  crumbs <- paste0('<nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="', up, 'index.html">Home</a></li>',
                   if (depth > 0) paste0('<li><a href="', st, 'index.html">Worked example</a></li><li aria-current="page">', esc(title), '</li>')
                   else '<li aria-current="page">Worked example</li>', '</ol></nav>')
  paste0(
'<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>', esc(title), ' | Trial biostatistics toolkit</title>
<meta name="description" content="', esc(desc), '">
', partial(sprintf("_head-d%d.html", depth + 1)), '
<link rel="stylesheet" href="', st, 'study.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
', partial(sprintf("_topbar-example-d%d.html", depth + 1)), '
<main id="main" class="wrap">
  ', crumbs, '
  <section class="page-head">
    <p class="kicker">', esc(kicker), '</p>
    <h1>', esc(h1), '</h1>
', if (!is.null(labels)) paste0('    <p class="meta">', labels, '</p>\n') else "",
'    <p class="synthetic">', esc(SYNTHETIC_NOTE), '</p>
  </section>
', body, '
</main>
<footer class="site">
  <div class="wrap">
    <p class="fine">Generated by <code>study/run_all.R</code> from code in this repository. ', esc(SYNTHETIC_NOTE),
' <a href="', st, 'index.html">Back to the worked example</a>.</p>
  </div>
</footer>
</body>
</html>')
}

`%||%` <- function(a, b) if (is.null(a)) b else a

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d)
fmt_p <- function(p) ifelse(p < 0.0001, "<0.0001", formatC(p, format = "f", digits = 4))
