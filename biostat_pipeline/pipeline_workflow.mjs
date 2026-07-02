export const meta = {
  name: 'biostat-pipeline-map',
  description: 'Map the COMPLETE early-phase clin-pharm biostatistics deliverables pipeline (Protocol review -> CSR Draft): every document, dataset, and biostat output, with owner/inputs/outputs/standards/QC and the hybrid-AI routing overlay',
  phases: [
    { title: 'Map stages', detail: 'parallel: deliverables for each stage (design, planning, data/CDISC, analysis, reporting)' },
    { title: 'Completeness', detail: 'adversarial — what is missing from the deliverables map?' },
    { title: 'Synthesize', detail: 'ordered register + comprehensive document + visual pipeline stages' },
  ],
}

const DELIV = {
  type: 'object',
  properties: {
    stage: { type: 'string' },
    deliverables: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          deliverable: { type: 'string' },
          type: { type: 'string', description: 'Document / Specification / Dataset / Output (TLF) / Plan / Code / Review / Meeting output' },
          description: { type: 'string' },
          owner: { type: 'string', description: 'primary owner (Lead biostatistician / Stat programmer / PK scientist / Data mgmt / Medical writer / Pharmacometrician)' },
          inputs: { type: 'string' },
          outputs: { type: 'string', description: 'what it feeds downstream' },
          standard: { type: 'string', description: 'governing standard/regulation (CDISC SDTMIG/ADaMIG/Define-XML, ICH E3/E9/E9(R1)/M11/E6(R3), 21 CFR Part 11, etc.)' },
          qc: { type: 'string', description: 'QC/validation method (independent double-programming, conformance check, peer review, etc.)' },
          ai_tier: { type: 'string', description: 'Green / Amber / Red (Model Risk = influence x consequence)' },
          ai_engine: { type: 'string', description: 'Local / Cloud / Local+Cloud / Validated engine only (no LLM)' },
          ai_use: { type: 'string', description: 'what AI assists with vs. what stays human / validated engine' },
        },
        required: ['deliverable', 'type', 'description', 'owner', 'ai_tier', 'ai_engine'],
      },
    },
  },
  required: ['stage', 'deliverables'],
}

const BASE = [
  'CONTEXT: Early-phase clinical pharmacology (Phase 1) — e.g., First-in-Human SAD/MAD, with PK/PD focus, NCA + popPK/exposure-response, safety; may include food-effect, DDI, QT/TQT, bioavailability/bioequivalence, special-population substudies.',
  'STANDARDS BASELINE (current mid-2026; use these): CDISC SDTMIG v3.4, ADaMIG v1.3, Define-XML v2.1, Controlled Terminology; ICH E3 (CSR structure), ICH E9 + E9(R1) estimands, ICH M11 (CeSHarP protocol template, final), ICH E6(R3) GCP, 21 CFR Part 11, ALCOA++; Pinnacle 21 / CDISC conformance; Phoenix WinNonlin (validated NCA); NONMEM/Monolix (popPK). Reviewer guides: cSDRG (SDTM) and ADRG (ADaM).',
  'HYBRID-AI OVERLAY (from our design): route by data sensitivity first — PHI/unblinded/subject-level -> LOCAL frozen open-weight model (zero egress); hard non-sensitive reasoning on de-identified text/specs -> CLOUD Claude (API + BAA). Reported numbers ALWAYS come from a validated engine (Phoenix WinNonlin for NCA), never an LLM. Independent double-programming mandatory. Risk tiers: GREEN (drafts/scaffolds/docs), AMBER (dataset/TLF code, AI as one side of double-programming), RED (reported numbers, submission datasets, unblinding-adjacent — validated engine + human, LLM out of the path).',
].join('\n');

