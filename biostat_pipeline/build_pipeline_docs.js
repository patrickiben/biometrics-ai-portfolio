// Build the reference document (markdown) + the xlsx-register data from the deduped register.
const fs = require("fs");
const reg = JSON.parse(fs.readFileSync(__dirname + "/_register.json", "utf8"));
const STAGES = [
  ["S1", "Study Design & Protocol", "Protocol approved / finalized", "Biostatistics shapes the design: estimands, endpoints, sample-size rationale, randomization, and the statistical sections of the protocol."],
  ["S2", "Planning & Specifications", "SAP & specifications final", "Everything is specified before data: the SAP, TLF shells, ADaM/SDTM specs, the randomization schedule, the data-review and QC plans."],
  ["S3", "Data & CDISC", "Database lock", "Raw data becomes standardized, conformant, traceable CDISC datasets (SDTM → ADaM) with reviewer guides and Define-XML, under full data integrity controls."],
  ["S4", "Analysis & QC", "All outputs QC-passed", "TLFs and PK/PD analyses are produced and independently double-programmed; reported numbers come from validated engines (Phoenix WinNonlin for NCA), never an LLM."],
  ["S5", "Reporting & CSR", "CSR draft delivered", "Results become the CSR — statistical methods and results text, in-text tables/figures, appendices, the submission package, and cross-document consistency."],
];
const esc = (s) => String(s == null ? "" : s).replace(/\|/g, "\\|").replace(/\n/g, " ").trim();
const primaryTier = (t) => { t = (t || "").toUpperCase(); const i = ["GREEN", "AMBER", "RED"].map(x => [x, t.indexOf(x)]).filter(([, j]) => j >= 0).sort((a, b) => a[1] - b[1]); return i.length ? i[0][0] : ""; };
const codeOf = (s) => { s = (s || "").toLowerCase(); if (s.includes("design") || s.includes("protocol")) return "S1"; if (s.includes("planning") || s.includes("spec")) return "S2"; if (s.includes("data") || s.includes("cdisc")) return "S3"; if (s.includes("analysis") || s.includes("qc")) return "S4"; if (s.includes("report") || s.includes("csr")) return "S5"; return "S2"; };
reg.forEach(d => { d.code = codeOf(d.stage); d.stage = (STAGES.find(s => s[0] === d.code) || [])[1] || d.stage; });
const byStage = (code) => reg.filter(d => d.code === code);

let md = "# Early-Phase Clinical Pharmacology — Biostatistics Deliverables Pipeline\n\n";
md += "**Protocol review → CSR draft · every document, dataset, and statistical output · with the hybrid-AI routing overlay**\n\n";
md += "> **Scope & how to read this.** This is the complete biometrics deliverables map for a Phase 1 clinical-pharmacology study (e.g., First-in-Human SAD/MAD with PK/PD, NCA + popPK, safety). " + reg.length + " deliverables across five stages, each with its owner, inputs, outputs, governing standard, QC method, and how AI is (or is not) used. The at-a-glance tables are below; the **full register with every field is the companion `.xlsx`**, and the **one-page visual is the `.pdf` map**. Standards are current as of mid-2026 (CDISC SDTMIG v3.4 / ADaMIG v1.3 / Define-XML v2.1; ICH E3, E6(R3), E9/E9(R1), M11; 21 CFR Part 11; ISPE GAMP 5).\n\n";
md += "## How the pipeline flows\n\nFive sequential stages, each closed by a gate. A **CDISC data-standards track** (SDTM → ADaM → Define-XML + reviewer guides) runs through Stages 3–5, and a **hybrid-AI governance track** (data-classification routing, model-freeze records, engine-of-record register) runs across all five.\n\n";
md += "| Stage | Focus | Gate |\n|---|---|---|\n";
STAGES.forEach(([c, n, gate, , ]) => { md += `| **${c} — ${n}** | ${esc(STAGES.find(s => s[0] === c)[3])} | ${gate} |\n`; });
md += "\n";

STAGES.forEach(([code, name, gate, intro]) => {
  const items = byStage(code);
  md += `\n## ${code} — ${name}\n\n${intro}\n\n`;
  md += "| ID | Deliverable | Owner | Standard | QC | AI |\n|---|---|---|---|---|---|\n";
  items.forEach(d => { md += `| ${d.id} | **${esc(d.deliverable)}** | ${esc(d.owner)} | ${esc(d.standard)} | ${esc(d.qc)} | ${primaryTier(d.ai_tier)} |\n`; });
  md += `\n*Stage gate: **${gate}.** ${items.length} deliverables.*\n`;
});

// CDISC inventory
const cdisc = reg.filter(d => d.code === "S3" && /sdtm|adam|define|reviewer guide|cSDRG|ADRG|conformance|dataset|adsl|adpc|adpp|metadata|pinnacle|controlled term/i.test(d.deliverable));
md += "\n## CDISC dataset & metadata inventory\n\nThe standardized-data spine that makes the study submission-ready (SDTM → ADaM → Define-XML, with conformance and reviewer guides).\n\n";
md += "| ID | Deliverable | Standard | QC |\n|---|---|---|---|\n";
cdisc.forEach(d => { md += `| ${d.id} | ${esc(d.deliverable)} | ${esc(d.standard)} | ${esc(d.qc)} |\n`; });

