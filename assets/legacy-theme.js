/* Same bp-theme preference as assets/ui.js; inline for portable/offline pages. */
(function () {
  'use strict';
  var root = document.documentElement, key = 'bp-theme';
  var media = window.matchMedia('(prefers-color-scheme: light)');
  function saved() { try { var t = localStorage.getItem(key); return /^(light|dark)$/.test(t) ? t : null; } catch (_) { return null; } }
  function apply(t) {
    t = t || (media.matches ? 'light' : 'dark');
    root.dataset.theme = t;
    document.querySelectorAll('.toolkit-theme-toggle').forEach(function (b) {
      b.setAttribute('aria-pressed', String(t === 'dark'));
      b.title = 'Switch to ' + (t === 'dark' ? 'light' : 'dark') + ' theme';
      b.setAttribute('aria-label', b.title);
      b.textContent = t === 'dark' ? '☀ Light' : '☾ Dark';
    });
    document.querySelectorAll('meta[name="theme-color"]').forEach(function (m) { m.content = t === 'dark' ? '#0b0f15' : '#f4f6f9'; });
  }
  apply(saved());
  document.addEventListener('DOMContentLoaded', function () {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'theme-toggle toolkit-theme-toggle';
    var nav = document.querySelector('.top .nav') || document.querySelector('.top');
    if (nav) nav.appendChild(b);
    else { b.classList.add('toolkit-theme-floating'); document.body.appendChild(b); }
    b.addEventListener('click', function () {
      var t = root.dataset.theme === 'dark' ? 'light' : 'dark';
      try { localStorage.setItem(key, t); } catch (_) {}
      apply(t);
    });
    apply(saved());
  });
  window.addEventListener('storage', function (e) { if (e.key === key || e.key === null) apply(saved()); });
  if (media.addEventListener) media.addEventListener('change', function () { if (!saved()) apply(null); });
})();
