// Compact Markdown -> .docx converter (GFM subset: headings, bold/italic/code/links,
// bullet & numbered lists, tables, blockquotes, hr). Tailored to the roadmap markdown.
const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, ExternalHyperlink, Table, TableRow, TableCell,
  WidthType, BorderStyle, ShadingType, HeadingLevel, AlignmentType,
} = require("docx");

const NAVY = "1E2761", INK = "1B2340", GREY = "555F77", HDRBG = "1E2761", ZEBRA = "F3F6FC";

function inlineRuns(text, base = {}) {
  const runs = [];
  const push = (t, opts) => { if (t) runs.push(new TextRun({ text: t, ...base, ...opts })); };
  const re = /(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)]+)\))|(https?:\/\/[^\s)]+)/g;
  let last = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) push(text.slice(last, m.index), {});
    if (m[1]) push(m[2], { bold: true });
    else if (m[3]) push(m[4], { italics: true });
    else if (m[5]) push(m[6], { font: "Consolas" });
    else if (m[7]) runs.push(new ExternalHyperlink({ children: [new TextRun({ text: m[8], style: "Hyperlink", ...base })], link: m[9] }));
    else if (m[10]) runs.push(new ExternalHyperlink({ children: [new TextRun({ text: m[10].length > 70 ? m[10].slice(0, 67) + "..." : m[10], style: "Hyperlink", size: 16 })], link: m[10] }));
    last = re.lastIndex;
  }
  if (last < text.length) push(text.slice(last), {});
  if (runs.length === 0) push(text, {});
  return runs;
}

function buildTable(tblLines) {
  const split = (l) => l.replace(/^\s*\|/, "").replace(/\|\s*$/, "").split("|").map((c) => c.trim());
  const rows = tblLines.map(split);
  const header = rows[0], body = rows.slice(2);
  const ncol = header.length, totalW = 9360, cw = Math.floor(totalW / ncol);
  const widths = Array(ncol).fill(cw); widths[ncol - 1] = totalW - cw * (ncol - 1);
  const bd = { style: BorderStyle.SINGLE, size: 1, color: "D5DBEA" };
  const borders = { top: bd, bottom: bd, left: bd, right: bd };
  const cell = (txt, w, opt = {}) => {
    const parts = String(txt).split(/<br\s*\/?>/i);
    const paras = parts.map((p) => new Paragraph({ spacing: { after: 0, line: 230 }, children: inlineRuns(p, opt.run || { size: 17 }) }));
    return new TableCell({ borders, width: { size: w, type: WidthType.DXA }, shading: opt.fill ? { fill: opt.fill, type: ShadingType.CLEAR } : undefined, margins: { top: 60, bottom: 60, left: 110, right: 110 }, children: paras });
  };
  const head = new TableRow({ tableHeader: true, children: header.map((h, j) => cell(h, widths[j], { fill: HDRBG, run: { bold: true, color: "FFFFFF", size: 18 } })) });
  const brows = body.map((r, ri) => new TableRow({ children: header.map((_, j) => cell(r[j] || "", widths[j], { fill: ri % 2 ? ZEBRA : "FFFFFF", run: { size: 17 } })) }));
  return new Table({ width: { size: totalW, type: WidthType.DXA }, columnWidths: widths, rows: [head, ...brows] });
}

function parse(md) {
  const lines = md.replace(/\r/g, "").split("\n");
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*$/.test(line)) { i++; continue; }
    if (/^<!--.*-->\s*$/.test(line)) { i++; continue; }
    let h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      const lvl = Math.min(h[1].length, 3);
      out.push(new Paragraph({ heading: lvl === 1 ? HeadingLevel.HEADING_1 : lvl === 2 ? HeadingLevel.HEADING_2 : HeadingLevel.HEADING_3, children: inlineRuns(h[2]) }));
      i++; continue;
    }
    if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
      out.push(new Paragraph({ border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: "C7CFE2", space: 1 } }, spacing: { before: 60, after: 120 }, children: [] }));
      i++; continue;
    }
    if (/^>\s?/.test(line)) {
      const t = line.replace(/^>\s?/, "");
      out.push(new Paragraph({ indent: { left: 300 }, border: { left: { style: BorderStyle.SINGLE, size: 18, color: NAVY, space: 10 } }, shading: { fill: "EEF2FA", type: ShadingType.CLEAR }, spacing: { before: 100, after: 100 }, children: inlineRuns(t, { italics: true, color: GREY }) }));
      i++; continue;
    }
    if (/^\s*\|/.test(line) && i + 1 < lines.length && /^\s*\|?[\s:|-]*-{2,}[\s:|-]*\|?\s*$/.test(lines[i + 1])) {
      const tbl = [];
      while (i < lines.length && /^\s*\|/.test(lines[i])) { tbl.push(lines[i]); i++; }
      out.push(buildTable(tbl));
      out.push(new Paragraph({ spacing: { after: 60 }, children: [] }));
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        const t = lines[i].replace(/^\s*[-*]\s+/, "");
        out.push(new Paragraph({ bullet: { level: 0 }, spacing: { after: 40, line: 250 }, children: inlineRuns(t) }));
        i++;
      }
      continue;
    }
    if (/^\s*\d+\.\s+/.test(line)) {
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        const t = lines[i].trim();
        out.push(new Paragraph({ indent: { left: 460, hanging: 280 }, spacing: { after: 50, line: 255 }, children: inlineRuns(t) }));
        i++;
        // absorb indented continuation lines (e.g., a URL under a reference)
        while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*\d+\.\s+/.test(lines[i])) {
          out.push(new Paragraph({ indent: { left: 460 }, spacing: { after: 50 }, children: inlineRuns(lines[i].trim()) }));
          i++;
        }
      }
      continue;
    }
    out.push(new Paragraph({ spacing: { after: 120, line: 270 }, children: inlineRuns(line.trim()) }));
    i++;
  }
  return out;
}

const inFile = process.argv[2], outFile = process.argv[3];
const md = fs.readFileSync(inFile, "utf8");
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Calibri", size: 21, color: INK } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 30, bold: true, color: NAVY, font: "Georgia" }, paragraph: { spacing: { before: 120, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 24, bold: true, color: NAVY, font: "Georgia" }, paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1, border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: "C7CFE2", space: 4 } } } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 21, bold: true, color: "31407A", font: "Calibri" }, paragraph: { spacing: { before: 160, after: 80 }, outlineLevel: 2 } },
    ],
  },
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1180, right: 1180, bottom: 1180, left: 1180 } } },
    children: parse(md),
  }],
});
Packer.toBuffer(doc).then((b) => { fs.writeFileSync(outFile, b); console.log("WROTE", outFile, b.length, "bytes"); }).catch((e) => { console.error(e); process.exit(1); });
