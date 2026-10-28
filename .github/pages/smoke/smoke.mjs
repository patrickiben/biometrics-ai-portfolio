// smoke.mjs: deploy smoke test for the in-browser Shiny apps. Serves a built site the way GitHub
// Pages does (under /biometrics-ai-portfolio/), opens each app's launch page in headless Chrome
// with a fresh profile, and fails unless, for every app:
//   - the launch page shows its title and its "Try this" list at once (first contentful paint
//     under --max-fcp ms), before any R loads, inside the site's top bar (Operations current, with the
//     theme toggle);
//   - the launch page reaches "ready" within the app's smoke.timeout_s with no reported problem;
//   - every output in smoke.outputs has content (a plot image, table rows, text), each value in
//     smoke.expect matches, and no output anywhere shows an error (.shiny-output-error that is not
//     a validate() message);
//   - the app's controls carry the site's accent, not bslib's compiled default blue: every checked
//     radio and checkbox is filled with --accent, a slider handle has a visible border, and no
//     visible element is drawn in rgb(0, 123, 194) (checked in both themes and on every tab);
//   - the app shows the page's theme and R has it (input$bp_theme), and the theme toggle in the
//     site's top bar switches the app's page and R too (and back): R goes idle again within 30 s,
//     every listed plot is drawn again, and no output is left in an error;
//   - each tab in smoke.tabs, once clicked, fills its listed outputs with no error (a tab with
//     "theme": true repeats the theme check there, for its plots);
//   - each step list in smoke.interactions, done with real mouse and keyboard events (optionally at
//     another window size), ends with every expectation met (an element visible, its exact text,
//     an attribute or a computed style, inside the app's viewport, or focused) and leaves no
//     output anywhere in an error;
//   - after all of that the launch page reports no problem and no failed panel, and R is idle;
//   - nothing the visit asked the site for answered 404 (webR, for one, falls back to downloading a
//     missing package from elsewhere, so an app could still start without a file it should ship),
//     and the page logged no uncaught error and no console error about one of the site's files;
//   - a reload (the page now controlled by the service worker) reaches ready again.
// The lists come from apps/<name>/launch.json. Synthetic data only.
//
//   npm ci --prefix .github/pages/smoke
//   CHROME_PATH=/path/to/chrome node .github/pages/smoke/smoke.mjs <site_dir> [options]
//
// Options: --apps a,b   only these apps          --shots DIR    screenshots (launch page and app)
//          --report F   JSON report              --max-fcp MS   default 3000
//          --no-reload  skip the reload check    --port N       default: a free port
//          --base-url URL  test an existing published site (synthetic browser interactions only)
//          --fault 'REGEX=MODE'   answer matching requests with 404, drop the connection (drop) or
//                                 never answer (hang); for checking the error states locally
//          --expect-problem KIND  pass only if the launch page reports this problem instead
//          --log-requests F       write every request the server answered, with its time
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const puppeteer = require("puppeteer-core");

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const SITE = path.resolve(argv[0] && !argv[0].startsWith("--") ? argv[0] : "_site");
const PREFIX = "/biometrics-ai-portfolio";
const CHROME = opt("--chrome", process.env.CHROME_PATH || "");
const ONLY = (opt("--apps", "") || "").split(",").filter(Boolean);
const SHOTS = opt("--shots", "");
const REPORT = opt("--report", "");
const MAX_FCP = Number(opt("--max-fcp", "3000"));
const RELOAD = !argv.includes("--no-reload");
const FAULT = opt("--fault", "");
const EXPECT_PROBLEM = opt("--expect-problem", "");
const SPECS = opt("--specs", "apps");
const LOG_REQUESTS = opt("--log-requests", "");
const REMOTE_BASE = opt("--base-url", "").replace(/\/$/, "");
if (REMOTE_BASE && !/^https:\/\//.test(REMOTE_BASE)) throw new Error("--base-url must use HTTPS");
const requestLog = [];
const TAB_TIMEOUT_S = 60;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const t0 = Date.now();
const say = (...a) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(6)} s]`, ...a);

if (!CHROME || !fs.existsSync(CHROME)) { console.error("Set CHROME_PATH (or --chrome) to a Chrome binary"); process.exit(2); }
if (!fs.existsSync(path.join(SITE, "index.html"))) { console.error(`No built site at ${SITE}`); process.exit(2); }

// ---- the apps and what to check ----------------------------------------------------------
const apps = fs.readdirSync(SPECS).filter((d) => !d.startsWith("_") && fs.existsSync(path.join(SPECS, d, "launch.json")))
  .filter((d) => !ONLY.length || ONLY.includes(d)).sort()
  .map((name) => ({ name, ...JSON.parse(fs.readFileSync(path.join(SPECS, name, "launch.json"), "utf8")) }));
if (!apps.length) { console.error("No apps to check"); process.exit(2); }

// ---- a static server like GitHub Pages ---------------------------------------------------
const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".json": "application/json", ".wasm": "application/wasm", ".png": "image/png",
  ".jpg": "image/jpeg", ".webp": "image/webp", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".woff2": "font/woff2",
  ".ttf": "font/ttf", ".otf": "font/otf", ".gz": "application/gzip", ".tgz": "application/gzip", ".pdf": "application/pdf",
  ".txt": "text/plain; charset=utf-8", ".md": "text/plain; charset=utf-8", ".xml": "application/xml", ".csv": "text/csv",
};
let faultRx = null, faultMode = "";
if (FAULT) { const i = FAULT.lastIndexOf("="); faultRx = new RegExp(FAULT.slice(0, i)); faultMode = FAULT.slice(i + 1); }
const served = { bytes: 0, requests: 0, notFound: [] };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  let p = decodeURIComponent(url.pathname);
  if (LOG_REQUESTS) requestLog.push(`${((Date.now() - (served.since || t0)) / 1000).toFixed(2)}\t${req.method}\t${p}`);
  if (faultRx && faultRx.test(p)) {
    if (faultMode === "404") { res.writeHead(404); res.end("fault"); return; }
    if (faultMode === "drop") { req.socket.destroy(); return; }
    if (faultMode === "hang") return;
  }
  if (!p.startsWith(PREFIX + "/")) { res.writeHead(p === PREFIX ? 301 : 404, { Location: PREFIX + "/" }); res.end(); return; }
  let f = path.join(SITE, path.normalize(p.slice(PREFIX.length)).replace(/^([/\\])+/, ""));
  if (!f.startsWith(SITE)) { res.writeHead(403); res.end(); return; }
  fs.stat(f, (err, st) => {
    if (!err && st.isDirectory()) {
      if (!p.endsWith("/")) { res.writeHead(301, { Location: p + "/" + url.search }); res.end(); return; }
      f = path.join(f, "index.html");
      try { st = fs.statSync(f); } catch (e) { err = e; }
    }
    if (err || !st.isFile()) { served.notFound.push(p); res.writeHead(404, { "Content-Type": "text/plain" }); res.end("not found"); return; }
    const type = MIME[path.extname(f).toLowerCase()] || "application/octet-stream";
    res.writeHead(200, { "Content-Type": type, "Content-Length": st.size, "Cache-Control": "max-age=600" });
    served.requests++;
    if (req.method === "HEAD") { res.end(); return; }
    served.bytes += st.size;
    fs.createReadStream(f).pipe(res);
  });
});
await new Promise((r) => server.listen(Number(opt("--port", "0")), "127.0.0.1", r));
const BASE = REMOTE_BASE || `http://127.0.0.1:${server.address().port}${PREFIX}`;
say(`serving ${SITE} at ${BASE}/`);
if (SHOTS) fs.mkdirSync(SHOTS, { recursive: true });

