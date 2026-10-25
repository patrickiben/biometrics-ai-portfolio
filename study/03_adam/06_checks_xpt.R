################################################################################
# 03_adam/06_checks_xpt.R: check each ADaM dataset against the specification and write
# SAS XPORT v5 with labels and lengths, using the route in the verified baseline:
#   metacore::spec_to_metacore() -> metatools::check_variables() / check_ct_data() /
#   check_unique_keys() -> xportr_type / xportr_length / xportr_label / xportr_order /
#   xportr_format / xportr_df_label -> xportr_write()
# plus an optional CDISC Dataset-JSON v1.1 copy (datasetjson 0.4.1), which FDA has not
# accepted as of Oct 2026 (submission format stays SAS XPORT v5). SYNTHETIC DATA ONLY.
#
# Inputs : 03_adam/spec/adam_spec.xlsx; objects adsl, adpc, adpp, adae
# Outputs: 03_adam/data/{adsl,adpc,adpp,adae}.xpt and .csv, 03_adam/data/json/*.json,
#          03_adam/data/metadata_checks.csv
################################################################################
suppressPackageStartupMessages({ library(metacore); library(metatools); library(xportr) })
options(xportr.type_verbose = "stop", xportr.length_verbose = "stop", xportr.label_verbose = "stop",
        xportr.format_verbose = "stop", xportr.order_verbose = "message")

mc <- suppressMessages(spec_to_metacore(sp("03_adam", "spec", "adam_spec.xlsx"), where_sep_sheet = TRUE, verbose = "silent"))
spec_vars <- readxl::read_excel(sp("03_adam", "spec", "adam_spec.xlsx"), sheet = "Variables")
spec_ds <- readxl::read_excel(sp("03_adam", "spec", "adam_spec.xlsx"), sheet = "Datasets")

## numerics were rounded to 10 significant digits when each dataset was built (num_round());
## rounding again is a no-op that guards the files against a dataset that skipped it
adsl <- num_round(adsl); adpc <- num_round(adpc); adpp <- num_round(adpp); adae <- num_round(adae)

xpt_same <- function(a, b) {
  x <- haven::read_xpt(a); y <- haven::read_xpt(b)
  identical(as.data.frame(x), as.data.frame(y)) &&
    identical(lapply(x, attributes), lapply(y, attributes)) && identical(attr(x, "label"), attr(y, "label"))
}
json_same <- function(a, b) {
  strip <- function(f) sub('"datasetJSONCreationDateTime": ?"[^"]*"', "", paste(readLines(f, warn = FALSE), collapse = "\n"))
  identical(strip(a), strip(b))
}

ddj_type <- function(type, fmt) {
  if (type == "text") return(c("string", NA))
  if (!is.na(fmt) && fmt == "DATE9.") return(c("date", "integer"))
  if (!is.na(fmt) && fmt == "DATETIME20.") return(c("datetime", "integer"))
  if (!is.na(fmt) && fmt == "TIME8.") return(c("time", "integer"))
  if (type %in% c("date", "datetime")) return(c(type, NA))
  if (type == "integer") return(c("integer", NA))
  c("double", NA)
}