phase('Map stages')
const stages = [
  { label: 'design-protocol', name: 'Stage 1 — Study Design & Protocol', prompt: 'List ALL biostatistics deliverables in the STUDY DESIGN & PROTOCOL stage of an early-phase clin-pharm study. Include at least: biostatistics input to the protocol (design rationale; objectives -> estimands -> endpoints per ICH E9(R1); statistical considerations / analysis-overview section; populations/analysis sets); sample-size / power justification (or documented rationale for no formal sizing in FIH, with PK precision/CV considerations); randomization design & specification (incl. sentinel dosing, cohort/dose-escalation rules); DSMB/SRC/SEC statistical decision rules & dose-escalation criteria; interim/adaptive design elements if any; estimand framework; biostatistician protocol review & sign-off; design-stage simulation (e.g., dose-escalation operating characteristics). For each, fill the schema (owner, inputs, outputs, standard, qc, ai_tier, ai_engine, ai_use). Be complete and accurate to real Phase 1 practice.' },
  { label: 'planning-spec', name: 'Stage 2 — Planning & Specifications', prompt: 'List ALL biostatistics deliverables in the PLANNING & SPECIFICATIONS stage. Include at least: Statistical Analysis Plan (SAP); TLF shells / mock-up shells (table, listing, figure templates with titles/footnotes/dummy values); ADaM dataset specifications (ADSL, ADPC, ADPP, ADAE, ADLB, ADVS, ADEG, ADPD, etc.); SDTM mapping specification & annotated CRF (aCRF) review; programming specifications / derivation specs; randomization schedule generation + unblinding/code-break plan; Data Review Plan / blinded data-review plan; PK analysis plan detail (NCA parameter list, BLQ/LLOQ handling rules, nominal vs actual time, exclusion rules); popPK / exposure-response analysis plan (separate modelling analysis plan); Define-XML planning; validation / QC plan (independent double-programming strategy); pseudo/dummy data for shell testing; analysis-set definitions. Fill the schema for each.' },
  { label: 'data-cdisc', name: 'Stage 3 — Data & CDISC', prompt: 'List ALL biostatistics-relevant deliverables in the DATA & CDISC stage (raw data to database lock). Include at least: EDC/raw data extracts & data-transfer agreements interface; biostat review of edit checks / data queries / data-review listings; SDTM datasets (DM, PC, PP, AE, LB, VS, EG, EX, DS, MH, CM, PD/DV...); annotated CRF (aCRF); SDTM Define-XML; SDTM Reviewer Guide (cSDRG); ADaM datasets (ADSL, ADPC, ADPP, ADAE, ADLB, ADVS, ADEG, ADPD...); ADaM Define-XML; ADaM Reviewer Guide (ADRG); CDISC conformance / validation (Pinnacle 21) report; PK bioanalytical sample reconciliation (concentration data load, BLQ handling); blinded data review outputs; dry-run datasets; data-cleaning / soft lock; database hard lock; traceability (raw->SDTM->ADaM). Fill the schema for each. Note where AI is RED (submission datasets must be validated/double-programmed) vs AMBER (mapping/derivation code drafts).' },
  { label: 'analysis-qc', name: 'Stage 4 — Analysis & QC', prompt: 'List ALL biostatistics deliverables in the ANALYSIS & QC stage. Include at least: production of TLFs by domain — disposition; demographics & baseline; exposure/dosing & compliance; protocol deviations; PK concentration summary tables + mean concentration-time figures (linear/semilog); PK parameter (NCA) summary tables (Cmax, Tmax, AUC, t1/2, CL/F, Vz/F); dose-proportionality & accumulation; food-effect / DDI / relative BA-BE (ANOVA, 90% CI, GMR) if applicable; QT/QTc (concentration-QTc) if applicable; safety — TEAEs, deaths/SAEs, labs, vitals, ECG, physical exam; PD endpoints; immunogenicity/ADA if applicable; exploratory analyses. ALSO: NCA execution in validated Phoenix WinNonlin; popPK / exposure-response modelling (NONMEM/Monolix) with run records; statistical analysis execution; INDEPENDENT DOUBLE-PROGRAMMING QC + reconciliation; blinded/blind data review meeting & decisions; unblinding/code-break execution; QC documentation / validation records. Fill the schema for each — be explicit that reported PK numbers come from Phoenix (validated engine), not an LLM.' },
  { label: 'reporting-csr', name: 'Stage 5 — Reporting & CSR', prompt: 'List ALL biostatistics deliverables in the REPORTING & CSR stage. Include at least: CSR Statistical Methods section (per ICH E3); CSR Results — in-text summary tables & figures; biostatistician contribution to / review of the CSR draft (synopsis stats, efficacy/PK/safety results text, consistency QC); CSR appendices — 16.1.9 (documentation of statistical methods incl. final SAP), 16.2 data listings, Define-XML + reviewer guides as appendices/submission; patient narrative data support; subject (patient) profiles; datasets + analysis programs as submission/regulatory deliverables (with ADRG/cSDRG); traceability matrix; QC of CSR-vs-TLF-vs-dataset numerical consistency; statistical input to clinical study synopsis & any briefing documents. Fill the schema for each. Note AI use: drafting methods text / narratives over de-identified content (CLOUD), summarizing — but reported numbers and final outputs stay validated-engine + human.' },
]
const mapped = (await parallel(stages.map(st => () => agent(BASE + '\n\n' + st.prompt + '\n\nReturn stage="' + st.name + '".', { label: st.label, phase: 'Map stages', schema: DELIV })))).filter(Boolean)

