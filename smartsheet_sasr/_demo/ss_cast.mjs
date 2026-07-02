// True live screencast at the PACKAGE standard: per-frame headless-Chrome capture of the animated
// scene (window.seek), with Daniel@150 per-sentence narration + 0.30s gaps, the ttsClean pronunciation
// map, burned-in captions, fades, and 1920x1080 crf20 stereo — matching build_*_narration.js.
// usage:  node kb_cast.mjs
import { createRequire } from 'module';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const PPATH = require.resolve('puppeteer-core', { paths: [
  '/Users/patrickiben/Optimized_CCR_Slides/node_modules',
  '/Users/patrickiben/Documents/Resilience_Telemetry/_walkthrough/node_modules' ] });
const puppeteer = (m => m.default || m)(require(PPATH));

const PD = '/Users/patrickiben/Biometrics_AI_Program/smartsheet_sasr/_demo';
const notes = require(PD + '/ss_notes.js');
const SCENE = 'file://' + PD + '/ss_scene.html';
const OUT = '/Users/patrickiben/Biometrics_AI_Program/smartsheet_sasr/SAS_R_Smartsheet_Example_narrated.mp4';
const SRT = '/Users/patrickiben/Biometrics_AI_Program/smartsheet_sasr/SAS_R_Smartsheet_Example.srt';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const VOICE = 'Daniel', RATE = '150', FPS = 12, GAP = 0.30, TAIL = 1.0, FADE = 0.5, W = 1920, H = 1080;
const WORK = '/tmp/sscast_pkg'; fs.rmSync(WORK, { recursive: true, force: true }); fs.mkdirSync(WORK, { recursive: true });
const sh = (c, a) => execFileSync(c, a, { cwd: WORK, stdio: ['ignore', 'pipe', 'pipe'] }).toString();
const dur = f => parseFloat(sh('ffprobe', ['-v', 'quiet', '-of', 'csv=p=0', '-show_entries', 'format=duration', f]).trim());

const reps = [
  [/\bGUI\b/g, 'G-U-I'], [/\bDTA-03\b/g, 'D-T-A oh-three'], [/\bDTA\b/g, 'D-T-A'], [/\bHTML\b/g, 'H-T-M-L'],
  [/\bEntryID\b/g, 'Entry-I-D'], [/\bPowerShell\b/g, 'Power-Shell'], [/\bCP-101\b/g, 'C-P one-oh-one'],
  [/\bPHI\b/g, 'P-H-I'], [/\bAI\b/g, 'A-I'], [/\bKB\b/g, 'knowledge base'], [/\bSOP\b/g, 'S-O-P'], [/\bSAS\b/g, 'sass'],
  [/\bread-only\b/g, 'red-only'], [/\bCopilot\b/g, 'co-pilot'], [/\bPower Automate\b/g, 'Power Auto-mate'],
];
const ttsClean = s => reps.reduce((t, [a, b]) => t.replace(a, b), s);
const splitSentences = s => s.split(/(?<=[.!?])\s+/).map(x => x.trim()).filter(Boolean);
function srtTime(t) { const ms = Math.round(t * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, s = Math.floor(ms / 1000) % 60, mil = ms % 1000; const p = (n, w = 2) => String(n).padStart(w, '0'); return `${p(h)}:${p(m)}:${p(s)},${p(mil, 3)}`; }

sh('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', String(GAP), '-c:a', 'pcm_s16le', `${WORK}/_gap.wav`]);
sh('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-t', String(TAIL), '-c:a', 'pcm_s16le', `${WORK}/_tail.wav`]);

// 1) per-scene audio (sentence-level + gaps) + global SRT
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

// 2) capture animation per scene (synced to its audio), mux + fade
const b = await puppeteer.launch({ executablePath: CHROME, headless: 'new', args: ['--no-sandbox', '--disable-gpu', '--force-device-scale-factor=2', '--hide-scrollbars'] });
const p = await b.newPage(); await p.setViewport({ width: W, height: H, deviceScaleFactor: 2 });
await p.goto(SCENE, { waitUntil: 'load', timeout: 90000 }); await new Promise(r => setTimeout(r, 600));
const segs = [];
for (let i = 0; i < notes.length; i++) {
  const sd = sceneDur[i], nframes = Math.max(12, Math.round(sd * FPS)), fdir = `${WORK}/f${i}`; fs.mkdirSync(fdir);
  for (let f = 0; f < nframes; f++) {
    const t = nframes < 2 ? 1 : f / (nframes - 1);
    await p.evaluate((s, tt) => window.seek(s, tt), i, t);
    await p.screenshot({ path: `${fdir}/${String(f).padStart(4, '0')}.png` });
  }
  const seg = `${WORK}/seg${i}.mp4`;
  const vf = `scale=${W}:${H}:flags=lanczos,setsar=1,fade=t=in:st=0:d=${FADE},fade=t=out:st=${(sd - FADE).toFixed(3)}:d=${FADE},format=yuv420p`;
  sh('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', `${fdir}/%04d.png`, '-i', `${WORK}/audio${i}.wav`,
    '-t', sd.toFixed(3), '-vf', vf, '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', seg]);
  segs.push(`file 'seg${i}.mp4'`);
  process.stdout.write(`· ${i + 1}/${notes.length} ${sd.toFixed(1)}s `);
}
await b.close();

// 3) concat + burn captions (package caption style)
fs.writeFileSync(`${WORK}/segs.txt`, segs.join('\n') + '\n');
sh('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', `${WORK}/segs.txt`, '-c', 'copy', `${WORK}/_combined.mp4`]);
const style = "FontName=Arial,Fontsize=11,Bold=1,PrimaryColour=&H00FFFFFF,BackColour=&H59000000,BorderStyle=3,Outline=3,Shadow=0,MarginV=18,MarginL=60,MarginR=60,Alignment=2";
fs.copyFileSync(SRT, `${WORK}/cap.srt`);
sh('ffmpeg', ['-y', '-loglevel', 'error', '-i', `${WORK}/_combined.mp4`, '-vf', `subtitles=cap.srt:force_style='${style}'`,
  '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'copy', OUT]);
console.log(`\nOUTPUT ${OUT}  ${dur(OUT).toFixed(0)}s · ${cue} caption cues`);
