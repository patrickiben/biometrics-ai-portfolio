export const meta = {
  name: 'slm-sasr-trialops',
  description: 'Re-assess the 75-component trial-ops stack for on-device SLM + SAS/R, and author + fact-check the wiki content incl. IT enablement',
  phases: [
    { title: 'Assess', detail: 'per-area on-device-SLM feasibility verdicts for all 75 components' },
    { title: 'Verify', detail: 'adversarially challenge over-optimistic verdicts; fact-check authored technical claims' },
    { title: 'Author', detail: 'draft the wiki sections, IT enablement, worked example, and SAS/R-SLM glue spec' },
  ],
}

const INPUT = args.inputPath

const RUBRIC = `
ON-DEVICE SLM REALITY (early 2026) — the honesty backbone. Be skeptical, not promotional.
An "on-device SLM" = a 1-9B-parameter open-weight model, 4-8 bit quantized (GGUF), served LOCALLY by Ollama / llama.cpp / LM Studio on an ordinary workstation or laptop (CPU or a single consumer GPU), fully OFFLINE, no telemetry. Real examples: Llama 3.x 8B/3B, Qwen2.5 7B/3B/1.5B, Phi-3.5-mini / Phi-4-mini, Gemma 2 9B/2B, IBM Granite 3.x 8B/2B.

RELIABLY GOOD (only WITH: RAG grounding + JSON/grammar-CONSTRAINED output + a deterministic SAS/R validator + a narrow prompt):
- short text classification / labeling into a fixed set of buckets
- field / named-entity extraction from a SHORT passage
- routing & triage tagging (which owner/queue/severity bucket)
- near-duplicate / similarity grouping
- short, templated drafting grounded in retrieved text (a query text, a reminder email, a one-line status note, a candidate code for human confirmation)
- yes/no/which-bucket decisions over a small context

UNRELIABLE — do NOT trust a small quantized model with:
- ANYTHING numeric or quantitative (math, counts, reconciliation, stats) — SAS/R owns ALL numbers, always
- multi-document synthesis or long-context reasoning (small models degrade well before their advertised context window)
- nuanced clinical / safety / regulatory narrative or judgement / adjudication
- faithful long summaries; cross-correlating many signals
SLMs hallucinate MORE than frontier models and are MORE sensitive to prompt/format. A bigger-is-better instinct is correct: when the LANGUAGE work needs real reasoning, a 7B quantized model is not enough.

DIVISION OF LABOR (always): SAS/R owns data access, ALL computation/checks/reconciliation/stats, orchestration/scheduling, the validator that checks the SLM's structured output against allowed values, every write, and the audit log. The SLM is a constrained language sidecar that SAS/R calls (PROC HTTP / httr2 -> local 127.0.0.1 Ollama or llama.cpp endpoint) for the language sub-task ONLY, with schema-validated output and a HUMAN GATE before anything touches a record of truth. Reproducibility: pin model name+quantization+digest + decoding (temperature 0, fixed seed) + prompt = a frozen, re-runnable artifact (GAMP-5 / 21 CFR Part 11 friendly). Reported/regulated numbers come only from validated engines (Pinnacle 21, Phoenix WinNonlin, EDC/CTMS) — never the SLM.

VERDICTS (assign exactly one per component):
- "Ready"      = the LANGUAGE sub-task sits squarely in the reliable zone; SAS/R does all the deterministic work; low residual risk behind the human gate. A clean on-device win.
- "Guardrails" = feasible on-device ONLY with tight scaffolding (constrained output + RAG + SAS/R validator + narrow scope + human gate) because the task edges toward longer context, more nuance, or higher stakes; be explicit about the residual hallucination/quality risk.
- "Beyond"     = the language work genuinely needs frontier-level reasoning / long-context synthesis / nuanced narrative a small quantized model can't do reliably. Say whether to keep it DETERMINISTIC SAS/R-ONLY (no SLM at all) or ESCALATE to a larger local or cloud model (out of scope of "on-device SLM").
- "Platform"   = a pure-infrastructure component (gateway, egress firewall/Presidio, audit trail, approval queue, RBAC/secrets, model-freeze registry, the backend servers themselves) that is NOT an SLM language task. Note how the on-device-SLM+SAS/R variant realizes or SIMPLIFIES it (e.g., a single offline local model means there is no cloud egress to firewall — the control becomes "the box stays offline"; the model-agnostic gateway collapses to "SAS/R calls one local endpoint").
`

