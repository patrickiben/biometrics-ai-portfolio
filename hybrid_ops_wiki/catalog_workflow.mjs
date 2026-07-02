export const meta = {
  name: 'hybrid-ops-catalog',
  description: 'Map the comprehensive use-case catalog for a hybrid Claude+Local agentic trial-operations / project-management / monitoring layer (QC checks, SOP/doc RAG ingestion, eTMF filing, Smartsheet/timeline automation, RBQM)',
  phases: [
    { title: 'Catalog', detail: 'parallel: PM/timeline, eTMF/docs, data-QC, monitoring/RBQM, the agentic platform' },
    { title: 'Completeness', detail: 'adversarial — what trial-ops automations are missing?' },
  ],
}

const USECASE = {
  type: 'object',
  properties: {
    area: { type: 'string' },
    facts: { type: 'array', items: { type: 'string' }, description: '5-10 grounding facts: current tools/standards (TMF Reference Model, ICH E6(R3) RBQM, Smartsheet API, LiteLLM gateway, RAG, Pinnacle 21, MCP) and how they fit' },
    usecases: {
      type: 'array',
      description: 'up to 12 concrete automations/agents',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          trigger: { type: 'string', description: 'scheduled / event / on-demand — what fires it' },
          what_ai_does: { type: 'string', description: 'what the agent does (draft/classify/triage/route/summarize) vs what stays human/validated tool' },
          engine: { type: 'string', description: 'Local frozen model / Cloud Claude / Validated tool / Local+Cloud' },
          integration: { type: 'string', description: 'systems touched: eTMF (Veeva), Smartsheet, EDC, SharePoint, Outlook, Pinnacle 21, RAG store…' },
          tier: { type: 'string', description: 'GREEN / AMBER / RED' },
          human: { type: 'string', description: 'human-in-the-loop checkpoint' },
          value: { type: 'string', description: 'the payoff' },
        },
        required: ['name', 'what_ai_does', 'engine', 'tier'],
      },
    },
  },
  required: ['area', 'usecases'],
}

const BASE = [
  'CONTEXT: An in-house biometrics + clin-ops function at a CRO running early-phase clinical-pharmacology studies, building an OPERATIONS layer on the HYBRID Claude+Local AI stack: a self-hosted model-agnostic gateway (LiteLLM-class, OpenAI-compatible) fronting (a) a LOCAL frozen open-weight model on a GPU workstation (for sensitive/PHI/unblinded data, zero egress, air-gapped) and (b) the CLOUD Claude API under BAA (for hard, non-sensitive reasoning on de-identified text). Plus a RAG knowledge base (SOPs/WIs/study docs) and connectors.',
  'GOVERNANCE (apply to every use case): route by data sensitivity (PHI/unblinded -> LOCAL; de-identified -> CLOUD); reported/regulated numbers ALWAYS from a validated tool (Pinnacle 21 for conformance, Phoenix WinNonlin for PK, the EDC/CTMS of record), never an LLM; humans approve any change to a regulated record/timeline; 21 CFR Part 11 audit trail + ALCOA++; the LLM drafts/classifies/triages/routes/summarizes — it does not autonomously alter records. Tiers: GREEN (drafts/summaries/RAG answers), AMBER (classification/triage/code with human verify), RED (anything touching reported numbers, eTMF record-of-truth, or unblinded data -> validated tool + human, LLM out of the decision path).',
  'You may use web search to confirm current tool/standard names (DIA TMF Reference Model, ICH E6(R3) RBQM/KRIs/QTLs, Smartsheet API, LiteLLM, Pinnacle 21, MCP) — but prioritize a COMPLETE, accurate catalog over research depth.',
].join('\n');

