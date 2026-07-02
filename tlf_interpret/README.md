# Automated TLF Interpretation — Quarto + local SLM

A pipeline that **drafts the narrative interpretation** that accompanies each Table/Listing/Figure
(e.g. the AE-overview paragraph, the PK-parameter summary text), using an **on-prem small language
model (SLM)**, rendered with **Quarto**, and wired to the deterministic TLF outputs from
`../r_tlf_pseudocode/` (or `../sas_tlf_pseudocode/`).

This is a DESIGN + runnable skeleton, not a validated system. It is a drafting aid behind hard
guardrails — it does not replace the biostatistician and it does not produce any reported number.

## The one hard invariant
**The SLM never sources a number.** Every reported number comes from the validated TLF result
dataset (which itself traces to Phoenix WinNonlin / Pinnacle 21 / EDC per SOP). The model only writes
the *prose* around numbers it is *handed*, and that prose is then checked so that **every number in
the draft must already exist in the deterministic facts** — otherwise it is rejected as a
hallucination. The rendered table/figure in the report is the validated output, not anything the
model produced.

```
 validated TLF result dataset  ──►  fact extractor (deterministic R)  ──►  facts {typed numbers+labels}
   (aggregate, no PHI)                                                         │
                                                                              ▼
                                            local SLM  ◄── constrained prompt (temp 0, fixed seed,
                                          (Ollama, on-prem,     pinned model+digest): "use ONLY these
                                           frozen weights)       facts; introduce no new numbers"
                                                                              │  draft prose
                                                                              ▼
   ┌──────────────────────────  validators (deterministic R, NOT the model)  ──────────────────────┐
   │ 1. numeric-consistency : every number in the draft ∈ facts (else REJECT)                       │
   │ 2. forbidden-claim     : flag causal/efficacy/"safe"/"well tolerated" language for review      │
   │ 3. template conformance: length, required slots                                                │
   └───────────────────────────────────────────────────────────────────────────────────────────────┘
                                                                              │  status: DRAFT_OK / FLAGGED / REJECTED
                                                                              ▼
        Quarto render (interpret_tlf.qmd) : validated table/figure + DRAFT callout + the grounding
        facts + the validator results  ──►  biostatistician reviews / edits / SIGNS OFF (human gate)
                                                                              │  status: APPROVED
                                                                              ▼
                                              approved interpretation flows to the CSR narrative
                                                + audit record (model id+digest, seed, prompt hash,
                                                  facts hash, draft, approver, final text, timestamp)
```

## Why each piece
- **Numbers stay deterministic.** The fact extractor is plain R operating on the *aggregate* TLF
  result (n's, %'s, geometric means already computed by the validated program). No participant-level data
  and no PHI ever reach the model. The model cannot compute, only restate.
- **Local SLM, on-prem, NO daemon, NO admin (`reticulate` → `llama-cpp-python`, GGUF).** Runs the
  model *in-process from R* via a user-space Python wheel — no Ollama, no system service, no network,
  no admin rights (the things that get blocked on locked-down work laptops). Sovereignty + no data
  egress + a *frozen* GGUF file (pinned by name + SHA) so the same facts reproduce the same draft.

### Runtime & hardware (32 GB RAM / 4 GB VRAM target)
The default is now a **dense 4B medical model that fits in the 4 GB VRAM** at Q4 — a change from the
earlier 26B-A4B MoE, which had to run CPU-first from the 32 GB RAM. Either works; pick by how much VRAM
you have and how much capacity you want.

| Model | GGUF (size) | Params | Fit on 32 GB / 4 GB | Note |
|---|---|---|---|---|
| **MedGemma 1.5 4B-IT** (`google/medgemma-1.5-4b-it`) | Q4_K_M ≈ **2.6 GB** | 4B dense (Gemma 3 base) | **fits 4 GB VRAM** (full offload) *or* RAM | **recommended default** — medical-domain fine-tune; multimodal but used **text-only**; **no official GGUF → convert/quant yourself**; Gemma/HAI-DEF license |
| Gemma 4 26B-A4B-it QAT (Unsloth UD-Q4_K_XL) | 14.2 GB | 25.2B (3.8B active, MoE) | RAM + ~12–15 GB headroom; CPU-first or MoE-offload | heavier alternative — more capable, slower on this laptop; **Apache-2.0**; QAT keeps Q4 quality high |
| Gemma 3 1B | Q4 ≈ 0.8 GB | 1B dense | fully in 4 GB VRAM | ultra-light; weakest, tight slot-filling only |

**Getting a MedGemma GGUF** (Google ships safetensors only — there is no official GGUF):
- *convert it yourself* (recent llama.cpp): `python convert_hf_to_gguf.py google/medgemma-1.5-4b-it --outfile medgemma-1.5-4b-it-f16.gguf`
  then `./llama-quantize medgemma-1.5-4b-it-f16.gguf ~/models/medgemma-1.5-4b-it-Q4_K_M.gguf Q4_K_M`, **or**