const ASSESS_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['components'],
  properties: {
    components: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['name', 'slm_verdict', 'slm_role', 'sasr_role', 'note'],
        properties: {
          name: { type: 'string', description: 'EXACT component name as in the input file' },
          slm_verdict: { type: 'string', enum: ['Ready', 'Guardrails', 'Beyond', 'Platform'] },
          slm_role: { type: 'string', description: 'the specific language sub-task the on-device SLM does (or "none" for Beyond-deterministic / Platform)' },
          sasr_role: { type: 'string', description: 'what SAS/R deterministically owns for this component' },
          note: { type: 'string', description: 'one honest sentence: why this verdict, naming the binding constraint (context, numbers, nuance, stakes)' },
        },
      },
    },
  },
}

const AREAS = [
  'Project & Timeline Management', 'eTMF & Document Control', 'Data Validity & Recurrent QC',
  'Trial Monitoring & RBQM', 'The Hybrid Agentic Platform', 'Additional / easily-missed',
]

phase('Assess')
const areaResults = await pipeline(
  [0, 1, 2, 3, 4, 5],
  (i) => agent(
    `You are a biostatistics-informatics architect assessing whether each trial-ops automation can run with an ON-DEVICE SMALL LANGUAGE MODEL paired with SAS/R (no cloud, no big GPU model).
Read the file ${INPUT} (JSON). Focus ONLY on areas[${i}] = "${AREAS[i]}". For EVERY usecase in that area, return a verdict object.
${RUBRIC}
For each component: pick the verdict, state the SLM's exact language sub-task (slm_role), what SAS/R owns (sasr_role), and one honest note naming the binding constraint. Use the EXACT component name from the file. Cover all of them — do not skip any.`,
    { label: `assess:${i}`, phase: 'Assess', schema: ASSESS_SCHEMA }
  ),
  (draft, i) => agent(
    `You are an ADVERSARIAL reviewer. Here is a draft on-device-SLM feasibility assessment for area "${AREAS[i]}":
${JSON.stringify(draft.components)}
Read ${INPUT} (areas[${i}]) to see each component's real work. Your job: REFUTE over-optimistic verdicts and harden the honest ones.
${RUBRIC}
Apply this skeptically:
- Downgrade any "Ready" whose LANGUAGE part actually needs synthesis, long context, nuance, or multi-signal correlation -> "Guardrails" or "Beyond". (If only the NUMERIC part is hard, that's fine — SAS/R owns it — but judge the LANGUAGE task honestly.)
- Confirm each "Guardrails" genuinely needs the scaffolding and is not really "Beyond"; if a small model simply can't do the language task reliably even with guardrails, mark "Beyond" and say keep-deterministic or escalate.
- Make sure every verdict's note names the BINDING constraint and that sasr_role keeps ALL numbers/stats/reconciliation in SAS/R.
- Keep "Platform" for pure infrastructure and make the note explain how the single-offline-model variant simplifies it.
Return the FINAL corrected verdict objects for ALL components in this area (same schema, exact names).`,
    { label: `challenge:${i}`, phase: 'Verify', schema: ASSESS_SCHEMA }
  )
)
const flat = []
areaResults.forEach((r, idx) => { if (r) r.components.forEach(c => flat.push({ ...c, area: AREAS[idx] })) })
log(`assessed ${flat.length} components: ` + ['Ready', 'Guardrails', 'Beyond', 'Platform'].map(v => `${v}=${flat.filter(c => c.slm_verdict === v).length}`).join(' '))

phase('Author')
const SECTION_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['id', 'title', 'html'],
  properties: {
    id: { type: 'string' }, title: { type: 'string' },
    html: { type: 'string', description: 'clean HTML body using ONLY these classes/tags: <h1> <h2> <p> <ul><li> <ol><li> <table><tr><th><td> <code> and <div class="callout warn|tip"> and <div class="flow"><div class="node x"><b></b><span></span></div><div class="arrow">&darr;</div>. No <html>/<head>/<style>. No invented CSS.' },
  },
}
const dist = ['Ready', 'Guardrails', 'Beyond', 'Platform'].map(v => `${v}:${flat.filter(c => c.slm_verdict === v).length}`).join(', ')