phase('Catalog')
const areas = [
  { label: 'pm-timeline', name: 'Project & Timeline Management', prompt: 'Catalog automations for PROJECT & TIMELINE MANAGEMENT across the study lifecycle. Include at least: milestone & critical-path tracking; automated Smartsheet timeline updates + notifications on study events (data cut, lock, milestone slip); status-report generation; action-item & decision tracking from email/meetings; meeting agendas & minutes; vendor/CRO oversight & deliverable tracking; resourcing/capacity; risk register upkeep; budget/PO tracking; cross-study portfolio rollups. For each, fill the schema (trigger, what_ai_does, engine, integration, tier, human, value). Smartsheet automations should note the Smartsheet API + a gateway agent that recomputes the plan and posts notifications.' },
  { label: 'etmf-docs', name: 'eTMF & Document Control', prompt: 'Catalog automations for eTMF & DOCUMENT CONTROL. Include at least: auto-classify & file documents to the DIA TMF Reference Model zones/artifacts; TMF completeness/QC & missing-document detection; expiring-document (CV/training/license) alerts; SOP/WI/study-specific document INGESTION into a RAG knowledge base; compliance Q&A over SOPs ("what does SOP-12 require for X?"); version/superseded-document control; inspection-readiness gap analysis; redaction/PII detection before any cloud use. Fill the schema. eTMF record-of-truth filing is RED/AMBER (human approves final filing); RAG Q&A is GREEN.' },
  { label: 'data-qc', name: 'Data Validity & Recurrent QC', prompt: 'Catalog RECURRENT DATA-VALIDITY QC automations that run at EVERY stage of the study. Include at least: scheduled CDISC conformance (Pinnacle 21) on SDTM/ADaM with AI triage of findings; cross-form / edit-check / logical-consistency checks; PK timing (actual vs nominal) & BLQ/LLOQ rule checks; lab/IXRS/PK-sample reconciliation; query-management oversight & aging; duplicate/outlier/range checks; data-quality KRIs & trend dashboards; pre-lock data-review listings; discrepancy triage & routing to DM. Fill the schema. Be explicit: validated tools (Pinnacle 21) produce pass/fail; the LLM triages, explains, drafts the finding, and routes — subject-level data stays on the LOCAL model.' },
  { label: 'monitoring-rbqm', name: 'Trial Monitoring & RBQM', prompt: 'Catalog TRIAL MONITORING & RISK-BASED QUALITY MANAGEMENT automations (ICH E6(R3)). Include at least: KRI/QTL definition & threshold-breach signal detection; central/statistical monitoring signals (site outliers, digit preference, enrollment/visit anomalies); protocol-deviation surveillance & classification; safety signal triage (AE/SAE volume, lab shifts); site performance & enrollment metrics; CAPA tracking; DSMB/safety-review packet assembly; monitoring-visit report (MVR) summarization & follow-up tracking; QTL dashboard upkeep. Fill the schema. Note: unblinded/subject-level signals -> LOCAL model; reported safety numbers -> validated tools + medical review (RED).' },
  { label: 'platform', name: 'The Hybrid Agentic Platform', prompt: 'Describe the PLATFORM that runs all of the above, as a set of components/capabilities (fill schema usecases as platform capabilities). Include at least: the LiteLLM-class gateway (routing by data-classification, PII/PHI guardrails via Presidio, per-model cost/audit, caching); the LOCAL vLLM model + the CLOUD Claude API backends; the RAG knowledge base over SOPs/WIs/study docs (local vector store, permissioned); the orchestration layer (scheduled jobs / agent framework / n8n / Power Automate / cron+Python) that fires the agents; connectors/tools (eTMF API, Smartsheet API, EDC, CTMS, SharePoint, Outlook, Pinnacle 21) — possibly via MCP; the audit/observability layer (one unified Part 11 trail); the human-in-the-loop approval queue; model-freeze & engine-of-record registry. For each, give trigger="n/a (always-on)" where appropriate, engine, integration, tier, human, value.' },
]
const catalogs = (await parallel(areas.map(a => () => agent(BASE + '\n\n' + a.prompt + '\n\nReturn area="' + a.name + '".', { label: a.label, phase: 'Catalog', schema: USECASE })))).filter(Boolean)

phase('Completeness')
const flat = catalogs.flatMap(c => (c.usecases || []).map(u => '[' + c.area + '] ' + u.name))
const MISS = { type: 'object', properties: { missing: { type: 'array', items: { type: 'object', properties: { area: { type: 'string' }, name: { type: 'string' }, trigger: { type: 'string' }, what_ai_does: { type: 'string' }, engine: { type: 'string' }, integration: { type: 'string' }, tier: { type: 'string' }, human: { type: 'string' }, value: { type: 'string' } }, required: ['area', 'name', 'what_ai_does', 'engine', 'tier'] } } }, required: ['missing'] }
const crit = await agent(BASE + '\n\nYou audit a hybrid-AI trial-operations automation catalog for COMPLETENESS. Below is the current list. Identify GENUINELY MISSING automations across project management, trial management, monitoring, document control, and data QC that an early-phase CRO would want — think of easily-missed ones: informed-consent version tracking; site activation/feasibility; IP/drug accountability & reconciliation; randomization/IXRS oversight; lab manual & kit management; translation/localization control; regulatory submission tracking (IND/CTA, annual reports); audit/inspection logistics; training-compliance tracking; newsletter/sponsor-update drafting; lessons-learned capture; meeting-action SLA chasing; contract/CDA tracking; data-transfer (DTA) scheduling & receipt confirmation; safety reporting timelines (SUSAR clocks). Return ONLY genuinely missing items (do not repeat). Up to ~15.\n\nCURRENT LIST:\n' + flat.join('\n'), { label: 'completeness', phase: 'Completeness', schema: MISS })

return { catalogs, missing: crit.missing }
