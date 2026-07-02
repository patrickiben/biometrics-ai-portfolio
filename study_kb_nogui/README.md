# Study Knowledge Base — the no-GUI version (Windows, synced folder)

The no-GUI equivalent of the Copilot/Outlook wiki's **"when a new email arrives in the study folder →
file it"** Power Automate flow — but the trigger is a **scheduled local script**, not a cloud flow.
Point it at your study mail once and it files the **entire study automatically**: **no flow to build,
no SharePoint pages to click, no AI Builder/Copilot credits.** Dragging individual emails is only an
*ad-hoc fallback* for messages that live outside the study folder.

## How it works (the automatic path — the default)
```
 study mail lands in           Update-StudyKB.ps1                Notes\*.html + index.html
 an Outlook folder    ──►       every ~15 min:           ──►     (rebuilt each run)        ──► OneDrive
 (a one-time rule, or           reads the folder, files                 │                       syncs to
 sweep the Inbox by             every NEW message                       └─ read-only:           SharePoint
 subject/sender)                (read-only)                                 mail is never           (no API)
                                                                            moved/deleted
```
Each run connects to your already-open **classic Outlook**, reads the study folder(s) you named (or
sweeps the Inbox by subject/sender), and files every message it hasn't filed before. It remembers what
it's done in `.state\seen.json` (Outlook EntryIDs), so re-runs are idempotent and your mailbox is only
ever **read** — nothing is moved, deleted, or flagged. OneDrive does the SharePoint upload (no
Graph/connector/API).

> **Needs classic Outlook for Windows, open and signed in, in your own session.** The script *attaches*
> to your running Outlook (it won't launch one — that would hang on the profile prompt under a
> scheduler); if Outlook is closed it just skips auto-ingest until the next run. The "new" Outlook and
> Outlook on Mac don't expose this automation — see *Fallback* below.

> **Where the data lives.** The notes and index are plain files in your OneDrive/SharePoint-synced
> library, so the KB inherits **that library's permissions, DLP, and retention** — anyone who can read
> the library can read the whole study's filed mail. Point it at a **restricted, ops-team-scoped
> SharePoint site** (not a personal OneDrive, not an open Team site). Content stays inside your governed
> M365 tenant (no third-party API/connector) but does sync to the cloud tenant by design.

## Set it up once
1. **Drop the script in your synced library.** Put [`Update-StudyKB.ps1`](Update-StudyKB.ps1) in the
   local folder of your synced SharePoint library (right-click the library in File Explorer — it's
   already a folder on disk). That folder becomes the KB root automatically — **no path to edit**; every
   run prints `[StudyKB] root = …` so you can see where the wiki is written. (Override with `-Root` only
   if you keep the script outside the library.)
2. **Point it at the study mail** — pick whichever fits. Route on **source (who sent it)**, not on a
   topic keyword:
   - **By folder (recommended):** a one-time Outlook *rule* that routes your **operational sources**
     into a `CP-101` folder. In the rule wizard: **move to** `CP-101` **if** the mail is *from* your
     study's ops senders / distribution lists (CRO PM & data-management distros, clinical ops, named
     ops contacts), **except if** it's from a sensitive channel (safety/PV mailbox, EDC/IVRS or
     randomization system, the unblinded-stats distro, a lab portal carrying participant data) or the
     subject contains a marker like `unblinded` / `randomization` / `SAE narrative` / a participant ID.
     Then run with `-StudyFolders "CP-101"`. Nested/shared mailbox: a path, e.g.
     `-StudyFolders "Project Mailbox\Inbox\CP-101"`; several with `;`.
   - **By filter (no rule):** sweep the Inbox — but prefer `-SenderContains` (a known ops distro/domain)
     over `-SubjectContains "CP-101"`: **a subject tag also matches a *participant* email about CP-101.**
     The filter path has no "except-if", so it's coarser than the folder+rule — use it only when study
     mail comes from a clean, known sender. (`-SenderContains` matches display name + reply address; the
     script resolves the SMTP address for Exchange senders best-effort, but the folder-rule path is the
     surest target.)

   > **What the rule can — and can't — do.** An Outlook rule can't read an email and decide whether it's
   > "participant-level"; it only matches **who sent it, where it came from, and keywords**. Keep
   > participant data out by routing on **source** + excepting the sensitive channels — *not* a
   > `subject contains CP-101` rule, which routes a participant query straight in. The rule is a coarse
   > pre-filter; the real assurance is layered — (1) **you review what lands** and the KB is ops-only by
   > policy; (2) route by source + the except-list; (3) it assumes a **blinded operational mailbox** —
   > sensitive channels (lab portals, safety/PV, IVRS) *can* reach a blinded inbox, so the except-list is
   > a precondition, not a nicety; if the operator is unblinded by role, don't auto-ingest their Inbox.