- *use a trusted community quant* (e.g. an `unsloth`/`bartowski` GGUF, when available) — verify the publisher and record the SHA.
- We load the **text** model only (no `mmproj`/vision projector); the facts→prose task needs no image input.
- A medical model volunteers clinical conclusions more readily — the claim-guard (below) is essential, not optional.

**Running it on 4 GB VRAM** (the 4B now fits, unlike the MoE):
- *simplest:* `n_gpu_layers = 0` (pure CPU/RAM), `n_ctx = 4096` — always works.
- *fast (now viable for a 4B):* `TLF_SLM_GPU_LAYERS=999` puts the whole ~2.6 GB model on the GPU; drop toward `~28` if you hit a VRAM OOM (the KV cache + compute buffer also need room).
- *for the 26B-A4B alternative instead:* keep experts on CPU, offload the backbone — `options(tlf.slm.tensor_overrides = ".ffn_.*_exps.=CPU", tlf.slm.gpu_layers = 999)` (recent `llama-cpp-python`; = llama.cpp `--override-tensor ".ffn_.*_exps.=CPU" -ngl 999`).

Expect tens of tok/s with the 4B on the GPU (or ~5–15 tok/s CPU-only) → ~seconds per draft; fine for review-gated batch drafting.
Keep `n_ctx` small (4096) — the facts+prompt+draft is <1K tokens, so a large context just wastes RAM,
and on a busy work laptop (Outlook/Teams/browser open) close heavy apps to avoid swap. Install once in
a user venv: `pip install llama-cpp-python`; drop the `.gguf` on disk; point `tlf.slm.model_path` at it.
No admin, no daemon, no network. If even `reticulate` is blocked, the same wheel exposes a local
OpenAI-compatible server (`python -m llama_cpp.server`) on `localhost` — but in-process reticulate is
preferred (no port, no process to manage).
- **Deterministic decoding.** `temperature = 0`, fixed `seed` → reproducible drafts; logged in the
  audit record alongside the model digest and a hash of the prompt and facts.
- **Validators are not the model.** The numeric-consistency check (regex-extract every number from
  the draft; each must match a facts value within tolerance) is the core safety control — it makes a
  hallucinated statistic *structurally impossible to pass silently*. The claim guard flags
  efficacy/causal/"well tolerated"-style language for mandatory human judgement.
- **Human gate is mandatory.** Nothing is `APPROVED` without biostatistician sign-off. The Quarto
  doc renders drafts as `DRAFT — biostatistician review required` and shows exactly which facts the
  draft was grounded on, so review is fast and auditable.
- **Quarto** is the orchestration + rendering + freeze layer: one parameterized `.qmd` per TLF (or a
  master doc looping the TLF list), `freeze: true` + `renv` lockfile for reproducible reports.

## Honest limits
- Small local models are *weak writers*; this is **draft-assist + validate**, never autonomous
  authoring. The guardrails (number-validation + human gate), not the model's competence, are what
  make it safe.
- The numeric validator catches *fabricated/altered numbers*; it does not certify the *clinical
  correctness* of the interpretation — that is the reviewer's job (the claim guard only surfaces
  risky phrasings). Two specific boundaries the reviewer must cover: (a) it checks each number
  *exists* in the facts, not that it is *attached to the right quantity* — a model could pair a valid
  number with the wrong noun ("1 death" when the `1` was actually the SAE count); (b) spelled-out
  numbers ("twenty-four") bypass the digit regex — the prompt requires digits, but the human gate is
  the backstop.
- It does not, and must not, generate any regulated/reported number. Tables/figures shown are the
  validated outputs.
- Not validated software; treat outputs as draft text for human authoring, under ops governance.

## Files
- `R/slm_client.R`        — on-prem SLM client (`reticulate` → `llama-cpp-python`, GGUF, in-process;
                            CPU + partial GPU offload; temp 0; fixed seed; audit; graceful STUB
                            fallback so reports render with no model installed).
- `R/extract_facts.R`     — deterministic per-TLF fact extractors (AE overview, PK parameters, ...).
- `R/validate_interpretation.R` — numeric-consistency + claim + template validators.
- `R/interpret.R`         — orchestrator: facts → SLM draft → validate → status + audit record.
- `interpret_tlf.qmd`     — parameterized Quarto template (params: tlf_id, result dataset path).
- `selftest.R`            — runs the validators on a known-good and a hallucinated draft (no model needed).
- `_quarto.yml`           — project config (freeze).

## Wire-in
Point `extract_facts()` at the result tibble a TLF program returns (e.g. the AE-overview counts, the
`t_pk_param_summary` summary). The same pattern serves SAS: emit the result dataset, read it in R for
fact extraction + rendering, or call the SLM client from SAS via a shell/`PROC HTTP` step.
