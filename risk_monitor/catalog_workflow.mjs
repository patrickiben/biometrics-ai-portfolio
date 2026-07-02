export const meta = {
  name: 'risk-earlywarning-catalog',
  description: 'Map the signal catalog for a 3-tier trial-termination early-warning dashboard (participant / study / client) on a hybrid M365 Copilot + on-device local LLM',
  phases: [
    { title: 'Catalog', detail: 'parallel: participant-level, study-level, client-level signals + the dashboard platform' },
    { title: 'Completeness', detail: 'adversarial — what early-warning signals are missing?' },
  ],
}

const SIGNAL = {
  type: 'object',
  properties: {
    tier: { type: 'string' },
    facts: { type: 'array', items: { type: 'string' }, description: '5-9 grounding facts: methods/standards (DLT & dose-escalation designs 3+3/BOIN/mTPI-2/CRM, ICH E6(R3) RBQM KRIs/QTLs, central statistical monitoring, sponsor-risk indicators) and the hybrid routing' },
    signals: {
      type: 'array',
      description: 'up to 14 early-warning signals',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          category: { type: 'string', description: 'Safety / PK-PD / Enrollment / Quality / Operational / Commercial / Financial ...' },
          signal: { type: 'string', description: 'what the early-warning detects' },
          data_source: { type: 'string', description: 'EDC / safety DB / IXRS / labs / ECG / CTMS / Smartsheet / finance-AR / CRM / sponsor comms ...' },
          detection: { type: 'string', description: 'rule-based / statistical / model-assisted — HOW it is detected, and what the AI does vs the validated tool/human' },
          engine: { type: 'string', description: 'On-device local LLM (subject-level, zero egress) / Cloud M365 Copilot (non-sensitive) / Validated tool + human' },
          threshold: { type: 'string', description: 'the trigger / KRI / QTL / stopping-rule that fires the early warning' },
          action: { type: 'string', description: 'the escalation — to SRC/DSMB/medical monitor / PM / account lead' },
          severity: { type: 'string', description: 'what termination risk it indicates (the RAG meaning)' },
        },
        required: ['name', 'category', 'signal', 'engine', 'threshold', 'action'],
      },
    },
  },
  required: ['tier', 'signals'],
}

const BASE = [
  'CONTEXT: An early-phase clinical-pharmacology (Phase 1 FIH SAD/MAD, dose-escalation) biometrics/clin-ops team building a TRIAL-TERMINATION EARLY-WARNING dashboard across three tiers: PARTICIPANT-level, STUDY-level, and CLIENT/sponsor-level. On a HYBRID of M365 Copilot Premium (CLOUD — for non-sensitive operational & commercial signals) and ON-DEVICE LOCAL LLMs (for sensitive subject-level safety/PK data — zero egress, never leaves the device/validated environment).',
  'GOVERNANCE (apply to every signal): the AI DETECTS, AGGREGATES, TRIAGES, and EXPLAINS early-warning signals and drafts the alert — it never makes the safety/termination DECISION. Validated tools + the medical monitor / Safety Review Committee (SRC) / DSMB make safety & DLT determinations; the PM and the sponsor make study/contract decisions; humans own every call. Subject-level safety/PK/unblinded data -> ON-DEVICE LOCAL model only (zero egress). Non-sensitive operational/commercial/portfolio data -> CLOUD M365 Copilot. 21 CFR Part 11 audit + ALCOA++. Reported safety numbers come from the validated safety database, never an LLM.',
  'You may web-search to confirm current methods (DLT definitions & dose-escalation designs, ICH E6(R3) RBQM / KRIs / QTLs, central statistical monitoring, predictive trial early-warning, sponsor/CRO commercial-risk indicators) — but prioritize a COMPLETE, accurate, clinically-correct catalog.',
].join('\n');