const HOUSE = `HOUSE STYLE & HONESTY (match the existing companion wikis): plain, senior, non-promotional, regulator-credible. SAS/R owns every number and validated tools (Pinnacle 21, Phoenix WinNonlin, EDC/CTMS) own every reported/regulated value — the SLM only classifies/extracts/routes/drafts and is always human-gated. Never oversell a small model. This is the early-phase clin-pharm CRO's 75-component trial-ops stack. Verdict distribution found in the assessment: ${dist}.`

const htmlSpecs = [
  { id: 'why', title: 'Why on-device SLM + SAS/R',
    brief: `Make the honest value case for pairing a SMALL on-device open-weight model with SAS/R, vs the cloud-Claude / big-local-GPU hybrid. Strengths: maximum sovereignty (data physically never leaves the workstation -> the simplest possible HIPAA story), no GPU farm / runs on hardware you already own, near-zero marginal cost, trivially frozen for reproducibility, no vendor/network dependency. Be equally honest about the capability ceiling: a small quantized model is a constrained language helper, not a reasoning engine — so SAS/R does all determinism and the SLM does narrow language tasks behind a human gate. End with the one-line framing: "SAS/R owns the truth; the small model just helps with words." Use a callout for the honest headline.` },
  { id: 'envelope', title: "What a small model can and can't do",
    brief: `Author the capability-envelope section. Two clear lists (a "reliable with guardrails" list and a "do NOT trust a small model with" list) drawn from the RUBRIC. Explain: quantization (Q4/Q8 GGUF) and its quality/footprint tradeoff; why constrained/JSON or grammar-restricted output + a SAS/R validator is mandatory; why RAG grounding (retrieve-then-read short context) is what makes small models usable; effective vs advertised context window; determinism (temperature 0 + fixed seed). Include a short callout that ALL numbers stay in SAS/R.` },
  { id: 'architecture', title: 'The SLM + SAS/R architecture',
    brief: `Author the architecture section with a .flow of .node boxes showing: Scheduler/SAS-R job -> deterministic SAS/R work (data, checks, counts, reconciliation) -> SAS/R calls the LOCAL SLM endpoint (127.0.0.1 Ollama/llama.cpp) for the narrow language task with a JSON schema -> SAS/R validator checks the structured output against allowed values -> human approval queue -> write to record + audit log. Emphasize: the SLM is a sidecar SAS/R calls via PROC HTTP / httr2; output is schema-constrained and validated; the model is pinned (name+quant+digest+temp0+seed) = a frozen reproducible artifact; the box stays offline so egress is physically impossible. Note this is the SAME governance as the other companions, just with a small local model instead of cloud Claude.` },
  { id: 'landscape', title: 'Choosing an on-device model',
    brief: `Author a practical model-selection section with a <table> of representative early-2026 on-device open-weight SLMs: columns = Model family | Sizes that run on-device | License & commercial-use note | Good for. Cover at least: Llama 3.x (8B/3B/1B, Llama Community License — review the >700M MAU clause, fine for a CRO), Qwen2.5 (7B/3B/1.5B/0.5B, Apache-2.0), Phi-3.5-mini / Phi-4-mini (~3.8B, MIT), Gemma 2 (9B/2B, Gemma terms — usable, review), IBM Granite 3.x (8B/2B, Apache-2.0, built for enterprise/structured tasks). Guidance: prefer Apache-2.0/MIT to avoid licence friction; pick the SMALLEST model that passes your validation on the task; quantize Q4_K_M for footprint or Q8 for fidelity; favour instruct/structured-output-capable variants. Add a callout: licence + provenance review is an IT/legal gate, not an afterthought. Keep claims defensible and dated "as of early 2026, verify current versions".` },
  { id: 'it_enable', title: 'Standing it up with IT — instructions & hurdles',
    brief: `THIS IS THE FLAGSHIP SECTION (the user explicitly asked for clear instructions AND anticipated hurdles for using SLMs with IT). Two parts.
PART 1 — a numbered, concrete <ol> ENABLEMENT PLAYBOOK to deploy on-device SLMs with the IT department: (1) pick the use cases from the green/amber list and define the language task + output schema; (2) size hardware (CPU-first: a modern workstation runs a 7B Q4 model at usable tokens/sec; add one consumer GPU only where throughput needs it; give rough RAM/VRAM rules of thumb); (3) choose a runtime (Ollama for simplest ops; llama.cpp for embedded/most control; LM Studio for desktop trials; vLLM only if you later need server-grade throughput) and INSTALL it in the locked-down environment (signed releases / internal mirror / container image; pull the model on a connected staging box, checksum it, then transfer the model file to the offline box); (4) wire SAS/R to the local endpoint (PROC HTTP / httr2 -> 127.0.0.1) and add the SAS/R output-validator + human gate; (5) PIN the model (name+quant+digest) + decoding (temp 0, seed) and register it (engine-of-record/model-freeze registry); (6) validate (GAMP-5 risk-based: IQ the install, OQ the pinned model on a fixed test set, PQ on real workflow) and wire the 21 CFR Part 11 audit trail (SAS/R logs prompt+model digest+output+human decision); (7) define the support model (owner, patch cadence, change control) and phase the rollout.
PART 2 — an "ANTICIPATED HURDLES" <table>: columns = Hurdle (what IT/security/QA will raise) | Why it comes up | How to clear it. Cover at least: "we don't allow unknown binaries/downloads" (signed releases, internal artifact mirror, containerize, air-gapped model transfer + checksum); "no GPU budget" (CPU-first small quantized models; GPU only where needed); "is the AI validated / is it deterministic?" (frozen model + temp0/seed + GAMP-5 CSV + human gate; the SLM is decision-support, never the record); "where does the data go?" (nowhere — it's offline on the device; demonstrate by pulling the network cable; this is the EASIEST data-governance story of any AI option); "endpoint/device security" (disk encryption, endpoint management, no model can exfiltrate since it's local & offline, but treat the workstation as a controlled instrument); "open-weight model licensing" (prefer Apache-2.0/MIT; legal reviews the licence + model provenance/safety); "who supports & patches it" (named owner, treat like a qualified analytical tool, change-controlled model registry); "model quality / hallucination" (constrained output + SAS/R validator + RAG + human gate bound the risk; numbers never come from the model); "performance at volume" (batch/schedule off-hours, right-size the model, scale to a GPU host if throughput demands). Add a closing callout: the on-device-SLM story is, paradoxically, the EASIEST for IT/security to approve on data-egress grounds (nothing leaves) while the HARDEST honest constraint is model capability — so scope to narrow, validated language tasks.` },
  { id: 'governance', title: 'Governance & honest limits',
    brief: `Author governance & limits: SAS/R + validated tools own every number/record (RED unchanged); the SLM classifies/extracts/routes/drafts only, always human-gated; frozen model + Part 11 audit trail for reproducibility/inspection; the offline box = zero egress by physics. The HONEST LIMIT callout: a small on-device model is a narrow language helper — it will not synthesize across documents, reason over long context, or write nuanced clinical narrative reliably; those stay deterministic SAS/R or escalate to a larger model. Necessary discipline, not a frontier brain. Validate against a sandbox before production.` },
  { id: 'faq', title: 'FAQ',
    brief: `Author 6-7 FAQ <p><b>Q</b> ... </p> pairs a biostatistician/IT/QA would ask: Is this AI safe for regulated work? Does the small model touch the numbers? How is it different from the cloud-Claude hybrid and the M365 Copilot option? What hardware do we really need? Is it validated / reproducible? What happens to the data? Which model should we start with? Answer honestly and tersely in house voice.` },
]

