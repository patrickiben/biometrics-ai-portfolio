// Narrated, captioned, faded MP4 for the "Coverage while on leave" SAS/R example.
const fs = require("fs");
const { execFileSync } = require("child_process");
const PD = __dirname;
const N = PD + "/onleave_narration";
const notes = require("./onleave_notes.js");
const BASE = "SAS_R_OnLeave_Example";

const VOICE = "Daniel", RATE = "150";
const GAP = 0.30, TAIL = 1.0, FADE = 0.5;
const sh = (cmd, args) => execFileSync(cmd, args, { cwd: PD, stdio: ["ignore", "pipe", "pipe"] });
const dur = (f) => parseFloat(sh("ffprobe", ["-v", "quiet", "-of", "csv=p=0", "-show_entries", "format=duration", f]).toString().trim());

const reps = [
  [/\bAI\b/g, "A-I"], [/\bAEs\b/g, "A-Es"], [/\bAE\b/g, "A-E"], [/\bSAE\b/g, "S-A-E"], [/\bDLT\b/g, "D-L-T"],
  [/\bKRI\b/g, "K-R-I"], [/\bQTcF\b/g, "Q-T-c-F"], [/\bQT\b/g, "Q-T"], [/\bALT\b/g, "A-L-T"], [/\beDISH\b/g, "e-dish"],
  [/\bSLA\b/g, "S-L-A"], [/\bPHI\b/g, "P-H-I"], [/\bSAS\b/g, "sass"], [/\bSOP\b/g, "S-O-P"], [/\bCP-101\b/g, "C-P one-oh-one"],
];
const ttsClean = (s) => reps.reduce((t, [a, b]) => t.replace(a, b), s);
const splitSentences = (s) => s.split(/(?<=[.!?])\s+/).map((x) => x.trim()).filter(Boolean);
function srtTime(t) {
  const ms = Math.round(t * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60,
    s = Math.floor(ms / 1000) % 60, mil = ms % 1000;
  const p = (n, w = 2) => String(n).padStart(w, "0");
  return `${p(h)}:${p(m)}:${p(s)},${p(mil, 3)}`;
}

sh("ffmpeg", ["-y", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", String(GAP), "-c:a", "pcm_s16le", `${N}/_gap.wav`]);
sh("ffmpeg", ["-y", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", String(TAIL), "-c:a", "pcm_s16le", `${N}/_tail.wav`]);

const srt = [];
let cueNo = 0, offset = 0;
const segList = [];

for (let i = 0; i < notes.length; i++) {
  const slide = i + 1;
  const sents = splitSentences(notes[i]);
  const parts = [];
  let local = 0;
  for (let j = 0; j < sents.length; j++) {
    const aiff = `${N}/c-${slide}-${j}.aiff`, wav = `${N}/c-${slide}-${j}.wav`, txt = `${N}/c-${slide}-${j}.txt`;
    fs.writeFileSync(txt, ttsClean(sents[j]));
    sh("say", ["-v", VOICE, "-r", RATE, "-o", aiff, "-f", txt]);
    sh("ffmpeg", ["-y", "-i", aiff, "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", wav]);
    const d = dur(wav);
    cueNo++;
    srt.push(`${cueNo}\n${srtTime(offset + local)} --> ${srtTime(offset + local + d)}\n${sents[j]}\n`);
    parts.push(wav);
    local += d;
    if (j < sents.length - 1) { parts.push(`${N}/_gap.wav`); local += GAP; }
  }
  parts.push(`${N}/_tail.wav`); local += TAIL;
  const listPath = `${N}/_alist-${slide}.txt`;
  fs.writeFileSync(listPath, parts.map((p) => `file '${p}'`).join("\n") + "\n");
  const slideAudio = `${N}/slide-audio-${slide}.wav`;
  sh("ffmpeg", ["-y", "-f", "concat", "-safe", "0", "-i", listPath, "-c", "copy", slideAudio]);
  const sd = dur(slideAudio);
  const seg = `${N}/seg-${slide}.mp4`;
  const vf = `scale=1920:1080:flags=lanczos,setsar=1,fade=t=in:st=0:d=${FADE},fade=t=out:st=${(sd - FADE).toFixed(3)}:d=${FADE},format=yuv420p`;
  sh("ffmpeg", ["-y", "-loglevel", "error", "-loop", "1", "-framerate", "25", "-i", `${N}/slide-${slide}.png`,
    "-i", slideAudio, "-t", sd.toFixed(3), "-vf", vf,
    "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2", seg]);
  segList.push(`file 'seg-${slide}.mp4'`);
  offset += sd;
  console.log(`slide ${slide}: ${sents.length} cues, ${sd.toFixed(1)}s`);
}

fs.writeFileSync(`${PD}/${BASE}.srt`, srt.join("\n"));
fs.writeFileSync(`${N}/segs.txt`, segList.join("\n") + "\n");
sh("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", `${N}/segs.txt`, "-c", "copy", `${N}/_combined.mp4`]);
const style = "FontName=Arial,Fontsize=11,Bold=1,PrimaryColour=&H00FFFFFF,BackColour=&H59000000,BorderStyle=3,Outline=3,Shadow=0,MarginV=16,MarginL=50,MarginR=50,Alignment=2";
execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", `${N}/_combined.mp4`,
  "-vf", `subtitles=${BASE}.srt:force_style='${style}'`,
  "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "copy",
  `${PD}/${BASE}_narrated.mp4`], { cwd: PD, stdio: ["ignore", "pipe", "pipe"] });
const total = dur(`${PD}/${BASE}_narrated.mp4`);
console.log(`\nDONE — ${total.toFixed(0)}s (${(total / 60).toFixed(1)} min), ${cueNo} caption cues`);
