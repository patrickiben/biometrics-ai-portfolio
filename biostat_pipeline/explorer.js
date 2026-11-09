/* biostat_pipeline/explorer.js: the deliverables pipeline explorer.
   Reads window.PIPELINE_DATA (written by build_v2.py from pipeline.json). No network requests, no storage beyond the
   shared theme preference that assets/ui.js keeps. Views: map (swimlane timeline), trace (what a deliverable needs and
   what a change to it reaches), list (by stage and gate) and standards (verified references). */
(function () {
  "use strict";
  var D = window.PIPELINE_DATA;
  var d = document;
  var root = d.getElementById("px");
  if (!root) return;
  if (!D || !D.records) {
    root.innerHTML = '<p class="px-empty">The pipeline data did not load. Open the <a href="EarlyPhase_Biostat_Pipeline_Handbook.pdf">handbook</a> instead.</p>';
    return;
  }

  var R = D.records, M = D.milestones, TR = D.tracks, DES = D.designs, ST = D.stages;
  var byId = {}, refByKey = {}, mIdx = {};
  R.forEach(function (r) { byId[r.id] = r; r.feeds = []; });
  R.forEach(function (r) { (r.depends_on || []).forEach(function (p) { if (byId[p]) byId[p].feeds.push(r.id); }); });
  (D.refs || []).forEach(function (f) { refByKey[f.key] = f; });
  M.forEach(function (m, i) { mIdx[m.id] = i; });
  var desName = {}; DES.forEach(function (x) { desName[x.code] = x.name; });
  var stName = {}; ST.forEach(function (s) { stName[s.n] = s.name; });

  /* ---------- small helpers ---------- */
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function el(id) { return d.getElementById(id); }
  function mName(id) { var m = M[mIdx[id]]; return m ? m.label : id; }
  function designsText(r) { return r.designs.indexOf("all") >= 0 ? "All designs" : r.designs.map(function (c) { return desName[c] || c; }).join(", "); }
  function worked(r) { return (r.toolkit || []).some(function (t) { return /^Worked study/i.test(t.label); }); }
  function closure(id, dir) {             // all ancestors (dir "up") or descendants ("down") with BFS depth
    var seen = {}, out = [], q = [[id, 0]];
    while (q.length) {
      var cur = q.shift(), r = byId[cur[0]];
      var next = dir === "up" ? (r.depends_on || []) : r.feeds;
      next.forEach(function (n) { if (!seen[n] && byId[n]) { seen[n] = cur[1] + 1; out.push(n); q.push([n, cur[1] + 1]); } });
    }
    return { ids: out, depth: seen };
  }

  /* ---------- state, URL hash ---------- */
  var S = { view: window.innerWidth < 760 ? "list" : "map", design: "all", track: "", owner: "", stage: "", q: "", ref: "", worked: false, sel: "" };
  function readHash() {
    var h = (location.hash || "").replace(/^#/, "");
    h.split("&").forEach(function (kv) {
      var p = kv.split("="); if (p.length !== 2) return;
      var k = decodeURIComponent(p[0]), v = decodeURIComponent(p[1]);
      if (k === "view" && /^(map|trace|list|standards)$/.test(v)) S.view = v;
      if (k === "d" && byId[v]) S.sel = v;
      if (k === "design" && (v === "all" || desName[v])) S.design = v;
      if (k === "ref" && refByKey[v]) S.ref = v;
      if (k === "q") S.q = v;
    });
  }
  function writeHash() {
    var parts = ["view=" + S.view];
    if (S.sel) parts.push("d=" + encodeURIComponent(S.sel));
    if (S.design !== "all") parts.push("design=" + S.design);
    if (S.ref) parts.push("ref=" + encodeURIComponent(S.ref));
    if (S.q) parts.push("q=" + encodeURIComponent(S.q));
    var h = "#" + parts.join("&");
    if (location.hash !== h) history.replaceState(null, "", h);
  }

  function matches(r) {
    if (S.design !== "all" && r.designs.indexOf("all") < 0 && r.designs.indexOf(S.design) < 0) return false;
    if (S.track && r.track !== S.track) return false;
    if (S.owner && r.owner !== S.owner) return false;
    if (S.stage && String(r.stage) !== S.stage) return false;
    if (S.ref && !(r.refs || []).some(function (f) { return f.key === S.ref; })) return false;
    if (S.worked && !worked(r)) return false;
    if (S.q) {
      var q = S.q.toLowerCase();
      var hay = [r.id, r.title, r.summary, r.why, r.owner, r.inputs_text, r.outputs_text, r.qc, (r.pitfalls || []).join(" "),
        (r.refs || []).map(function (f) { var x = refByKey[f.key]; return f.key + " " + (x ? x.title : ""); }).join(" ")].join(" ").toLowerCase();
      if (hay.indexOf(q) < 0) return false;
    }
    return true;
  }

  /* ---------- controls ---------- */
  function buildControls() {
    var dc = DES.map(function (x) {
      var n = R.filter(function (r) { return r.designs.indexOf("all") >= 0 || r.designs.indexOf(x.code) >= 0; }).length;
      return '<button type="button" class="px-chip" data-design="' + x.code + '" aria-pressed="false" title="' + esc(x.name) + '">' + esc(x.code) + ' <span class="n">' + n + '</span></button>';
    }).join("");
    el("px-designs").innerHTML = '<button type="button" class="px-chip" data-design="all" aria-pressed="true">All <span class="n">' + R.length + '</span></button>' + dc;
    function opts(sel, list, all) { el(sel).innerHTML = '<option value="">' + all + '</option>' + list.map(function (v) { return '<option>' + esc(v) + '</option>'; }).join(""); }
    opts("px-track", TR.map(function (t) { return t.name; }), "All tracks");
    var owners = {}; R.forEach(function (r) { owners[r.owner] = 1; });
    opts("px-owner", Object.keys(owners).sort(), "All owners");
    el("px-stage").innerHTML = '<option value="">All stages</option>' + ST.map(function (s) { return '<option value="' + s.n + '">' + s.n + ". " + esc(s.name) + "</option>"; }).join("");
  }
  function syncControls() {
    [].forEach.call(d.querySelectorAll("#px-designs .px-chip"), function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-design") === S.design)); });
    [].forEach.call(d.querySelectorAll(".px-tabs [role=tab]"), function (b) {
      var on = b.getAttribute("data-view") === S.view; b.setAttribute("aria-selected", String(on)); b.tabIndex = on ? 0 : -1;
    });
    [].forEach.call(d.querySelectorAll(".px-panel"), function (p) { p.hidden = p.getAttribute("data-view") !== S.view; });
    el("px-track").value = S.track; el("px-owner").value = S.owner; el("px-stage").value = S.stage;
    if (el("px-q").value !== S.q) el("px-q").value = S.q;
    el("px-worked").checked = S.worked;
    var rf = el("px-reffilter");
    if (S.ref) { var x = refByKey[S.ref]; rf.hidden = false; rf.querySelector("span").textContent = (x ? x.short || x.key : S.ref); }
    else rf.hidden = true;
  }

  /* ---------- map (swimlane timeline) ---------- */
  var CW = 112, LW = 158, HH = 6, RH = 46, NH = 40, PAD = 10;
  var NS = "http://www.w3.org/2000/svg";
  function svgEl(tag, attrs) { var n = d.createElementNS(NS, tag); for (var k in attrs) n.setAttribute(k, attrs[k]); return n; }
  var mapPos = {};
  function renderMap() {
    var host = el("px-map"), vis = R.filter(matches);
    CW = Math.max(100, Math.floor(((host.clientWidth || 1400) - LW - 14) / M.length));
    var visSet = {}; vis.forEach(function (r) { visSet[r.id] = 1; });
    // pack each lane
    var lanes = TR.map(function (t) {
      var items = vis.filter(function (r) { return r.track === t.name; }).sort(function (a, b) {
        return mIdx[a.window[0]] - mIdx[b.window[0]] || mIdx[a.window[1]] - mIdx[b.window[1]] || a.stage - b.stage || (a.id < b.id ? -1 : 1);
      });
      var ends = [], rows = [];
      items.forEach(function (r) {
        var f = mIdx[r.window[0]], to = mIdx[r.window[1]], k = 0;
        while (k < ends.length && ends[k] >= f) k++;
        ends[k] = to; rows.push([r, k]);
      });
      return { t: t, rows: rows, n: Math.max(ends.length, 1) };
    });
    var W = LW + M.length * CW + 12, y = HH;
    lanes.forEach(function (L) { L.y = y; L.h = L.n * RH + PAD * 2; y += L.h; });
    var H = y + 8;
    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, width: W, height: H, role: "group", "aria-label": "Deliverables by track and milestone. " + vis.length + " shown." });
    // gate bands and column rules; the milestone names sit in the sticky strip above the map
    M.forEach(function (m, i) {
      var x = LW + i * CW;
      if (m.gate) svg.appendChild(svgEl("rect", { x: x, y: 0, width: CW, height: H, "class": "px-gateband" }));
      svg.appendChild(svgEl("line", { x1: x, y1: 0, x2: x, y2: H, "class": "px-col" }));
    });
    var head = el("px-mhead-in");
    head.style.width = W + "px";
    head.innerHTML = '<div class="px-mcorner" style="width:' + LW + 'px">Track \u2193 · milestone \u2192</div>' + M.map(function (m, i) {
      return '<div class="px-mcell' + (m.gate ? " gate" : "") + '" style="left:' + (LW + i * CW) + "px;width:" + CW + 'px"><span class="id">' + m.id + "</span>" + esc(m.label) + "</div>";
    }).join("");
    lanes.forEach(function (L, li) {
      svg.appendChild(svgEl("rect", { x: 0, y: L.y, width: W, height: L.h, "class": "px-lane " + (li % 2 ? "odd" : "even") }));
      var lab = svgEl("g", { "class": "px-lanelab" });
      wrapText(lab, L.t.name, 12, L.y + 20, LW - 22, 14, "px-ltxt");
      var c = svgEl("text", { x: 12, y: L.y + L.h - 10, "class": "px-lcount" }); c.textContent = L.rows.length + " shown"; lab.appendChild(c);
      svg.appendChild(lab);
    });
    var edges = svgEl("g", { "class": "px-edges" }); svg.appendChild(edges);
    mapPos = {};
    lanes.forEach(function (L) {
      L.rows.forEach(function (pair) {
        var r = pair[0], k = pair[1];
        var f = mIdx[r.window[0]], to = mIdx[r.window[1]];
        var x = LW + f * CW + 5, w = (to - f + 1) * CW - 10, yy = L.y + PAD + k * RH;
        mapPos[r.id] = { x: x, y: yy, w: w };
        var g = svgEl("g", { "class": "px-node s" + r.stage + (r.conditional ? " cond" : "") + (worked(r) ? " wk" : ""), tabindex: "0", role: "button",
          "data-id": r.id, "aria-label": r.id + " " + r.title + ". " + mName(r.window[0]) + " to " + mName(r.window[1]) + "." });
        g.appendChild(svgEl("rect", { x: x, y: yy, width: w, height: NH, rx: 5 }));
        var tid = svgEl("text", { x: x + 8, y: yy + 15, "class": "px-nid" }); tid.textContent = r.id + " "; g.appendChild(tid);
        var lines = fitLines(r.title, [Math.max(0, w - 22 - r.id.length * 7.2), w - 18], 6.1);
        var t1 = svgEl("text", { x: x + 13 + r.id.length * 7.2, y: yy + 15, "class": "px-ntt" }); t1.textContent = (lines[0] || "") + (lines[1] ? " " : ""); g.appendChild(t1);
        if (lines[1]) { var t2 = svgEl("text", { x: x + 8, y: yy + 31, "class": "px-ntt" }); t2.textContent = lines[1]; g.appendChild(t2); }
        if (worked(r)) { var b = svgEl("circle", { cx: x + w - 9, cy: yy + 9, r: 3.5, "class": "px-wdot" }); g.appendChild(b); }
        var tip = svgEl("title", {}); tip.textContent = r.id + " · " + r.title; g.appendChild(tip);
        svg.appendChild(g);
      });
    });
    host.innerHTML = ""; host.appendChild(svg);
    host.onscroll = function () { el("px-mhead-in").style.transform = "translateX(" + (-host.scrollLeft) + "px)"; };
    host.onscroll();
    host.querySelectorAll(".px-node").forEach(function (n) {
      n.addEventListener("click", function () { select(n.getAttribute("data-id"), n); });
      n.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); select(n.getAttribute("data-id"), n); } });
      n.addEventListener("mouseenter", function () { highlight(n.getAttribute("data-id")); });
      n.addEventListener("mouseleave", function () { highlight(S.sel); });
      n.addEventListener("focus", function () { highlight(n.getAttribute("data-id")); });
    });
    highlight(S.sel);
  }
  function fitLines(text, widths, cw) {   // greedy wrap into len(widths) lines of the given pixel widths
    // On overflow the ellipsis follows a whole word or a hyphen, never a cut word or an open parenthesis, so the
    // visible text stays part of the node's accessible name (WCAG 2.5.3) and reads cleanly.
    var words = String(text).split(/\s+/), lines = widths.map(function () { return []; }), i = 0;
    var maxOf = function (li) { return Math.floor(widths[li] / cw); };
    var used = function (li) { return lines[li].join(" ").length; };
    widths.forEach(function (wpx, li) {
      while (i < words.length && (used(li) ? used(li) + 1 : 0) + words[i].length <= maxOf(li)) { lines[li].push(words[i]); i++; }
    });
    if (i < words.length) {
      var last = lines.length - 1, parts = words[i].split("-"), pre = "";
      for (var j = 0; j < parts.length - 1; j++) {
        var c = pre + parts[j] + "-";
        if ((used(last) ? used(last) + 1 : 0) + c.length + 1 <= maxOf(last)) pre = c; else break;
      }
      if (pre) lines[last].push(pre);
      var open = function () { var s = lines.map(function (l) { return l.join(" "); }).join(" "); return (s.match(/\(/g) || []).length > (s.match(/\)/g) || []).length; };
      var lastFilled = function () { var li = lines.length - 1; while (li > 0 && !lines[li].length) li--; return li; };
      for (;;) {
        var li = lastFilled();
        if (!lines[li].length || (used(li) + 1 <= maxOf(li) && !open())) break;
        lines[li].pop();
      }
      var lf = lastFilled(), tail = lines[lf].length ? lines[lf].pop().replace(/[,;:]$/, "") : "";
      lines[lf].push(tail + "…");
    }
    return lines.map(function (l) { return l.join(" "); });
  }
  function wrapText(g, text, x, y, maxW, lh, cls) {
    var words = String(text).split(/\s+/), line = "", lines = [];
    words.forEach(function (w) { var t = line ? line + " " + w : w; if (t.length * 6.2 > maxW && line) { lines.push(line); line = w; } else line = t; });
    if (line) lines.push(line);
    lines.slice(0, 3).forEach(function (l, i) { var t = d.createElementNS(NS, "text"); t.setAttribute("x", x); t.setAttribute("y", y + i * lh); t.setAttribute("class", cls); if (g.getAttribute("class") && /px-mh/.test(g.getAttribute("class"))) t.setAttribute("text-anchor", "middle"); t.textContent = l; g.appendChild(t); });
  }
  function highlight(id) {
    var svg = el("px-map").querySelector("svg"); if (!svg) return;
    var edges = svg.querySelector(".px-edges"); edges.innerHTML = "";
    var nodes = svg.querySelectorAll(".px-node");
    if (!id || !mapPos[id]) { [].forEach.call(nodes, function (n) { n.classList.remove("dim", "up", "down", "on"); }); return; }
    var up = closure(id, "up"), dn = closure(id, "down"), on = {};
    up.ids.forEach(function (x) { on[x] = "up"; }); dn.ids.forEach(function (x) { on[x] = "down"; }); on[id] = "on";
    [].forEach.call(nodes, function (n) {
      var k = on[n.getAttribute("data-id")];
      n.classList.toggle("dim", !k); n.classList.toggle("up", k === "up"); n.classList.toggle("down", k === "down"); n.classList.toggle("on", k === "on");
    });
    var r = byId[id];
    function edge(a, b, cls) {
      var A = mapPos[a], B = mapPos[b]; if (!A || !B) return;
      var x1 = A.x + A.w, y1 = A.y + NH / 2, x2 = B.x, y2 = B.y + NH / 2;
      if (x2 < x1 + 8) { x1 = A.x + Math.min(A.w, 30); y1 = A.y + (B.y > A.y ? NH : 0); x2 = B.x + Math.min(B.w, 30); y2 = B.y + (B.y > A.y ? 0 : NH); }
      var mx = (x1 + x2) / 2, p = "M" + x1 + "," + y1 + " C" + mx + "," + y1 + " " + mx + "," + y2 + " " + x2 + "," + y2;
      edges.appendChild(svgEl("path", { d: p, "class": "px-edge " + cls }));
    }
    (r.depends_on || []).forEach(function (p) { edge(p, id, "up"); });
    r.feeds.forEach(function (c) { edge(id, c, "down"); });
  }

  /* ---------- trace (what it needs, what a change reaches) ---------- */
  function renderTrace() {
    var host = el("px-trace");
    if (!S.sel) {
      host.innerHTML = '<div class="px-empty"><p><strong>Pick a deliverable to trace.</strong> Click one on the map or in the list, or start with a common one:</p><p class="px-starts">' +
        ["S2-01", "S1-02", "S2-06", "S3-20", "S4-01"].filter(function (x) { return byId[x]; }).map(function (x) { return '<button type="button" class="px-link" data-go="' + x + '">' + x + " " + esc(byId[x].title) + "</button>"; }).join("") + "</p></div>";
      return;
    }
    var r = byId[S.sel], up = closure(S.sel, "up"), dn = closure(S.sel, "down");
    function cols(c, dir) {
      var by = {}; c.ids.forEach(function (x) { var k = c.depth[x]; (by[k] = by[k] || []).push(x); });
      var keys = Object.keys(by).map(Number).sort(function (a, b) { return dir === "up" ? b - a : a - b; });
      return keys.map(function (k) {
        return '<div class="px-tcol"><p class="px-tstep">' + (dir === "up" ? k + (k === 1 ? " step before" : " steps before") : k + (k === 1 ? " step after" : " steps after")) + "</p>" +
          by[k].sort().map(function (x) { var y = byId[x]; return '<button type="button" class="px-tcard s' + y.stage + '" data-go="' + x + '"><span class="i">' + x + "</span>" + esc(y.title) + "</button>"; }).join("") + "</div>";
      }).join("");
    }
    var stCount = {}; dn.ids.forEach(function (x) { var s = byId[x].stage; stCount[s] = (stCount[s] || 0) + 1; });
    var impact = Object.keys(stCount).sort().map(function (s) { return '<li><span class="n">' + stCount[s] + "</span> in stage " + s + " · " + esc(stName[s]) + "</li>"; }).join("");
    host.innerHTML =
      '<div class="px-tsum"><div><p class="px-kick">Tracing</p><h2><span class="i">' + r.id + "</span> " + esc(r.title) + "</h2>" +
      '<p class="px-tline">Needs <strong>' + up.ids.length + "</strong> upstream deliverable" + (up.ids.length === 1 ? "" : "s") +
      ". A change to it reaches <strong>" + dn.ids.length + "</strong> downstream deliverable" + (dn.ids.length === 1 ? "" : "s") + ".</p></div>" +
      (dn.ids.length ? '<div class="px-impact"><p class="px-kick">If it changes, recheck</p><ul>' + impact + "</ul></div>" : "") + "</div>" +
      '<div class="px-tflow"><div class="px-tside up">' + (up.ids.length ? cols(up, "up") : '<p class="px-none">Nothing upstream: a starting point.</p>') + "</div>" +
      '<div class="px-tcol focus"><p class="px-tstep">Selected</p><button type="button" class="px-tcard s' + r.stage + ' on" data-open="' + r.id + '"><span class="i">' + r.id + "</span>" + esc(r.title) + "</button></div>" +
      '<div class="px-tside down">' + (dn.ids.length ? cols(dn, "down") : '<p class="px-none">Nothing downstream: an end point.</p>') + "</div></div>";
  }

  /* ---------- list ---------- */
  function renderList() {
    var vis = R.filter(matches), host = el("px-list");
    if (!vis.length) { host.innerHTML = '<p class="px-empty">No deliverables match these filters. <button type="button" class="px-link" data-reset="1">Clear filters</button></p>'; return; }
    host.innerHTML = ST.map(function (s) {
      var items = vis.filter(function (r) { return r.stage === s.n; });
      if (!items.length) return "";
      return '<section class="px-stage s' + s.n + '" aria-labelledby="pxs' + s.n + '"><header><p class="px-kick">Stage ' + s.n + '</p><h2 id="pxs' + s.n + '">' + esc(s.name) + '</h2><p class="px-gate">Closes at <strong>' + esc(mName(s.gate)) + "</strong> · " + items.length + " shown</p></header><ul>" +
        items.map(function (r) {
          return '<li><button type="button" class="px-row" data-open="' + r.id + '"><span class="i">' + r.id + '</span><span class="t">' + esc(r.title) +
            (r.conditional ? ' <span class="px-cond">conditional</span>' : "") + (worked(r) ? ' <span class="px-wk">worked study</span>' : "") +
            '</span><span class="o">' + esc(r.owner) + '</span><span class="w">' + esc(r.window[0]) + " → " + esc(r.window[1]) + '</span><span class="g">' + esc(designsText(r)) + "</span></button></li>";
        }).join("") + "</ul></section>";
    }).join("");
  }

  /* ---------- standards ---------- */
  function renderStandards() {
    var host = el("px-standards"), refs = (D.refs || []).slice();
    var cite = {}; R.forEach(function (r) { (r.refs || []).forEach(function (f) { cite[f.key] = (cite[f.key] || 0) + 1; }); });
    if (!refs.length) { host.innerHTML = '<p class="px-empty">The verified reference table is not in this build.</p>'; return; }
    refs.sort(function (a, b) { return (a.issuer + a.title).localeCompare(b.issuer + b.title); });
    host.innerHTML = '<p class="px-note">Each reference was checked against its issuing body\'s own page on <strong>' + esc(D.refs_checked_on || "") +
      '</strong>. Confirm the version that applies to your study and submission before relying on it.</p><div class="px-tablewrap" role="region" aria-label="Verified references" tabindex="0"><table class="px-refs"><thead><tr><th scope="col">Reference</th><th scope="col">Issuer</th><th scope="col">Version and date</th><th scope="col">Status</th><th scope="col">Cited by</th></tr></thead><tbody>' +
      refs.map(function (f) {
        var n = cite[f.key] || 0;
        return "<tr><td><a href=\"" + esc(f.url) + "\" rel=\"noopener\" target=\"_blank\">" + esc(f.title) + '</a><span class="px-key">' + esc(f.key) + "</span></td><td>" + esc(f.issuer) + "</td><td>" + esc([f.version, f.date].filter(Boolean).join(", ")) +
          '</td><td><span class="px-status ' + esc(f.status) + '">' + esc(f.status) + (f.superseded_by ? " · see " + esc(f.superseded_by) : "") + "</span></td><td>" +
          (n ? '<button type="button" class="px-link" data-ref="' + esc(f.key) + '">' + n + " deliverable" + (n === 1 ? "" : "s") + "</button>" : "0") + "</td></tr>";
      }).join("") + "</tbody></table></div>";
  }

  /* ---------- detail drawer ---------- */
  var lastFocus = null;
  function select(id, from) { S.sel = id; lastFocus = from || d.activeElement; writeHash(); openDrawer(id); highlight(id); if (S.view === "trace") renderTrace(); }
  function chipsFor(list) { return list.map(function (x) { var y = byId[x]; return y ? '<button type="button" class="px-dep s' + y.stage + '" data-open="' + x + '" title="' + esc(y.title) + '">' + x + " " + esc(y.title) + "</button>" : ""; }).join(""); }
  function openDrawer(id) {
    var r = byId[id], dr = el("px-drawer"); if (!r) return;
    var a = mIdx[r.window[0]], b = mIdx[r.window[1]];
    var bar = M.map(function (m, i) { return '<span class="' + (i >= a && i <= b ? "on" : "") + (m.gate ? " gate" : "") + '" title="' + esc(m.label) + '"></span>'; }).join("");
    var refs = (r.refs || []).map(function (f) {
      var x = refByKey[f.key];
      return "<li>" + (x ? '<a href="' + esc(x.url) + '" rel="noopener" target="_blank">' + esc(x.title) + "</a>" + (x.version || x.date ? ' <span class="px-meta">' + esc([x.version, x.date].filter(Boolean).join(", ")) + "</span>" : "") : "<strong>" + esc(f.key) + "</strong>") +
        (f.note ? '<span class="px-rnote">' + esc(f.note) + "</span>" : "") + "</li>";
    }).join("");
    var tk = (r.toolkit || []).map(function (t) { return '<li><a href="../' + esc(t.href) + '">' + esc(t.label) + "</a></li>"; }).join("");
    el("px-dbody").className = "px-dbody s" + r.stage;
    dr.scrollTop = 0;
    el("px-dbody").innerHTML =
      '<p class="px-kick">Stage ' + r.stage + " · " + esc(stName[r.stage]) + "</p>" +
      '<h2 id="px-dtitle"><span class="i">' + r.id + "</span> " + esc(r.title) + "</h2>" +
      '<p class="px-chips"><span class="px-tag">' + esc(r.type) + '</span><span class="px-tag">' + esc(r.track) + '</span><span class="px-tag own">' + esc(r.owner) + "</span>" +
      (r.contributors && r.contributors.length ? '<span class="px-tag">with ' + esc(r.contributors.join(", ")) + "</span>" : "") + "</p>" +
      '<div class="px-when"><div class="px-bar" aria-hidden="true">' + bar + '</div><p>' + esc(mName(r.window[0])) + " → " + esc(mName(r.window[1])) + " · " + esc(designsText(r)) + "</p>" +
      (r.conditional ? '<p class="px-condnote">' + esc(r.conditional) + "</p>" : "") + "</div>" +
      "<h3>What it is</h3><p>" + esc(r.summary) + "</p>" +
      (r.why ? "<h3>Why it matters</h3><p>" + esc(r.why) + "</p>" : "") +
      "<h3>Needs</h3><p>" + esc(r.inputs_text) + "</p>" + ((r.depends_on || []).length ? '<p class="px-deps">' + chipsFor(r.depends_on) + "</p>" : "") +
      "<h3>Produces</h3><p>" + esc(r.outputs_text) + "</p>" + (r.feeds.length ? '<p class="px-sub">Feeds</p><p class="px-deps">' + chipsFor(r.feeds) + "</p>" : "") +
      "<h3>Quality control</h3><p>" + esc(r.qc) + "</p>" +
      ((r.pitfalls || []).length ? '<h3>Common pitfalls</h3><ul class="px-pit">' + r.pitfalls.map(function (p) { return "<li>" + esc(p) + "</li>"; }).join("") + "</ul>" : "") +
      (refs ? '<h3>Standards and guidance</h3><ul class="px-rlist">' + refs + "</ul>" : "") +
      (tk ? '<h3>In this toolkit</h3><ul class="px-tk">' + tk + "</ul>" : "") +
      '<p class="px-actions"><button type="button" class="px-btn" data-trace="' + r.id + '">Trace what it needs and what it feeds</button></p>';
    dr.hidden = false; dr.classList.add("open"); d.body.classList.add("px-drawer-open");
    el("px-dclose").focus();
  }
  function closeDrawer() {
    var dr = el("px-drawer"); dr.classList.remove("open"); dr.hidden = true; d.body.classList.remove("px-drawer-open");
    S.sel = ""; writeHash(); highlight("");
    if (lastFocus && lastFocus.focus && d.body.contains(lastFocus)) lastFocus.focus();
  }

  /* ---------- export for the register workspace ---------- */
  function exportRows() {
    return R.filter(matches).map(function (r) {
      return { id: r.id, stage: "Stage " + r.stage + ": " + stName[r.stage], deliverable: r.title, type: r.type, description: r.summary, owner: r.owner,
        inputs: r.inputs_text, outputs: r.outputs_text,
        standard: (r.refs || []).map(function (f) { var x = refByKey[f.key]; return x ? (x.short || x.title) : f.key; }).join("; "), qc: r.qc };
    });
  }
  function download(name, text, type) {
    var b = new Blob([text], { type: type }), a = d.createElement("a");
    a.href = URL.createObjectURL(b); a.download = name; d.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 0);
  }

  /* ---------- render all ---------- */
  function renderCount() {
    var n = R.filter(matches).length;
    el("px-count").textContent = n === R.length ? "Showing all " + n + " deliverables" : "Showing " + n + " of " + R.length + " deliverables";
  }
  function render() {
    syncControls(); renderCount();
    if (S.view === "map") renderMap();
    if (S.view === "trace") renderTrace();
    if (S.view === "list") renderList();
    if (S.view === "standards") renderStandards();
    writeHash();
  }

  /* ---------- events ---------- */
  function setView(v) { S.view = v; render(); var p = d.querySelector('.px-panel[data-view="' + v + '"]'); if (p && v !== "map") p.focus({ preventScroll: true }); }
  root.addEventListener("click", function (e) {
    var t = e.target.closest ? e.target.closest("button, a") : null; if (!t) return;
    if (t.hasAttribute("data-design")) { S.design = t.getAttribute("data-design"); render(); }
    else if (t.hasAttribute("data-view")) setView(t.getAttribute("data-view"));
    else if (t.hasAttribute("data-open")) select(t.getAttribute("data-open"), t);
    else if (t.hasAttribute("data-go")) { S.sel = t.getAttribute("data-go"); renderTrace(); writeHash(); highlight(S.sel); }
    else if (t.hasAttribute("data-trace")) { S.sel = t.getAttribute("data-trace"); closeDrawerOnly(); setView("trace"); }
    else if (t.hasAttribute("data-ref")) { S.ref = t.getAttribute("data-ref"); setView("list"); }
    else if (t.hasAttribute("data-reset")) { S.design = "all"; S.track = S.owner = S.stage = S.q = S.ref = ""; S.worked = false; render(); }
    else if (t.id === "px-clearref") { S.ref = ""; render(); }
    else if (t.id === "px-dclose") closeDrawer();
    else if (t.id === "px-export-json") download("pipeline-register-starter.json", JSON.stringify({ schema: 1, kind: "toolkit-pipeline-register", study: "", rows: exportRows() }, null, 1), "application/json");
  });
  function closeDrawerOnly() { var dr = el("px-drawer"); dr.classList.remove("open"); dr.hidden = true; d.body.classList.remove("px-drawer-open"); }
  d.addEventListener("keydown", function (e) { if (e.key === "Escape" && !el("px-drawer").hidden) closeDrawer(); });
  el("px-track").addEventListener("change", function () { S.track = this.value; render(); });
  el("px-owner").addEventListener("change", function () { S.owner = this.value; render(); });
  el("px-stage").addEventListener("change", function () { S.stage = this.value; render(); });
  el("px-worked").addEventListener("change", function () { S.worked = this.checked; render(); });
  var qt; el("px-q").addEventListener("input", function () { var v = this.value; clearTimeout(qt); qt = setTimeout(function () { S.q = v.trim(); render(); }, 160); });
  // arrow keys between tabs
  d.querySelector(".px-tabs").addEventListener("keydown", function (e) {
    var tabs = [].slice.call(this.querySelectorAll("[role=tab]")), i = tabs.indexOf(d.activeElement);
    if (i < 0 || (e.key !== "ArrowRight" && e.key !== "ArrowLeft")) return;
    e.preventDefault(); var n = tabs[(i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length]; n.focus(); setView(n.getAttribute("data-view"));
  });

  var rz; window.addEventListener("resize", function () { clearTimeout(rz); rz = setTimeout(function () { if (S.view === "map") renderMap(); }, 200); });
  readHash(); buildControls(); render();
  if (S.sel && S.view !== "trace") openDrawer(S.sel);
  root.classList.add("ready");
})();