phase('Catalog')
const tiers = [
  { label: 'participant', name: 'Participant-level', prompt: 'Catalog PARTICIPANT-LEVEL early-termination & safety early-warning signals for early-phase dose-escalation. Include at least: DLTs (dose-limiting toxicities) during the DLT-evaluation window in dose escalation (note the design — 3+3 / BOIN / mTPI-2 / CRM / accelerated titration — and sentinel dosing); emerging individual AE/SAE clusters & severity-grade escalation (CTCAE); SAE / death / life-threatening events; lab shifts & Hy\'s Law (drug-induced liver injury) signals; ECG / QTcF prolongation thresholds; PK exposure outliers — supra-threshold Cmax/AUC, unexpected accumulation, exposure exceeding the safety margin / NOAEL-scaled limit; vital-sign / hemodynamic events; immunogenicity / infusion reactions; individual withdrawal / dropout / non-compliance; eligibility-violation & individual stopping-criteria breaches. For each fill the schema — subject-level data routes to the ON-DEVICE local model; the SRC / medical monitor makes the DLT/safety call (the AI flags & aggregates EARLY, before the formal cohort review). Return tier="Participant-level".' },
  { label: 'study', name: 'Study-level', prompt: 'Catalog STUDY-LEVEL early-termination risk early-warning signals. Include at least: cohort-level DLT RATE vs the dose-escalation stopping/de-escalation rule (excess toxicity -> dose-escalation termination / MTD reached early / stop); enrollment lag & screen-failure rate & recruitment KRIs vs plan; futility signals; SAFETY QUALITY TOLERANCE LIMIT (QTL) breaches (ICH E6(R3)); aggregate safety trends (AE/SAE rate vs background, lab/ECG cohort shifts); data-quality KRIs (query rate/aging, missing data, protocol-deviation trend, randomization/IXRS issues); site/operational performance; data-integrity / central statistical-monitoring signals (digit preference, outliers, site anomalies); timeline slip vs critical milestones; budget burn vs milestones; probability of meeting the primary objective. For each fill the schema (engine: cloud Copilot for de-identified aggregate KRIs; local for any subject-level drill-down; validated tools + DSMB/SRC + PM for decisions). Return tier="Study-level".' },
  { label: 'client', name: 'Client / Sponsor-level', prompt: 'Catalog CLIENT / SPONSOR-LEVEL early-termination (COMMERCIAL) risk early-warning signals — the CRO\'s early warning that a sponsor may cancel, de-scope, or not renew the program. Include at least: accounts-receivable / payment aging & invoice disputes; change-order / scope-reduction / hold trend; communication cadence drop & sentiment decline (emails/meetings); milestone disputes & escalations; sponsor PIPELINE reprioritization / portfolio cuts; sponsor FINANCIAL health & funding runway (for public sponsors: cash runway, going-concern, layoffs, stock signal) & M&A / acquisition; competitive readouts or a failed adjacent program affecting this asset; contract end-date / renewal window & option-exercise signals; relationship / governance-meeting risk flags; KOL / strategy pivots. For each fill the schema — this is mostly NON-SENSITIVE business/portfolio data routed to CLOUD M365 Copilot (CRM, finance/AR, sponsor comms, public filings via web), with the account/BD lead owning the call. Be honest that this tier is signal/triage support for the account team, not a verdict. Return tier="Client / Sponsor-level".' },
  { label: 'platform', name: 'The dashboard platform', prompt: 'Describe the dashboard PLATFORM (fill the schema "signals" array as platform/dashboard CAPABILITIES, one per item). Include at least: the ON-DEVICE local LLM backend (subject-level safety/PK, zero egress) and the M365 Copilot cloud backend (non-sensitive ops/commercial) and the routing rule; the data connectors (EDC / safety DB / IXRS / central-lab / ECG / CTMS / Smartsheet / finance-AR / CRM / sponsor comms / web for public filings); the 3-tier RAG dashboard view (Participant / Study / Client risk panels with red-amber-green status, top-signals, trend sparklines, drill-down); the scoring / aggregation layer (how individual signals roll up to a tier risk level — weighted KRIs, not an autonomous verdict); the alerting & escalation routing (SRC / DSMB / medical monitor for safety; PM for study; account/BD lead for client); the human-acknowledgement / disposition log; the Part-11 audit trail; refresh cadence (near-real-time safety, daily ops, weekly commercial). For each give category, engine, threshold (n/a), action, severity (n/a). Return tier="Platform".' },
]
const catalogs = (await parallel(tiers.map(t => () => agent(BASE + '\n\n' + t.prompt, { schema: SIGNAL, label: t.label, phase: 'Catalog' })))).filter(Boolean)

phase('Completeness')
const flat = catalogs.flatMap(c => (c.signals || []).map(s => '[' + c.tier + '] ' + s.name))
const MISS = { type: 'object', properties: { missing: { type: 'array', items: { type: 'object', properties: { tier: { type: 'string' }, name: { type: 'string' }, category: { type: 'string' }, signal: { type: 'string' }, data_source: { type: 'string' }, detection: { type: 'string' }, engine: { type: 'string' }, threshold: { type: 'string' }, action: { type: 'string' }, severity: { type: 'string' } }, required: ['tier', 'name', 'category', 'signal', 'engine'] } } }, required: ['missing'] }
const crit = await agent(BASE + '\n\nYou audit a 3-tier trial-termination early-warning signal catalog for COMPLETENESS. Below is the current list. Identify GENUINELY MISSING early-warning signals an early-phase team would want — think of easily-missed ones: pharmacovigilance SUSAR / expedited-reporting clock breaches; aggregate benefit-risk / emerging-safety-profile shift; bioanalytical assay failure / sample-integrity affecting PK; cohort-expansion / RP2D decision risk; IDMC/DSMB recommendation-to-stop; regulatory hold / clinical-hold / IND safety-report signal; protocol-amendment churn; supply / IP (drug) shortage or expiry; lab/ECG vendor failure; informed-consent re-consent triggers; data-monitoring-committee meeting cadence; cross-study safety signal for the same compound; site for-cause audit findings; sponsor merger closing; competitive drug approval/failure; FX / contract-currency exposure. Return ONLY genuinely missing items (do not repeat). Up to ~15.\n\nCURRENT LIST:\n' + flat.join('\n'), { schema: MISS, label: 'completeness', phase: 'Completeness' })

return { catalogs, missing: crit.missing }