const authoredHtml = await parallel(htmlSpecs.map(s => () =>
  agent(`Write the wiki section "${s.title}" (id=${s.id}).
${HOUSE}
${RUBRIC}
SECTION BRIEF: ${s.brief}
Return id="${s.id}", the title, and the HTML body.`, { label: `author:${s.id}`, phase: 'Author', schema: SECTION_SCHEMA })
    .then(d => agent(`Adversarially FACT-CHECK and tighten this wiki section for an FDA-credible audience. Refute any overstated small-model capability, any wrong technical claim (model sizes, licences, quantization, runtimes, hardware, GAMP-5/Part 11, Ollama/llama.cpp mechanics), and any drift from the honesty rubric (SAS/R owns all numbers; SLM is human-gated). Fix it and return the CORRECTED full section (same schema, same id="${s.id}").
${RUBRIC}
DRAFT:\n${JSON.stringify(d)}`, { label: `verify:${s.id}`, phase: 'Verify', schema: SECTION_SCHEMA }))
))
const sections = {}; authoredHtml.filter(Boolean).forEach(x => { sections[x.id] = x })

const BEATS_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['title', 'beats'],
  properties: {
    title: { type: 'string' },
    beats: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['n', 'title', 'caption', 'narration'],
      properties: { n: { type: 'number' }, title: { type: 'string' }, caption: { type: 'string', description: '1-2 sentence figure caption' }, narration: { type: 'string', description: '2-4 sentence spoken narration for the video' } } } },
  },
}
const worked = await agent(
  `Design an 8-beat WORKED EXAMPLE: "A morning of on-device triage" on Study CP-101, showing a scheduled SAS/R job + an on-device small model doing the language layer, fully offline on a workstation, no AI in the number path.
${HOUSE}
${RUBRIC}
Concrete, SLM-FEASIBLE scenario: the nightly SAS/R QC run (or Pinnacle 21) produces deterministic findings/discrepancies; the LOCAL small model, called by SAS/R via PROC HTTP to 127.0.0.1, (a) clusters/labels each finding new-vs-known, (b) classifies type/severity/owner, (c) drafts a candidate query text grounded by RAG over the study's specs — all as schema-constrained JSON; SAS/R validates the output against allowed values, drops anything malformed, and assembles a ranked worklist; the biostatistician approves each draft; SAS/R writes the approved queries + a Part 11 audit line with the model digest. Show the offline guarantee (pull the network cable), the human gate, and that the COUNTS/CHECKS came from SAS/R, not the model.
8 beats: 1 title/the loop; 2 the offline on-device setup (workstation + Ollama + pinned model); 3 SAS/R runs the deterministic checks (numbers are SAS/R's); 4 SAS/R calls the local SLM for classification/triage (JSON out); 5 SAS/R validator + RAG-grounded draft query; 6 the human-gated worklist + approve; 7 write + Part 11 audit (model digest pinned) + offline proof; 8 close (what was SLM vs SAS/R vs human). Give each beat n, title, a figure caption, and 2-4 sentence narration.`,
  { label: 'author:worked', phase: 'Author', schema: BEATS_SCHEMA }
)

