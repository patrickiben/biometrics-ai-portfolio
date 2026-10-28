// Build the reference document (Markdown) and the spreadsheet data from the register.
//   in : _register.json (the deliverables), _ai_use_records.json (the AI-use appendix)
//   out: EarlyPhase_Biostat_Pipeline.md, _xlsx_data.json (input to make_xlsx.js; not committed)
//
// Rebuild every export from this folder (biostat_pipeline/):
//   node build_pipeline_docs.js
//   rm -rf /tmp/reg && node make_xlsx.js /tmp/reg _xlsx_data.json && rm -f EarlyPhase_Biostat_Pipeline_Register.xlsx \
//     && (cd /tmp/reg && zip -X -r "$OLDPWD/EarlyPhase_Biostat_Pipeline_Register.xlsx" '[Content_Types].xml' _rels xl)
//   node md2docx.js EarlyPhase_Biostat_Pipeline.md EarlyPhase_Biostat_Pipeline.docx      # needs the docx package
//   soffice --headless --convert-to pdf EarlyPhase_Biostat_Pipeline.docx
//   node build_map.js && soffice --headless --convert-to pdf EarlyPhase_Biostat_Pipeline_Map.pptx   # needs pptxgenjs
// Then run python3 ../package_qc.py, which reads the text of every export.
const fs = require("fs");
const reg = JSON.parse(fs.readFileSync(__dirname + "/_register.json", "utf8"));
const aiRecords = JSON.parse(fs.readFileSync(__dirname + "/_ai_use_records.json", "utf8"));
const STAGES = [
  ["S1", "Study Design & Protocol", "Protocol approved / finalized", "Biostatistics shapes the design: estimands, endpoints, sample-size rationale, randomization, and the statistical sections of the protocol."],
  ["S2", "Planning & Specifications", "SAP & specifications final", "Everything is specified before data: the SAP, TLF shells, ADaM/SDTM specs, the randomization schedule, the data-review and QC plans."],
  ["S3", "Data & CDISC", "Database lock", "Raw data becomes standardized, conformant, traceable CDISC datasets (SDTM → ADaM) with reviewer guides and Define-XML, under full data integrity controls."],
  ["S4", "Analysis & QC", "All outputs QC-passed", "TLFs and PK/PD analyses are produced and independently double-programmed; reported numbers come from validated programs and engines (Phoenix WinNonlin or PKNCA for NCA)."],
  ["S5", "Reporting & CSR", "CSR draft delivered", "Results become the CSR: statistical methods and results text, in-text tables/figures, appendices, the submission package, and cross-document consistency."],
];
const esc = (s) => String(s == null ? "" : s).replace(/\|/g, "\\|").replace(/\n/g, " ").trim();
const primaryTier = (t) => { t = (t || "").toUpperCase(); const i = ["GREEN", "AMBER", "RED"].map(x => [x, t.indexOf(x)]).filter(([, j]) => j >= 0).sort((a, b) => a[1] - b[1]); return i.length ? i[0][0] : ""; };
const title = (t) => t ? t[0] + t.slice(1).toLowerCase() : "";
reg.forEach(d => { d.code = d.id.slice(0, 2); d.stageName = (STAGES.find(s => s[0] === d.code) || [])[1] || d.stage; });
const byStage = (code) => reg.filter(d => d.code === code);
const N = reg.length;

let md = "# Early-Phase Clinical Pharmacology: Biostatistics Deliverables Pipeline\n\n";
md += "**Protocol review → CSR draft · every document, dataset, and statistical output, with its owner, standard, and QC**\n\n";
md += "> **Reference map, not a track record.** This register maps the deliverables of a Phase 1 clinical pharmacology study and how each would be produced and checked. It is a reusable planning reference for consultants and employees, not a list of completed client deliverables. The [toolkit home page](../index.html) links to runnable examples. A short appendix sets out where AI tools could assist under controls; it is a proposal, not an adopted policy.\n\n";
md += `> **Scope & how to read this.** ${N} deliverables across five stages of a Phase 1 clinical-pharmacology study (e.g., First-in-Human SAD/MAD with PK/PD, NCA + popPK, safety), each with its owner, inputs, outputs, governing standard, and QC method. The at-a-glance tables are below; the **full register with every field is the companion \`.xlsx\`**, and the **one-page visual is the \`.pdf\` map**. Reference versions used here: CDISC SDTMIG v3.4, ADaMIG v1.3, and Define-XML v2.1; ICH E3, E6(R3), E9(R1), and M11; 21 CFR Part 11; ISPE GAMP 5. Confirm applicable requirements, supported versions and effective dates for the intended study and submission.\n\n`;
md += "## How the pipeline flows\n\nFive sequential stages, each closed by a gate. A **CDISC data-standards track** (SDTM → ADaM → Define-XML + reviewer guides) runs through Stages 3 to 5, and a **quality track** (independent double programming, engine-of-record records, audit trail, named sign-off) runs across all five.\n\n";
md += "| Stage | Focus | Gate |\n|---|---|---|\n";
STAGES.forEach(([c, n, gate, intro]) => { md += `| **${c}: ${n}** | ${esc(intro)} | ${gate} |\n`; });
md += "\n";

