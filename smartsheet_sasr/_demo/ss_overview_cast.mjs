// TRUE live screencast of the REAL interactive dashboard (CP101_Tracker_Demo.html) being driven
// on screen — real-time headless-Chrome capture (clicks Run / Re-run / Try-a-non-ops-column), synced
// to Daniel@150 per-sentence narration with burned captions, fades, 1920x1080 — package standard.
// usage:  node _demo/ss_overview_cast.mjs
import { createRequire } from 'module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const PPATH = require.resolve('puppeteer-core', { paths: [
  '/Users/patrickiben/Optimized_CCR_Slides/node_modules',
  '/Users/patrickiben/Documents/Resilience_Telemetry/_walkthrough/node_modules' ] });
const puppeteer = (m => m.default || m)(require(PPATH));

const ROOT = '/Users/patrickiben/Biometrics_AI_Program/smartsheet_sasr';
const notes = require(ROOT + '/_demo/ss_overview_notes.js');
const acts = notes.acts;
const PAGE = 'file://' + ROOT + '/CP101_Tracker_Demo.html';
const OUT = ROOT + '/SAS_R_Smartsheet_Screencast_narrated.mp4';
const SRT = ROOT + '/SAS_R_Smartsheet_Screencast.srt';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const VOICE = 'Daniel', RATE = '150', GAP = 0.30, TAIL = 1.0, FADE = 0.5, W = 1920, H = 1080;
// capture window (real seconds of live action) per action kind
const WIN = { none: 1.6, run: 7.5, rerun: 6.0, guard: 3.8 };
const WORK = '/tmp/ssoverview'; fs.rmSync(WORK, { recursive: true, force: true }); fs.mkdirSync(WORK, { recursive: true });
const sh = (c, a) => execFileSync(c, a, { cwd: WORK, stdio: ['ignore', 'pipe', 'pipe'] }).toString();
const dur = f => parseFloat(sh('ffprobe', ['-v', 'quiet', '-of', 'csv=p=0', '-show_entries', 'format=duration', f]).trim());
const sleep = ms => new Promise(r => setTimeout(r, ms));

const reps = [
  [/\bGUI\b/g, 'G-U-I'], [/\bHTML\b/g, 'H-T-M-L'], [/\bAPI\b/g, 'A-P-I'], [/\bCP-101\b/g, 'C-P one-oh-one'],
  [/\bPHI\b/g, 'P-H-I'], [/\bAI\b/g, 'A-I'], [/\bSAS\b/g, 'sass'], [/\bread-only\b/g, 'red-only'],
];
const ttsClean = s => reps.reduce((t, [a, b]) => t.replace(a, b), s);
const splitSentences = s => s.split(/(?<=[.!?])\s+/).map(x => x.trim()).filter(Boolean);
function srtTime(t) { const ms = Math.round(t * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60, mil = ms % 1000; const p = (n, w = 2) => String(n).padStart(w, '0'); return `${p(h)}:${p(m)}:${p(s)},${p(mil, 3)}`; }

sh('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', String(GAP), '-c:a', 'pcm_s16le', `${WORK}/_gap.wav`]);
sh('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', String(TAIL), '-c:a', 'pcm_s16le', `${WORK}/_tail.wav`]);

// 1) per-scene audio + global SRT
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

// 2) real-time capture of the live dashboard
const b = await puppeteer.launch({ executablePath: CHROME, headless: 'new', args: ['--no-sandbox', '--disable-gpu', '--hide-scrollbars'] });
const p = await b.newPage(); await p.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
await p.goto(PAGE, { waitUntil: 'load', timeout: 90000 }); await sleep(800);

async function clickWhenReady(sel) {
  await p.waitForFunction(s => { const e = document.querySelector(s); return e && !e.disabled; }, { timeout: 15000 }, sel);
  await p.click(sel);
}
const segs = [];
for (let i = 0; i < notes.length; i++) {
  const sd = sceneDur[i], kind = acts[i] || 'none', win = WIN[kind], fdir = `${WORK}/f${i}`; fs.mkdirSync(fdir);
  // trigger the live action at scene start
  if (kind === 'run') await clickWhenReady('#bRun');
  else if (kind === 'rerun') await clickWhenReady('#bRerun');
  else if (kind === 'guard') await clickWhenReady('#bGuard');
  // capture as fast as possible across the real-time window
  const t0 = Date.now(); let k = 0;
  while ((Date.now() - t0) / 1000 < win) {
    await p.screenshot({ path: `${fdir}/${String(k).padStart(4, '0')}.png` }); k++;
  }
  const realWin = (Date.now() - t0) / 1000, fpsPlay = Math.max(1, k / realWin), rest = Math.max(0, sd - realWin);
  const seg = `${WORK}/seg${i}.mp4`;
  const vf = `scale=${W}:${H}:flags=lanczos,setsar=1,tpad=stop_mode=clone:stop_duration=${rest.toFixed(3)},` +
    `fade=t=in:st=0:d=${FADE},fade=t=out:st=${(sd - FADE).toFixed(3)}:d=${FADE},format=yuv420p`;
  sh('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', fpsPlay.toFixed(4), '-i', `${fdir}/%04d.png`,
    '-i', `${WORK}/audio${i}.wav`, '-t', sd.toFixed(3), '-vf', vf, '-c:v', 'libx264', '-preset', 'medium',
    '-crf', '20', '-pix_fmt', 'yuv420p', '-r', '25', '-vsync', 'cfr',
    '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', seg]);
  segs.push(`file 'seg${i}.mp4'`);
  process.stdout.write(`· ${i + 1}/${notes.length} ${kind} ${k}f/${realWin.toFixed(1)}s→${sd.toFixed(1)}s `);
}
await b.close();

// 3) concat + burn captions (package style)
fs.writeFileSync(`${WORK}/segs.txt`, segs.join('\n') + '\n');
sh('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', `${WORK}/segs.txt`, '-c', 'copy', `${WORK}/_combined.mp4`]);
const style = "FontName=Arial,Fontsize=11,Bold=1,PrimaryColour=&H00FFFFFF,BackColour=&H59000000,BorderStyle=3,Outline=3,Shadow=0,MarginV=18,MarginL=60,MarginR=60,Alignment=2";
fs.copyFileSync(SRT, `${WORK}/cap.srt`);
sh('ffmpeg', ['-y', '-loglevel', 'error', '-i', `${WORK}/_combined.mp4`, '-vf', `subtitles=cap.srt:force_style='${style}'`,
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'copy', OUT]);
console.log(`\nOUTPUT ${OUT}  ${dur(OUT).toFixed(0)}s · ${cue} caption cues`);