3. **Schedule it** every ~15 min, to run **only while you are logged on, as yourself, interactive**
   (`/IT`) so COM lands on the same desktop as your open Outlook:
   ```bat
   schtasks /Create /TN "StudyKB Update" /SC MINUTE /MO 15 /IT /F ^
     /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\Users\you\Study Knowledge Base\Update-StudyKB.ps1\" -StudyFolders CP-101"
   ```
   Do **not** run it as `SYSTEM` or as a stored-password (`/RU`/`/RP`) task — those run in a session
   with no Outlook and the auto-ingest can't attach. **Preferred posture:** have IT code-sign the script
   or allowlist its path; `-ExecutionPolicy Bypass` above is the unsigned quick-start (ExecutionPolicy is
   an execution-convenience setting, not a security boundary — per Microsoft).

Run it once now to confirm (it back-fills the last 30 days on the first run; change with `-BackfillDays`):
```bat
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\you\Study Knowledge Base\Update-StudyKB.ps1" -StudyFolders CP-101
```
After that you don't touch it — **there is no daily gesture.** While Outlook is open the scheduled job
files new study mail on its own; open `index.html` anytime for the searchable wiki.

## Ad-hoc capture (the exception, not the routine)
For a one-off that isn't in the study folder — a thread forwarded from outside the study — drop it into
the `_Inbox` subfolder and it's filed on the next run:
- **Drag** the email from Outlook into `<SyncedLibrary>\_Inbox` (classic Outlook drops `.msg`, new
  Outlook drops `.eml`; both work, plus `.txt`/`.md`/`.html` you paste in).
- **One click (classic Outlook):** add [`FileToKB.vba`](FileToKB.vba) as a toolbar button (setup in its
  header) — select email(s) → click → saved into `_Inbox` as `.msg`.

Disable the ad-hoc pass entirely with `-NoDropFolder`.

## Fallback: new Outlook, or Mac (no classic-Outlook COM)
The automatic folder-read needs classic Outlook's COM, which the new Outlook and Mac don't expose. There
the path is the **ad-hoc drop folder**: drag/Save-As your study emails as `.eml` (or `.html`) into the
synced `_Inbox` — both new Outlook and Outlook-for-Mac can drag a message to a File Explorer/Finder
folder — and let the scheduled script file them. It's less hands-off (you drag), but still **no flow,
no SharePoint clicking, no Copilot.** The `.eml`/`.txt`/`.html` drop path doesn't even need Outlook
installed, so the script can run on the Windows box while you drag from anywhere. (`.msg` reading is the
only part that requires Outlook present.)

## Folder layout (auto-created)
```
<SyncedLibrary>\
  Notes\               <- one .html note per email (this is the KB content)
  index.html           <- the searchable wiki (rebuilt every run)
  _Inbox\              <- ad-hoc drop folder (the exception path)
  _Inbox\_processed\   <- ad-hoc originals moved here after filing
  .state\seen.json     <- which messages are already filed (Outlook EntryIDs)
```