STAGES.forEach(([code, name, gate, intro]) => {
  const items = byStage(code);
  md += `\n## ${code}: ${name}\n\n${intro}\n\n`;
  md += "| ID | Deliverable | Owner | Standard | QC |\n|---|---|---|---|---|\n";
  items.forEach(d => { md += `| ${d.id} | **${esc(d.deliverable)}** | ${esc(d.owner)} | ${esc(d.standard)} | ${esc(d.qc)} |\n`; });
  md += `\n*Stage gate: **${gate}.** ${items.length} deliverables.*\n`;
});

// CDISC inventory
const cdisc = reg.filter(d => d.code === "S3" && /sdtm|adam|define|reviewer guide|cSDRG|ADRG|conformance|dataset|adsl|adpc|adpp|metadata|pinnacle|controlled term/i.test(d.deliverable));
md += "\n## CDISC dataset & metadata inventory\n\nThe standardized-data spine that makes the study submission-ready (SDTM → ADaM → Define-XML, with conformance and reviewer guides).\n\n";
md += "| ID | Deliverable | Standard | QC |\n|---|---|---|---|\n";
cdisc.forEach(d => { md += `| ${d.id} | ${esc(d.deliverable)} | ${esc(d.standard)} | ${esc(d.qc)} |\n`; });

// TLF inventory
const tlf = reg.filter(d => d.code === "S4" && /tlf|table|figure|listing|concentration|parameter|nca|safety|teae|demographic|disposition|dose|exposure|qtc|immunogen|pharmacomet|poppk|profile/i.test(d.deliverable.toLowerCase()));
md += "\n## TLF & analysis-output inventory (Stage 4)\n\nTables, listings, and figures by domain, plus the PK/PD analyses. Reported numbers come from validated programs and engines and are independently double-programmed.\n\n";
md += "| ID | Deliverable | Owner | QC |\n|---|---|---|---|\n";
tlf.forEach(d => { md += `| ${d.id} | ${esc(d.deliverable)} | ${esc(d.owner)} | ${esc(d.qc)} |\n`; });

// Validation & quality
md += "\n## Validation & quality (cross-cutting)\n\n";
md += "- **Independent double programming** of every submission-grade output, with every discrepancy logged and resolved.\n";
md += "- **Engine of record** for every deliverable: reported numbers come from validated, double-programmed SAS/R programs on ADaM; NCA from Phoenix WinNonlin (version per the ADRG, currently 8.8) or PKNCA; CDISC conformance is checked with Pinnacle 21 (FDA engine 2304.3). Software version and build are documented, as FDA's statistical software statement asks.\n";
md += "- **Data integrity:** records that are attributable, legible, contemporaneous, original, accurate, complete, secure, and reliable (ICH E6(R3)); audit trails and e-signatures in systems designed to meet 21 CFR Part 11.\n";
md += "- **Software / environment qualification** (IQ/OQ/PQ) for SAS/R, Phoenix WinNonlin, NONMEM/Monolix, and Pinnacle 21.\n";
md += "- **Named sign-off:** a qualified statistician reviews and signs each deliverable.\n";

