// TRUE live screencast of the REAL interactive TRIALMON safety dashboard being driven on screen
// (navigates sections, clicks a flagged participant to open the evidence modal + trajectories).
// Real-time headless-Chrome capture + Daniel@150 narration + burned captions + fades, 1920x1080, CFR-25.
import { createRequire } from 'module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const PPATH = require.resolve('puppeteer-core', { paths: ['/Users/patrickiben/Optimized_CCR_Slides/node_modules'] });
const puppeteer = (m => m.default || m)(require(PPATH));

const DIR = '/Users/patrickiben/Biometrics_AI_Program/sasr_monitoring_wiki';
const notes = require(DIR + '/tm_notes.js');
const acts = notes.acts;
const PAGE = 'file://' + DIR + '/TRIALMON_Dashboard.html';
const OUT = DIR + '/TRIALMON_Dashboard_Screencast_narrated.mp4';
const SRT = DIR + '/TRIALMON_Dashboard_Screencast.srt';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const VOICE = 'Daniel', RATE = '150', GAP = 0.30, TAIL = 1.0, FADE = 0.5, W = 1920, H = 1080;
const WIN = { ov: 1.8, hep: 2.4, clickSubj: 3.2, hold: 1.6, card: 2.4 };
const WORK = '/tmp/tmcast'; fs.rmSync(WORK, { recursive: true, force: true }); fs.mkdirSync(WORK, { recursive: true });
const sh = (c, a) => execFileSync(c, a, { cwd: WORK, stdio: ['ignore', 'pipe', 'pipe'] }).toString();
const dur = f => parseFloat(sh('ffprobe', ['-v', 'quiet', '-of', 'csv=p=0', '-show_entries', 'format=duration', f]).trim());
const sleep = ms => new Promise(r => setTimeout(r, ms));

const reps = [[/\bAI\b/g, 'A-I'], [/\bALT\b/g, 'A-L-T'], [/\bQTcF\b/g, 'Q-T-c-F'], [/\bE14\b/g, 'E-14'],
  [/\beDISH\b/g, 'e-DISH'], [/\bDLT\b/g, 'D-L-T'], [/\bSRC\b/g, 'S-R-C']];
const ttsClean = s => reps.reduce((t, [a, b]) => t.replace(a, b), s);
const splitSentences = s => s.split(/(?<=[.!?])\s+/).map(x => x.trim()).filter(Boolean);
function srtTime(t) { const ms = Math.round(t * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60, mil = ms % 1000; const p = (n, w = 2) => String(n).padStart(w, '0'); return `${p(h)}:${p(m)}:${p(s)},${p(mil, 3)}`; }

sh('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', String(GAP), '-c:a', 'pcm_s16le', `${WORK}/_gap.wav`]);
sh('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', String(TAIL), '-c:a', 'pcm_s16le', `${WORK}/_tail.wav`]);

const srt = []; let cue = 0, offset = 0; const sceneDur = [];
for (let i = 0; i < notes.length; i++) {
  const sents = splitSentences(notes[i]); const parts = []; let local = 0;
  for (let j = 0; j < sents.length; j++) {
    const aiff = `${WORK}/s${i}-${j}.aiff`, wav = `${WORK}/s${i}-${j}.wav`, txt = `${WORK}/s${i}-${j}.txt`;
    fs.writeFileSync(txt, ttsClean(sents[j]));
    sh('say', ['-v', VOICE, '-r', RATE, '-o', aiff, '-f', txt]);
    sh('ffmpeg', ['-y', '-i', aiff, '-ar', '48000', '-ac', '2', '-c:a', 'pcm_s16le', wav]);
    const d = dur(wav); cue++;
    srt.push(`${cue}\n${srtTime(offset + local)} --> ${srtTime(offset + local + d)}\n${sents[j]}\n`);
    parts.push(wav); local += d;
    if (j < sents.length - 1) { parts.push(`${WORK}/_gap.wav`); local += GAP; }
  }
  parts.push(`${WORK}/_tail.wav`); local += TAIL;
  fs.writeFileSync(`${WORK}/al${i}.txt`, parts.map(p => `file '${p}'`).join('\n') + '\n');
  sh('ffmpeg', ['-y', '-f', 'concat', '-safe', '0', '-i', `${WORK}/al${i}.txt`, '-c', 'copy', `${WORK}/audio${i}.wav`]);
  sceneDur.push(dur(`${WORK}/audio${i}.wav`)); offset += sceneDur[i];
}
fs.writeFileSync(SRT, srt.join('\n'));