phase('Completeness')
const flat = mapped.flatMap(m => (m.deliverables || []).map(d => '[' + m.stage + '] ' + d.deliverable));
const MISSING = { type: 'object', properties: { missing: { type: 'array', items: { type: 'object', properties: { stage: { type: 'string' }, deliverable: { type: 'string' }, type: { type: 'string' }, description: { type: 'string' }, owner: { type: 'string' }, inputs: { type: 'string' }, outputs: { type: 'string' }, standard: { type: 'string' }, qc: { type: 'string' }, ai_tier: { type: 'string' }, ai_engine: { type: 'string' }, ai_use: { type: 'string' } }, required: ['stage', 'deliverable', 'type', 'description'] } } }, required: ['missing'] }
const crit = await agent(BASE + '\n\nYou are a meticulous biometrics QA lead auditing a deliverables map for COMPLETENESS. Below is the current list of deliverables across the Protocol->CSR pipeline. Identify what is MISSING or under-specified for a real, inspection-ready early-phase clin-pharm study. Think about cross-cutting and easily-missed items: estimand/SAP amendments & version control; blinded sample-size re-estimation; interim analyses & DSMB outputs; bioanalytical/PK sample reconciliation; randomization QC & emergency unblinding; protocol-deviation classification; analysis-population derivation; TLF validation/QC documentation & discrepancy logs; Define-XML/value-level metadata; controlled terminology; data-transfer specs; reviewer guides; submission package assembly (eCTD m5); audit trail / 21 CFR Part 11 records; pharmacometrics analysis report; data review meeting minutes; software validation / environment qualification; risk-based QC; and the hybrid-AI governance artifacts (data-classification routing log, engine-of-record per deliverable, model freeze records, prompt/output retention). Return ONLY genuinely missing items as structured deliverables (do not repeat ones already present).\n\nCURRENT LIST:\n' + flat.join('\n'), { label: 'completeness-critic', phase: 'Completeness', schema: MISSING })

const allDelivs = [];
mapped.forEach(m => (m.deliverables || []).forEach(d => allDelivs.push({ ...d, stage: m.stage })));
(crit.missing || []).forEach(d => allDelivs.push(d));

phase('Synthesize')
const SYNTH = {
  type: 'object',
  properties: {
    register: { type: 'array', description: 'the full, de-duplicated, logically-ordered deliverables register', items: { type: 'object', properties: { id: { type: 'string', description: 'e.g. S1-01' }, stage: { type: 'string' }, deliverable: { type: 'string' }, type: { type: 'string' }, description: { type: 'string' }, owner: { type: 'string' }, inputs: { type: 'string' }, outputs: { type: 'string' }, standard: { type: 'string' }, qc: { type: 'string' }, ai_tier: { type: 'string' }, ai_engine: { type: 'string' }, ai_use: { type: 'string' } }, required: ['id', 'stage', 'deliverable', 'type', 'owner', 'ai_tier', 'ai_engine'] } },
    document_markdown: { type: 'string', description: 'comprehensive reference document (markdown) — intro, pipeline overview, one section per stage WITH a markdown table of its deliverables, the CDISC dataset inventory, the TLF inventory, the hybrid-AI routing overlay, governance/validation, and a sequence/dependency narrative' },
    pipeline_stages: { type: 'array', description: '5 stages for a visual map', items: { type: 'object', properties: { stage: { type: 'string' }, key_deliverables: { type: 'array', items: { type: 'string' } }, gate: { type: 'string', description: 'the milestone/lock that ends the stage' } }, required: ['stage', 'key_deliverables', 'gate'] } },
  },
  required: ['register', 'document_markdown', 'pipeline_stages'],
}
const synthesis = await agent('You are the lead biostatistician assembling the definitive end-to-end deliverables pipeline for an early-phase clinical pharmacology study (Protocol review -> CSR Draft), to be used as the operational map for an in-house, hybrid-AI biometrics function. De-duplicate and logically ORDER the deliverables below into a clean register with stable ids (S1-01, S1-02, ... S5-nn), grouped by the 5 stages (Design & Protocol; Planning & Specifications; Data & CDISC; Analysis & QC; Reporting & CSR). Fill any gaps in fields (owner, inputs, outputs, standard, qc, ai_tier, ai_engine, ai_use) consistently and accurately. Then write a COMPREHENSIVE reference document_markdown: intro + how to read it; an end-to-end overview with the 5 stages and their gates (protocol approval -> SAP/specs final -> database lock -> outputs QC-passed -> CSR draft); one section per stage, each containing a markdown TABLE (columns: ID | Deliverable | Type | Owner | Standard | QC | AI tier/engine) plus brief narrative on sequence and dependencies; a CDISC dataset inventory (SDTM + ADaM, with reviewer guides + define.xml); a TLF inventory by domain; the HYBRID-AI ROUTING OVERLAY (which deliverables run local vs cloud vs validated-engine-only, with the 3 hard rules); a VALIDATION & GOVERNANCE section (double-programming, Part 11/ALCOA++, engine-of-record, model freeze, audit); and a one-paragraph closing. Keep it accurate to real CDISC/ICH practice and consistent with the standards baseline. Also return pipeline_stages (5) for a visual map. Be thorough.\n\nSTANDARDS BASELINE:\n' + BASE + '\n\nDELIVERABLES (raw, to de-dupe/order/complete):\n' + JSON.stringify(allDelivs), { label: 'synthesize', phase: 'Synthesize', schema: SYNTH })

return { mapped, missing: crit.missing, register: synthesis.register, document_markdown: synthesis.document_markdown, pipeline_stages: synthesis.pipeline_stages }
