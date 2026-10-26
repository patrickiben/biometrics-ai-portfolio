# =====================================================================================
# slm_companion.R  -  LOCALMIND R companion: call a LOCAL, OFFLINE small language model
# (Ollama) for the language layer only. httr2 + jsonlite. Same contract as slm_macros.sas:
# loopback-only (no egress), schema-constrained output, allowlist validator, temp0+seed,
# pinned model, human gate. The model NEVER produces a number.
# =====================================================================================
suppressPackageStartupMessages({ library(httr2); library(jsonlite) })

# ---- pin the model + assert loopback/offline + assert the model is pulled -------------
slm_init <- function(model, base = "http://127.0.0.1:11434", seed = 42L) {
  if (!grepl("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]+)?(/|$)", base))
    stop("[LOCALMIND] non-loopback endpoint blocked: ", base, " - egress not allowed", call. = FALSE)
  live <- tryCatch(request(base) |> req_url_path_append("api", "version") |> req_timeout(5) |>
                     req_perform() |> resp_status(), error = function(e) 0)
  if (!identical(live, 200L)) stop("[LOCALMIND] local model server not reachable at ", base, call. = FALSE)
  tags <- request(base) |> req_url_path_append("api", "tags") |> req_perform() |> resp_body_json()
  names <- vapply(tags$models, function(m) tolower(m$name), character(1))
  if (!tolower(model) %in% names)
    stop("[LOCALMIND] model '", model, "' is not pulled (run: ollama pull ", model, ")", call. = FALSE)
  show <- request(base) |> req_url_path_append("api", "show") |> req_method("POST") |>
    req_body_json(list(model = model)) |> req_perform() |> resp_body_json()
  digest <- show$details$digest %||% show$model_info$general.digest %||% NA_character_
  structure(list(model = model, base = base, seed = as.integer(seed), digest = digest), class = "slm")
}

# ---- the trust boundary: validate a parsed result against an allowlist + range --------
slm_validate <- function(x, field, allow, conf = "confidence") {
  v <- toupper(as.character(x[[field]]))
  if (!v %in% toupper(allow))
    stop(sprintf("[LOCALMIND] off-allowlist %s: %s (allowed: %s)", field, v, paste(allow, collapse = ", ")), call. = FALSE)
  if (!is.null(x[[conf]]) && (!is.numeric(x[[conf]]) || x[[conf]] < 0 || x[[conf]] > 1))
    stop(sprintf("[LOCALMIND] %s out of range: %s", conf, x[[conf]]), call. = FALSE)
  invisible(TRUE)
}

# ---- classify/route/label: build a one-enum schema, call locally, validate, stamp -----
# sys = system instruction; usr = the SHORT finding text. allow = character vector of labels.
slm_classify <- function(con, sys, usr, field = "label", allow, num_predict = 512L, num_ctx = 8192L) {
  stopifnot(inherits(con, "slm"))
  # build the enum-constrained JSON schema (set the label field by name)
  props <- list(); props[[field]] <- list(type = "string", enum = as.list(allow))
  props$confidence <- list(type = "number"); props$rationale <- list(type = "string")
  schema <- list(type = "object", properties = props,
                 required = as.list(c(field, "confidence", "rationale")), additionalProperties = FALSE)

  resp <- request(con$base) |> req_url_path_append("api", "chat") |>
    req_body_json(list(model = con$model, stream = FALSE, keep_alive = "-1",
      options = list(temperature = 0, seed = con$seed, top_k = 1L, top_p = 1, repeat_penalty = 1,
                     num_predict = num_predict, num_ctx = num_ctx),
      format = schema,                                   # server-side grammar constraint
      messages = list(list(role = "system", content = sys),
                      list(role = "user",   content = usr))), auto_unbox = TRUE) |>
    req_timeout(180) |> req_perform() |> resp_body_json()

  out <- fromJSON(resp$message$content)                  # message.content is a JSON string -> parse again
  slm_validate(out, field = field, allow = allow)        # reject -> stop() (fail loud, no write)
  c(out, list(slm_model = con$model, slm_digest = con$digest, slm_seed = con$seed,
              slm_temp = 0, slm_endpoint = con$base))    # provenance
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

# ---- example -------------------------------------------------------------------------
if (sys.nframe() == 0) {
  con <- slm_init("llama3.1:8b-instruct-q8_0")
  r <- slm_classify(con,
    sys = "You triage a CDISC conformance finding. Reply only as the schema. Do not invent numbers.",
    usr = "SD0064: AESTDTC is after AEENDTC for 3 records in domain AE.",
    field = "owner", allow = c("DM", "PROGRAMMING", "PK", "MEDICAL CODING", "SITE"))
  str(r)
}
