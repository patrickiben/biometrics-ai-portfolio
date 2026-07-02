// Dependency-free .xlsx writer: emits OOXML parts to a temp dir; caller zips them with the `zip` CLI.
// Usage: node make_xlsx.js <out_parts_dir> <data.json>
//   data.json = { sheet, headers:[...], rows:[[...]], tierCol:<idx|null>, widths:[...]|null, freezeCols:<n> }
const fs = require("fs");
const path = require("path");

const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const colName = (n) => { let s = ""; n++; while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); } return s; };

const cfg = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const outDir = process.argv[2];
const { sheet = "Register", headers, rows, tierCol = null, freezeCols = 0 } = cfg;
const widths = cfg.widths || headers.map((h, i) => Math.min(60, Math.max(10, Math.max(h.length, ...rows.map(r => String(r[i] == null ? "" : r[i]).split("\n")[0].length)) + 2)));

const mk = (p, c) => { fs.mkdirSync(path.dirname(path.join(outDir, p)), { recursive: true }); fs.writeFileSync(path.join(outDir, p), c); };

mk("[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`);
mk("_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`);
mk("xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`);
mk("xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${esc(sheet)}" sheetId="1" r:id="rId1"/></sheets></workbook>`);

// styles: fills[0 none,1 gray125,2 headerDark,3 green,4 amber,5 red,6 zebra]; fonts[0 default,1 whiteBold]
mk("xl/styles.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3"><font><sz val="10"/><name val="Calibri"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="10"/><name val="Calibri"/></font></fonts>
<fills count="7"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF23264F"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD6F0E2"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFBEFCB"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF3D6D0"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF4F5FB"/></patternFill></fill></fills>
<borders count="1"><border><left style="thin"><color rgb="FFD9D9E3"/></left><right style="thin"><color rgb="FFD9D9E3"/></right><top style="thin"><color rgb="FFD9D9E3"/></top><bottom style="thin"><color rgb="FFD9D9E3"/></bottom></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="7">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="4" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="5" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="6" borderId="0" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
</cellXfs></styleSheet>`);

const tierStyle = (v) => { const t = String(v).toLowerCase(); if (t.includes("green")) return 3; if (t.includes("amber")) return 4; if (t.includes("red")) return 5; return 2; };
function cell(ci, ri, val, style) { const ref = colName(ci) + (ri + 1); return `<c r="${ref}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${esc(val)}</t></is></c>`; }

let body = "";
// header row
body += `<row r="1" ht="30" customHeight="1">` + headers.map((h, ci) => cell(ci, 0, h, 1)).join("") + `</row>`;
rows.forEach((r, idx) => {
  const ri = idx + 1; const zebra = idx % 2 === 1;
  const cells = r.map((v, ci) => {
    let st = zebra ? 6 : 2;
    if (tierCol != null && ci === tierCol) st = tierStyle(v);
    return cell(ci, ri, v, st);
  }).join("");
  body += `<row r="${ri + 1}">${cells}</row>`;
});

const cols = `<cols>` + widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("") + `</cols>`;
const lastRef = colName(headers.length - 1) + (rows.length + 1);
const pane = freezeCols > 0
  ? `<pane xSplit="${freezeCols}" ySplit="1" topLeftCell="${colName(freezeCols)}2" activePane="bottomRight" state="frozen"/>`
  : `<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>`;
mk("xl/worksheets/sheet1.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0">${pane}</sheetView></sheetViews><sheetFormatPr defaultRowHeight="14"/>${cols}<sheetData>${body}</sheetData><autoFilter ref="A1:${lastRef}"/></worksheet>`);

console.log("xlsx parts written to", outDir, "(" + rows.length + " rows x " + headers.length + " cols)");