// ---- what the page and the app look like right now --------------------------------------------
const LAUNCH = () => {
  const s = window.launchStatus || null;
  return s && { stage: s.stage, ready: s.ready, problem: s.problem, times: s.times, outputs: s.outputs,
                events: s.events.slice(-40), hidden: document.hidden };
};
const OUTPUTS = (ids) => {
  const one = (id) => {
    const e = document.getElementById(id);
    if (!e) return { id, found: false };
    const err = e.classList.contains("shiny-output-error") && !e.classList.contains("shiny-output-error-validation");
    const validation = e.classList.contains("shiny-output-error-validation");
    let content = false, detail = "";
    if (e.classList.contains("shiny-plot-output") || e.classList.contains("shiny-image-output")) {
      const img = e.querySelector("img");
      content = !!(img && img.getAttribute("src") && img.complete && img.naturalWidth > 0);
      detail = img ? `${img.naturalWidth}x${img.naturalHeight}` : "no image";
    } else if (e.classList.contains("html-widget-output") || e.querySelector("table.dataTable")) {
      const rows = [...e.querySelectorAll("table.dataTable tbody tr")];
      const empty = e.querySelector("td.dataTables_empty");
      content = rows.length > 0 && !empty;
      detail = `${rows.length} rows${empty ? " (empty: " + empty.textContent.trim() + ")" : ""}`;
    } else {
      const t = (e.innerText || e.textContent || "").trim();
      content = t.length > 0 || !!e.querySelector("img,svg,canvas,table");
      detail = t.replace(/\s+/g, " ").slice(0, 120);
    }
    return { id, found: true, content: content && !err && !validation, err, validation,
             recalc: e.classList.contains("recalculating"), detail,
             text: err || validation ? (e.innerText || "").trim().slice(0, 400) : undefined };
  };
  const errors = [...document.querySelectorAll(".shiny-output-error:not(.shiny-output-error-validation)")]
    .map((e) => ({ id: e.id || e.className, text: (e.innerText || "").trim().slice(0, 400) }));
  return { outputs: ids.map(one), errors };
};
const appFrame = (page) => page.frames().find((f) => /\/app_[^/]+\/?/.test(f.url()));

