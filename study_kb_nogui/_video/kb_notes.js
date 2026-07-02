// Narration for the "Study Knowledge Base — no GUI" terminal screencast — one entry per scene,
// first-person and natural (the package's narration voice), walking through the REAL session on screen.
module.exports = [
  // 0 · the real script
  "You wanted to see the real thing, so here it is — no graphical interface, just the actual script. There's the listing: the PowerShell file, the one-click macro, and nothing else. And look at what the script itself says it does: it attaches to your already-open Outlook and reads the study folder — it never moves, deletes, or modifies your mail; it only reads. The one function worth seeing is the sanitizer: before any email is saved, it strips out scripts, styles, and tracking — so a note can never run code or phone home when you open it.",
  // 1 · the folder + ad-hoc drop
  "Now let me run it on a real folder, on this machine. Here's the knowledge base folder, with its drop inbox. The ad-hoc capture — the one you already have — is exactly this: you drop a few study emails into that inbox, which is what the one-click Outlook macro does for you. Three operational emails, ready to file.",
  // 2 · run it
  "Run the script. Each email becomes one read-only, structured note, written to the Notes folder. And every one is stamped with its Outlook EntryID, recorded in seen-dot-json. That watermark is what makes it safe to run unattended — it is how the script knows what it has already filed.",
  // 3 · a filed note + the sanitize proof
  "Here is one of the filed notes — subject, sender, the time it was captured, and the operations-only footer. Now the safety net, made visible. The source email carried a tracking script and a remote pixel. The filed note has neither: the script is gone, and the remote image is neutralized — turned into a dead, blocked link. Every note is sanitized on the way in.",
  // 4 · idempotency
  "And the watermark earns its keep. Drop the very same emails in again, run the script again — and it skips every one. Zero filed, three skipped. It is genuinely idempotent: it never files the same message twice, no matter how often it runs.",
  // 5 · the ad-hoc macro + close
  "Finally, the ad-hoc one-click — a small Outlook macro, for the rare email that lives outside your study folder. So that is the whole tool: one Outlook rule to route the mail, one scheduled script to file it, real notes on a real drive. No graphical interface, operations-only — and the validated systems still own every number.",
];