// Appendix: AI-use proposal (short, vendor-neutral)
const tiers = { GREEN: 0, AMBER: 0, RED: 0, "": 0 };
reg.forEach(d => tiers[primaryTier(d.ai_tier)]++);
md += "\n## Appendix: AI-use proposal\n\n";
md += "A proposal, not an adopted policy, for where AI tools could assist on these deliverables and where they may not. For context, FDA's guidance on using AI to support regulatory decision-making for drugs is still a draft (January 2025), and the FDA-EMA guiding principles for AI in drug development (January 2026) are non-binding.\n\n";
md += "1. Every reported number comes from a validated program or engine. An AI tool may draft code that is one side of independent double programming, never both sides.\n";
md += "2. Participant-level, unblinded, or identifiable data stays inside the validated environment (a local, version-pinned model, if any model is used). Only de-identified text and specifications may go to a contracted cloud service under a data-processing agreement, never a consumer account.\n";
md += "3. A named statistician reviews and signs every output, and AI use is recorded.\n\n";
md += "| Tier | Deliverables | What an AI tool may do |\n|---|---|---|\n";
md += `| Green | ${tiers.GREEN} | Draft text, scaffolds, and documentation from de-identified content |\n`;
md += `| Amber | ${tiers.AMBER} | Draft dataset or TLF code as one side of double programming |\n`;
md += `| Red | ${tiers.RED} | Nothing: validated programs and engines produce the numbers, and a human checks them |\n\n`;
const WORDS = ["no", "one", "two", "three", "four", "five", "six"];
md += `If AI tools are used, ${WORDS[aiRecords.length] || aiRecords.length} records are kept:\n\n`;
aiRecords.forEach(r => { md += `- **${r.id} ${esc(r.record)}** (${esc(r.when)}): ${esc(r.description)}\n`; });
md += "\nThe tier and AI note for each deliverable are on the spreadsheet's \"AI use (proposal)\" sheet.\n";

fs.writeFileSync(__dirname + "/EarlyPhase_Biostat_Pipeline.md", md);

// xlsx data: a read-me sheet, the register, and the appendix sheets
const readme = [
  ["Early-Phase Clinical Pharmacology: Biostatistics Deliverables Register"],
  ["Reference map, not a track record. This register maps the deliverables of a Phase 1 clinical pharmacology study and how each would be produced and checked. It is a reusable planning reference for consultants and employees, not a list of completed client deliverables. The toolkit home page links to runnable examples."],
  [`Register sheet: ${N} deliverables across five stages, with owner, inputs, outputs, governing standard, QC method, and description. Reference versions used here: CDISC SDTMIG v3.4, ADaMIG v1.3, Define-XML v2.1; ICH E3, E6(R3), E9(R1), M11; 21 CFR Part 11. Confirm applicable requirements, supported versions and effective dates for the intended study and submission.`],
  ["AI use (proposal) and AI-use records sheets: the appendix of the reference document. A proposal, not an adopted policy: every reported number comes from a validated program or engine, identifiable data stays inside the validated environment, and a named statistician signs every output."],
  ["Companion files: EarlyPhase_Biostat_Pipeline.md / .docx / .pdf (reference document) and EarlyPhase_Biostat_Pipeline_Map.pdf (one-page map)."],
];
const regHeaders = ["ID", "Stage", "Deliverable", "Type", "Owner", "Inputs", "Outputs", "Standard", "QC", "Description"];
const regRows = reg.map(d => [d.id, `${d.code}: ${d.stageName}`, d.deliverable || "", d.type || "", d.owner || "", d.inputs || "", d.outputs || "", d.standard || "", d.qc || "", d.description || ""]);
const aiHeaders = ["ID", "Deliverable", "AI tier", "Where an AI tool could run", "What an AI tool could do"];
const aiRows = reg.map(d => [d.id, d.deliverable || "", title(primaryTier(d.ai_tier)), d.ai_engine || "", d.ai_use || ""]);
const recHeaders = ["ID", "Record", "When", "Owner", "Description", "Standard"];
const recRows = aiRecords.map(r => [r.id, r.record, r.when, r.owner, r.description, r.standard]);
fs.writeFileSync(__dirname + "/_xlsx_data.json", JSON.stringify({ sheets: [
  { sheet: "Read me", note: true, headers: ["Read me"], rows: readme, widths: [110] },
  { sheet: "Register", headers: regHeaders, rows: regRows, widths: [7, 24, 34, 16, 20, 30, 30, 26, 30, 50], freezeCols: 3 },
  { sheet: "AI use (proposal)", headers: aiHeaders, rows: aiRows, tierCol: 2, widths: [7, 34, 9, 30, 60], freezeCols: 2 },
  { sheet: "AI-use records", headers: recHeaders, rows: recRows, widths: [7, 30, 24, 22, 60, 30], freezeCols: 2 },
] }, null, 0));

console.log("doc:", md.length, "chars | register rows:", regRows.length, "| CDISC:", cdisc.length, "TLF:", tlf.length, "| tiers G/A/R:", tiers.GREEN, tiers.AMBER, tiers.RED, "| AI-use records:", recRows.length);