const SPEC_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['ollama', 'llamacpp', 'decoding', 'structured_output', 'no_egress', 'validator', 'sas_snippet', 'r_snippet', 'pitfalls'],
  properties: {
    ollama: { type: 'string', description: 'exact Ollama local API: endpoint(s), method, JSON request body fields (model, messages/prompt, stream:false, format, options), and where the text is in the response' },
    llamacpp: { type: 'string', description: 'llama.cpp server: the OpenAI-compatible /v1/chat/completions and native /completion, response_format/GBNF grammar for constrained output' },
    decoding: { type: 'string', description: 'how to make it reproducible: temperature 0, seed, num_predict, and pinning model+quant+digest' },
    structured_output: { type: 'string', description: 'how to force JSON/schema output on Ollama (format=<json schema>) and llama.cpp (grammar/response_format) and why it is mandatory' },
    no_egress: { type: 'string', description: 'how SAS/R asserts the endpoint is loopback/offline before use' },
    validator: { type: 'string', description: 'the SAS/R validator pattern: parse the JSON, check every field against an allowlist/enum, reject+log on miss, never trust free text' },
    sas_snippet: { type: 'string', description: 'a short correct PROC HTTP call to Ollama with a JSON body fileref and JSON-libname parse of the response (illustrative, accurate)' },
    r_snippet: { type: 'string', description: 'a short correct httr2 call to the local Ollama endpoint with json body + parse' },
    pitfalls: { type: 'string', description: 'real gotchas: streaming must be off, model must be pulled first, context limits, JSON sometimes wrapped in prose if not constrained, quantization affects adherence' },
  },
}
const helper = await agent(
  `You are an engineer who has wired SAS and R to a LOCAL Ollama / llama.cpp server. Provide the ACCURATE mechanics so a macro library can be written. Be correct and specific, not hand-wavy. The endpoint is on 127.0.0.1, fully offline. SAS uses PROC HTTP + the JSON LIBNAME engine; R uses httr2 + jsonlite. Output must be schema-constrained JSON, decoding must be reproducible (temp 0 + seed), and a SAS/R validator must check every field against an allowlist. Fill every field of the schema with correct, current (early 2026) detail.`,
  { label: 'author:helper-spec', phase: 'Author', schema: SPEC_SCHEMA }
)

return { assessments: flat, distribution: dist, sections, worked, helper }