checks <- list()
for (ds in c("ADSL", "ADPC", "ADPP", "ADAE")) {
  d <- get(tolower(ds))
  m <- select_dataset(mc, ds, verbose = "silent")
  sv <- spec_vars[spec_vars$Dataset == ds, ]
  res <- function(check, ok, detail) checks[[length(checks) + 1]] <<- data.frame(dataset = ds, check = check, pass = ok, detail = detail)

  ## 1. variables: none missing, none extra (strict = TRUE stops on a mismatch)
  ok <- tryCatch({ suppressMessages(check_variables(d, m, strict = TRUE)); TRUE }, error = function(e) FALSE)
  res("metatools::check_variables (strict)", ok, sprintf("%d variables in data, %d in spec", ncol(d), nrow(sv)))
  ## 2. controlled terminology
  bad <- tryCatch({ suppressMessages(check_ct_data(d, m, na_acceptable = TRUE)); "" }, error = function(e) conditionMessage(e))
  res("metatools::check_ct_data", identical(bad, ""), if (identical(bad, "")) "all values in their codelists" else gsub("\\s+", " ", bad))
  ## 3. unique keys
  ok <- tryCatch({ suppressMessages(check_unique_keys(d, m)); TRUE }, error = function(e) FALSE)
  res("metatools::check_unique_keys", ok, spec_ds$`Key Variables`[spec_ds$Dataset == ds])
  ## 4. text lengths fit the spec; mandatory variables have no missing values
  txt <- sv[sv$`Data Type` %in% c("text", "date", "datetime"), ]
  over <- txt$Variable[vapply(txt$Variable, function(x) max(c(0, nchar(as.character(d[[x]])), na.rm = TRUE), na.rm = TRUE) > txt$Length[txt$Variable == x], logical(1))]
  res("text values fit the spec lengths", !length(over), if (length(over)) paste(over, collapse = ", ") else sprintf("%d text variables", nrow(txt)))
  mand <- sv$Variable[sv$Mandatory == "Yes"]
  miss <- mand[vapply(mand, function(x) anyNA(d[[x]]), logical(1))]
  res("mandatory variables populated", !length(miss), if (length(miss)) paste(miss, collapse = ", ") else sprintf("%d mandatory variables", length(mand)))
  cur <- do.call(rbind, checks); cur <- cur[cur$dataset == ds & !cur$pass, ]
  if (nrow(cur)) { print(cur); stop("metadata checks failed for ", ds) }

  ## 5. xportr: types, lengths, labels, order, formats, dataset label; then XPT v5
  dx <- d %>% xportr_type(m, domain = ds) %>% xportr_length(m, domain = ds) %>% xportr_label(m, domain = ds) %>%
    xportr_order(m, domain = ds) %>% xportr_format(m, domain = ds) %>% xportr_df_label(m, domain = ds)
  write_if_changed(sp("03_adam", "data", paste0(tolower(ds), ".xpt")),
                   function(p) xportr_write(dx, p, metadata = m, domain = ds, strict_checks = TRUE), xpt_same)
  rb <- haven::read_xpt(sp("03_adam", "data", paste0(tolower(ds), ".xpt")))
  lab_ok <- identical(unname(vapply(rb, function(x) attr(x, "label") %||% "", "")), sv$Label)
  res("XPT v5 read back: names, order and labels match the spec", lab_ok && identical(names(rb), sv$Variable),
      sprintf("%d rows x %d columns; dataset label '%s'", nrow(rb), ncol(rb), attr(rb, "label") %||% ""))

  ## 6. text copy for review and diffs
  write_csv_det(d[, sv$Variable], sp("03_adam", "data", paste0(tolower(ds), ".csv")))

  ## 7. Dataset-JSON v1.1 (not accepted by FDA as of Oct 2026)
  cols <- do.call(rbind, lapply(seq_len(nrow(sv)), function(i) {
    tt <- ddj_type(sv$`Data Type`[i], sv$Format[i])
    data.frame(itemOID = paste0("IT.", ds, ".", sv$Variable[i]), name = sv$Variable[i], label = sv$Label[i],
               dataType = tt[1], targetDataType = tt[2],
               length = ifelse(sv$`Data Type`[i] %in% c("text", "date", "datetime"), as.integer(sv$Length[i]), NA_integer_),
               displayFormat = ifelse(is.na(sv$Format[i]), NA_character_, sv$Format[i]),
               keySequence = NA_integer_)
  }))
  dj_data <- as.data.frame(d[, sv$Variable])
  for (nm in names(dj_data)) if (inherits(dj_data[[nm]], "POSIXt")) attr(dj_data[[nm]], "tzone") <- "UTC"
  for (nm in names(dj_data)) attributes(dj_data[[nm]])[setdiff(names(attributes(dj_data[[nm]])), c("class", "tzone", "units", "levels"))] <- NULL
  dj <- datasetjson::dataset_json(dj_data, file_oid = paste0("SIMBE01.", ds), last_modified = paste0(STUDY$cutoff, "T00:00:00"),
                                  originator = "study/run_all.R (synthetic worked example)", sys = "R",
                                  sys_version = paste(R.version$major, R.version$minor, sep = "."),
                                  study = STUDY$studyid, metadata_version = "MDV.SIMBE01.ADAM.1", metadata_ref = "adam_spec.json",
                                  item_oid = paste0("IG.", ds), name = ds,
                                  dataset_label = spec_ds$Description[spec_ds$Dataset == ds], columns = cols)
  dir.create(sp("03_adam", "data", "json"), showWarnings = FALSE)
  write_if_changed(sp("03_adam", "data", "json", paste0(tolower(ds), ".json")),
                   function(p) datasetjson::write_dataset_json(dj, p, pretty = TRUE), json_same)
}
metadata_checks <- do.call(rbind, checks)
write_csv_det(metadata_checks, sp("03_adam", "data", "metadata_checks.csv"))
stopifnot(all(metadata_checks$pass))
cat(sprintf("[03_adam/xpt] %d metadata checks passed; XPT v5 and Dataset-JSON written for ADSL, ADPC, ADPP, ADAE\n", nrow(metadata_checks)))
