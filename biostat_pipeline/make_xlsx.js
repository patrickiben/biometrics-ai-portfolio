// Dependency-free .xlsx writer: emits OOXML parts to a directory; the caller zips them with the `zip` CLI.
// Usage: node make_xlsx.js <out_parts_dir> <data.json>
//   data.json = { sheets: [ { sheet, headers:[...], rows:[[...]], tierCol:<idx|null>, widths:[...]|null,
//                             freezeCols:<n>, note:<bool> } ... ] }
//   (a single-sheet object { sheet, headers, rows, ... } is also accepted)
//   note: true writes a plain text sheet (one wrapped paragraph per row, no header styling or filter).
const fs = require("fs");
const path = require("path");

const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const colName = (n) => { let s = ""; n++; while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); } return s; };

const raw = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const sheets = raw.sheets || [raw];
const outDir = process.argv[2];
const mk = (p, c) => { fs.mkdirSync(path.dirname(path.join(outDir, p)), { recursive: true }); fs.writeFileSync(path.join(outDir, p), c); };

const ct = sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("");
mk("[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${ct}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`);
mk("_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`);
const rels = sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("");
mk("xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${rels}<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`);
// autoFilter needs a hidden _xlnm._FilterDatabase name per filtered sheet
const names = sheets.map((s, i) => s.note ? "" : `<definedName name="_xlnm._FilterDatabase" localSheetId="${i}" hidden="1">'${esc(s.sheet).replace(/'/g, "''")}'!$A$1:$${colName(s.headers.length - 1)}$${s.rows.length + 1}</definedName>`).join("");
mk("xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.map((s, i) => `<sheet name="${esc(s.sheet)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets>${names ? `<definedNames>${names}</definedNames>` : ""}</workbook>`);

// styles: fills[0 none,1 gray125,2 headerDark,3 green,4 amber,5 red,6 zebra]; fonts[0 default,1 whiteBold,2 bold,3 title]
mk("xl/styles.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="4"><font><sz val="10"/><name val="Calibri"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="10"/><name val="Calibri"/></font><font><b/><sz val="13"/><name val="Calibri"/></font></fonts>
<fills count="7"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF23264F"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD6F0E2"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFBEFCB"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF3D6D0"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF4F5FB"/></patternFill></fill></fills>
<borders count="1"><border><left style="thin"><color rgb="FFD9D9E3"/></left><right style="thin"><color rgb="FFD9D9E3"/></right><top style="thin"><color rgb="FFD9D9E3"/></top><bottom style="thin"><color rgb="FFD9D9E3"/></bottom></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="8">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="4" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="5" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="6" borderId="0" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
</cellXfs></styleSheet>`);

const tierStyle = (v) => { const t = String(v).toLowerCase(); if (t.includes("green")) return 3; if (t.includes("amber")) return 4; if (t.includes("red")) return 5; return 2; };
const cell = (ci, ri, val, style) => `<c r="${colName(ci) + (ri + 1)}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${esc(val)}</t></is></c>`;

sheets.forEach((cfg, si) => {
  const { headers, rows, tierCol = null, freezeCols = 0, note = false } = cfg;
  let body = "", cols, view, filter = "";
  if (note) {
    // plain text sheet: the first row is a title, the rest are wrapped paragraphs in column A
    rows.forEach((r, ri) => { body += `<row r="${ri + 1}">${cell(0, ri, r[0], ri === 0 ? 7 : 2)}</row>`; });
    cols = `<cols><col min="1" max="1" width="${(cfg.widths || [110])[0]}" customWidth="1"/></cols>`;
    view = `<sheetView workbookViewId="0"${si === 0 ? ' tabSelected="1"' : ""}/>`;
  } else {
    const widths = cfg.widths || headers.map((h, i) => Math.min(60, Math.max(10, Math.max(h.length, ...rows.map(r => String(r[i] == null ? "" : r[i]).split("\n")[0].length)) + 2)));
    body += `<row r="1" ht="30" customHeight="1">` + headers.map((h, ci) => cell(ci, 0, h, 1)).join("") + `</row>`;
    rows.forEach((r, idx) => {
      const ri = idx + 1, zebra = idx % 2 === 1;
      body += `<row r="${ri + 1}">` + r.map((v, ci) => cell(ci, ri, v, tierCol != null && ci === tierCol ? tierStyle(v) : (zebra ? 6 : 2))).join("") + `</row>`;
    });
    cols = `<cols>` + widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("") + `</cols>`;
    const pane = freezeCols > 0
      ? `<pane xSplit="${freezeCols}" ySplit="1" topLeftCell="${colName(freezeCols)}2" activePane="bottomRight" state="frozen"/>`
      : `<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>`;
    view = `<sheetView workbookViewId="0"${si === 0 ? ' tabSelected="1"' : ""}>${pane}</sheetView>`;
    filter = `<autoFilter ref="A1:${colName(headers.length - 1) + (rows.length + 1)}"/>`;
  }
  mk(`xl/worksheets/sheet${si + 1}.xml`, `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews>${view}</sheetViews><sheetFormatPr defaultRowHeight="14"/>${cols}<sheetData>${body}</sheetData>${filter}</worksheet>`);
  console.log(`sheet ${si + 1} "${cfg.sheet}": ${rows.length} rows`);
});
console.log("xlsx parts written to", outDir);
