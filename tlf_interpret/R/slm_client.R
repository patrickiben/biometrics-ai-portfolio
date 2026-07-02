################################################################################
# slm_client.R — on-prem small-language-model client for TLF interpretation
#
# Backend: reticulate -> llama-cpp-python -> a local GGUF model (default
# MedGemma 1.5 4B; any Gemma 3 / Qwen3 GGUF works). IN-PROCESS from R: no Ollama,
# no daemon, no system service, no
# network, no admin rights. Sized for a 32 GB RAM / 4 GB VRAM work laptop:
# CPU-first on RAM with a small partial GPU offload (n_gpu_layers).
#
# The model NEVER sources a number; it drafts prose from facts it is handed
# (see README invariant). Deterministic decoding (temperature 0, fixed seed) +
# a pinned GGUF file => reproducible drafts. PSEUDOCODE/skeleton.
################################################################################
## Soft-load deps so the STUB path still runs with neither installed.
.has_reticulate <- requireNamespace("reticulate", quietly = TRUE)
.has_digest     <- requireNamespace("digest",     quietly = TRUE)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (is.atomic(a) && is.na(a[1]))) b else a

## content hash for the audit trail (digest if available, else a stable fallback)
.sha1 <- function(x) {
  if (.has_digest) return(digest::digest(x, algo = "sha1"))
  paste0("nohash-", format(sum(utf8ToInt(paste(deparse(x), collapse = ""))), scientific = FALSE))
}

## Config — override via options() or env. Pin the GGUF by path (+ record its
## SHA in the audit) so the frozen weights are reproducible across runs/sites.
## Default = MedGemma 1.5 4B-IT (google/medgemma-1.5-4b-it) — a medical-domain
## fine-tune of Gemma 3 4B. ~2.6 GB at Q4_K_M, so it FITS the 4 GB VRAM (a big
## win over the 26B MoE, which had to run CPU-first). NOTES / CAVEATS:
##  - No OFFICIAL GGUF: Google ships safetensors only. Use a trusted community
##    quant or convert it yourself (llama.cpp convert_hf_to_gguf.py -> quantize
##    Q4_K_M; see README). Pin the file + its SHA once you have it.
##  - It is a MULTIMODAL (image+text) model; we use the TEXT path only (no mmproj
##    / vision projector is loaded), which is all the facts->prose task needs.
##  - License = Gemma / Health AI Developer Foundations terms (NOT Apache) —
##    review them for your use. A medical model is MORE likely to volunteer a
##    clinical conclusion ("well tolerated", "consistent with ..."), so the
##    claim-guard in validate_interpretation.R is essential, not optional.
## Heavier alternative (more capable, slower, CPU-first on this laptop): Gemma 4
## 26B-A4B QAT Unsloth UD-Q4_K_XL (~14.2 GB MoE) — point TLF_SLM_GGUF at it.
slm_config <- function() list(
  model_path  = getOption("tlf.slm.model_path",
                          Sys.getenv("TLF_SLM_GGUF", "~/models/medgemma-1.5-4b-it-Q4_K_M.gguf")),
  model_name  = getOption("tlf.slm.model_name", "medgemma-1.5-4b-it-Q4_K_M"),
  ## --- OLLAMA backend (open-source, localhost) — the easy path on a Mac -------
  ## `brew install ollama` + `ollama pull qwen2.5:7b` (or gemma3:27b / qwen2.5:32b
  ## on a 64 GB machine for best quality). Tried FIRST; falls through to the GGUF /
  ## stub paths if it isn't serving or the model isn't pulled.
  ollama_url  = getOption("tlf.slm.ollama_url",   Sys.getenv("TLF_SLM_OLLAMA_URL",   "http://localhost:11434")),
  ollama_model= getOption("tlf.slm.ollama_model", Sys.getenv("TLF_SLM_OLLAMA_MODEL", "alibayram/medgemma:27b")),
  n_ctx       = getOption("tlf.slm.n_ctx", 4096L),        # task needs <1K tokens; small KV cache saves RAM
  ## A 4B at Q4_K_M (~2.6 GB) now FITS the 4 GB VRAM, so GPU offload is viable
  ## (it wasn't for the 26B MoE). Leave 0 for guaranteed pure-CPU; set
  ## TLF_SLM_GPU_LAYERS=999 to push the whole model onto the GPU (lower it toward
  ## ~28 if you hit a VRAM OOM -- the KV cache + compute buffer also need room).
  n_gpu_layers= getOption("tlf.slm.gpu_layers", as.integer(Sys.getenv("TLF_SLM_GPU_LAYERS", "0"))),
  tensor_overrides = getOption("tlf.slm.tensor_overrides", NA_character_),  # advanced llama.cpp tensor placement
  n_threads   = getOption("tlf.slm.threads", max(1L, parallel::detectCores() - 1L)),
  seed        = getOption("tlf.slm.seed", 1L),
  temperature = 0,                                         # greedy decoding -> reproducible
  max_tokens  = getOption("tlf.slm.max_tokens", 400L)
)

