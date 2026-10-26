/* launch.js: starts one in-browser Shiny app (Shinylive and webR) on its launch page and reports
   every step, so a visitor can always tell whether the app is loading, computing, ready or stuck.

   The steps and the real signal behind each one:
     2 service worker   navigator.serviceWorker: registered, then in control of this page
     3 R engine         shinylive.js imported and runExportedApp() called; R's startup banner on
                        the webR worker's channel says R itself has downloaded and started; the
                        step ends when the Shinylive viewer gives its iframe an app_* address,
                        which happens once the packages have loaded and app.R has run
     4 app page         the iframe's load event
     5 first results    inside the same-origin iframe: shiny:connected, shiny:busy / shiny:idle,
                        shiny:value and the outputs themselves (filled, recalculating or failed)
   Failures it reports instead of staying blank: no service worker support, a failed registration,
   a page the service worker does not control (reloads once, guarded against loops), the
   "ServiceWorker controller was not found" viewer error (reloads once), a loader or app.json that
   did not download, an R error while starting the app, the webR worker stopping, a lost connection,
   no result after 60 s of visible time (120 s once R has started, because a first visit on a slow
   connection spends most of its time loading packages; 45 s after the app's page loaded for the
   first results), a file that does not answer, and R busy for more than 45 s after the app was ready.
   The app follows the site's theme: the toggle in the site's top bar on this page (assets/ui.js,
   saved as bp-theme) or the system setting. The app's page reads the same saved choice when it
   loads (bp_theme_head() in portfolio_app.R) and hears later changes; this page also sets the
   theme on the app's page directly, so the two never disagree.
   State for tests and bug reports: window.launchStatus, and data-state on #app. */
