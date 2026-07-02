# =====================================================================================
# ss_companion.R  -  SHEETLINK R companion: drive Smartsheet from scheduled R (no AI).
# httr2 + jsonlite. Same governance as ss_macros.sas: ops-only column allowlist, token
# from an env var (never hard-coded), idempotent upsert-by-key, 429/5xx retry, fail-loud.
# Schedule with cronR / taskscheduleR; pin packages with renv.
# =====================================================================================
suppressPackageStartupMessages({ library(httr2); library(dplyr); library(purrr); library(tibble) })

SS_BASE <- "https://api.smartsheet.com/2.0"

# ---- a request pre-loaded with auth, JSON, and 429/5xx retry with backoff -------------
ss_req <- function(...) {
  token <- Sys.getenv("SMARTSHEET_TOKEN")
  if (!nzchar(token)) stop("[SHEETLINK] SMARTSHEET_TOKEN not set", call. = FALSE)
  request(SS_BASE) |>
    req_url_path_append(...) |>
    req_auth_bearer_token(token) |>
    req_headers(Accept = "application/json") |>
    req_retry(max_tries = 5, is_transient = \(resp) resp_status(resp) %in% c(429, 500, 502, 503, 504),
              backoff = \(i) 2^i)
}

# ---- FAIL LOUD --------------------------------------------------------------------------
ss_assert <- function(cond, msg) if (!isTRUE(cond)) stop("[SHEETLINK] ", msg, call. = FALSE)

# ---- enforce the ops-only column ALLOWLIST in code (no PHI to the cloud) ---------------
ss_guard <- function(cols, allow) {
  bad <- setdiff(toupper(cols), toupper(allow))
  ss_assert(length(bad) == 0, paste("BLOCKED non-allowlisted column(s):", paste(bad, collapse = ", "),
                                     "- possible PHI/sensitive leak"))
}

# ---- GET the sheet -> fresh column NAME -> columnId map (rebuilt every run) ------------
ss_colmap <- function(sheet) {
  body <- ss_req("sheets", sheet) |> req_perform() |> resp_body_json()
  setNames(map_dbl(body$columns, "id"), toupper(map_chr(body$columns, "title")))
}

# ---- GET the sheet rows -> tibble(rowId, <Col Title> = value), keyed for upsert --------
ss_get_rows <- function(sheet, colmap) {
  body <- ss_req("sheets", sheet) |> req_url_query(includeAll = "true") |> req_perform() |> resp_body_json()
  id2name <- setNames(names(colmap), as.character(colmap))
  map_dfr(body$rows, function(r) {
    vals <- map(r$cells, function(c) c$value %||% NA); names(vals) <- id2name[as.character(map_dbl(r$cells, "columnId"))]
    tibble(rowId = r$id, !!!vals)
  })
}

# ---- the flagship: IDEMPOTENT upsert by a stable external key (never duplicates) -------
# df: a data.frame with the key column + one column per Smartsheet column title to write.
ss_upsert <- function(sheet, key, df, allow, dryrun = FALSE) {
  ss_guard(c(names(df)), allow)
  colmap  <- ss_colmap(sheet)
  current <- tryCatch(ss_get_rows(sheet, colmap), error = function(e) tibble(rowId = numeric()))
  keyname <- toupper(key)
  existing <- if (nrow(current) && keyname %in% toupper(names(current)))
                setNames(current$rowId, current[[which(toupper(names(current)) == keyname)]]) else numeric()
  rows <- pmap(df, function(...) {
    r <- list(...); kv <- as.character(r[[key]]); rid <- existing[kv]
    cells <- imap(r, function(v, nm) list(columnId = unname(colmap[toupper(nm)]), value = v))
    # drop cells with no mapped column, AND cells whose value is NA: an NA means "leave this
    # cell untouched" — never write a blank/NA, which would otherwise land in the sheet as the
    # literal text "NA" (and clobber a real value).
    cells <- Filter(function(c) !is.na(c$columnId) &&
                    !(length(c$value) == 1 && (is.na(c$value) || (is.character(c$value) && c$value == ""))), cells)
    if (!is.na(rid)) list(id = unname(rid), cells = unname(cells))
    else             list(toBottom = TRUE,  cells = unname(cells))
  })
  upd <- Filter(function(x) !is.null(x$id), rows); new <- Filter(function(x) is.null(x$id), rows)
  if (isTRUE(dryrun)) {   # preview what WOULD be sent (validate a job before you schedule it)
    message(sprintf("[SHEETLINK] DRY RUN sheet %s: would update %d, add %d (idempotent by %s) - nothing sent",
                    sheet, length(upd), length(new), key))
    return(invisible(list(update = upd, add = new)))
  }
  if (length(upd)) ss_req("sheets", sheet, "rows") |> req_method("PUT")  |> req_body_json(upd) |> req_perform()
  if (length(new)) ss_req("sheets", sheet, "rows") |> req_method("POST") |> req_body_json(new) |> req_perform()
  message(sprintf("[SHEETLINK] upsert sheet %s: %d updated, %d added (idempotent by %s)", sheet, length(upd), length(new), key))
}

# ---- attach an operational artifact to a row (rate-intensive; ops-only files) ---------
ss_attach <- function(sheet, row, file) {
  ss_req("sheets", sheet, "rows", row, "attachments") |>
    req_body_file(file, type = "application/pdf") |>
    req_headers(`Content-Disposition` = sprintf('attachment; filename="%s"', basename(file))) |>
    req_perform()
  message("[SHEETLINK] attached ", basename(file), " to row ", row)
}

# ---- supported human-in-the-loop notification: an update request (ops-only text) ------
ss_update_request <- function(sheet, rowIds, columnIds, sendTo, subject, message) {
  body <- list(sendTo = map(sendTo, ~list(email = .x)), rowIds = rowIds, columnIds = columnIds,
               subject = subject, message = message, includeAttachments = FALSE)
  ss_req("sheets", sheet, "updaterequests") |> req_method("POST") |> req_body_json(body) |> req_perform()
  message("[SHEETLINK] update request sent")
}

# ---- read ONE cell value back by its key (verification / read-after-write) -------------
ss_get <- function(sheet, key, keycol, col) {
  cm <- ss_colmap(sheet); rows <- ss_get_rows(sheet, cm)
  kc <- which(toupper(names(rows)) == toupper(keycol)); cc <- which(toupper(names(rows)) == toupper(col))
  if (!length(kc) || !length(cc)) return(NA)
  hit <- rows[!is.na(rows[[kc]]) & toupper(as.character(rows[[kc]])) == toupper(key), , drop = FALSE]
  if (!nrow(hit)) NA else hit[[cc]][1]
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- example nightly driver (schedule with cronR::cron_add / taskscheduleR) -----------
if (sys.nframe() == 0) {
  allow <- c("TaskID", "Status", "PctDone", "Owner", "Due")    # the ops-only allowlist
  df <- tibble(TaskID = c("CP101-ENR", "CP101-ADPC"),
               Status = c("At Risk", "On Track"), PctDone = c(NA, 0.85), Due = c("", "2026-06-15"))
  ss_upsert(sheet = Sys.getenv("CP101_TRACKER_ID"), key = "TaskID", df = df, allow = allow)
}
