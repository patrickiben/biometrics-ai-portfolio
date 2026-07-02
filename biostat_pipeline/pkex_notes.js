// Narration for the Protocol->CSR PK-package worked example (one entry per slide).
module.exports = [
  // 1 title
  "Let me follow one deliverable — the Phase-1 PK package on Study CP-101 — all the way from Protocol to CSR, and show exactly what each stage hands to AI, to a validated tool, and to a human. The rule never changes: sensitivity decides the engine, validated tools own every reported number, and a statistician signs.",
  // 2 routing
  "The PK package is three things: the ADPC dataset, the PK tables and figures, and the PK section of the CSR. At every stage the same rule applies. Anything touching unmasked, participant-level data runs on the local model, with zero egress. Hard reasoning on de-identified text goes to cloud Claude, under a business-associate agreement. And every reported number comes from a validated tool, QC'd, and signed by a human.",
  // 3 stage 1
  "Stage one, the statistical analysis plan. Cloud Claude drafts the PK statistical-methods prose from the protocol and the SAP shell — the NCA parameters, the BLQ rule, nominal versus actual time, the populations — with placeholders for anything study-specific. It invents nothing. There is no number here yet; this is text. The statistician reviews every derivation rule, owns the estimand and endpoint decisions, and signs the SAP.",
  // 4 stage 2
  "Stage two, building the ADPC dataset on the real, unmasked PK data — so this runs on the local model, zero egress. It drafts the spec and code: the BLQ handling, nominal and actual time, deviation flags, the mapping to ADPC. Conformance comes from Pinnacle 21 — a validated tool, not the model. Then an independent program double-checks ADPC, discrepancies are resolved, and the statistician signs and freezes it.",
  // 5 stage 3
  "Stage three, the analysis — the numbers. This is the line nobody crosses: the reported NCA parameters, Cmax, AUC, half-life, clearance, come from Phoenix WinNonlin, the validated tool. The local model only assists the QC — it sanity-checks the profiles and flags outliers for review, on the unmasked data. It never produces a reported value. A second analyst double-programs the parameters, the medical monitor reviews the emerging PK, and the statistician signs.",
  // 6 stage 4
  "Stage four, the tables, listings, and figures. The model drafts the shells, titles, and footnotes, and checks wording consistency across outputs — text only. The actual tables and figures are produced by the validated SAS programs, from the frozen ADPC and the NCA results. QC ties every cell back to source, and the package is signed.",
  // 7 stage 5
  "Stage five, the CSR. Cloud Claude drafts the PK methods and results narrative from the de-identified summary outputs, consistent with the tables and citing them — it copies numbers, it never computes them. The signed TLFs remain the source of truth. A medical writer and the statistician finalize and sign the regulated text.",
  // 8 close
  "So across the whole package, AI did the drafting and the QC; validated tools and humans owned the numbers. Sensitivity routed the engine — unmasked data stayed local, de-identified reasoning went to cloud. Phoenix computed the NCA, Pinnacle 21 validated conformance, SAS produced the TLFs — the model never produced a reported value. And a human signed every gate. Faster drafting, tighter QC, the data staying put, and the regulated outputs unchanged in their provenance.",
];