// TLF inventory
const tlf = reg.filter(d => d.code === "S4" && /tlf|table|figure|listing|concentration|parameter|nca|safety|teae|demographic|disposition|dose|exposure|qtc|immunogen|pharmacomet|poppk|profile/i.test(d.deliverable.toLowerCase()));
md += "\n## TLF & analysis-output inventory (Stage 4)\n\nTables, listings, and figures by domain, plus the PK/PD analyses. Reported numbers are produced by validated engines, then independently double-programmed.\n\n";
md += "| ID | Deliverable | Owner | QC |\n|---|---|---|---|\n";
tlf.forEach(d => { md += `| ${d.id} | ${esc(d.deliverable)} | ${esc(d.owner)} | ${esc(d.qc)} |\n`; });

// AI overlay
const tiers = { GREEN: 0, AMBER: 0, RED: 0, "": 0 };
reg.forEach(d => tiers[primaryTier(d.ai_tier)]++);
md += "\n## The hybrid-AI routing overlay\n\nEvery deliverable is risk-tiered (**Model Risk = influence × consequence**) and routed by data sensitivity. The pattern from the hybrid AI strategy applies here, deliverable by deliverable.\n\n";
md += "| Tier | Count | What AI does | Engine |\n|---|---|---|---|\n";
md += `| 🟢 GREEN | ${tiers.GREEN} | Drafts, scaffolds, documentation, summaries on de-identified text | Cloud Claude (API + BAA) or local |\n`;
md += `| 🟡 AMBER | ${tiers.AMBER} | Dataset/TLF code; AI as **one side** of double-programming | Local frozen model (participant-level) / cloud (de-identified) |\n`;
md += `| 🔴 RED | ${tiers.RED} | **Nothing autonomous** — validated engine produces the number; LLM out of the path | Validated engine (Phoenix WinNonlin / SAS / NONMEM) only |\n\n`;
md += "**The three hard rules (override everything):** (1) PHI / unblinded / randomization data never leaves — always the local frozen model; (2) every **reported number** comes from a validated engine, never an LLM; (3) de-identification is the only thing that unlocks the cloud path (Claude API under BAA — never a consumer Copilot/Max seat).\n";

// Governance
md += "\n## Validation & governance (cross-cutting)\n\n";
md += "- **Independent double-programming** of every submission-grade output; the AI may replace at most one side, never both.\n";
md += "- **21 CFR Part 11 + ALCOA++**: secure, attributable, time-stamped audit trails; e-signatures; reproducibility.\n";
md += "- **Engine-of-record** recorded per deliverable; reported numbers always from a validated, qualified engine.\n";
md += "- **Model-freeze records** for the local open-weight model (fixed weights + config + seed = a re-runnable validation artifact); change control on any model update.\n";
md += "- **Data-classification routing log** and **zero-egress attestation** for sensitive data; consolidated into a submission-level hybrid-AI governance dossier.\n";
md += "- **Software / environment qualification** (IQ/OQ/PQ) for SAS/R, Phoenix WinNonlin, NONMEM/Monolix, Pinnacle 21.\n";
md += "\n## Closing\n\nThis pipeline is the operating map for an in-house, hybrid-AI biometrics function: human-owned and signed at every step, validated engines for every reported number, full CDISC and Part 11 rigor — with AI accelerating the language, code-drafting, and QC-support layers under explicit, deliverable-by-deliverable controls. The complete register (every field, all " + reg.length + " deliverables) is in the companion spreadsheet; the visual map is the accompanying one-pager.\n";

fs.writeFileSync(__dirname + "/EarlyPhase_Biostat_Pipeline.md", md);

// xlsx data
const headers = ["ID", "Stage", "Deliverable", "Type", "Owner", "Inputs", "Outputs", "Standard", "QC", "AI tier", "AI engine", "AI use", "Description"];
const rows = reg.map(d => [d.id, (d.stage || ""), d.deliverable || "", d.type || "", d.owner || "", d.inputs || "", d.outputs || "", d.standard || "", d.qc || "", primaryTier(d.ai_tier), d.ai_engine || "", d.ai_use || "", d.description || ""]);
const widths = [7, 22, 34, 16, 20, 30, 30, 26, 30, 9, 26, 30, 50];
fs.writeFileSync(__dirname + "/_xlsx_data.json", JSON.stringify({ sheet: "Biostat Pipeline Register", headers, rows, tierCol: 9, widths, freezeCols: 3 }, null, 0));

console.log("doc:", md.length, "chars | xlsx rows:", rows.length, "| CDISC:", cdisc.length, "TLF:", tlf.length, "| tiers G/A/R:", tiers.GREEN, tiers.AMBER, tiers.RED);