async function doAct(p, kind) {
  if (kind === 'hold') return;
  if (kind === 'clickSubj') {
    await p.evaluate(() => { const n = document.querySelector('[data-sec="hep"]'); if (n) n.dispatchEvent(new MouseEvent('click', { bubbles: true })); });
    await sleep(500);
    await p.evaluate(() => {
      const circles = [...document.querySelectorAll('circle.subj')];
      let best = null;
      for (const c of circles) { const f = ((c.getAttribute('fill') || '') + ' ' + getComputedStyle(c).fill).toLowerCase(); if (f.includes('c4544a') || f.includes('196, 84') || f.includes('c45')) { best = c; break; } }
      if (!best) { let sc = -1e9; for (const c of circles) { const x = +c.getAttribute('cx') || 0, y = +c.getAttribute('cy') || 0; if (x - y > sc) { sc = x - y; best = c; } } }
      if (best) best.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await sleep(300);
    return;
  }
  await p.evaluate((sec) => { try { if (window.closeModal) closeModal(); } catch (e) {} const m = document.getElementById('modal'); if (m) m.classList.remove('show'); const n = document.querySelector('[data-sec="' + sec + '"]'); if (n) n.dispatchEvent(new MouseEvent('click', { bubbles: true })); window.scrollTo(0, 0); }, kind);
}

const b = await puppeteer.launch({ executablePath: CHROME, headless: 'new', args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars'] });
const p = await b.newPage(); await p.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
await p.goto(PAGE, { waitUntil: 'networkidle0', timeout: 90000 }); await sleep(900);
const segs = [];
for (let i = 0; i < notes.length; i++) {
  const sd = sceneDur[i], kind = acts[i] || 'hold', win = WIN[kind] || 2, fdir = `${WORK}/f${i}`; fs.mkdirSync(fdir);
  await doAct(p, kind); await sleep(250);
  const t0 = Date.now(); let k = 0;
  while ((Date.now() - t0) / 1000 < win) { await p.screenshot({ path: `${fdir}/${String(k).padStart(4, '0')}.png` }); k++; }
  const realWin = (Date.now() - t0) / 1000, fpsPlay = Math.max(1, k / realWin), rest = Math.max(0, sd - realWin);
  const seg = `${WORK}/seg${i}.mp4`;
  const vf = `scale=${W}:${H}:flags=lanczos,setsar=1,tpad=stop_mode=clone:stop_duration=${rest.toFixed(3)},` +
    `fade=t=in:st=0:d=${FADE},fade=t=out:st=${(sd - FADE).toFixed(3)}:d=${FADE},format=yuv420p`;
  sh('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', fpsPlay.toFixed(4), '-i', `${fdir}/%04d.png`,
    '-i', `${WORK}/audio${i}.wav`, '-t', sd.toFixed(3), '-vf', vf, '-c:v', 'libx264', '-preset', 'medium',
    '-crf', '20', '-pix_fmt', 'yuv420p', '-r', '25', '-vsync', 'cfr', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', seg]);
  segs.push(`file 'seg${i}.mp4'`);
  process.stdout.write(`· ${i + 1}/${notes.length} ${kind} ${k}f/${realWin.toFixed(1)}s→${sd.toFixed(1)}s `);
}
await b.close();

fs.writeFileSync(`${WORK}/segs.txt`, segs.join('\n') + '\n');
sh('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', `${WORK}/segs.txt`, '-c', 'copy', `${WORK}/_combined.mp4`]);
const style = "FontName=Arial,Fontsize=11,Bold=1,PrimaryColour=&H00FFFFFF,BackColour=&H59000000,BorderStyle=3,Outline=3,Shadow=0,MarginV=18,MarginL=60,MarginR=60,Alignment=2";
fs.copyFileSync(SRT, `${WORK}/cap.srt`);
sh('ffmpeg', ['-y', '-loglevel', 'error', '-i', `${WORK}/_combined.mp4`, '-vf', `subtitles=cap.srt:force_style='${style}'`,
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'copy', OUT]);
console.log(`\nOUTPUT ${OUT}  ${dur(OUT).toFixed(0)}s · ${cue} caption cues`);