async function waitReady(page, timeoutS, label) {
  const end = Date.now() + timeoutS * 1000;
  let s = null;
  while (Date.now() < end) {
    s = await page.evaluate(LAUNCH).catch(() => null);
    if (s && s.ready) return s;
    if (s && s.problem && (EXPECT_PROBLEM || !["slow", "stalled-compute"].includes(s.problem))) return s;
    await sleep(500);
  }
  say(`${label}: not ready after ${timeoutS} s`);
  return s;
}
// ---- interactions: real mouse and keyboard events in the app's frame --------------------------
//   {"name": "...", "viewport": [390, 844], "steps": [{"click": "css"}, {"dblclick": "css"},
//    {"focus": "css"}, {"key": "Escape"}, {"type": "text"}, {"wait": 300}],
//    "expect": [{"visible": "css"}, {"text": ["css", "exact text"]}, {"inViewport": "css"},
//    {"focused": "css"} (the focused element matches), {"attr": ["css", "name", "value"]},
//    {"style": ["css", "computed property", "regex"]} (for example a focus ring)],
//    "after": [steps], "timeout_s": 15}. A wait, a key and a click are each followed by waiting
//    (up to 10 s) for R to finish what they started.
const EXPECT = (list) => list.map((x) => {
  if (x.focused) {
    const a = document.activeElement;
    const got = a ? a.tagName.toLowerCase() + (a.id ? "#" + a.id : "") + (a.className && typeof a.className === "string" ? "." + a.className.trim().split(/\s+/).join(".") : "") : "nothing";
    return { sel: x.focused, ok: !!(a && a.matches(x.focused)), got, want: "focused" };
  }
  const sel = x.visible || x.inViewport || (x.text && x.text[0]) || (x.attr && x.attr[0]) || (x.style && x.style[0]);
  const e = document.querySelector(sel);
  const r = e && e.getBoundingClientRect();
  const shown = !!(r && r.width > 0 && r.height > 0);
  let ok = shown, got = shown ? "visible" : e ? "not visible" : "missing";
  if (x.text && e) { got = (e.innerText || e.textContent || "").replace(/\s+/g, " ").trim(); ok = got === x.text[1]; }
  if (x.attr && e) { got = e.getAttribute(x.attr[1]); ok = got === x.attr[2]; got = `${x.attr[1]}=${JSON.stringify(got)}`; }
  if (x.style && e) { got = getComputedStyle(e)[x.style[1]]; ok = new RegExp(x.style[2]).test(got); got = `${x.style[1]}: ${got}`; }
  if (x.inViewport && shown) {
    got = `left ${Math.round(r.left)}, right ${Math.round(r.right)}, top ${Math.round(r.top)}, bottom ${Math.round(r.bottom)} in ${innerWidth}x${innerHeight}`;
    ok = r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight;
  }
  return { sel, ok, got, want: x.text ? x.text[1] : x.attr ? `${x.attr[1]}=${JSON.stringify(x.attr[2])}` : x.inViewport ? "inside the viewport"
                               : x.style ? `${x.style[1]} matching /${x.style[2]}/` : "visible" };
});
const idle = (fr) => fr.evaluate(() => !document.documentElement.classList.contains("shiny-busy")).catch(() => false);
async function settle(fr, ms = 10000) {
  const end = Date.now() + ms;
  await sleep(150);
  while (Date.now() < end && !(await idle(fr))) await sleep(100);
  await sleep(250);
}
async function doSteps(page, fr, steps) {
  for (const st of steps || []) {
    if (st.wait) { await sleep(st.wait); await settle(fr); continue; }
    if (st.focus) {
      const ok = await fr.evaluate((sel) => { const e = document.querySelector(sel); if (e) { e.scrollIntoView({ block: "center" }); e.focus(); } return !!e; }, st.focus);
      if (!ok) throw new Error(`no element matches ${st.focus}`);
      await sleep(150); continue;
    }
    if (st.key) { await page.keyboard.press(st.key); await settle(fr); continue; }
    if (st.type) { await page.keyboard.type(st.type, { delay: 20 }); await settle(fr); continue; }
    const sel = st.click || st.dblclick;
    const h = await fr.$(sel);
    if (!h) throw new Error(`no element matches ${sel}`);
    await h.evaluate((e) => e.scrollIntoView({ block: "center" }));
    await sleep(200);
    await h.click(st.dblclick ? { count: 2 } : {});
    await settle(fr);
  }
}
async function runInteraction(page, it, size, shot) {
  const fr = appFrame(page);
  if (!fr) return { ok: false, detail: "no app frame" };
  if (it.viewport) {
    await page.setViewport({ width: it.viewport[0], height: it.viewport[1] });
    await page.evaluate(() => document.getElementById("app").scrollIntoView());
    await sleep(600);
  }
  try {
    await doSteps(page, fr, it.steps);
    const end = Date.now() + (it.timeout_s || 15) * 1000;
    let r = [];
    const seen = {};   // the last observation of each element while it existed (a toast expires)
    while (Date.now() < end) {
      r = await fr.evaluate(EXPECT, it.expect || []);
      r.forEach((x, k) => { if (x.got !== "missing") seen[k] = x.got; });
      if (r.every((x) => x.ok)) break;
      await sleep(250);
    }
    r.forEach((x, k) => { if (!x.ok && x.got === "missing" && seen[k]) x.got = `${seen[k]} (then it went away)`; });
    const bad = r.filter((x) => !x.ok).map((x) => `${x.sel}: got "${x.got}", expected ${x.want}`);
    // an interaction must not break another panel (a later reload starts a fresh R, which would hide it)
    await settle(fr);
    const after = await fr.evaluate(OUTPUTS, []).catch((e) => ({ errors: [{ id: "the app page", text: String(e) }] }));
    for (const e of after.errors || []) bad.push(`output ${e.id} shows an error: ${e.text}`);
    if (shot) await shot().catch(() => {});   // before the clean-up steps and at the interaction's size
    return { ok: !bad.length, detail: bad.join("; ") };
  } catch (e) {
    return { ok: false, detail: String(e && e.message || e) };
  } finally {
    await doSteps(page, fr, it.after).catch(() => {});
    if (it.viewport) { await page.setViewport(size); await sleep(400); }
  }
}

