// Narration for the "a day on the trial-ops platform" worked example (one entry per slide).
module.exports = [
  // 1 title
  "Let me walk through a single day on the hybrid trial-ops platform. Five automations fire across the day — recurrent QC, SOP knowledge, eTMF filing, a timeline cascade, and risk-based monitoring. Every one follows the same shape: a trigger, an AI-drafted proposal, and a human who approves. Nothing reaches a validated system of record without that approval.",
  // 2 the rule
  "That is the rule across all seventy-five automations on the platform. The agent drafts a proposal into a human-approval queue; nothing is filed, sent, or changed in a validated system until a human approves it. And the same sensitivity routing applies — participant-level data stays on the local model; non-sensitive work goes to cloud.",
  // 3 QC
  "Eight a.m. The nightly QC run catches a data discrepancy — an adverse-event onset date that falls after its resolution date, for one participant. Because it is participant-level data, the agent drafts the data query on the local model, zero egress — a clear, specific query citing the fields and the rule. The data manager reviews it, edits if needed, and issues it in the validated EDC. The agent never writes to the EDC itself.",
  // 4 SOP
  "Ten-thirty. A CRA asks: what is our process for a missed PK sample? The assistant is grounded on the SOP library — non-sensitive, so cloud. It answers in plain language and cites the exact SOP and version. The CRA checks the cited SOP before acting; the controlled document stays the source of truth, not the model's paraphrase.",
  // 5 eTMF
  "One p.m. A monitoring visit report lands in the shared drive. The agent classifies it against the TMF reference model, proposes the filing location, and pre-fills the metadata — on the non-sensitive document. Nothing is filed yet: the TMF specialist confirms the classification and files it in the validated eTMF. The proposal is a draft in the approval queue.",
  // 6 Smartsheet
  "Three p.m. A confirmed change — the data cut moves from the seventeenth to the nineteenth — means downstream dates must shift. The agent computes the dependent cascade: soft-lock, dry-run TLFs, the DSMB pack, and drafts the Smartsheet update and a notification. The project manager reviews, adjusts, and applies it. The PM owns the timeline.",
  // 7 RBQM
  "Four-thirty. A risk-based-monitoring KRI crosses its quality tolerance limit — a site's query rate is too high. The agent packages the breach with its trend and the contributing records, and drafts the action note. The PM, or the central monitor, reviews the packaged signal and decides the response — perhaps a targeted visit. The system flags; the human decides.",
  // 8 close
  "So across the day, the platform did the drafting; the humans approved; the validated systems owned the records. One shape every time — trigger, draft, approval. Sensitivity routed the engine, and the validated systems stayed authoritative: the EDC issued the query, the eTMF filed the document, Smartsheet held the timeline. The busywork is automated; judgment and accountability stay human.",
];
