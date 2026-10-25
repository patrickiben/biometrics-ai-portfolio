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
    var noun = box.getAttribute("data-noun") || "items";
    function on(attr) { var b = box.querySelector("button[" + attr + '][aria-pressed="true"]'); return b ? b.getAttribute(attr) : ""; }
    function run() {
      var st = on("data-f-stage"), lb = on("data-f-label"), text = q ? q.value.trim().toLowerCase() : "", n = 0;
      items.forEach(function (el) {
        var ok = (!st || (" " + (el.getAttribute("data-stages") || "") + " ").indexOf(" " + st + " ") > -1) &&
                 (!lb || (" " + (el.getAttribute("data-labels") || "") + " ").indexOf(" " + lb + " ") > -1) &&
                 (!text || el.textContent.toLowerCase().indexOf(text) > -1);
        el.hidden = !ok; if (ok) n++;
      });
      groups.forEach(function (g) { g.hidden = !g.querySelector("[data-item]:not([hidden])"); });
      if (out) out.textContent = n + " of " + items.length + " " + noun + " shown";
    }
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

  function init() {
    paint();
    if (saved()) quarto(saved());
    d.querySelectorAll("[data-filter]").forEach(filter);
    copyButtons();
  }
  window.addEventListener("beforeprint", function () { d.querySelectorAll("details:not([open])").forEach(function (x) { x.setAttribute("open", ""); x.setAttribute("data-print-open", ""); }); });
  window.addEventListener("afterprint", function () { d.querySelectorAll("details[data-print-open]").forEach(function (x) { x.removeAttribute("open"); x.removeAttribute("data-print-open"); }); });
  if (d.readyState === "loading") d.addEventListener("DOMContentLoaded", init); else init();
})();
