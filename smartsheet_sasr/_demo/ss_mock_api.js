// ss_mock_api.js — a LOCAL, in-memory stand-in for the Smartsheet REST API, just enough
// for the real ss_companion.R / ss_macros.sas job to run end-to-end on this machine.
// REPRESENTATIVE API ONLY — not Smartsheet; it exists so the demo's HTTP calls, JSON,
// idempotent upsert, attachment and update-request are genuinely exercised, and so the
// grid view can render the real resulting sheet state. Ops-only; no PHI ever stored.
const http = require('http');
const fs = require('fs');
const PORT = +(process.env.SS_MOCK_PORT || 9787);
const SHEET_ID = process.env.SS_MOCK_SHEET || '5500';
const STATE_FILE = process.env.SS_MOCK_STATE || '/tmp/ss_mock_state.json';
const EVENTS = [];

// ---- seed: the CP-101 Program Tracker (BEFORE the nightly run) ------------------------
const COLS = [
  { id: 101, title: 'TaskID' }, { id: 102, title: 'Task' }, { id: 103, title: 'Status' },
  { id: 104, title: 'PctDone' }, { id: 105, title: 'Owner' }, { id: 106, title: 'Due' },
];
function row(id, taskid, task, status, pct, owner, due) {
  return { id, attachments: [], cells: [
    { columnId: 101, value: taskid }, { columnId: 102, value: task }, { columnId: 103, value: status },
    { columnId: 104, value: pct }, { columnId: 105, value: owner }, { columnId: 106, value: due }] };
}
let SHEET = {
  id: +SHEET_ID, name: 'CP-101 Program Tracker', columns: COLS,
  rows: [
    row(1001, 'CP101-ENR',  'Enrollment vs plan',          'On Track', null,  'PM',       'ongoing'),
    row(1002, 'CP101-ADPC', 'ADaM spec — finalize',        'On Track', 0.60,  'A. Patel', '15 Jun'),
    row(1003, 'CP101-CUT',  'Database soft-lock / data cut','On Track', null,  'DM',       '17 Jun'),
    row(1004, 'CP101-TLF',  'Dry-run TLFs',                'On Track', 0.10,  'J. Kim',   '24 Jun'),
    row(1005, 'CP101-DSMB', 'DSMB pack',                   'On Track', 0.00,  'Biostat',  '30 Jun'),
  ],
};
let NEXT_ROW = 2000;
const persist = () => { try { fs.writeFileSync(STATE_FILE, JSON.stringify({ sheet: SHEET, events: EVENTS }, null, 1)); } catch (e) {} };
const log = (m) => { const s = `[mock-api] ${m}`; EVENTS.push(s); process.stderr.write(s + '\n'); };
persist();

const cellsToObj = (cells) => { const m = {}; const t = {}; COLS.forEach(c => t[c.id] = c.title); cells.forEach(c => m[t[c.columnId]] = c.value); return m; };
const send = (res, code, obj) => { const b = JSON.stringify(obj); res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(b) }); res.end(b); };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const parts = url.pathname.split('/').filter(Boolean);   // e.g. ['2.0','sheets','5500','rows']
  // diagnostic endpoints for the grid view (not part of the Smartsheet API surface)
  if (url.pathname === '/__state') return send(res, 200, SHEET);
  if (url.pathname === '/__events') return send(res, 200, EVENTS);

  // ---- auth: every real Smartsheet call needs a Bearer token --------------------------
  const auth = req.headers['authorization'] || '';
  if (!/^Bearer\s+\S+/.test(auth)) { log(`401 ${req.method} ${url.pathname} (no bearer token)`); return send(res, 401, { errorCode: 1002, message: 'Your Access Token is invalid.' }); }

  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => {
    const json = body && req.headers['content-type'] && req.headers['content-type'].includes('json') ? JSON.parse(body) : null;
    // GET /2.0/sheets/{id}
    if (req.method === 'GET' && parts[1] === 'sheets' && parts[2] && !parts[3]) {
      log(`200 GET /sheets/${parts[2]}  (${SHEET.columns.length} cols, ${SHEET.rows.length} rows)`);
      return send(res, 200, SHEET);
    }
    // PUT /2.0/sheets/{id}/rows   (update existing rows by id)
    if (req.method === 'PUT' && parts[1] === 'sheets' && parts[3] === 'rows') {
      const arr = Array.isArray(json) ? json : [json];
      const result = arr.map(u => {
        const r = SHEET.rows.find(x => x.id === u.id); if (!r) return { id: u.id, missing: true };
        u.cells.forEach(c => { const cell = r.cells.find(x => x.columnId === c.columnId); if (cell) cell.value = c.value; });
        return { id: u.id, ...cellsToObj(u.cells) };
      });
      log(`200 PUT /sheets/${parts[2]}/rows  (${arr.length} row(s) updated)`);
      persist(); return send(res, 200, { message: 'SUCCESS', result });
    }
    // POST /2.0/sheets/{id}/rows  (append new rows)
    if (req.method === 'POST' && parts[1] === 'sheets' && parts[3] === 'rows' && !parts[4]) {
      const arr = Array.isArray(json) ? json : [json];
      const result = arr.map(n => { const id = ++NEXT_ROW; SHEET.rows.push({ id, attachments: [], cells: n.cells }); return { id, ...cellsToObj(n.cells) }; });
      log(`200 POST /sheets/${parts[2]}/rows  (${arr.length} row(s) appended)`);
      persist(); return send(res, 200, { message: 'SUCCESS', result });
    }
    // POST /2.0/sheets/{id}/rows/{rowId}/attachments
    if (req.method === 'POST' && parts[3] === 'rows' && parts[5] === 'attachments') {
      const cd = req.headers['content-disposition'] || '';
      const name = (cd.match(/filename="?([^"]+)"?/) || [, 'attachment.pdf'])[1];
      const r = SHEET.rows.find(x => x.id === +parts[4]); if (r) r.attachments.push({ name, bytes: Buffer.byteLength(body) });
      log(`200 POST .../rows/${parts[4]}/attachments  (${name})`);
      persist(); return send(res, 200, { message: 'SUCCESS', result: { name, attachmentType: 'FILE' } });
    }
    // POST /2.0/sheets/{id}/updaterequests
    if (req.method === 'POST' && parts[3] === 'updaterequests') {
      log(`200 POST /sheets/${parts[2]}/updaterequests  (sent to ${(json && json.sendTo || []).length} recipient(s))`);
      return send(res, 200, { message: 'SUCCESS', result: { id: 99 } });
    }
    log(`404 ${req.method} ${url.pathname}`);
    return send(res, 404, { message: 'NOT FOUND' });
  });
});
server.listen(PORT, '127.0.0.1', () => log(`representative Smartsheet API on http://127.0.0.1:${PORT}/2.0  (sheet ${SHEET_ID})`));
