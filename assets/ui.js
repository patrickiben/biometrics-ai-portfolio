/* assets/ui.js: theme toggle ("bp-theme"; Quarto kept in step), Menu, the hub filter, Copy, print.
   No network. build_pages.py copies it inline where a page loads no files. */
(function () {
  "use strict";
  var d = document, root = d.documentElement, KEY = "bp-theme";
  var mq = window.matchMedia ? window.matchMedia("(prefers-color-scheme: light)") : null;
  function saved() { try { var t = localStorage.getItem(KEY); return t === "light" || t === "dark" ? t : null; } catch (e) { return null; } }
  function current() { return root.getAttribute("data-theme") || (mq && mq.matches ? "light" : "dark"); }
  function quarto(t) {
    if (typeof window.quartoToggleColorScheme !== "function" || !d.body) return;
    if (d.body.classList.contains("quarto-dark") !== (t === "dark")) window.quartoToggleColorScheme();
  }
  function paint() {
    var t = current(), dark = t === "dark";
    d.querySelectorAll(".theme-toggle").forEach(function (b) {
      b.setAttribute("aria-pressed", dark ? "true" : "false");
      b.title = dark ? "Switch to light theme" : "Switch to dark theme";
    });
    d.querySelectorAll('meta[name="theme-color"]').forEach(function (m) { m.content = dark ? "#0b0f15" : "#f4f6f9"; });
    d.querySelectorAll('source[media*="prefers-color-scheme"], source[data-media]').forEach(function (s) {
      var q = s.getAttribute("data-media") || s.getAttribute("media"); s.setAttribute("data-media", q);
      s.media = (/dark/.test(q) === dark) ? "all" : "not all";
    });
  }
  function apply(t, store) {
    root.classList.add("theme-switching");
    if (t) root.setAttribute("data-theme", t); else root.removeAttribute("data-theme");
    if (store) { try { if (t) localStorage.setItem(KEY, t); else localStorage.removeItem(KEY); } catch (e) {} }
    paint(); quarto(current());
    requestAnimationFrame(function () { requestAnimationFrame(function () { root.classList.remove("theme-switching"); }); });
  }
  d.addEventListener("click", function (e) {
    var b = e.target.closest ? e.target.closest(".theme-toggle, [data-theme-reset], .menu-toggle") : null;
    if (!b) return;
    if (b.classList.contains("theme-toggle")) apply(current() === "dark" ? "light" : "dark", true);
    else if (b.hasAttribute("data-theme-reset")) apply(null, true);
    else menu(b, b.getAttribute("aria-expanded") !== "true");
  });
  window.addEventListener("storage", function (e) { if (e.key === KEY) apply(saved(), false); });
  if (mq && mq.addEventListener) mq.addEventListener("change", function () { if (!saved()) apply(null, false); });

  /* Menu: a disclosure; Escape, a click outside or a link closes it */
  function menu(btn, open) {
    var bar = btn.closest(".top"); if (!bar) return;
    bar.classList.toggle("open", open);
    btn.setAttribute("aria-expanded", open ? "true" : "false");
  }
  function closeMenus(focus) {
    d.querySelectorAll('.menu-toggle[aria-expanded="true"]').forEach(function (b) { menu(b, false); if (focus) b.focus(); });
  }
  d.addEventListener("keydown", function (e) { if (e.key === "Escape") closeMenus(true); });
  d.addEventListener("click", function (e) {
    if (!e.target.closest) return;
    if (e.target.closest(".top .nav a") || !e.target.closest(".top")) closeMenus(false);
  });

  /* filter: chips and a search box; it only hides, never reorders */
  function filter(box) {
    var scope = d.querySelector(box.getAttribute("data-filter")) || d.body;
    var items = [].slice.call(scope.querySelectorAll("[data-item]"));
    var groups = [].slice.call(scope.querySelectorAll("[data-group]"));
    var q = box.querySelector('input[type="search"]'), out = box.querySelector(".count");
    var noun = box.getAttribute("data-noun") || "items", empty = scope.querySelector(".f-empty");
    function on(attr) { var b = box.querySelector("button[" + attr + '][aria-pressed="true"]'); return b ? b.getAttribute(attr) : ""; }
    function run() {
      var st = on("data-f-stage"), lb = on("data-f-label"), text = q ? q.value.trim().toLowerCase() : "", n = 0;
      items.forEach(function (el) {
        var ok = (!st || (" " + (el.getAttribute("data-stages") || "") + " ").indexOf(" " + st + " ") > -1) &&
                 (!lb || (" " + (el.getAttribute("data-labels") || "") + " ").indexOf(" " + lb + " ") > -1) &&
                 (!text || el.textContent.toLowerCase().indexOf(text) > -1);
        el.hidden = !ok; if (ok) n++;
        if (ok && text && el.tagName === "DETAILS") el.open = true;   /* a search shows its matches */
      });
      groups.forEach(function (g) { g.hidden = !g.querySelector("[data-item]:not([hidden])"); });
      if (out) out.textContent = n ? n + " of " + items.length + " " + noun + " shown" : "No " + noun + " match; 0 of " + items.length + " shown";
      if (empty) empty.hidden = n > 0;
    }
    function reset() {
      box.querySelectorAll('button[aria-pressed="true"]').forEach(function (x) { x.setAttribute("aria-pressed", "false"); });
      if (q) q.value = "";
      run();
      if (q) q.focus();
    }
    if (empty) empty.addEventListener("click", function (e) { if (e.target.closest("[data-f-reset]")) reset(); });
    box.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-f-stage], button[data-f-label]"); if (!b) return;
      var attr = b.hasAttribute("data-f-stage") ? "data-f-stage" : "data-f-label", was = b.getAttribute("aria-pressed") === "true";
      box.querySelectorAll("button[" + attr + "]").forEach(function (x) { x.setAttribute("aria-pressed", "false"); });
      b.setAttribute("aria-pressed", was ? "false" : "true"); run();
    });
    if (q) q.addEventListener("input", run);
    d.addEventListener("keydown", function (e) {
      if (e.key !== "/" || !q || e.ctrlKey || e.metaKey || e.altKey) return;
      var t = e.target; if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      e.preventDefault(); q.focus();
    });
    run();
  }

  function copyButtons() {
    var pres = [].slice.call(d.querySelectorAll("pre.cmd"));
    d.querySelectorAll("pre > code.language-sh").forEach(function (c) { if (pres.indexOf(c.parentNode) < 0) pres.push(c.parentNode); });
    pres.forEach(function (pre) {
      pre.classList.add("cmd");
      var b = d.createElement("button"); b.type = "button"; b.className = "copy"; b.textContent = "Copy";
      b.addEventListener("click", function () {
        var txt = (pre.querySelector("code") || pre).textContent;
        function done(ok) { b.textContent = ok ? "Copied" : "Select"; setTimeout(function () { b.textContent = "Copy"; }, 1600); }
        try { navigator.clipboard.writeText(txt).then(function () { done(true); }, function () { sel(); done(false); }); }
        catch (e) { sel(); done(false); }
        function sel() { var r = d.createRange(); r.selectNodeContents(pre.querySelector("code") || pre); var s = getSelection(); s.removeAllRanges(); s.addRange(r); }
      });
      pre.appendChild(b);
    });
  }

  /* lifecycle stages: disclosures, open by default; on phones all but a linked stage start folded */
  function stages() {
    var list = [].slice.call(d.querySelectorAll("details.stage-sec"));
    if (!list.length) return;
    function target() { var id = location.hash ? decodeURIComponent(location.hash.slice(1)) : ""; var t = id && d.getElementById(id); return t && t.matches("details.stage-sec") ? t : null; }
    var t = target();
    if (window.matchMedia && window.matchMedia("(max-width: 719.98px)").matches) {
      list.forEach(function (x) { if (x !== t) x.open = false; });
      if (t) t.scrollIntoView();
    }
    window.addEventListener("hashchange", function () { var x = target(); if (x) { x.open = true; x.scrollIntoView(); } });
    d.querySelectorAll("[data-f-expand]").forEach(function (b) {
      function label() { var all = list.every(function (x) { return x.open; }); b.textContent = all ? "Fold all stages" : "Open all stages"; }
      b.addEventListener("click", function () { var all = list.every(function (x) { return x.open; }); list.forEach(function (x) { x.open = !all; }); label(); });
      list.forEach(function (x) { x.addEventListener("toggle", label); });
      label();
    });
  }

  /* keyboard access: a box that scrolls and holds nothing tabbable takes focus, with a name unique on the page.
     data-scroll-focus lists the attributes this script added; only those are removed when the box stops
     scrolling. A table or list keeps its native role. */
  var TABBABLE = 'a[href]:not([tabindex^="-"]), button:not([tabindex^="-"]), input:not([tabindex^="-"]), select:not([tabindex^="-"]), textarea:not([tabindex^="-"]), summary:not([tabindex^="-"]), [tabindex]:not([tabindex^="-"])';
  function scrollName(el, used) {
    var kind = el.matches("pre, div.sourceCode") ? "Code" : el.matches("table") || el.querySelector("table") ? "Table" : "Scrolling region";
    var cap = el.querySelector("caption"), t = cap ? cap.textContent : "";
    /* the nearest earlier rendered heading, inside the box's own tab panel when it has one; else that panel's tab */
    function near(root) { var hs = root.querySelectorAll("h1, h2, h3, h4, h5, h6"); for (var i = hs.length - 1; i >= 0; i--) if ((hs[i].compareDocumentPosition(el) & 4) && hs[i].getClientRects().length) return hs[i].textContent; return ""; }
    var panel = el.closest('[role="tabpanel"]');
    if (!t && panel) { t = near(panel); if (!t) { var tab = d.getElementById(panel.getAttribute("aria-labelledby") || ""); t = tab ? tab.textContent : panel.getAttribute("aria-label") || ""; } }
    if (!t) t = near(d);
    t = t.replace(/\s+/g, " ").trim().slice(0, 80);
    var base = kind + (t ? ": " + t : ""), name = base, n = 1;
    while (used[name]) name = base + " (" + (++n) + ")";
    used[name] = 1; return name;
  }
  function scrollers() {
    if (!d.body) return;
    var used = {};
    d.querySelectorAll("[aria-label]").forEach(function (x) { used[x.getAttribute("aria-label")] = 1; });
    [].forEach.call(d.body.getElementsByTagName("*"), function (el) {
      var mine = el.getAttribute("data-scroll-focus"), over = el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1;
      if (over) { var cs = getComputedStyle(el); over = /auto|scroll/.test(cs.overflowX + " " + cs.overflowY); }
      if (over && mine !== null && / aria-label( |$)/.test(" " + mine)) {   /* a name this script gave follows a re-rendered heading */
        var was = el.getAttribute("aria-label"); delete used[was];
        var now = scrollName(el, used); if (now !== was) el.setAttribute("aria-label", now);
        return;
      }
      if (over && mine === null && !el.hasAttribute("tabindex") && !el.matches(TABBABLE) && !el.querySelector(TABBABLE)) {
        var added = ["tabindex"];
        el.setAttribute("tabindex", "0");
        if (!el.hasAttribute("role") && !el.matches("table, ul, ol, dl, figure, nav, main, aside, form, fieldset, section, header, footer")) { el.setAttribute("role", "region"); added.push("role"); }
        if (!el.hasAttribute("aria-label") && !el.hasAttribute("aria-labelledby")) { el.setAttribute("aria-label", scrollName(el, used)); added.push("aria-label"); }
        el.setAttribute("data-scroll-focus", added.join(" "));
      } else if (!over && mine !== null) {
        mine.split(" ").forEach(function (a) { if (a) el.removeAttribute(a); });
        el.removeAttribute("data-scroll-focus");
      }
    });
  }
  function names() {
    d.querySelectorAll("a.quarto-color-scheme-toggle:not([aria-label])").forEach(function (a) { a.setAttribute("aria-label", "Switch Quarto color theme"); });
    d.querySelectorAll(".slide-menu-button a:not([aria-label])").forEach(function (a) { a.setAttribute("aria-label", "Slide menu"); });
    d.querySelectorAll('.sourceCode a[href=""]:empty, .sourceCode a[href="#"]:empty').forEach(function (a) { a.setAttribute("aria-hidden", "true"); a.setAttribute("tabindex", "-1"); });
  }

  function init() {
    paint();
    if (saved()) quarto(saved());
    stages();
    d.querySelectorAll("[data-filter]").forEach(filter);
    copyButtons();
    names(); scrollers();
    /* boxes that appear or change later: a resize, an opened <details>, a tab switch, a re-render */
    var rt, again = function () { clearTimeout(rt); rt = setTimeout(function () { names(); scrollers(); }, 150); };
    window.addEventListener("resize", again);
    window.addEventListener("load", again);
    d.addEventListener("toggle", again, true);
    if (window.MutationObserver) new MutationObserver(again).observe(d.body, { subtree: true, childList: true, attributes: true, attributeFilter: ["hidden", "open", "aria-selected", "aria-expanded"] });
  }
  window.addEventListener("beforeprint", function () { d.querySelectorAll("details:not([open])").forEach(function (x) { x.setAttribute("open", ""); x.setAttribute("data-print-open", ""); }); });
  window.addEventListener("afterprint", function () { d.querySelectorAll("details[data-print-open]").forEach(function (x) { x.removeAttribute("open"); x.removeAttribute("data-print-open"); }); });
  if (d.readyState === "loading") d.addEventListener("DOMContentLoaded", init); else init();
})();