(function () {
  'use strict';

  var cfg = {};
  try { cfg = JSON.parse(document.getElementById('launch-config').textContent) || {}; } catch (e) { cfg = {}; }
  var REL = cfg.relPath || '../../';
  var MB = cfg.download_mb || 55;
  var TIMEOUT_S = cfg.timeout_s || 60;                         // nothing ready, before R has started
  var STARTED_S = cfg.timeout_started_s || 2 * TIMEOUT_S;       // once R has started (packages download)
  var COMPUTE_S = cfg.compute_timeout_s || 45;                  // the first results, after the app's page loaded
  var ANSWER_S = 20;                                             // a file check that gets no answer
  var BUSY_S = cfg.busy_timeout_s || 45;
  var SETTLE_S = 5;   // once R is idle, how long a still-empty panel may delay "ready"
  var AUTO_RELOAD_KEY = 'launch-reload:' + location.pathname;

  var app = document.getElementById('app');
  var root = document.getElementById('root');
  var statusBox = app.querySelector('.app-status');
  var stageText = app.querySelector('.status-stage');
  var detailText = app.querySelector('.status-detail');
  var clock = app.querySelector('.status-clock');
  var pill = document.querySelector('.status-pill');
  var pillText = pill && pill.querySelector('.pill-text');
  var cover = app.querySelector('[data-cover]');
  var coverTitle = cover.querySelector('.cover-title');
  var problemBox = cover.querySelector('.cover-problem');
  var barReload = app.querySelector('.app-bar [data-action="reload"]');
  var fullBtn = app.querySelector('[data-action="full"]');
  var baseTitle = document.title;

  function now() { return performance.now() / 1000; }   // seconds since this page started loading
  function secs(t) { return (Math.round(t * 10) / 10).toFixed(1) + ' s'; }

  var L = window.launchStatus = {
    stage: 'page', ready: false, busy: false, connected: false, problem: null,
    times: { page: +now().toFixed(2) }, outputs: null, events: []
  };
  function log(kind, msg) {
    L.events.push({ t: +now().toFixed(2), kind: kind, msg: String(msg).slice(0, 800) });
    if (L.events.length > 300) L.events.shift();
  }

  var ORDER = ['page', 'sw', 'engine', 'frame', 'compute', 'ready'];
  var STAGES = {
    page: ['Starting', 'The page is ready; the app starts here.'],
    sw: ['Step 2 of 5: preparing the in-page server', 'Registering the service worker that lets R serve the app inside this page.'],
    engine: ['Step 3 of 5: starting R in your browser', 'Downloading R for the browser (webR) and starting it. ' +
      'Together with the app\'s packages, a first visit downloads about ' + MB + ' MB; this is the longest step.'],
    frame: ['Step 4 of 5: loading the app', 'R is serving the app\'s page.'],
    compute: ['Step 5 of 5: computing the first results', 'R is computing.'],
    ready: ['Ready', '']
  };

  // what to say when something goes wrong; tone "warn" = may still recover, offers Keep waiting
  var LOAD_REASONS = [
    'A download was interrupted or is very slow. A first visit downloads about ' + MB + ' MB.',
    'The browser blocks service workers, for example some private windows, blocked cookies or site data for this site, or a managed browser policy.',
    'A browser extension blocks scripts or WebAssembly on this site.'
  ];
  var TRY_MORE = 'If it fails again, try a normal (not private) window or another browser. The read-only snapshot shows the same content without R.';
  var PROBLEMS = {
    insecure: { title: 'This page needs a secure connection', text: 'The app runs R inside the page with a service worker, which browsers allow only over https or on localhost.', fatal: true },
    'no-sw': { title: 'This browser does not allow the app to start', text: 'The app needs a service worker, and this browser or window does not provide one (common in private windows and with blocked site data).', reasons: LOAD_REASONS.slice(1), fatal: true },
    'sw-failed': { title: 'The in-page server did not start', text: 'The browser could not register the service worker that lets R serve the app inside this page.', reasons: LOAD_REASONS, fatal: true },
    'no-controller': { title: 'The in-page server did not take control', text: 'The service worker registered but did not take control of this page, even after a reload.', reasons: LOAD_REASONS.slice(1), fatal: true },
    loader: { title: 'The app\'s loader did not download', text: 'shinylive.js, the code that starts R in the page, failed to load.', reasons: LOAD_REASONS, fatal: true },
    'app-json': { title: 'The app\'s code did not download', text: 'app.json, the file with the app\'s R code and data, failed to load.', reasons: LOAD_REASONS.slice(0, 1), fatal: true },
    'r-start': { title: 'R stopped while starting the app', text: 'R reported an error while running the app\'s code. This is a bug in the app, not something you did.', fatal: true },
    'engine-died': { title: 'A file R needs did not download', text: 'R (webR) stopped because one of its files failed to download. This is usually a network hiccup, not a bug in the app.', reasons: LOAD_REASONS.slice(0, 1), said: true },
    'viewer-crash': { title: 'The app viewer stopped', text: 'The code that shows the app in this page stopped with an error.', reasons: LOAD_REASONS },
    slow: { title: 'Still not ready after ' + TIMEOUT_S + ' seconds', text: 'The app has not finished starting. It may still finish; the step list shows where it is.', reasons: LOAD_REASONS, tone: 'warn', said: true },
    'stalled-compute': { title: 'The first results have not arrived after ' + COMPUTE_S + ' seconds', text: 'The app\'s layout is drawn, but R has not filled it. R has probably stopped, usually because a file it loads on demand failed to download.', reasons: LOAD_REASONS.slice(0, 1), tone: 'warn', said: true },
    'no-answer': { title: 'A file R needs is not answering', text: 'R may be waiting for a file that the site does not answer for. On a very slow connection it may still finish; if nothing changes, reload the page.', reasons: LOAD_REASONS.slice(0, 1), tone: 'warn', said: true },
    disconnected: { title: 'The app lost its connection to R', text: 'R stopped responding. Reload the page to start the app again; changes made in this visit are not kept.' },
    'busy-long': { title: 'R has been computing for ' + BUSY_S + ' seconds', text: 'An update is taking much longer than usual. R may have stopped.', tone: 'warn' },
    updated: { title: 'The site was updated while the app was open', text: 'Reload the page to keep using the app.', tone: 'warn' }
  };
  var dismissed = {};
  var DOWNLOAD_RX = /Emscripten filesystem|download|NetworkError|Failed to fetch|Failed to load|Load failed|fetching/i;

  // ---- rendering ------------------------------------------------------------------------
  function tone() {
    if (L.problem) return (PROBLEMS[L.problem] || {}).tone || 'error';
    if (L.ready && !L.busy) return L.outputs && L.outputs.failed ? 'warn' : 'ok';
    return 'progress';
  }
  function render() {
    var st = STAGES[L.stage] || STAGES.page, title = st[0], detail = st[1];
    var k = L.outputs, t = tone();
    if (L.stage === 'engine' && L.times.rStarted) detail = 'R is running (started at ' + secs(L.times.rStarted) +
      '). Now loading the app\'s R packages, most of the first-visit download, and running the app\'s code.';
    if (L.stage === 'engine' && L.pkg) detail = 'R is running. The bundled packages did not load, so R is downloading them ' +
      'one by one from the webR package repository, which is slower: now ' + L.pkg + '.';
    if (L.stage === 'compute' && k && k.total) detail = 'R is computing: ' + k.filled + ' of ' + k.total + ' panels filled.';
    if (L.ready) {
      if (L.busy) { title = 'Working'; detail = 'R is computing' + (k && k.recalc ? ': ' + k.recalc + ' panel' + (k.recalc > 1 ? 's' : '') + ' updating.' : '.'); }
      else if (k && k.failed) { title = 'Ready, with ' + k.failed + ' failed panel' + (k.failed > 1 ? 's' : ''); detail = 'The failed panel says what went wrong; that is a bug in the app. The other panels work.'; }
      else { title = 'Ready'; detail = 'Loaded in ' + secs(L.times.ready) + '; everything runs in your browser. "Try this", above the app, suggests where to start.'; }
    }
    if (L.problem) {
      var p = PROBLEMS[L.problem]; title = p.title; detail = p.text;
      if (p.tone === 'warn' && !L.ready) detail += ' Now: ' + st[0].replace(/^Step (\d) of 5: /, 'step $1 of 5, ') +
        (L.stage === 'engine' && L.times.rStarted ? ' (R started at ' + secs(L.times.rStarted) + ', loading packages)' : '') + '.';
    }
    stageText.textContent = title;
    detailText.textContent = detail;
    statusBox.setAttribute('data-tone', t);
    if (pill) {
      pill.setAttribute('data-tone', t);
      pillText.textContent = L.problem ? 'Problem: ' + title.charAt(0).toLowerCase() + title.slice(1)
        : L.ready ? 'Ready: go to the app' : title + ' (' + Math.round(now()) + ' s)';
    }
    // the clock stops at a hard problem: a count beside "did not start" would read as still loading
    if (!(L.problem && (PROBLEMS[L.problem].fatal || t === 'error'))) clock.textContent = L.ready && !L.problem ? '' : Math.round(now()) + ' s';
    document.title = (L.problem ? 'Problem: ' : L.ready ? '' : 'Loading: ') + baseTitle;
    barReload.hidden = !L.problem;
    barReload.classList.toggle('btn--primary', t !== 'warn');   // while it may still finish, waiting comes first
    app.setAttribute('data-state', L.stage);
    if (L.problem) app.setAttribute('data-problem', L.problem); else app.removeAttribute('data-problem');
  }
  function setStage(name) {
    if (ORDER.indexOf(name) <= ORDER.indexOf(L.stage) && name !== 'page') { render(); return; }
    L.stage = name;
    if (!(name in L.times)) L.times[name] = +now().toFixed(2);
    log('stage', name);
    var idx = ORDER.indexOf(name);
    [].forEach.call(cover.querySelectorAll('[data-step]'), function (li) {
      var i = ORDER.indexOf(li.getAttribute('data-step'));
      li.classList.toggle('done', i < idx);
      li.classList.toggle('active', i === idx);
      var next = ORDER[i + 1];
      if (i < idx) { var note = li.querySelector('.step-note'); if (note) note.remove(); }
      if (i < idx && L.times[next] && !li.querySelector('.step-time')) {
        var s = document.createElement('span'); s.className = 'step-time'; s.textContent = 'done at ' + secs(L.times[next]);
        li.appendChild(s);
      }
    });
    render();
  }

  function showProblem(kind, extra) {
    var p = PROBLEMS[kind];
    if (!p || dismissed[kind] || L.problem === kind) return;
    if (L.problem && PROBLEMS[L.problem].fatal && !p.fatal) return;   // keep the first hard failure
    L.problem = kind;
    if (extra) log('problem', kind + ': ' + extra); else log('problem', kind);
    app.classList.add('has-problem');
    problemBox.hidden = false;
    problemBox.classList.toggle('tone-warn', p.tone === 'warn');
    coverTitle.textContent = p.tone === 'warn' ? 'Taking longer than expected' : 'The app did not start';
    if (L.ready) coverTitle.textContent = p.tone === 'warn' ? 'Still working' : 'The app stopped';
    problemBox.querySelector('.problem-text').textContent = p.title + '. ' + p.text;
    var said = problemBox.querySelector('.problem-said');
    said.textContent = extra && (kind === 'r-start' || p.said) ? 'Message: ' + extra : '';
    said.hidden = !said.textContent;
    var ul = problemBox.querySelector('.problem-reasons');
    ul.textContent = '';
    // drop the reasons that what already worked rules out
    var reasons = (p.reasons || []).filter(function (r) {
      if (r === LOAD_REASONS[1]) return !L.times.engine;          // the service worker is in control
      if (r === LOAD_REASONS[2]) return !L.times.rStarted;        // R itself has started
      return true;
    });
    if (L.hiddenSeen && !L.ready) reasons.push('This tab was in the background for part of the time, which slows loading in most browsers.');
    reasons.forEach(function (r) { var li = document.createElement('li'); li.textContent = r; ul.appendChild(li); });
    ul.hidden = !reasons.length;
    problemBox.querySelector('.problem-reasons-head').hidden = !reasons.length;
    var tryText = problemBox.querySelector('.problem-try');
    tryText.textContent = 'What to try: ' + (kind === 'r-start'
      ? 'reload the page. If the error comes back, the read-only snapshot shows the same content without R.'
      : (p.tone === 'warn' ? 'wait a little longer, or reload the page (a second visit is usually faster). '
                           : 'reload the page; a second visit is usually faster. ') + TRY_MORE);
    var keep = problemBox.querySelector('[data-action="dismiss"]'), again = problemBox.querySelector('[data-action="reload"]');
    keep.hidden = p.tone !== 'warn';
    keep.classList.toggle('btn--primary', p.tone === 'warn');      // still loading: waiting is the first choice
    again.classList.toggle('btn--primary', p.tone !== 'warn');
    var cur = cover.querySelector('[data-step].active');
    // a file that did not download before the app's page loaded failed step 3, even when the viewer
    // has already given the frame its address (it does so after a failed package load too)
    var eng = cover.querySelector('[data-step="engine"]');
    if (kind === 'engine-died' && !L.times.frameLoaded && eng) {
      if (cur && cur !== eng) cur.classList.remove('active');
      eng.classList.remove('done');
      [].forEach.call(eng.querySelectorAll('.step-time:not(.step-note)'), function (x) { x.remove(); });
      cur = eng;
    }
    if (cur && p.tone !== 'warn') { cur.classList.remove('active'); cur.classList.add('failed'); }
    problemBox.querySelector('.log').textContent = details();
    if (kind === 'engine-died') diagnose(true);
    render();
  }
  function clearProblem() {
    if (!L.problem) return;
    log('problem-cleared', L.problem);
    L.problem = null;
    app.classList.remove('has-problem');
    problemBox.hidden = true;
    var f = cover.querySelector('[data-step].failed');
    if (f) { f.classList.remove('failed'); f.classList.add('active'); }
    coverTitle.textContent = 'Starting the app';
    render();
  }
  function details() {
    var lines = ['page: ' + location.href, 'browser: ' + navigator.userAgent, 'stage: ' + L.stage + ', elapsed ' + secs(now()),
                 'service worker controller: ' + (navigator.serviceWorker && navigator.serviceWorker.controller ? 'yes' : 'no')];
    if (L.outputs) lines.push('outputs: ' + JSON.stringify(L.outputs));
    L.events.slice(-60).forEach(function (e) { lines.push(e.t.toFixed(1) + ' s  ' + e.kind + ': ' + e.msg); });
    return lines.join('\n');
  }

  // ---- auto reload, at most once per two minutes per page --------------------------------
  function autoReload(why) {
    var last = 0, store = true;
    try { last = +sessionStorage.getItem(AUTO_RELOAD_KEY) || 0; } catch (e) { store = false; }
    if (!store && /[?&]launch-retry=1\b/.test(location.search)) last = Date.now();
    if (Date.now() - last < 120000) { log('reload', 'not reloading again (' + why + ')'); return false; }
    log('reload', 'reloading once: ' + why);
    L.reloading = true;
    if (store) {
      try { sessionStorage.setItem(AUTO_RELOAD_KEY, String(Date.now())); } catch (e) { store = false; }
    }
    if (store) location.reload();
    else { var u = new URL(location.href); u.searchParams.set('launch-retry', '1'); location.replace(u.href); }
    return true;
  }
  function forgetAutoReload() {
    try { sessionStorage.removeItem(AUTO_RELOAD_KEY); } catch (e) { /* storage blocked */ }
    if (/[?&]launch-retry=1\b/.test(location.search) && history.replaceState) {
      var u = new URL(location.href); u.searchParams.delete('launch-retry'); history.replaceState(null, '', u.href);
    }
  }

  // ---- step 2: the service worker --------------------------------------------------------
  function register(url) {
    var sw = navigator.serviceWorker;
    // the same options as Shinylive's own loader, so an existing registration is reused as is;
    // browsers without module service workers get a classic one (the script has no imports)
    return sw.register(url, { type: 'module' }).catch(function (err) {
      log('sw', 'registration failed once: ' + err);
      return new Promise(function (res) { setTimeout(res, 1500); }).then(function () {
        return sw.register(url, { type: 'module' }).catch(function (err2) {
          log('sw', 'module registration failed again, trying a classic worker: ' + err2);
          return sw.register(url);
        });
      });
    });
  }
  function waitForController(reg) {
    var sw = navigator.serviceWorker;
    return new Promise(function (resolve) {
      var done = false;
      function finish(v) { if (!done) { done = true; resolve(v); } }
      if (sw.controller) return finish(true);
      sw.addEventListener('controllerchange', function () { if (sw.controller) finish(true); });
      sw.ready.then(function (r) {
        var a = r && r.active;
        // an active worker that already ran its activation will not claim this page (for example
        // after a hard reload): a normal reload brings the page under its control
        var wait = a && a.state === 'activated' ? 600 : 6000;
        setTimeout(function () { finish(!!sw.controller); }, wait);
      });
      setTimeout(function () { finish(!!sw.controller); }, 15000);
    });
  }
  function startServiceWorker() {
    if (!window.isSecureContext) return showProblem('insecure');
    if (!('serviceWorker' in navigator)) return showProblem('no-sw');
    setStage('sw');
    var url = new URL(REL + 'shinylive-sw.js', location.href).href;
    var sw = navigator.serviceWorker;
    if (sw.controller) {
      log('sw', 'already in control');
      register(url).catch(function (e) { log('sw', 'refresh failed: ' + e); });
      return startEngine();
    }
    register(url).then(function (reg) {
      log('sw', 'registered for ' + reg.scope);
      return waitForController(reg);
    }).then(function (ok) {
      if (ok) { log('sw', 'in control'); return startEngine(); }
      if (!autoReload('the service worker is not in control of this page')) showProblem('no-controller');
    }, function (err) {
      showProblem('sw-failed', String(err && err.message || err));
    });
  }

  // ---- step 3: R ----------------------------------------------------------------------------
  function watchWorkers() {
    var W = window.Worker;
    if (!W || W.launchWatched) return;
    var Watched = function (url, opts) {
      var w = opts === undefined ? new W(url) : new W(url, opts);
      var name = String(url).split('/').pop().slice(0, 80);
      log('worker', 'started ' + name);
      w.addEventListener('error', function (ev) { onWorkerError(name, ev && ev.message); });
      // webR prints R's startup banner on its channel once R.wasm has downloaded and R has started
      var banner = function (ev) {
        var d = ev.data;
        if (d && d.type === 'stdout' && /^R version/.test(String(d.data))) {
          w.removeEventListener('message', banner);
          L.times.rStarted = +now().toFixed(2);
          log('engine', 'R started: ' + String(d.data).slice(0, 60));
          var li = cover.querySelector('[data-step="engine"]');
          if (li && !li.querySelector('.step-note')) {
            var s = document.createElement('span'); s.className = 'step-time step-note';
            s.textContent = 'R started at ' + secs(L.times.rStarted) + '; loading packages';
            li.appendChild(s);
          }
          render();
        }
      };
      w.addEventListener('message', banner);
      return w;
    };
    Watched.prototype = W.prototype;
    Watched.launchWatched = true;
    try { window.Worker = Watched; } catch (e) { log('worker', 'cannot watch workers: ' + e); }
  }
  function onWorkerError(name, msg) {
    log('worker-error', name + ': ' + (msg || 'error'));
    if (!L.ready) showProblem('engine-died', msg || name);
    else showProblem('disconnected', msg || name);
  }
  var engineStarted = false;
  function startEngine() {
    if (engineStarted) return;
    engineStarted = true;
    setStage('engine');
    watchWorkers();
    watchRoot();
    import(new URL(REL + 'shinylive/shinylive.js', location.href).href).then(function (mod) {
      L.times.loader = +now().toFixed(2);
      log('engine', 'shinylive.js loaded');
      return mod.runExportedApp({ id: 'root', appEngine: 'r', relPath: REL });
    }).then(function () {
      log('engine', 'runExportedApp started');
    }, function (err) {
      var m = String(err && err.message || err);
      showProblem(/app\.json/i.test(m) ? 'app-json' : 'loader', m);
    });
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      log('sw', 'controller changed while the app was running');
      if (!L.ready) { if (!autoReload('the service worker was replaced while the app started')) showProblem('updated'); }
      else showProblem('updated');
    });
  }

  // ---- steps 3 to 4: the Shinylive viewer ----------------------------------------------------
  var frame = null, viewerSeen = false, rErrorSeen = false;
  function watchRoot() {
    var mo = new MutationObserver(checkRoot);
    mo.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'class'] });
    setInterval(checkRoot, 500);
  }
  function checkRoot() {
    if (root.querySelector('.shinylive-viewer') && !viewerSeen) { viewerSeen = true; L.times.viewer = +now().toFixed(2); log('engine', 'viewer shown'); }
    if (viewerSeen && root.childElementCount === 0) showProblem('viewer-crash');
    var err = root.querySelector('.loading-wrapper-error');
    if (err && !rErrorSeen) {
      rErrorSeen = true;
      var pre = err.querySelector('pre'), said = ((pre ? pre.textContent : err.textContent) || '').trim().slice(0, 600);
      // a file webR loads on demand that did not download is a network failure, not a bug in the app
      var lost = DOWNLOAD_RX.test(said) || /unreachable|Aborted\(/.test(said) || L.downloadError;
      showProblem(lost ? 'engine-died' : 'r-start', lost && L.downloadError ? L.downloadError : said);
    }
    var f = root.querySelector('iframe');
    if (f && !f.hasAttribute('title')) {   // the viewer's frame has no name of its own
      var h1 = document.getElementById('launch-title');
      f.setAttribute('title', (h1 ? h1.textContent.trim() : 'The app') + ': the live app');
    }
    if (f && !frame && /app_/.test(f.getAttribute('src') || '')) {
      frame = f;
      log('frame', 'app address ' + f.getAttribute('src'));
      setStage('frame');
      f.addEventListener('load', onFrameLoad);
      try { if (f.contentDocument && f.contentDocument.readyState === 'complete' && /app_/.test(f.contentWindow.location.pathname)) onFrameLoad(); } catch (e) { /* not ready */ }
    }
  }

  // ---- step 5: Shiny, inside the same-origin iframe -------------------------------------------
  var attachedTo = null;
  function onFrameLoad() {
    var w;
    try { w = frame.contentWindow; if (!/app_/.test(w.location.pathname)) return; } catch (e) { log('frame', 'cannot read the app page: ' + e); return; }
    if (attachedTo === w) return;
    attachedTo = w;
    L.times.frameLoaded = +now().toFixed(2);
    log('frame', 'loaded');
    pushTheme();
    setStage('compute');
    attachShiny(w, 0);
  }
  function attachShiny(w, tries) {
    var $ = w.jQuery, S = w.Shiny;
    if (!$ || !S) {
      if (tries < 240) setTimeout(function () { attachShiny(w, tries + 1); }, 250);
      else log('shiny', 'no Shiny in the app page');
      return;
    }
    var doc = $(w.document);
    pushTheme();
    doc.on('shiny:connected', onConnected);
    doc.on('shiny:disconnected', function () { log('shiny', 'disconnected'); showProblem('disconnected'); });
    doc.on('shiny:busy', function () { setBusy(true); });
    doc.on('shiny:idle', function () { setBusy(false); });
    // count again just after each value is drawn (Shiny draws it right after this event), so the
    // status line never says "0 of N panels filled" while the app already shows its panels
    var recount = null;
    doc.on('shiny:value shiny:error', function () {
      L.values = (L.values || 0) + 1;
      if (!recount) recount = setTimeout(function () { recount = null; countOutputs(w); }, 0);
    });
    doc.on('shiny:error', function (ev) {
      var e = ev.error || {}, types = [].concat(e.type || []);
      if (e.message && types.indexOf('validation') < 0) log('output-error', (ev.name || 'output') + ': ' + e.message);
    });
    w.addEventListener('error', function (ev) { log('app-error', ev.message || 'error'); });
    w.addEventListener('keydown', onKey);
    if (S.shinyapp && S.shinyapp.isConnected && S.shinyapp.isConnected()) onConnected();
    setInterval(function () { countOutputs(w); }, 500);
  }
  function onConnected() {
    if (L.connected) return;
    L.connected = true; L.times.connected = +now().toFixed(2);
    log('shiny', 'connected');
    render();
  }
  function setBusy(b) {
    L.busy = b;
    if (b) { L.busySince = now(); }
    else { L.busySince = null; L.idleSeen = true; if (L.problem === 'busy-long') clearProblem(); }
    if (!b && attachedTo) countOutputs(attachedTo);
    render();
  }
  function shown(e) {
    var x = e.ownerDocument.defaultView.getComputedStyle(e).display === 'contents' ? e.parentElement : e;
    return !!(x && (x.offsetWidth || x.offsetHeight || x.getClientRects().length));
  }
  function filled(e) {
    if (e.classList.contains('shiny-plot-output') || e.classList.contains('shiny-image-output')) {
      var i = e.querySelector('img'); return !!(i && i.getAttribute('src'));
    }
    // a DataTable counts once it shows rows or its own empty message, not while it is loading
    // (with scrollX the first table.dataTable is the header's copy, which has no body rows)
    if (e.querySelector('table.dataTable')) {
      var td = e.querySelector('table.dataTable tbody td');
      return !!td && !(td.classList.contains('dataTables_empty') && /^(loading|processing)/i.test((td.textContent || '').trim()));
    }
    return (e.textContent || '').trim().length > 0 || !!e.querySelector('img,svg,canvas,table');
  }
  function countOutputs(w) {
    var outs;
    try { outs = [].slice.call(w.document.querySelectorAll('.shiny-bound-output')).filter(shown); } catch (e) { return; }
    var k = { total: outs.length, filled: 0, recalc: 0, failed: 0, empty: [] , failedIds: [] };
    outs.forEach(function (e) {
      var err = e.classList.contains('shiny-output-error') && !e.classList.contains('shiny-output-error-validation');
      var rc = e.classList.contains('recalculating');
      if (rc) k.recalc++;
      if (err) { k.failed++; k.failedIds.push(e.id); }
      if (!rc && (err || filled(e))) k.filled++;
      else if (!rc && !err) k.empty.push(e.id);
    });
    L.outputs = k;
    // the first shiny:idle can fire before this page attached its listeners: catch up from the
    // page itself (Shiny marks <html> with shiny-busy while R works)
    if (!L.idleSeen && L.connected && (L.values || k.filled) &&
        !w.document.documentElement.classList.contains('shiny-busy')) L.idleSeen = true;
    // ready once R is idle and every visible panel has content; a panel still empty then (a
    // widget drawing, or one empty by design) gets at most SETTLE_S more before the app counts as ready
    var settled = !L.ready && L.connected && L.idleSeen && !L.busy && k.recalc === 0;
    if (!settled) L.settledAt = null;
    else if (L.settledAt == null) L.settledAt = now();
    if (settled && (k.filled >= k.total || now() - L.settledAt > SETTLE_S)) markReady();
    else render();
  }
  function markReady() {
    L.ready = true; L.times.ready = +now().toFixed(2);
    log('ready', 'first results at ' + secs(L.times.ready) + (L.outputs ? ', ' + JSON.stringify(L.outputs) : ''));
    if (L.problem && L.problem !== 'updated') clearProblem();   // it started after all
    forgetAutoReload();
    setStage('ready');
  }

  // ---- the site's theme, in the app too -----------------------------------------------------------
  var docEl = document.documentElement;
  var mqLight = window.matchMedia ? window.matchMedia('(prefers-color-scheme: light)') : null;
  function siteTheme() {
    var t = docEl.getAttribute('data-theme');
    return t === 'light' || t === 'dark' ? t : (mqLight && mqLight.matches ? 'light' : 'dark');
  }
  function pushTheme() {
    L.theme = siteTheme();
    if (!frame) return;
    try {
      var r = frame.contentDocument && frame.contentDocument.documentElement;
      if (r && /app_/.test(frame.contentWindow.location.pathname) && r.getAttribute('data-bs-theme') !== L.theme) {
        r.setAttribute('data-bs-theme', L.theme);
        log('theme', 'app set to ' + L.theme);
      }
    } catch (e) { /* the app's page is not readable yet */ }
  }
  new MutationObserver(pushTheme).observe(docEl, { attributes: true, attributeFilter: ['data-theme'] });
  if (mqLight && mqLight.addEventListener) mqLight.addEventListener('change', pushTheme);

  // ---- when the start stalls: are the app's main files reachable? ---------------------------------
  var diagnosed = false, diagnosing = false;
  var MAIN_FILES = ['shinylive-sw.js', 'shinylive/shinylive.js', 'shinylive/webr/webr-worker.js', 'shinylive/webr/R.js',
                    'shinylive/webr/R.wasm', 'shinylive/webr/library.data.gz', 'shinylive/webr/packages/metadata.rds'];
  // the files webR loads on demand while the apps start (R's translations and graphics library, the
  // plot fonts): webR's own message for one of them does not say which
  var V = 'shinylive/webr/vfs/', LIB = V + 'usr/lib/R/library/';
  var LAZY_FILES = [LIB + 'translations.data.gz', LIB + 'translations.js.metadata', LIB + 'parallel.data.gz',
                    LIB + 'tcltk.data.gz', LIB + 'grDevices/libs.data.gz', LIB + 'grDevices/libs.js.metadata',
                    V + 'usr/lib/R/share.data.gz', V + 'etc/fonts/fonts.conf', V + 'usr/share/fonts/NotoSans-Regular.ttf',
                    V + 'usr/share/fonts/NotoSans-Bold.ttf'];
  function head(f) {
    var ctl = window.AbortController ? new AbortController() : null, timer = null;
    var name = f.replace(REL, '');
    var limit = new Promise(function (res) { timer = setTimeout(function () { if (ctl) ctl.abort(); res({ late: name }); }, ANSWER_S * 1000); });
    var ask = fetch(f, { method: 'HEAD', cache: 'no-store', signal: ctl ? ctl.signal : undefined }).then(function (r) {
      return r.ok ? {} : { bad: name + ' (HTTP ' + r.status + ')' };
    }, function (e) { return { bad: name + ' (' + (e && e.message || 'no answer') + ')' }; });
    return Promise.race([ask, limit]).then(function (x) { clearTimeout(timer); return x; });
  }
  function diagnose(again) {
    if (!window.fetch || diagnosing || (diagnosed && !again)) return;
    diagnosed = diagnosing = true;
    var files = MAIN_FILES.concat(LAZY_FILES).map(function (f) { return REL + f; }).concat(['app.json']);
    Promise.all(files.map(head)).then(function (res) {
      var bad = res.map(function (x) { return x.bad; }).filter(Boolean), late = res.map(function (x) { return x.late; }).filter(Boolean);
      log('diagnose', bad.length || late.length ? 'not reachable: ' + bad.concat(late.map(function (x) { return x + ' (no answer within ' + ANSWER_S + ' s)'; })).join(', ') : 'the app\'s files are reachable');
      if (bad.length && !L.ready) {
        // no file at all answers (offline, or the site is down): say that, not the whole list
        var down = bad.length === files.length && bad.every(function (x) { return !/\(HTTP \d+\)$/.test(x); });
        var why = down && /\(([^)]*)\)$/.exec(bad[0]);
        var said = down ? 'None of the app\'s files can be reached (' + (why ? why[1] : 'no answer') + '): the connection may be down.'
                        : 'Not reachable: ' + bad.join(', ');
        if (L.problem === 'engine-died') {   // keep webR's message and name the file
          var el = problemBox.querySelector('.problem-said');
          if (el.textContent.indexOf(said) < 0) el.textContent = (el.textContent ? el.textContent + ' ' : 'Message: ') + said;
          el.hidden = false;
          L.downloadError = said;
        } else {
          L.downloadError = said;
          if (L.problem && !PROBLEMS[L.problem].fatal) { L.problem = null; }
          showProblem('engine-died', said);
        }
      } else if (late.length && !L.ready && L.problem && PROBLEMS[L.problem].tone === 'warn') {
        // only once the start is already overdue: a slow connection can delay one check, not the start
        L.problem = null;
        showProblem('no-answer', 'No answer within ' + ANSWER_S + ' s: ' + late.join(', '));
      }
      if (L.problem) problemBox.querySelector('.log').textContent = details();
      diagnosing = false;
    });
  }

  // ---- watchdogs, errors, controls --------------------------------------------------------------
  var visible = 0, last = now();
  L.hiddenSeen = document.hidden;
  document.addEventListener('visibilitychange', function () { if (document.hidden && !L.ready) L.hiddenSeen = true; });
  setInterval(function () {
    var t = now();
    if (!document.hidden) visible += t - last;
    last = t;
    L.visibleSeconds = +visible.toFixed(1);
    if (!L.ready && !L.problem) {
      // before R starts: TIMEOUT_S of visible time; once it has started (it then loads the packages,
      // most of a first visit's download), STARTED_S; the first results: COMPUTE_S after the app's
      // page loaded
      var lim = L.times.rStarted ? STARTED_S : TIMEOUT_S;
      if (L.stage === 'compute') {
        if (L.visibleAtCompute == null) L.visibleAtCompute = visible;
        if (visible - L.visibleAtCompute >= COMPUTE_S && !dismissed['stalled-compute']) { showProblem('stalled-compute', L.downloadError); diagnose(true); }
      } else if (visible >= lim && !dismissed.slow) {
        PROBLEMS.slow.title = 'Still not ready after ' + lim + ' seconds';
        showProblem('slow', L.downloadError); diagnose(true);
      }
    }
    if (L.stage === 'engine' && !L.times.rStarted && visible >= 20 && !diagnosed) diagnose();
    // R printed an error and the app's page never arrived: app.R stopped while it was sourced
    if (L.stage === 'frame' && L.rError && t - L.times.frame > 4 && !(L.problem && PROBLEMS[L.problem].fatal))
      showProblem(DOWNLOAD_RX.test(L.rError) ? 'engine-died' : 'r-start', L.rError);
    if (L.ready && L.busy && L.busySince && t - L.busySince >= BUSY_S && !L.problem) showProblem('busy-long');
    render();
  }, 1000);

  function onPageError(msg) {
    msg = String(msg || 'error');
    log('page-error', msg);
    if (/Unexpected response type/i.test(msg) && L.stage === 'frame' && L.rError) {
      showProblem(DOWNLOAD_RX.test(L.rError) ? 'engine-died' : 'r-start', L.rError);
    } else if (/ServiceWorker controller was not found/i.test(msg)) {
      if (!autoReload('the app viewer found no service worker controller')) showProblem('no-controller', msg);
    } else if (!L.ready && DOWNLOAD_RX.test(msg)) {
      showProblem('engine-died', msg);
    }
  }
  window.addEventListener('error', function (ev) { onPageError(ev.message || (ev.error && ev.error.message)); });
  window.addEventListener('unhandledrejection', function (ev) {
    var r = ev.reason; onPageError(r && r.message ? r.message : r);
  });
  // webR forwards its worker's console to this page: keep the message that names a file R could
  // not download, so the problem panel can say which one
  ['error', 'warn'].forEach(function (level) {
    var orig = console[level];
    if (typeof orig !== 'function') return;
    console[level] = function () {
      try {
        var m = [].map.call(arguments, function (a) { return a && a.message ? a.message : String(a); }).join(' ');
        var pk = /Downloading webR package: ([A-Za-z0-9.]+)/.exec(m);
        var rerr = /^(?:preload error:)?(Error(?: in [^\n]*?)?: [\s\S]*)$/.exec(m);
        if (pk) { L.pkg = pk[1]; log('webr-package', pk[1]); render(); }
        else if (rerr && !L.ready) {
          // R's own error output (webR forwards R's stderr here): keep the first, the root cause
          log('r-error', rerr[1]);
          if (!L.rError) L.rError = rerr[1].slice(0, 400);
        }
        else if (/Couldn't load|Can't download|preload error|Error fetching|Failed to load/i.test(m)) {
          log('webr-' + level, m);
          if (!L.downloadError && /Couldn't load|Error fetching|Failed to load|Can't download/i.test(m))
            L.downloadError = m.replace(/^preload error:/, '').slice(0, 300);
        }
      } catch (e) { /* never break the console */ }
      return orig.apply(console, arguments);
    };
  });
  window.addEventListener('pageshow', function (ev) { if (ev.persisted) location.reload(); });

  // full screen covers the page: what is behind it leaves the tab order (inert), and a copy of the
  // top bar's theme toggle (assets/ui.js handles every .theme-toggle) shows in the app's bar
  var behind = [].slice.call(document.querySelectorAll('body > .skip, header.top, #main > .wrap, footer.site'));
  var siteToggle = document.querySelector('header.top .theme-toggle');
  if (siteToggle && fullBtn) fullBtn.parentNode.insertBefore(siteToggle.cloneNode(true), fullBtn);
  function setFull(on) {
    behind.forEach(function (el) { if (on) el.setAttribute('inert', ''); else el.removeAttribute('inert'); });
    app.classList.toggle('is-full', on);
    document.body.classList.toggle('launch-full', on);
    fullBtn.setAttribute('aria-pressed', on ? 'true' : 'false');
    fullBtn.textContent = on ? 'Exit full screen' : 'Full screen';
  }
  function onKey(ev) { if (ev.key === 'Escape' && app.classList.contains('is-full')) setFull(false); }
  document.addEventListener('keydown', onKey);
  app.addEventListener('click', function (ev) {
    var b = ev.target.closest && ev.target.closest('[data-action]');
    if (!b) return;
    var a = b.getAttribute('data-action');
    if (a === 'reload') location.reload();
    else if (a === 'full') setFull(!app.classList.contains('is-full'));
    else if (a === 'dismiss' && L.problem) { dismissed[L.problem] = true; clearProblem(); }
  });

  render();
  startServiceWorker();
})();