## Lazy-load the GGUF once per session (cached); returns NULL if unavailable.
.slm_cache <- new.env(parent = emptyenv())
slm_model <- function(cfg = slm_config()) {
  if (!is.null(.slm_cache[[cfg$model_path]])) return(.slm_cache[[cfg$model_path]])
  if (!.has_reticulate ||
      !reticulate::py_module_available("llama_cpp") ||
      !file.exists(path.expand(cfg$model_path))) return(NULL)
  llama <- reticulate::import("llama_cpp", delay_load = TRUE)  # pip install llama-cpp-python (user venv, no admin)
  args <- list(
    model_path   = path.expand(cfg$model_path),
    n_ctx        = as.integer(cfg$n_ctx),
    n_gpu_layers = as.integer(cfg$n_gpu_layers),    # 0 = pure CPU; >0 offloads layers to the 4 GB VRAM
    n_threads    = as.integer(cfg$n_threads),
    seed         = as.integer(cfg$seed),
    verbose      = FALSE)
  ## MoE expert-offload (keep experts on CPU, backbone on GPU) — needs a recent
  ## llama-cpp-python; e.g. cfg$tensor_overrides = ".ffn_.*_exps.=CPU" + gpu_layers=999.
  if (!is.na(cfg$tensor_overrides)) args$override_tensor <- cfg$tensor_overrides
  m <- do.call(llama$Llama, args)
  .slm_cache[[cfg$model_path]] <- m
  m
}

## ---- OLLAMA backend (open-source local model over HTTP, no Python build) -----
## Deterministic (temperature 0, fixed seed). Returns NULL on any failure so the
## caller falls through to the GGUF backend and then the deterministic stub.
.has_httr2 <- requireNamespace("httr2", quietly = TRUE)
ollama_complete <- function(prompt, system = NULL, cfg = slm_config()) {
  if (!.has_httr2) return(NULL)
  msgs <- c(if (!is.null(system)) list(list(role = "system", content = system)),
            list(list(role = "user", content = prompt)))
  tryCatch({
    resp <- httr2::request(paste0(cfg$ollama_url, "/api/chat"))
    resp <- httr2::req_body_json(resp, list(
      model = cfg$ollama_model, messages = msgs, stream = FALSE,
      options = list(temperature = cfg$temperature, seed = as.integer(cfg$seed),
                     num_predict = as.integer(cfg$max_tokens))))
    resp <- httr2::req_timeout(resp, 180)
    j <- httr2::resp_body_json(httr2::req_perform(resp))
    txt <- j$message$content
    if (is.null(txt) || !nzchar(trimws(txt))) return(NULL)
    txt
  }, error = function(e) NULL)
}

## Draft from facts. Returns text + full provenance for the audit record.
## Falls back to a deterministic STUB (templated from facts) when no model is
## installed, so Quarto still renders offline / in CI — clearly marked STUB.
slm_complete <- function(prompt, system = NULL, facts = NULL, cfg = slm_config()) {
  out <- tryCatch({
    oll <- ollama_complete(prompt, system, cfg)              # 1) open-source Ollama (HTTP, localhost)
    if (!is.null(oll)) list(text = oll, stub = FALSE, backend = "ollama")
    else {
      m <- slm_model(cfg)                                    # 2) in-process GGUF (llama-cpp-python)
      if (is.null(m)) stop("no local model")
      msgs <- c(if (!is.null(system)) list(reticulate::dict(role = "system", content = system)),
                list(reticulate::dict(role = "user", content = prompt)))
      res <- m$create_chat_completion(
        messages    = msgs, temperature = cfg$temperature,
        seed        = as.integer(cfg$seed), max_tokens = as.integer(cfg$max_tokens))
      list(text = res$choices[[1]]$message$content, stub = FALSE, backend = "llama-cpp")
    }
  }, error = function(e) list(text = stub_draft(facts), stub = TRUE, backend = "stub"))

  list(
    text = trimws(out$text),
    meta = list(                         # audit provenance — logged with every interpretation
      backend      = switch(out$backend %||% "stub",
                            ollama      = sprintf("ollama (HTTP %s, open-weight)", cfg$ollama_url),
                            `llama-cpp` = "reticulate -> llama-cpp-python (GGUF, in-process, no-daemon)",
                            "deterministic stub (no local model installed)"),
      model_name   = if (isTRUE(out$backend == "ollama")) cfg$ollama_model else cfg$model_name,
      model_path   = cfg$model_path,
      model_sha1   = if (.has_digest && file.exists(path.expand(cfg$model_path)))
                       digest::digest(file = path.expand(cfg$model_path), algo = "sha1") else NA_character_,
      stub         = out$stub,
      seed         = cfg$seed,
      temperature  = cfg$temperature,
      n_gpu_layers = cfg$n_gpu_layers,
      prompt_sha1  = .sha1(prompt),
      facts_sha1   = if (!is.null(facts)) .sha1(facts) else NA_character_,
      created_at   = format(Sys.time(), tz = "UTC", usetz = TRUE)))
}

## Deterministic offline fallback: a flat, number-faithful sentence from facts.
## Guarantees the pipeline (and its validators) run with no model installed.
stub_draft <- function(facts) {
  if (is.null(facts) || !length(facts)) return("[STUB] No facts supplied.")
  kv <- vapply(names(facts), function(k) sprintf("%s = %s", k, format(facts[[k]])), character(1))
  paste0("[STUB DRAFT - no local SLM installed] Reported values: ",
         paste(kv, collapse = "; "), ".")
}