async function waitOutputs(page, ids, timeoutS) {
  const end = Date.now() + timeoutS * 1000;
  let r = null;
  while (Date.now() < end) {
    const fr = appFrame(page);
    r = fr ? await fr.evaluate(OUTPUTS, ids).catch((e) => ({ evalError: String(e) })) : { evalError: "no app frame" };
    if (r.outputs && (r.errors.length || r.outputs.every((o) => o.content || o.err))) return r;
    await sleep(500);
  }
  return r;
}

// ---- the site's accent, not bslib's compiled default blue --------------------------------------
const BRAND = () => {
  const probe = document.createElement("span");
  probe.style.color = "var(--accent)"; document.body.appendChild(probe);
  const accent = getComputedStyle(probe).color; probe.remove();
  const shown = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const name = (e) => e.tagName.toLowerCase() + (e.id ? "#" + e.id : "") + (typeof e.className === "string" && e.className.trim() ? "." + e.className.trim().split(/\s+/).slice(0, 2).join(".") : "");
  const stock = /rgba?\(0, 123, 194\b/;
  const blue = [];
  for (const e of document.querySelectorAll("body *")) {
    if (blue.length >= 6 || !shown(e)) continue;
    const cs = getComputedStyle(e);
    for (const k of ["color", "backgroundColor", "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor", "boxShadow"])
      if (stock.test(cs[k])) { blue.push(`${name(e)} ${k} ${cs[k]}`); break; }
  }
  const checks = [...document.querySelectorAll("input[type=radio]:checked, input[type=checkbox]:checked")].filter(shown)
    .filter((e) => getComputedStyle(e).backgroundColor !== accent).map((e) => `${name(e)} ${getComputedStyle(e).backgroundColor}`);
  const handles = [...document.querySelectorAll(".irs-handle")].filter(shown)
    .filter((e) => !(parseFloat(getComputedStyle(e).borderTopWidth) > 0)).map(name);
  return { accent, blue, checks, handles };
};
async function checkBrand(fr, where, fail) {
  const b = await fr.evaluate(BRAND).catch((e) => ({ error: String(e) }));
  if (b.error) { fail(`${where}: cannot read the app's colors: ${b.error}`); return; }
  for (const x of b.blue) fail(`${where}: ${x} is bslib's default blue, not the site's accent`);
  for (const x of b.checks) fail(`${where}: the checked ${x} is not filled with the accent (${b.accent})`);
  for (const x of b.handles) fail(`${where}: the slider handle ${x} has no visible border`);
}

// ---- the site's theme, in the app's page and in R --------------------------------------------
const THEME_WAIT_S = 30;
const pageTheme = (page) => page.evaluate(() => document.documentElement.getAttribute("data-theme") ||
  (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"));
const APP_THEME = (ids) => {
  const S = window.Shiny, iv = S && S.shinyapp && S.shinyapp.$inputValues;
  const plots = {};
  for (const id of ids) {
    const e = document.getElementById(id);
    if (e && e.classList.contains("shiny-plot-output") && (e.offsetWidth || e.offsetHeight)) plots[id] = (e.querySelector("img") || {}).src || "";
  }
  return { bs: document.documentElement.getAttribute("data-bs-theme"), input: iv ? iv.bp_theme ?? null : null,
           busy: document.documentElement.classList.contains("shiny-busy"), plots };
};
// toggle to the other theme and back; returns { ok, plots: how many plots were compared }
async function checkTheme(page, ids, t1, where, fail) {
  const appTheme = () => appFrame(page).evaluate(APP_THEME, ids).catch(() => null);
  let a = await appTheme(), ok = true, plots = 0;
  const bad = (m) => { ok = false; fail(where + m); };
  if (!a || a.bs !== t1) { bad(`the app shows the ${a && a.bs} theme on a ${t1} page`); return { ok, plots }; }
  if (a.input !== t1) { bad(`R has input$bp_theme = ${JSON.stringify(a.input)} on a ${t1} page`); return { ok, plots }; }
  await checkBrand(appFrame(page), `${where}${t1} theme`, fail);
  // R idle with the same images twice in a row: a redraw that a resize started must not pass for
  // the redraw that the theme starts
  const steady = async (ms) => {
    const end = Date.now() + ms;
    let x = await appTheme();
    while (Date.now() < end) {
      await sleep(600);
      const y = await appTheme();
      if (x && y && !x.busy && !y.busy && JSON.stringify(x.plots) === JSON.stringify(y.plots)) return y;
      x = y;
    }
    return x;
  };
  for (const want of [t1 === "dark" ? "light" : "dark", t1]) {
    const before = ((await steady(15000)) || {}).plots || {};
    plots = Object.values(before).filter(Boolean).length;
    await page.click("header.top .theme-toggle");
    const end = Date.now() + THEME_WAIT_S * 1000;
    await sleep(300);
    // the plot test belongs inside the wait: R may not have gone busy yet when the loop starts
    const redrawn = (x) => Object.keys(before).every((id) => !before[id] || (x.plots[id] && x.plots[id] !== before[id]));
    while (Date.now() < end) {
      a = await appTheme();
      if ((await pageTheme(page)) === want && a && a.bs === want && a.input === want && !a.busy && redrawn(a)) {
        const b = await steady(5000);   // and nothing redraws again just after
        if (b && !b.busy && JSON.stringify(b.plots) === JSON.stringify(a.plots)) break;
      }
      await sleep(200);
    }
    if (!a || a.bs !== want) { bad(`the theme toggle set the page to ${await pageTheme(page)}, the app stayed ${a && a.bs}`); break; }
    if (a.input !== want) { bad(`after switching to the ${want} theme, R still has input$bp_theme = ${JSON.stringify(a.input)}`); break; }
    if (a.busy) { bad(`after switching to the ${want} theme, R was still busy after ${THEME_WAIT_S} s`); break; }
    const same = Object.keys(before).filter((id) => before[id] && a.plots[id] === before[id]);
    if (same.length) bad(`after switching to the ${want} theme, ${same.join(", ")} kept the image drawn for the other theme`);
    const rt = await waitOutputs(page, ids, 30);
    for (const e of rt.errors || []) bad(`after switching to the ${want} theme: output ${e.id} shows an error: ${e.text}`);
    if (want !== t1) await checkBrand(appFrame(page), `${where}${want} theme`, fail);
  }
  return { ok, plots };
}

// ---- one app ----------------------------------------------------------------------------------
async function checkApp(spec) {
  const smoke = spec.smoke || {};
  const res = { app: spec.name, failures: [], warnings: [], timings: {} };
  const fail = (m) => { res.failures.push(m); say(`${spec.name}: FAIL ${m}`); };
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "smoke-profile-"));
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: true, userDataDir: profile,
    args: ["--no-first-run", "--no-default-browser-check", "--window-size=1440,900",
           ...(process.env.CI ? ["--no-sandbox"] : [])],
  });
  const consoleErrors = [];
  const remoteMissing = [];
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    page.on("response", (response) => { if (REMOTE_BASE && response.status() === 404 && response.url().startsWith(BASE + "/")) remoteMissing.push(response.url()); });
    page.on("pageerror", (e) => consoleErrors.push(`pageerror: ${String(e && e.message || e).slice(0, 300)}`));
    page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text().slice(0, 300)); });
    const url = `${BASE}/apps/${spec.name}/`;
    served.bytes = 0; served.requests = 0; served.since = Date.now();
    const notFound0 = served.notFound.length;
    if (LOG_REQUESTS) requestLog.push(`# ${spec.name}`);
    const start = Date.now();
    say(`${spec.name}: open ${url}`);
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });

    // Wait for a paint entry, rather than assuming Chrome has recorded one within 400 ms.
    await page.bringToFront();
    await page.waitForFunction(() => performance.getEntriesByName("first-contentful-paint").length > 0, { timeout: MAX_FCP }).catch(() => {});
    // the launch page, before waiting for R
    await sleep(100);
    const intro = await page.evaluate(() => ({
      title: (document.getElementById("launch-title") || {}).textContent || "",
      tries: document.querySelectorAll(".launch-try li").length,
      status: (document.querySelector(".app-status .status-stage") || {}).textContent || "",
      fcp: (performance.getEntriesByName("first-contentful-paint")[0] || {}).startTime || null,
      bar: !!document.querySelector("header.top .theme-toggle"),
      current: ((document.querySelector("header.top nav a[aria-current]") || {}).textContent || "").trim(),
    }));
    res.timings.fcp_ms = intro.fcp && Math.round(intro.fcp);
    if (intro.title.trim() !== spec.title) fail(`launch page title is "${intro.title}", expected "${spec.title}"`);
    if (intro.tries !== (spec.try || []).length) fail(`launch page lists ${intro.tries} things to try, expected ${(spec.try || []).length}`);
    if (!intro.fcp || intro.fcp > MAX_FCP) fail(`launch page first contentful paint ${intro.fcp ? Math.round(intro.fcp) + " ms" : "missing"} (limit ${MAX_FCP} ms)`);
    if (!intro.status.trim()) fail("the status line is empty");
    if (!intro.bar || intro.current !== "Operations") fail(`the launch page lacks the site's top bar with Operations current and the theme toggle (current: "${intro.current}")`);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, `${spec.name}-launch.png`) });

    // the app: ready, with content, without errors
    const st = await waitReady(page, smoke.timeout_s || 150, spec.name);
    res.timings.ready_s = st && st.times && st.times.ready;
    res.stage = st && st.stage; res.problem = st && st.problem;
    res.served_mb = REMOTE_BASE ? null : +(served.bytes / 1e6).toFixed(1);
    if (EXPECT_PROBLEM) {
      if (st && st.problem === EXPECT_PROBLEM) say(`${spec.name}: reported "${EXPECT_PROBLEM}" as expected`);
      else fail(`expected the launch page to report "${EXPECT_PROBLEM}", got ${JSON.stringify(st && { stage: st.stage, problem: st.problem })}`);
      const text = await page.evaluate(() => {
        const p = document.querySelector(".cover-problem");
        return p && !p.hidden ? p.querySelector(".problem-text").textContent : "";
      });
      res.problem_text = text;
      if (!text) fail("the problem panel is not shown");
      if (SHOTS) {
        await page.evaluate(() => document.getElementById("app").scrollIntoView());
        await page.screenshot({ path: path.join(SHOTS, `${spec.name}-problem-${EXPECT_PROBLEM}.png`) });
      }
      return res;
    }
    if (!st || !st.ready) {
      fail(`not ready: stage ${st && st.stage}, problem ${st && st.problem}, outputs ${JSON.stringify(st && st.outputs)}`);
      res.events = st && st.events;
    } else {
      say(`${spec.name}: ready at ${st.times.ready} s (served ${res.served_mb} MB)`);
      const r = await waitOutputs(page, smoke.outputs, 30);
      res.outputs = r.outputs;
      if (r.evalError) fail(`cannot read the app page: ${r.evalError}`);
      for (const o of r.outputs || []) {
        if (!o.found) fail(`output ${o.id} is not on the page`);
        else if (o.err) fail(`output ${o.id} shows an error: ${o.text}`);
        else if (o.validation) fail(`output ${o.id} shows only a message: ${o.text}`);
        else if (!o.content) fail(`output ${o.id} is empty (${o.detail})`);
      }
      for (const e of r.errors || []) if (!(smoke.outputs || []).includes(e.id)) fail(`output ${e.id} shows an error: ${e.text}`);
      for (const [id, want] of Object.entries(smoke.expect || {})) {
        const o = (r.outputs || []).find((x) => x.id === id);
        if (!o) fail(`expected value for ${id}, which is not in smoke.outputs`);
        else if (o.detail.trim() !== String(want)) fail(`output ${id} reads "${o.detail}", expected "${want}"`);
      }
      if (SHOTS) {
        await page.evaluate(() => document.getElementById("app").scrollIntoView());
        await sleep(300);
        const stage = await page.$("#app .app-stage");
        if (stage) await stage.screenshot({ path: path.join(SHOTS, `${spec.name}-app.png`) });
      }
      // optional: elements that must fit without sideways scrolling at a window width, for
      // example a table at phone width ({"selector": ".lc-heat", "width": 390})
      for (const fit of smoke.fit || []) {
        await page.setViewport({ width: fit.width, height: 900 });
        await sleep(1000);   // the app lays out again inside its frame
        const got = await appFrame(page).evaluate((sel) => [...document.querySelectorAll(sel)].map((e) => {
          let box = e.parentElement;
          while (box && box !== document.body && getComputedStyle(box).overflowX === "visible") box = box.parentElement;
          return { w: Math.ceil(e.getBoundingClientRect().width), room: box.clientWidth, right: Math.ceil(e.getBoundingClientRect().right),
                   frame: innerWidth, scrolls: box.scrollWidth > box.clientWidth + 1 };
        }), fit.selector).catch((e) => String(e));
        if (!Array.isArray(got) || !got.length) fail(`fit: ${fit.selector} is not on the page at ${fit.width} px (${got})`);
        else for (const g of got) {
          if (g.scrolls || g.w > g.room + 1 || g.right > g.frame + 1)
            fail(`fit: ${fit.selector} is ${g.w} px wide in a ${g.room} px box at a ${fit.width} px window (right edge ${g.right} of ${g.frame})`);
          else say(`${spec.name}: ${fit.selector} fits at ${fit.width} px (${g.w} of ${g.room} px)`);
        }
        if (SHOTS) {
          await page.evaluate(() => document.getElementById("app").scrollIntoView());
          const stage = await page.$("#app .app-stage");
          if (stage) await stage.screenshot({ path: path.join(SHOTS, `${spec.name}-fit-${fit.width}.png`) });
        }
      }
      if ((smoke.fit || []).length) { await page.setViewport({ width: 1440, height: 900 }); await sleep(500); }
      // the site's theme: the app shows the page's theme, R has it as input$bp_theme, and the top
      // bar's toggle switches the page, the app's page and R, after which R goes idle again and
      // every listed plot is drawn again (its image changes); the controls carry the accent in both
      const t1 = await pageTheme(page);
      const th = await checkTheme(page, smoke.outputs || [], t1, "", fail);
      res.theme = { page: t1, toggled: th.ok, plots_redrawn: th.plots };
      if (th.ok) say(`${spec.name}: the app follows the site's theme (${t1}, toggled and back; R had input$bp_theme each time` +
                     (th.plots ? `, ${th.plots} plot${th.plots > 1 ? "s" : ""} redrawn each time)` : `; no plot on this page)`));
      // the tabs
      for (const tab of smoke.tabs || []) {
        const fr = appFrame(page);
        const clicked = await fr.evaluate((name) => {
          const a = [...document.querySelectorAll(".nav-link")].find((x) => x.getAttribute("data-value") === name || x.textContent.trim() === name);
          if (a) a.click();
          return !!a;
        }, tab.tab).catch(() => false);
        if (!clicked) { fail(`tab "${tab.tab}" not found`); continue; }
        const tt = Date.now();
        const rt = await waitOutputs(page, tab.outputs, TAB_TIMEOUT_S);
        for (const o of rt.outputs || []) {
          if (!o.found) fail(`tab "${tab.tab}": output ${o.id} is not on the page`);
          else if (o.err) fail(`tab "${tab.tab}": output ${o.id} shows an error: ${o.text}`);
          else if (!o.content) fail(`tab "${tab.tab}": output ${o.id} is empty (${o.detail})`);
        }
        for (const e of rt.errors || []) fail(`tab "${tab.tab}": output ${e.id} shows an error: ${e.text}`);
        say(`${spec.name}: tab "${tab.tab}" filled in ${((Date.now() - tt) / 1000).toFixed(1)} s`);
        await checkBrand(fr, `tab "${tab.tab}"`, fail);
        if (tab.theme) {
          const t = await pageTheme(page);
          const th = await checkTheme(page, tab.outputs, t, `tab "${tab.tab}": `, fail);
          if (th.ok) say(`${spec.name}: tab "${tab.tab}" follows the theme (${th.plots} plot${th.plots === 1 ? "" : "s"} redrawn each time)`);
        }
        if (SHOTS) {
          const stage = await page.$("#app .app-stage");
          if (stage) await stage.screenshot({ path: path.join(SHOTS, `${spec.name}-tab-${tab.tab.replace(/[^A-Za-z0-9]+/g, "_")}.png`) });
        }
      }
      // the interactions: real mouse and keyboard events, in order, on the same page
      for (const it of smoke.interactions || []) {
        const tt = Date.now();
        const shot = SHOTS ? async () => {
          const stage = await page.$("#app .app-stage");
          if (stage) await stage.screenshot({ path: path.join(SHOTS, `${spec.name}-do-${it.name.replace(/[^A-Za-z0-9]+/g, "_").slice(0, 60)}.png`) });
        } : null;
        const r = await runInteraction(page, it, { width: 1440, height: 900 }, shot);
        if (!r.ok) fail(`interaction "${it.name}": ${r.detail}`);
        else say(`${spec.name}: interaction "${it.name}" passed in ${((Date.now() - tt) / 1000).toFixed(1)} s`);
        (res.interactions = res.interactions || []).push({ name: it.name, ok: r.ok, detail: r.detail || "" });
      }
      // still healthy after everything above: no problem reported, no failed panel, R idle
      const fin = await page.evaluate(LAUNCH).catch(() => null);
      if (!fin || fin.problem || (fin.outputs && fin.outputs.failed > 0))
        fail(`after the checks the launch page reports problem ${fin && fin.problem}, outputs ${JSON.stringify(fin && fin.outputs)}`);
      else if ((await idle(appFrame(page))) === false) {
        await settle(appFrame(page), 30000);
        if (!(await idle(appFrame(page)))) fail("after the checks R is still busy 30 s later");
      }
      // a second visit: the service worker now controls the page from the start
      if (RELOAD) {
        await page.reload({ waitUntil: "domcontentloaded" });
        const s2 = await waitReady(page, smoke.timeout_s || 150, `${spec.name} reload`);
        res.timings.reload_ready_s = s2 && s2.times && s2.times.ready;
        if (!s2 || !s2.ready) fail(`after a reload: not ready (stage ${s2 && s2.stage}, problem ${s2 && s2.problem})`);
        else {
          const r2 = await waitOutputs(page, smoke.outputs, 30);
          const bad = (r2.outputs || []).filter((o) => !o.content);
          if (bad.length || (r2.errors || []).length) fail(`after a reload: ${bad.map((o) => o.id).join(", ")} empty, ${(r2.errors || []).length} errors`);
          else say(`${spec.name}: reload ready at ${s2.times.ready} s`);
        }
      }
    }
    const missing = [...new Set([...served.notFound.slice(notFound0), ...remoteMissing])];
    if (missing.length && !EXPECT_PROBLEM) fail(`the site answered 404 for ${missing.slice(0, 8).join(", ")}${missing.length > 8 ? ` and ${missing.length - 8} more` : ""}`);
    // an uncaught error on the page, or a console error about one of the site's own files
    const own = consoleErrors.filter((m) => m.startsWith("pageerror:") || m.includes(PREFIX + "/"));
    if (own.length && !EXPECT_PROBLEM) fail(`the page logged ${own.length} error${own.length > 1 ? "s" : ""}: ${own.slice(0, 3).join(" | ")}`);
    const claimed = spec.first_load && spec.first_load.download_mb;
    if (claimed && res.served_mb && Math.abs(res.served_mb - claimed) / claimed > 0.35)
      res.warnings.push(`the first visit served ${res.served_mb} MB; the launch page says about ${claimed} MB`);
    res.total_s = +((Date.now() - start) / 1000).toFixed(1);
  } catch (e) {
    fail(`driver error: ${e && e.stack || e}`);
  } finally {
    res.console_errors = consoleErrors.slice(0, 30);
    await browser.close().catch(() => {});
    fs.rmSync(profile, { recursive: true, force: true });
  }
  return res;
}

