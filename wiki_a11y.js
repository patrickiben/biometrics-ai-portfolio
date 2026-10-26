// Shared print-disability accessibility layer for the section-nav LLM wikis.
// Each builder: const A=require("../wiki_a11y.js"); append A.CSS to its css string; set
// js = A.JS(defaultSectionId); add aria-label to sections; wrap the shell with A.skip
// and the accessible nav/search/main attributes.
// NOTE (2026-06-26): the A-/A+ text-size control was REMOVED package-wide (its font-scaling
// reflowed/dragged the layout); this module no longer emits it. Do not re-add it.
const CSS = `
.vh{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap}
.skip{position:absolute;left:-9999px;top:0;background:#15183A;color:#fff;padding:10px 16px;z-index:100}.skip:focus{left:0}
a:focus-visible,button:focus-visible,#side a:focus-visible,#search:focus-visible,#main:focus-visible{outline:3px solid #8b86f0;outline-offset:2px}
@media (prefers-reduced-motion:reduce){section.show{animation:none}}
@media print{#side,#search,.skip,label[for=search]{display:none!important}#main{max-width:none;padding:18px}section{display:block!important;page-break-before:always}section:first-of-type{page-break-before:avoid}h1,h2{page-break-after:avoid}.footer{display:none}}
`;
// A script appended AFTER a wiki's existing inline js. It layers accessibility on top of the
// existing show()/.active/.show behaviour without rewriting it: aria-current, the hidden attribute
// (so screen readers skip inactive sections), focus management, and a print handler that un-hides
// every section so the PDF is a complete linear document.
const enhanceScript = `<script>(function(){
var secs=[].slice.call(document.querySelectorAll('section')),links=[].slice.call(document.querySelectorAll('#side a[data-t]'));
function sync(){var act=links.filter(function(a){return a.classList.contains('active');})[0];var id=act?act.dataset.t:null;secs.forEach(function(s){s.hidden=!(s.id===id);});links.forEach(function(a){if(a.classList.contains('active'))a.setAttribute('aria-current','page');else a.removeAttribute('aria-current');});}
/* wrap the wiki's existing show() so EVERY navigation (click, hash, or programmatic) keeps the
   hidden attribute + aria-current in sync and moves focus to main -- no desync for screen readers */
if(typeof window.show==='function'){var _os=window.show;window.show=function(id){_os(id);sync();var m=document.getElementById('main');if(m&&document.hasFocus())m.focus();};}
window.addEventListener('beforeprint',function(){secs.forEach(function(s){s.hidden=false;});});
window.addEventListener('afterprint',sync);sync();
})();</script>`;
// the enhanced show/search/print JS (alternative: replaces a wiki's inline js)
const JS = (first = "start") => `const secs=[...document.querySelectorAll('section')],links=[...document.querySelectorAll('#side a[data-t]')];
function show(id){secs.forEach(s=>{const on=s.id===id;s.classList.toggle('show',on);s.hidden=!on;});links.forEach(a=>{const on=a.dataset.t===id;a.classList.toggle('active',on);if(on)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current');});window.scrollTo(0,0);const m=document.getElementById('main');if(m)m.focus();if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);}
links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(a.dataset.t);}));
document.querySelectorAll('#main a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const id=a.getAttribute('href').slice(1);if(document.getElementById(id)){e.preventDefault();show(id);}}));
const q=document.getElementById('search');if(q)q.addEventListener('input',()=>{const v=q.value.toLowerCase().trim();links.forEach(a=>{const s=document.getElementById(a.dataset.t);a.style.display=(!v||s.textContent.toLowerCase().includes(v))?'block':'none';});});
show((location.hash||'#${first}').slice(1)||'${first}');
window.addEventListener('beforeprint',()=>secs.forEach(s=>s.hidden=false));
window.addEventListener('afterprint',()=>show((location.hash||'#${first}').slice(1)||'${first}'));`;
// pieces for the shell
const skip = `<a href="#main" class="skip">Skip to content</a>`;
const controls = ``; // (the A-/A+ text-size control was removed; intentionally empty)
// build a readable transcript section html from a notes array
const transcript = (notes, captions = []) =>
  notes.map((t, i) => `<h2>${i + 1}. ${captions[i] || "Part " + (i + 1)}</h2><p>${t}</p>`).join("");

// rewrite a wiki's shell string to be accessible: skip link, nav aria-label, search label+type,
// main tabindex, injected CSS, and the enhancement script.
function accessibleShell(html) {
  return html
    .replace("<body>", "<body>" + skip)
    .replace('<nav id="side">', '<nav id="side" aria-label="Wiki sections">')
    .replace('<input id="search"', '<label for="search" class="vh">Search the wiki</label><input id="search" type="search"')
    .replace('<main id="main">', '<main id="main" tabindex="-1">')
    .replace("</style>", CSS + "</style>")
    .replace("</body></html>", controls + enhanceScript + "</body></html>");
}
module.exports = { CSS, JS, skip, controls, transcript, enhanceScript, accessibleShell };