## Ask the knowledge base with a local model (optional)
`Notes\` is a small, clean corpus — perfect for an on-device RAG so you can ask over the whole study
with no cloud. The flow is **strip tags → embed → ask**, all local:
1. Plain-text the notes (no extra tools):
   ```powershell
   New-Item -Type Directory -Force "$Root\.rag" | Out-Null
   Get-ChildItem "$Root\Notes\*.html" | ForEach-Object {
     $t = (Get-Content -Raw $_) -replace '<[^>]+>',' ' -replace '&nbsp;',' ' -replace '\s+',' '
     Set-Content "$Root\.rag\$($_.BaseName).txt" $t.Trim() -Encoding UTF8
   }
   ```
2. Point the same on-prem GGUF used in [`tlf_interpret`](../tlf_interpret/index.html) at `.rag\` (llama.cpp
   + a small local embedding model). Retrieve the top notes for the question, pass them as context, and
   require the answer to **quote and cite** the note it used.
3. Keep it grounded: the model may only restate what's in the notes; a reported/regulated number is
   never sourced from a note or its summary — it comes from the validated system. (Notes are already
   de-duplicated: one per message, by EntryID.)

The **local model runs on-device** — no content goes to any third-party AI or external API. (The KB
*files* live in your governed SharePoint tenant — see **Where the data lives** above.)

## Fidelity & honest caveats
- **Auto-ingest (Outlook folder / Inbox filter):** high fidelity — reads each message's `HTMLBody`
  straight from Outlook, in your own session. Read-only: nothing is moved, deleted, or flagged.
- **`.msg` (ad-hoc classic-Outlook drag):** high fidelity — read via the installed Outlook as a *file
  reader* only.
- **`.txt` / `.html` (you save/paste):** exact.
- **`.eml` (ad-hoc new-Outlook/Mac drag):** full fidelity **if you drop `MimeKit.dll` next to the
  script** (auto-detected: `MimeMessage.Load` → Subject/From/Date/HtmlBody). Without it, a built-in
  naive MIME reader handles plain/simple-HTML emails (multipart/encoded may show raw sections). MimeKit
  on Windows PowerShell 5.1 needs its dependency DLLs alongside it (use the **net48** build from the
  nupkg) or run under **PowerShell 7**; the script falls back to the naive parser if it can't load.
- **The script doesn't judge content.** It files whatever is in the target folder/filter — so
  governance lives in *what you point it at*. Keep participant-level mail out of the KB folder.
- **State:** `.state\seen.json` records which messages are already filed (by EntryID). It's the
  idempotence key — keep it. If it's lost, the next run re-files everything within `-BackfillDays`
  (default 30 days); older history won't come back unless you raise `-BackfillDays`.
- This is **not validated software** and was structure-verified, not executed, in authoring — run/parse
  it on your Windows machine first.

## If a script won't run (IT policy)
**Preferred (production posture):** have IT code-sign the script — or allowlist its path — which also
satisfies change control. `-ExecutionPolicy Bypass` is the unsigned quick-start; ExecutionPolicy is an
execution-convenience setting, *not* a security boundary (per Microsoft), so the signature/allowlist is
the real control. If a run is blocked: `Unblock-File .\Update-StudyKB.ps1` first; if still blocked, ask
IT for the signature/allowlist. If your org blocks **programmatic access to Outlook** (the *"a program
is trying to access Outlook"* prompt never clears), the clean fix is to **code-sign the script and trust
that publisher** in Trust Center ▸ Programmatic Access — keeping the object-model guard ON for everything
unsigned — or fall back to the drop-folder path. No admin rights are otherwise needed.

## Governance (unchanged)
Operations content only — **no PHI, no participant-level data, no unblinded/sponsor-restricted material**
in the knowledge base. The auto-ingest files whatever reaches the study folder, and an Outlook rule can
only filter by **source and keywords — not by understanding content**. So keep participant data out with
a **layered** control, not one clever rule: (1) **you review what's filed**, and the KB is ops-only by
policy; (2) route the folder from your operational senders/distros and *except* the sensitive channels
(safety/PV, EDC/IVRS/randomization, unblinded-stats, lab portals); (3) it assumes a **blinded
operational mailbox** — sensitive channels *can* reach a blinded inbox, so the except-list is a
precondition, not a nicety; if the operator is unblinded by role, don't auto-ingest their Inbox.
Reported/regulated numbers always come from validated tools, never from notes or an LLM summary of them.