const results = [];
for (const spec of apps) results.push(await checkApp(spec));
server.close();
if (served.notFound.length) say(`404s: ${[...new Set(served.notFound)].slice(0, 20).join(", ")}`);
if (LOG_REQUESTS) fs.writeFileSync(LOG_REQUESTS, requestLog.join("\n") + "\n");
if (REPORT) fs.writeFileSync(REPORT, JSON.stringify({ base: BASE, fault: FAULT || null, results }, null, 2));
console.log("\nSmoke test summary");
for (const r of results) {
  const t = r.timings || {};
  console.log(`  ${r.failures.length ? "FAIL" : "ok  "} ${r.app.padEnd(22)} launch paint ${t.fcp_ms ?? "-"} ms, ready ${t.ready_s ?? "-"} s` +
              `${t.reload_ready_s ? `, reload ready ${t.reload_ready_s} s` : ""}, served ${r.served_mb ?? "-"} MB`);
  for (const f of r.failures) console.log(`       - ${f}`);
  for (const w of r.warnings) console.log(`       warning: ${w}`);
}
const failed = results.filter((r) => r.failures.length).length;
console.log(failed ? `\n${failed} of ${results.length} apps failed` : `\nAll ${results.length} apps passed`);
process.exit(failed ? 1 : 0);
