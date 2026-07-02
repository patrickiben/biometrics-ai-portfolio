// ============================================================================
// SUPERSEDED -- the shipped .html for this page is HAND-ENHANCED beyond what this
// builder generates: the package DARK theme, inline SVG diagrams, and content
// updates (2026-06). Rebuilding from this script regenerates the OLD output and
// DROPS all of that. The .html is the SOURCE OF TRUTH.
// Rebuild is guarded: aborts unless you deliberately set REBUILD=1.
// ============================================================================
if (process.env.REBUILD !== '1') {
  console.error('[SUPERSEDED] ' + __filename.split('/').pop() + ': out of sync with the hand-enhanced shipped HTML. Rebuilding would REGRESS it. The .html is the source of truth. Re-run with REBUILD=1 only if you intend to redo those enhancements.');
  process.exit(1);
}

// Builds a self-contained, interactive training-course platform for biostatisticians:
// 3 courses, lessons with embedded content, a KNOWLEDGE CHECK after each lesson, a final
// assessment per course, progress tracking (localStorage), and a printable certificate.
// Works offline (file://). Accessible (keyboard, ARIA, focus mgmt). Run: node build_courses.js
const fs = require("fs");

// ---- helpers for authoring questions -------------------------------------------------
const Q = (q, options, answer, explain, type = "single") => ({ q, type, options, answer, explain });
// answer = array of correct indices (single = one index; tf uses options ["True","False"])

const SERIES = {
  title: "AI Operations for Biostatisticians",
  subtitle: "A hands-on training series — build the AI operating layer, run it safely, and keep the numbers where they belong.",
  passMark: 0.8,
  courses: [

  // ===================================================================================
  { id: "wiki", title: "Build the Self-Updating Copilot Wiki", level: "Core", est: "~60 min",
    blurb: "Turn study email into a shared, queryable knowledge base using the M365 tools you already pay for — built click-by-click, with the PHI and accuracy guardrails baked in.",
    lessons: [

    { id: "found", title: "Foundations & the one governance rule", est: "8 min", html: `
      <p class="lede">The Copilot wiki turns every study-operations email into a structured, searchable knowledge entry — automatically — and lets the whole team ask questions of it in plain language. It runs on tools you already have: Outlook, Power Automate, AI Builder, SharePoint, and a Copilot agent.</p>
      <h3>The shape of it</h3>
      <div class="flowrow">
        <span class="fchip o">Outlook</span><span class="far">→</span>
        <span class="fchip f">Power Automate</span><span class="far">→</span>
        <span class="fchip a">AI Builder</span><span class="far">→</span>
        <span class="fchip s">SharePoint</span><span class="far">→</span>
        <span class="fchip c">Copilot agent</span>
      </div>
      <p>A tagged email triggers a flow; the flow summarizes & classifies it to JSON and files it as a SharePoint row; an agent answers from that store with citations. A weekly digest flow keeps it alive.</p>
      <div class="callout warn"><b>The one rule — memorize it.</b> Route <b>only study-operations content</b> (timelines, decisions, action items, logistics, vendor/process comms, meeting notes). <b>Never</b> route email containing PHI, unblinded treatment assignments, randomization codes/seeds, participant-level data, or sponsor-restricted IP.</div>
      <h3>Why operations content is reasonably safe</h3>
      <ul>
        <li>M365 Copilot processes prompts and data <b>within your Microsoft 365 service boundary</b> and <b>does not train foundation models on your data</b>.</li>
        <li>It honors your <b>existing permissions</b> — it can only surface what the user could already see.</li>
        <li>Your organization's <b>enterprise BAA generally extends to M365 Copilot</b> on covered SKUs.</li>
      </ul>
      <div class="callout tip"><b>The hard limit.</b> Microsoft itself says Copilot is "best suited for scenarios where deterministic accuracy is not required." So <b>reported numbers, submission outputs, and QC stay on validated tools with human double-programming — never Copilot.</b> This wiki is the <i>operational memory</i>; it is not part of the regulated statistical pipeline.</div>`,
      check: { questions: [
        Q("Which of these is acceptable to route into the Copilot wiki?", ["An email with a participant's unblinded lab values", "A CRO timeline-update email about the data-cut date", "A randomization seed from the IXRS vendor", "A listing of patient-level AE narratives"], [1], "Only study-operations content (timelines, decisions, logistics) goes in. Anything participant-level, unblinded, or a randomization seed is forbidden."),
        Q("True or false: reported PK numbers can be produced by the Copilot wiki if a human reviews them.", ["True", "False"], [1], "False. Reported numbers always come from validated tools (e.g., Phoenix WinNonlin) with double-programming — never Copilot. The wiki is operational memory, not the regulated pipeline.", "tf"),
        Q("Why is routing operations email into Copilot considered reasonably safe? (Select all that apply.)", ["Data stays within the M365 service boundary", "Copilot trains its foundation models on your data to improve answers", "It honors your existing permissions", "The enterprise BAA generally extends to covered Copilot SKUs"], [0, 2, 3], "Copilot does NOT train foundation models on your data — that's the whole point. The other three are real reasons it's reasonably safe for ops content.", "multi"),
      ] } },

    { id: "flow", title: "Build 1 — the email-routing flow", est: "14 min", html: `
      <p class="lede">This is the engine: a Power Automate flow that turns every tagged study email into a structured knowledge entry — with a PHI guardrail and an accuracy guardrail built in.</p>
      <div class="videowrap"><video controls preload="none" poster="" src="../copilot_wiki/Copilot_Wiki_BuildWalkthrough_narrated.mp4"></video><p class="cap">▶ Watch the full build (~12 min) — an on-screen operator clicks through every step. <a href="../copilot_wiki/Copilot_Wiki_BuildWalkthrough.pdf">Picture guide (PDF)</a></p></div>
      <h3>1.1 — Tag the email (Outlook)</h3>
      <p>Create a category (e.g. <code>StudyKB-CP101</code>) and an Outlook <b>rule</b> that auto-categorizes study-ops email by sender/subject/distribution list. The flow watches that category, so the right email routes itself.</p>
      <h3>1.2 — The flow, in order</h3>
      <ol class="steps">
        <li><b>Create → Automated cloud flow.</b></li>
        <li><b>Trigger:</b> <i>When a new email arrives (V3)</i> (Office 365 Outlook); set the Folder / category filter in advanced options.</li>
        <li><b>PHI guardrail (Condition):</b> if the message sensitivity label is Restricted / Confidential-PHI → <b>Terminate</b>. Nothing sensitive ever reaches the AI step.</li>
        <li><b>AI Builder → Run a prompt:</b> feed it Subject + Body; ask it to summarize & classify and <b>return JSON only</b>.</li>
        <li><b>Parse JSON</b> on the model output (use the schema from the prompt library).</li>
        <li><b>Parse-guard (do NOT skip):</b> wrap Parse JSON in a <i>Scope</i> with a "run after <b>has failed</b>" branch — malformed JSON routes to a human-review queue; <b>never</b> write unvalidated data to the list.</li>
        <li><b>SharePoint → Create item</b> in the Study Knowledge Base list; map the parsed fields to columns.</li>
        <li>(Optional) <b>Post adaptive card</b> to Teams.</li>
        <li><b>Save</b>, then <b>Test</b> with a sample email.</li>
      </ol>
      <div class="callout warn"><b>Why the parse-guard matters.</b> In a regulated register, silently writing bad data is an <b>accuracy defect</b>. If the model returns malformed JSON, a human reviews it — the list never receives unvalidated data.</div>`,
      check: { questions: [
        Q("Where in the flow does the PHI guardrail sit, and what does it do?", ["At the very end, it deletes sensitive rows after filing", "Right after the trigger, it terminates the flow on Restricted/PHI-labeled mail before the AI sees it", "Inside the AI prompt, it asks the model to ignore PHI", "It runs weekly to scan the SharePoint list"], [1], "The Condition runs immediately after the trigger and terminates the flow on sensitive mail — so PHI never reaches the AI step."),
        Q("The model returns malformed JSON. What should happen?", ["Write it to the list anyway and fix it later", "Route it to a human-review queue and write nothing to the list", "Retry the prompt 10 times automatically", "Delete the email"], [1], "The parse-guard (Scope + 'run after has failed') routes malformed output to a human and never writes unvalidated data — silently writing bad data is an accuracy defect."),
        Q("What is the AI Builder 'Run a prompt' step asked to return?", ["A formatted Word document", "Valid JSON with the extracted fields", "The raw email forwarded to a vendor", "A reported PK table"], [1], "It returns JSON only (subject/study/category/summary/owner/due date) so Parse JSON can map it to SharePoint columns. It never produces a reported number."),
        Q("True or false: the Outlook rule means you must remember to tag each study email by hand.", ["True", "False"], [1], "False — the rule auto-categorizes, so the right email routes itself with no manual tagging.", "tf"),
      ] } },

    { id: "kb", title: "Build 2 — the SharePoint knowledge base", est: "9 min", html: `
      <p class="lede">The durable, permissioned store the flow writes into and the agent reads from.</p>
      <h3>2.1 — The list</h3>
      <p>Create a list <b>"Study Knowledge Base"</b> with eight columns — this is the schema the flow maps into:</p>
      <table class="data"><tr><th>Column</th><th>Type</th></tr>
        <tr><td>Title</td><td>Single line</td></tr><tr><td>Study</td><td>Choice</td></tr>
        <tr><td>Category</td><td>Choice (Decision · Action · Risk · Timeline · Vendor · Other)</td></tr>
        <tr><td>Summary</td><td>Multiple lines</td></tr><tr><td>Owner</td><td>Person</td></tr>
        <tr><td>DueDate</td><td>Date</td></tr><tr><td>SourceEmail</td><td>Hyperlink</td></tr>
        <tr><td>ReceivedDate / ReviewDate</td><td>Date</td></tr></table>
      <h3>2.2 — Pages for narrative knowledge</h3>
      <p>For decision logs, process notes, and FAQs, add <b>SharePoint pages</b> with clear <b>H1/H2/H3</b> headings and metadata columns. Copilot chunks on document structure, so well-headed pages retrieve best.</p>
      <h3>2.3 — Lock it down (the most important compliance step)</h3>
      <ul><li>Restrict the site to the biostat team; turn <b>off</b> external sharing.</li>
      <li>Apply <b>sensitivity labels</b> (these also drive the flow's PHI guardrail).</li>
      <li>Turn on <b>audit</b>.</li></ul>
      <div class="callout warn"><b>Permissions ARE the compliance story.</b> The agent in Build 3 can only ever be as safe as the store it reads — so lock the store down first.</div>`,
      check: { questions: [
        Q("Why structure SharePoint pages with clear H1/H2/H3 headings?", ["It's required by 21 CFR Part 11", "Copilot chunks on document structure, so well-headed pages retrieve better", "It makes the PDF export smaller", "It encrypts the content"], [1], "Retrieval quality depends on document structure — clear headings (and metadata) improve how well the agent can find and cite the content."),
        Q("Which is described as the single most important compliance step for the knowledge base?", ["Adding more columns", "Locking the site down: restrict access, sensitivity labels, audit", "Posting to Teams", "Naming the list correctly"], [1], "The knowledge base holds operations content from email, so its permissions, labels, and audit ARE the compliance story — and the agent is only as safe as the store."),
        Q("The eight list columns serve what purpose in the overall system?", ["They are the schema the email flow maps its parsed fields into", "They store patient-level lab results", "They replace the validated statistical pipeline", "They are decorative"], [0], "The columns are exactly the schema the flow's Parse JSON output maps into — Title, Study, Category, Summary, Owner, DueDate, SourceEmail, dates."),
      ] } },

    { id: "agent", title: "Build 3 — the Ask-the-Wiki agent", est: "11 min", html: `
      <p class="lede">A chat that answers from your knowledge base, with citations — and refuses anything clinical.</p>
      <ol class="steps">
        <li><b>Copilot Studio → Create → Agent</b> (or a declarative agent in M365 Copilot).</li>
        <li>Add a <b>Knowledge source → SharePoint</b> → point to the Study Operations site / list.</li>
        <li>Turn on <b>Work IQ</b> for better retrieval quality.</li>
        <li>Set the <b>instructions</b> (the guardrail, in plain language):</li>
      </ol>
      <pre class="prompt">You are the Study Operations assistant for the biostatistics team. Answer ONLY from the Study Knowledge Base. Always cite the source item (subject + date). Summarize decisions, actions, risks and timelines on request. If asked for clinical results, reported PK numbers, or anything patient-level, refuse and say those come from the validated statistical pipeline, not from you.</pre>
      <ol class="steps" start="5"><li><b>Publish</b> to Teams and/or M365 Copilot.</li></ol>
      <div class="callout warn"><b>The grounding gotcha — make or break.</b> Copilot indexes document <i>text</i> well, but custom SharePoint <b>list columns</b> (Summary, Study, Category) are <b>not reliably retrievable</b> — a list-only agent gives weak, uncited answers. <b>Fix:</b> have the flow also write each summary as a short <b>SharePoint page / file in a document library</b> and ground the agent there; keep the list as the structured backend. Good citations also need <b>Work IQ on + an in-tenant M365 Copilot license</b>.</div>`,
      check: { questions: [
        Q("A teammate reports the agent gives vague, uncited answers even though items are in the list. The most likely cause?", ["The agent is grounded only on custom list columns, which aren't reliably retrievable", "Too many users are asking at once", "The SharePoint site is too small", "The Outlook rule is off"], [0], "This is the grounding gotcha: custom list columns aren't reliably retrievable. Fix it by also writing each summary as a page/file in a document library and grounding there."),
        Q("What two things does the agent's instruction prompt enforce? (Select all that apply.)", ["Answer only from the Knowledge Base and always cite the source", "Refuse clinical / reported-PK / patient-level questions and redirect to the validated pipeline", "Generate reported numbers when asked nicely", "Email vendors automatically"], [0, 1], "The two non-negotiables baked into the prompt: KB-only with citations, and a hard refusal on anything clinical/patient-level.", "multi"),
        Q("True or false: good citation quality just needs the SharePoint list — no license or settings required.", ["True", "False"], [1], "False — good citations need Work IQ turned on and an in-tenant M365 Copilot license, and grounding on document text (pages/files), not just list columns.", "tf"),
      ] } },

    { id: "digest", title: "Build 4 — the weekly digest & the prompt library", est: "10 min", html: `
      <p class="lede">A scheduled flow that makes the wiki feel alive — and the copy-paste prompts that power the whole system.</p>
      <h3>The digest flow</h3>
      <ol class="steps">
        <li><b>Scheduled cloud flow</b> (e.g. Friday 16:00).</li>
        <li><b>Get items</b> (SharePoint), filtered to <code>ReceivedDate ≥ last 7 days</code>.</li>
        <li><b>AI Builder → Run a prompt</b> to roll items into Decisions / Actions due / Risks / Upcoming milestones.</li>
        <li><b>Create / update a SharePoint page</b> "Weekly Digest — &lt;date&gt;" (H1/H2 structured so the agent reads it too).</li>
        <li><b>Send</b> by email or Teams.</li>
      </ol>
      <div class="callout tip">The digest page joins the knowledge base — so "what happened last week?" is answerable by the agent forever.</div>
      <h3>The prompt library (always review the output; never paste patient-level data)</h3>
      <p>The flow's <b>email-extraction prompt</b> returns strict JSON, and contains its own safety clause:</p>
      <pre class="prompt">...If the email contains patient-level or unblinded data, return {"category":"Other","summary":"REDACTED - sensitive"}.</pre>
      <p>Other reusable prompts: the <b>weekly-digest</b> prompt, <b>email triage</b> (3-bullet summary + decisions + actions + a draft reply), <b>SAP drafting</b> (placeholders only — invent nothing), and <b>meeting recap</b>.</p>`,
      check: { questions: [
        Q("How does the weekly-digest flow find the right items to summarize?", ["It reads every email in Outlook", "Get items from the list filtered to ReceivedDate within the last 7 days", "It asks the agent to remember", "It scans attachments"], [1], "A scheduled flow runs Get items filtered to the last 7 days, then summarizes those into the digest page + message."),
        Q("The email-extraction prompt has a built-in safety clause. What does it do on patient-level/unblinded content?", ["Summarizes it anyway", "Returns category 'Other' with summary 'REDACTED - sensitive'", "Emails it to the medical monitor", "Crashes the flow"], [1], "Defense in depth: even past the Condition guardrail, the prompt itself redacts sensitive content rather than summarizing it."),
        Q("For SAP drafting, the prompt instructs the model to…", ["Invent realistic study-specific values to save time", "Use [PLACEHOLDERS] for any study-specific value and invent nothing", "Produce the final reported numbers", "Skip the methods section"], [1], "It drafts boilerplate with placeholders and invents nothing — the real values and numbers come from the validated work, not Copilot."),
      ] } },

    { id: "live", title: "Going live — governance recap & IT readiness", est: "10 min", html: `
      <p class="lede">The build is half a day. Getting IT to say yes is the real path — and it's about timing & permissions, not feasibility.</p>
      <h3>Honest IT risk: Medium-High</h3>
      <div class="callout warn"><b>The single biggest blocker — a DLP connector split.</b> The flow chains <b>Outlook + SharePoint + AI Builder "Run a prompt"</b>. If tenant DLP puts them in <b>different data groups</b>, Power Automate <b>suspends the flow</b> — and you can't fix it yourself. Ask IT to place the three connectors in the <b>same DLP group</b> in one scoped/managed environment.</div>
      <h3>The hard clock</h3>
      <p>Microsoft <b>removes seeded AI Builder credits on 1 Nov 2026</b>; after that the GPT step needs purchased <b>Copilot Credits</b> (PAYG, a few $/month at ops volume). <b>No $30/seat M365 Copilot license is required</b> — it's connector + consumption billing.</p>
      <h3>What to ask IT for</h3>
      <ol class="steps">
        <li>Attach a small <b>Copilot-Credits PAYG meter</b> (mandatory after 1 Nov 2026).</li>
        <li>Put <b>Outlook + SharePoint + AI Builder</b> in the <b>same DLP group</b> in a dedicated environment.</li>
        <li>Confirm generative-AI is enabled and a <b>scoped agent publish</b> is allowed.</li>
        <li>Provide a <b>service account</b> that owns the flow.</li>
        <li>Classify the wiki as a <b>non-GxP decision-support tool</b> (intended-use memo; QA signer) — not a Part 11 system of record.</li>
        <li>Get <b>privacy sign-off</b> that the GPT path is in-tenant / excluded from training.</li>
      </ol>
      <div class="callout tip"><b>The version that ships Monday.</b> If approvals stall, drop the two metered AI parts: Outlook + SharePoint only (same DLP group) appends each email's key fields with a light template; replace the agent with native SharePoint search; <b>keep the weekly digest exactly as designed</b>. ~80% of the value, zero AI entitlement. And <b>submit it separately</b> from the heavy hybrid so it isn't swept into a multi-quarter security review.</div>`,
      check: { questions: [
        Q("What is named as the single biggest blocker to going live?", ["The cost of a Copilot license", "A DLP connector split — Outlook/SharePoint/AI Builder in different data groups suspends the flow", "Slow internet", "Too few SharePoint columns"], [1], "If DLP places the three connectors in different data groups, Power Automate suspends the flow — and you can't self-fix. Ask IT to put them in the same DLP group."),
        Q("After 1 Nov 2026, what changes about the AI step's billing?", ["Nothing", "Seeded AI Builder credits retire; you need a Copilot-Credits PAYG meter (a few $/month at ops volume)", "You must buy $30/seat M365 Copilot for everyone", "The flow stops working permanently"], [1], "Seeded credits retire; a small PAYG Copilot-Credits meter covers it. No per-seat M365 Copilot license is required."),
        Q("If approvals stall, what is the 'ships Monday' fallback? (Select all that apply.)", ["Use Outlook + SharePoint only (same DLP group), appending fields with a light template", "Replace the agent with native SharePoint search", "Keep the weekly-digest flow as designed", "Cancel the project entirely"], [0, 1, 2], "Drop the two metered AI parts to get ~80% of the value with zero AI entitlement, and re-add AI later as a phase 2.", "multi"),
        Q("True or false: this change request should be bundled with the heavy hybrid (on-prem GPU + Claude API) program.", ["True", "False"], [1], "False — submit it separately and M365-native, or a half-day build gets swept into a multi-quarter security review by association.", "tf"),
      ] } },
    ],
    final: { pass: 0.8, questions: [
      Q("The wiki captures an email that turns out to contain an unblinded interim figure. What SHOULD have happened?", ["It files normally; a human can redact later", "The PHI/sensitivity guardrail Condition terminates the flow; the prompt also redacts as a backstop", "The agent answers questions about it", "It is emailed to the sponsor"], [1], "Two layers: the Condition terminates on sensitive-labeled mail, and the extraction prompt redacts sensitive content — defense in depth."),
      Q("Which component owns reported PK numbers in this system?", ["The Copilot agent", "AI Builder", "Validated tools (e.g., Phoenix WinNonlin) with human double-programming", "The SharePoint list"], [2], "Always validated tools + humans. The wiki is operational memory and never produces a reported number."),
      Q("Order matters: which is the correct guardrail sequence in the flow?", ["Create item → Condition → Run a prompt", "Trigger → Condition (PHI) → Run a prompt → Parse JSON → parse-guard → Create item", "Run a prompt → Trigger → Create item", "Parse JSON → Terminate → Trigger"], [1], "The PHI Condition gates before the AI; the parse-guard gates before the write."),
      Q("Select every item that belongs in the 'what to ask IT for' list.", ["Same DLP group for the three connectors", "A Copilot-Credits PAYG meter", "A service account that owns the flow", "Permission to upload patient data to the cloud"], [0, 1, 2], "The first three are real asks. Patient data never goes to the cloud — that's the standing rule.", "multi"),
      Q("The agent gives weak, uncited answers. Best fix?", ["Buy more storage", "Ground it on document text (pages/files in a library) instead of only list columns; Work IQ on", "Add more questions", "Turn off the PHI guardrail"], [1], "The grounding gotcha — list columns aren't reliably retrievable; ground on document text and enable Work IQ."),
      Q("True or false: the whole thing can be built in roughly half a day on tools you already pay for.", ["True", "False"], [0], "True — the build is ~half a day on existing M365 tools; the real path is IT timing & permissions, not feasibility.", "tf"),
    ] },
  },

  // ===================================================================================
  { id: "sasr", title: "Deterministic SAS/R Automation (No AI)", level: "Companion", est: "~35 min",
    blurb: "The lowest-risk tier: scheduled SAS/R that detects, packages, and notifies — with zero AI, zero new vendor, and zero PHI egress. Validated tools own the numbers; humans decide.",
    lessons: [
    { id: "why", title: "Why deterministic SAS/R", est: "7 min", html: `
      <p class="lede">Before any AI, there's a tier you can ship today: scheduled, validated SAS and/or R that does pre-specified work reproducibly inside the environment you already have.</p>
      <ul>
        <li><b>Deterministic & reproducible</b> — same data in, byte-identical result out. No sampling, no model drift, nothing to "explain."</li>
        <li><b>Zero PHI egress</b> — runs where the data already lives; no external API, no new vendor.</li>
        <li><b>No new approval gate</b> — only the team's normal program validation / change control.</li>
      </ul>
      <div class="callout warn"><b>The honest boundary.</b> Deterministic checks answer <b>pre-specified</b> questions and deliver the answer reliably to a human. They do <b>not</b> triage a borderline signal, narrate across signals, or judge clinical meaning — that's the seam the AI hybrid fills later. <b>Necessary, not sufficient — and that's the point: ship this now, layer AI on top when approved.</b></div>`,
      check: { questions: [
        Q("What is the defining property that makes this tier the lowest-risk?", ["It uses the newest AI model", "It's deterministic & reproducible with zero PHI egress and no new approval gate", "It runs in the cloud", "It needs no validation"], [1], "Deterministic + reproducible + zero egress + no new vendor means only the team's normal validation/change-control applies — no new approval gate."),
        Q("True or false: deterministic SAS/R automation can triage a borderline safety signal and decide what it means.", ["True", "False"], [1], "False. It detects and delivers pre-specified facts to a human; judgment/triage is the seam the AI hybrid fills later. Humans and the medical monitor decide.", "tf"),
      ] } },
    { id: "trialmon", title: "TRIALMON — scheduled trial monitoring", est: "10 min", html: `
      <p class="lede">A deterministic SAS/R macro library (<code>%tm_*</code>) that runs the ingest → freshness-gate → checks → digest → alert → heartbeat loop unattended.</p>
      <h3>The loop</h3>
      <p>A scheduler fires a version-controlled program under a <b>service account</b>; it ingests the latest validated extract, runs a fixed battery of <b>deterministic checks</b> (AE/SAE counts, candidate-DLT vs the rule, Hy's-Law/eDISH lab pattern, QTcF tiers, lab/PK reconciliation, enrollment vs plan…), renders a report, and notifies in two tiers (a scheduled digest + an immediate threshold alert).</p>
      <div class="callout warn"><b>It won't fail silently.</b> "No news" is never "all clear." Every run emits a <b>heartbeat</b> with a data-freshness timestamp; a <b>data-freshness gate</b> runs first so a frozen feed announces itself; and alerts are <b>de-duplicated</b> so one ongoing event doesn't fire the same RED dozens of times.</li></div>
      <p>Every flag is a <b>prompt to look</b>, never an adjudication — the medical monitor and humans own every decision.</p>`,
      check: { questions: [
        Q("Why does every run emit a heartbeat with a freshness timestamp?", ["To look busy", "So silence is never mistaken for 'all clear' — a dead job or frozen feed announces itself", "To reduce file size", "Because the FDA mandates emojis"], [1], "The dead-man's-switch principle: 'no news' is never 'good news.' The heartbeat + freshness gate make a stale or dead job visible."),
        Q("A candidate Hy's-Law lab pattern trips the check battery. What does TRIALMON do?", ["Adjudicates it as DILI and closes it", "Detects, pages the right people, and packages the evidence — a human decides", "Edits the lab value", "Emails the sponsor the diagnosis"], [1], "It detects, pages, and packages — humans and the medical monitor make every clinical decision. A flag is a prompt to look, never a finding."),
      ] } },
    { id: "sheetlink", title: "SHEETLINK — Smartsheet from SAS/R", est: "9 min", html: `
      <p class="lede">Keep a Smartsheet program tracker current automatically from scheduled SAS/R — and let Smartsheet's own workflows send the alerts. <b>Code owns the data; Smartsheet owns the notifications.</b></p>
      <h3>The five guarantees of the <code>%ss_*</code> library</h3>
      <ol class="steps">
        <li><b>Idempotent</b> — upsert by a stable key; existing rows update in place, new rows append. Re-running never duplicates.</li>
        <li><b>Ops-only</b> — a coded <b>column allowlist</b> (<code>%ss_guard</code>) fails the job if any non-operational column is written. The in-code PHI boundary.</li>
        <li><b>Token never logged</b> — read from an env var / secret at runtime, never hard-coded.</li>
        <li><b>Rate-limit aware</b> — retries 429/5xx with backoff.</li>
        <li><b>Fails loud</b> — a stale tracker that looks fresh is the dangerous failure; the job stops loudly instead.</li>
      </ol>
      <div class="callout tip">Notifications are configured <b>once</b> in Smartsheet ("when Status changes to At Risk → alert the PM"). SAS/R just writes the truthful cell; Smartsheet decides who to tell.</div>`,
      check: { questions: [
        Q("What does 'idempotent upsert by key' guarantee?", ["The job runs faster", "Re-running it never creates duplicate rows — existing keys update in place", "It encrypts the token", "It sends more emails"], [1], "Matching on a stable key means re-runs converge to the same sheet state; existing rows update, only genuinely new keys append."),
        Q("How is the no-PHI boundary enforced in SHEETLINK?", ["A policy document only", "A coded column allowlist that fails the job if a non-operational column is written", "By asking the user nicely", "By encrypting Smartsheet"], [1], "%ss_guard checks every column against an allowlist and fails loud on any non-operational column — a code-enforced boundary, not just policy."),
        Q("Who sends the alert when a status changes to 'At Risk'?", ["SAS/R sends the email directly", "Smartsheet's own configured workflow", "The CRO", "Nobody"], [1], "Code owns the data; Smartsheet owns the notifications. SAS/R writes the truthful cell and a Smartsheet automation (set up once) fires the alert."),
      ] } },
    ],
    final: { pass: 0.8, questions: [
      Q("What is the single biggest reason this tier needs no new approval gate?", ["It's cheap", "Deterministic, reproducible, zero PHI egress, no new vendor — only normal program validation applies", "It uses AI", "IT loves it"], [1], "No AI to validate, no model to freeze, no data leaving the boundary — so only the team's normal SDLC/change-control applies."),
      Q("Match the safeguard to its failure mode: a feed silently stops refreshing but checks still run green. The safeguard is…", ["Alert de-duplication", "The data-freshness gate (runs first; a frozen feed announces itself)", "The heartbeat only", "Nothing"], [1], "The freshness gate runs before the safety logic so a 'green on stale data' masquerade is caught. (The heartbeat catches a dead job; de-dup catches alert storms.)"),
      Q("True or false: in SHEETLINK, the API token may be hard-coded in the program if the repo is private.", ["True", "False"], [1], "False — the token is read from an env var / secret at runtime, never hard-coded and never logged, regardless of repo privacy.", "tf"),
      Q("A flag fires. Who decides what it means?", ["The macro library", "The scheduler", "Humans / the medical monitor — a flag is a prompt to look, never an adjudication", "Smartsheet"], [2], "Every tier here detects, packages, and notifies; humans and the medical monitor own every decision."),
    ] },
  },

  // ===================================================================================
  { id: "slm", title: "On-Device Small Language Models with SAS/R", level: "Advanced", est: "~35 min",
    blurb: "The most sovereign AI tier: a small open-weight model running offline on a workstation, paired with SAS/R, doing only the language layer behind a human gate. SAS/R owns every number.",
    lessons: [
    { id: "envelope", title: "What a small on-device model can & can't do", est: "9 min", html: `
      <p class="lede">An on-device SLM is a 1–9B-parameter open-weight model, quantized, running offline on a workstation via Ollama/llama.cpp. It's a narrow language helper — not a reasoning engine.</p>
      <div class="twocol">
        <div class="col good"><h4>✓ Reliable (with guardrails)</h4><ul><li>Short text classification / labeling</li><li>Field/entity extraction from a short passage</li><li>Routing & triage tagging</li><li>Near-duplicate grouping</li><li>Short, templated drafting over retrieved text</li></ul></div>
        <div class="col bad"><h4>✗ Do NOT trust it with</h4><ul><li>Anything numeric — math, counts, reconciliation (SAS/R owns ALL numbers)</li><li>Multi-document synthesis / long-context reasoning</li><li>Nuanced clinical/safety narrative or judgment</li><li>Faithful long summaries</li></ul></div>
      </div>
      <div class="callout warn"><b>Bigger-is-better is correct here.</b> A small quantized model hallucinates more and is more prompt-sensitive. When the <i>language</i> work needs real reasoning, a 7B model isn't enough — keep it deterministic SAS/R or escalate to a larger model.</div>`,
      check: { questions: [
        Q("Which task is squarely inside what a small on-device model does reliably?", ["Reconciling lab counts across two transfers", "Labeling a short QC finding as new-vs-known into a fixed set", "Writing a nuanced safety narrative", "Computing AUC"], [1], "Short classification into a fixed vocabulary is in the reliable zone. Numbers and reconciliation are SAS/R's; nuanced narrative is beyond a small model."),
        Q("Who owns every number in this architecture?", ["The small model", "SAS/R and the validated engines — always", "Whoever asks", "Ollama"], [1], "The model never produces a number. SAS/R does all computation/checks/reconciliation; the model only handles the narrow language sub-task."),
      ] } },
    { id: "arch", title: "The SLM + SAS/R architecture", est: "9 min", html: `
      <p class="lede">SAS/R orchestrates and owns determinism; the small model is a constrained, offline sidecar it calls only for the language sub-task.</p>
      <div class="flowrow">
        <span class="fchip f">SAS/R checks</span><span class="far">→</span>
        <span class="fchip a">local SLM (127.0.0.1)</span><span class="far">→</span>
        <span class="fchip s">SAS/R validator</span><span class="far">→</span>
        <span class="fchip c">human gate</span><span class="far">→</span>
        <span class="fchip o">write + audit</span>
      </div>
      <ul>
        <li><b>Offline</b> — the endpoint is loopback only; the box stays off the network, so egress is physically impossible.</li>
        <li><b>Schema-constrained</b> — the model must return JSON matching a fixed schema (enum-constrained), so output is parseable, not best-effort.</li>
        <li><b>Validated</b> — a SAS/R validator checks every field against an allowlist; off-list ⇒ reject and fail loud (never coerce).</li>
        <li><b>Pinned & frozen</b> — model tag + quantization + digest + temperature 0 + seed = a reproducible artifact for GAMP-5 / Part 11.</li>
        <li><b>Human-gated</b> — nothing the model emits is written until a person approves it.</li>
      </ul>`,
      check: { questions: [
        Q("How is 'nothing leaves the box' enforced — not just promised?", ["A signed policy", "The endpoint is loopback-only and the box stays offline — egress is physically impossible; code asserts the loopback before use", "A firewall rule in the cloud", "The model refuses"], [1], "Offline + loopback-only is a physical guarantee; the LOCALMIND library also asserts the endpoint is loopback before every run."),
        Q("Why must the model's output be schema-constrained AND validated against an allowlist?", ["To make it slower", "Belt-and-suspenders: the grammar constrains output at sample time, and the SAS/R validator rejects anything off-list — an untrusted text source", "Only one is needed", "To save tokens"], [1], "Constrain at the server and validate at the client. The model is an untrusted text source; a non-conforming response is a failure, not data."),
      ] } },
    { id: "localmind", title: "LOCALMIND & standing it up with IT", est: "11 min", html: `
      <p class="lede">The <code>%slm_*</code> helper library makes calling the offline model a few lines — and the IT story is, paradoxically, the easiest of any AI option.</p>
      <h3>The worked example (a morning of on-device triage)</h3>
      <p>SAS/R + Pinnacle 21 produce 214 findings (every count SAS/R's). The local model labels each new-vs-known, routes by owner, and drafts a candidate query — as schema-constrained JSON. The validator drops anything off-list; the biostatistician approves; SAS/R writes the queries + a Part 11 audit line with the model digest.</p>
      <div class="callout tip"><b>The IT paradox.</b> On data-egress grounds this is the <b>easiest</b> AI to approve — nothing leaves the box; you prove it by pulling the network cable. The <b>hardest</b> honest constraint is model capability — so scope tightly to short, validated language tasks.</div>
      <h3>Anticipated hurdles (each clearable)</h3>
      <ul>
        <li>"Unknown binaries" → signed release / internal mirror; air-gapped model transfer + checksum.</li>
        <li>"No GPU budget" → CPU-first; a 7B Q4 model runs on a normal workstation.</li>
        <li>"Is it validated/deterministic?" → frozen model + temp 0 + GAMP-5 CSV + human gate; the SLM is decision-support, never the record.</li>
        <li>"Licensing" → prefer Apache-2.0/MIT models (Granite, Phi, Qwen Apache sizes).</li>
      </ul>`,
      check: { questions: [
        Q("In the worked example, where did the 214 findings (the counts) come from?", ["The small model", "SAS/R + Pinnacle 21 — validated code; the model only labels/routes/drafts", "A cloud API", "The biostatistician typed them"], [1], "Every count came from validated, double-programmed code. The model never produces a number — it only does the narrow language layer."),
        Q("Why is the on-device SLM described as the EASIEST AI option for IT to approve on data grounds?", ["It's the cheapest", "Nothing leaves the box — you can prove it by pulling the network cable; no egress, vendor, or telemetry", "It needs no validation", "IT likes small models"], [1], "Offline = the simplest data-governance story of any AI option. The hard part is the opposite of usual: model capability, not security."),
        Q("To minimize licensing friction, which models are preferred?", ["Whatever is newest", "Apache-2.0 / MIT models (e.g., IBM Granite, Phi, the Apache sizes of Qwen)", "Only models with a custom license", "Closed cloud models"], [1], "Prefer genuinely permissive (Apache-2.0/MIT) weights; legal reviews the specific model and size variant."),
      ] } },
    ],
    final: { pass: 0.8, questions: [
      Q("A new use case needs the model to synthesize across five documents and write a nuanced safety narrative. The right call?", ["Use the 7B model anyway", "That's beyond a small on-device model — keep it deterministic SAS/R or escalate to a larger model", "Skip validation", "Buy a bigger GPU and force it"], [1], "Multi-document synthesis and nuanced narrative are beyond a small quantized model; don't force it — keep deterministic or escalate."),
      Q("Select every control the LOCALMIND library enforces.", ["Loopback-only endpoint (offline)", "Schema-constrained output", "Allowlist validation with fail-loud", "Uploading findings to a vendor for a second opinion"], [0, 1, 2], "Offline + schema-constrained + validated (+ pinned model + human gate). Nothing is uploaded anywhere — it's offline by design.", "multi"),
      Q("True or false: temperature 0 + a fixed seed + a pinned model digest guarantees byte-identical output on ANY hardware.", ["True", "False"], [1], "False — it gives run-to-run stable output on the SAME box/build; cross-hardware bit-exactness is not guaranteed (floating-point non-associativity). Pin the hardware too.", "tf"),
      Q("What makes the model output safe to act on in a regulated workflow?", ["It's from an AI so it must be right", "Schema-constrain + validate + human gate, and the model never produces a number — SAS/R and validated engines do", "It's fast", "It runs offline"], [1], "The discipline (constrain, validate, human-gate) plus keeping every number with SAS/R and validated tools is what makes it safe — offline alone isn't enough."),
    ] },
  },
  ],
};

// ---- engine (CSS + JS) ---------------------------------------------------------------
const CSS = `
:root{--ink:#16203A;--muted:#5A6378;--line:#E2E7F2;--bg:#F6F8FC;--ind:#4338CA;--indd:#312C8A;--indbg:#ECECFB;--teal:#0E7C86;--green:#1F9D55;--greenbg:#E7F6EE;--amber:#C2891C;--red:#B5564B;--redbg:#FBEDEA;--gold:#B8860B}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}
a.skip{position:absolute;left:-999px;top:0;background:var(--ind);color:#fff;padding:8px 14px;border-radius:6px;z-index:50}a.skip:focus{left:8px;top:8px}
header.top{background:linear-gradient(135deg,#1b1e44,#312C8A);color:#fff;padding:26px 7% 22px}
header.top .eyebrow{font-size:11px;letter-spacing:2px;font-weight:700;color:#aeb4e0}
header.top h1{font-family:Georgia,serif;font-size:28px;margin:7px 0 4px}
header.top .sub{color:#cdd2f3;font-size:14.5px;max-width:840px}
header.top .prog{margin-top:14px;font-size:12.5px;color:#cdd2f3}
.wrap{max-width:1040px;margin:0 auto;padding:22px 7% 70px}
#view{outline:none}
.crumb{font-size:12.5px;color:var(--muted);margin:4px 0 16px}.crumb a{color:var(--ind);text-decoration:none}.crumb a:hover{text-decoration:underline}
.ccard{background:#fff;border:1px solid var(--line);border-left:6px solid var(--ind);border-radius:12px;padding:18px 20px;margin:14px 0;box-shadow:0 2px 8px rgba(20,20,40,.05)}
.ccard.companion{border-left-color:var(--teal)}.ccard.advanced{border-left-color:var(--gold)}
.ccard h2{margin:0 0 4px;font-family:Georgia,serif;font-size:21px}
.ccard .meta{font-size:12px;color:var(--muted);margin-bottom:7px}.ccard .meta .lvl{display:inline-block;background:var(--indbg);color:var(--indd);font-weight:700;padding:1px 8px;border-radius:20px;margin-right:7px}
.ccard p{font-size:14px;color:#33405e;margin:0 0 12px}
.bar{height:8px;background:#e7eaf3;border-radius:6px;overflow:hidden;margin:8px 0 4px}.bar > i{display:block;height:100%;background:var(--green);width:0}
.ccard .pc{font-size:12px;color:var(--muted)}
.btn{display:inline-block;background:var(--ind);color:#fff;text-decoration:none;font-weight:700;font-size:13.5px;padding:9px 16px;border-radius:8px;border:none;cursor:pointer}
.btn:hover{opacity:.92}.btn.ghost{background:#fff;color:var(--ind);border:1.5px solid var(--ind)}.btn.gold{background:var(--gold)}
.btn:disabled{opacity:.45;cursor:not-allowed}
.llist{list-style:none;padding:0;margin:14px 0}
.llist li{display:flex;align-items:center;gap:12px;background:#fff;border:1px solid var(--line);border-radius:10px;padding:11px 15px;margin:8px 0}
.llist li .num{width:26px;height:26px;border-radius:50%;background:var(--indbg);color:var(--indd);font-weight:700;font-size:12px;display:flex;align-items:center;justify-content:center;flex:0 0 26px}
.llist li.done .num{background:var(--green);color:#fff}
.llist li .lt{flex:1}.llist li .lt b{font-size:14.5px}.llist li .lt span{display:block;font-size:11.5px;color:var(--muted)}
.llist li a.go{font-size:12.5px;font-weight:700;color:var(--ind);text-decoration:none;white-space:nowrap}
.llist li.final{border-style:dashed;border-color:var(--gold);background:#fffdf5}
h2.lh{font-family:Georgia,serif;font-size:25px;margin:6px 0 4px}
.lmeta{font-size:12px;color:var(--muted);margin-bottom:14px}
.lbody{font-size:15px}.lbody .lede{font-size:16.5px;color:#222}
.lbody h3{font-family:Georgia,serif;color:var(--indd);font-size:18px;margin:22px 0 8px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lbody h4{margin:0 0 6px;font-size:14.5px}
.lbody ul,.lbody ol{padding-left:22px}.lbody li{margin:5px 0}
.lbody code{background:var(--indbg);color:var(--indd);padding:1px 6px;border-radius:5px;font-family:Consolas,monospace;font-size:13px}
.lbody pre.prompt{background:#0f1130;color:#e6e8ff;padding:14px 16px;border-radius:10px;overflow:auto;font-family:Consolas,monospace;font-size:12.5px;line-height:1.5;border-left:4px solid var(--ind);white-space:pre-wrap}
.callout{border-radius:10px;padding:12px 16px;margin:15px 0;font-size:14px}.callout.warn{background:var(--redbg);border-left:4px solid var(--red)}.callout.tip{background:#e4f2f3;border-left:4px solid var(--teal)}
table.data{border-collapse:collapse;width:100%;margin:10px 0;font-size:13px}table.data th,table.data td{border:1px solid var(--line);padding:6px 10px;text-align:left}table.data th{background:#15183A;color:#fff}
.flowrow{display:flex;align-items:center;gap:7px;flex-wrap:wrap;margin:14px 0}
.fchip{display:inline-block;color:#fff;font-weight:700;font-size:12.5px;padding:6px 11px;border-radius:8px}.fchip.o{background:#0F6CBD}.fchip.f{background:#0B53CE}.fchip.a{background:#742774}.fchip.s{background:#037B7B}.fchip.c{background:#6E54C8}.far{color:var(--muted);font-weight:700}
.steps li{margin:7px 0}
.twocol{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0}.twocol .col{flex:1;min-width:260px;border-radius:10px;padding:12px 16px}.twocol .col.good{background:var(--greenbg);border:1px solid #bfe6cd}.twocol .col.bad{background:var(--redbg);border:1px solid #ecc9c2}.twocol .col h4{margin-top:0}
.videowrap{margin:14px 0}.videowrap video{width:100%;border-radius:10px;border:1px solid var(--line);background:#000;display:block}.videowrap .cap{font-size:12.5px;color:var(--muted);margin-top:6px}
/* quiz */
.check{margin:24px 0 8px;background:#fff;border:1px solid var(--line);border-radius:12px;padding:18px 20px}
.check h3{margin:0 0 4px;font-family:Georgia,serif;font-size:19px;color:var(--indd)}
.check .ci{font-size:12.5px;color:var(--muted);margin-bottom:12px}
.qq{border-top:1px solid var(--line);padding:14px 0}.qq:first-of-type{border-top:none}
.qq .qt{font-weight:700;font-size:14.5px;margin-bottom:9px}.qq .qt .qn{color:var(--ind)}
.opt{display:block;border:1px solid var(--line);border-radius:8px;padding:9px 12px;margin:6px 0;cursor:pointer;font-size:14px;background:#fff;transition:background .1s}
.opt:hover{background:#f3f5fc}.opt input{margin-right:9px}
.opt.correct{background:var(--greenbg);border-color:var(--green)}.opt.wrong{background:var(--redbg);border-color:var(--red)}.opt.miss{border-color:var(--green);border-style:dashed}
.fb{margin-top:8px;font-size:13px;padding:9px 12px;border-radius:8px;display:none}.fb.show{display:block}.fb.ok{background:var(--greenbg);color:#16633c}.fb.no{background:var(--redbg);color:#7a2e26}
.qscore{margin-top:16px;padding:13px 16px;border-radius:10px;font-weight:700;font-size:15px;display:none}.qscore.show{display:block}.qscore.pass{background:var(--greenbg);color:#16633c}.qscore.fail{background:#fff3da;color:#7a5512}
.nav2{display:flex;justify-content:space-between;gap:10px;margin:22px 0 0;flex-wrap:wrap}
.cert{background:#fff;border:3px double var(--gold);border-radius:14px;padding:34px;text-align:center;margin:20px 0}
.cert .seal{font-size:40px;color:var(--gold)}.cert h2{font-family:Georgia,serif;font-size:28px;margin:6px 0}.cert .nm{font-size:24px;font-weight:700;border-bottom:1px solid var(--line);display:inline-block;padding:4px 26px;margin:10px 0}.cert .meta{color:var(--muted);font-size:13px}
:focus-visible{outline:3px solid var(--gold);outline-offset:2px}
@media print{header.top,.nav2,.btn,.skip{display:none}.cert{break-inside:avoid}}
`;

const JS = String.raw`
const SERIES = __SERIES__;
const PM = SERIES.passMark;
const LS = "biostat_course_progress_v1";
function load(){ try{return JSON.parse(localStorage.getItem(LS))||{}}catch(e){return {}} }
function save(p){ try{localStorage.setItem(LS,JSON.stringify(p))}catch(e){} }
function done(cid,lid){ const p=load(); return !!(p[cid]&&p[cid][lid]&&p[cid][lid].done); }
function setDone(cid,lid,score){ const p=load(); p[cid]=p[cid]||{}; p[cid][lid]={done:true,score:score}; save(p); }
function courseProg(c){ const n=c.lessons.length+1; let d=0; c.lessons.forEach(l=>{if(done(c.id,l.id))d++}); if(done(c.id,"FINAL"))d++; return {d:d,n:n,pct:Math.round(d/n*100)}; }
function esc(s){return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}
function go(h){location.hash=h}
const view=()=>document.getElementById("view");
function focusView(){const v=view();if(v){v.setAttribute("tabindex","-1");v.focus()}}

function render(){
  const h=location.hash.replace(/^#\/?/,"");
  const parts=h.split("/"); updateTopProg();
  if(parts[0]==="course"&&parts[1]){
    const c=SERIES.courses.find(x=>x.id===parts[1]); if(!c)return home();
    if(parts[2]==="lesson"&&parts[3]) return lesson(c,parts[3]);
    if(parts[2]==="final") return finalView(c);
    return courseHome(c);
  }
  home();
  updateTopProg();
}
function updateTopProg(){
  let d=0,n=0; SERIES.courses.forEach(c=>{const p=courseProg(c);d+=p.d;n+=p.n});
  const el=document.getElementById("topprog"); if(el)el.textContent="Overall progress: "+Math.round(d/n*100)+"% · "+SERIES.courses.length+" courses";
}
function home(){
  let h='<div class="crumb">Course catalog</div>';
  h+=SERIES.courses.map(c=>{const p=courseProg(c);const cls=c.level==="Companion"?"companion":c.level==="Advanced"?"advanced":"";
    return '<div class="ccard '+cls+'"><h2>'+esc(c.title)+'</h2><div class="meta"><span class="lvl">'+esc(c.level)+'</span>'+esc(c.est)+' · '+c.lessons.length+' lessons + final assessment</div><p>'+esc(c.blurb)+'</p><div class="bar"><i style="width:'+p.pct+'%"></i></div><div class="pc">'+p.d+' / '+p.n+' complete ('+p.pct+'%)</div><div style="margin-top:12px"><a class="btn" href="#/course/'+c.id+'">'+(p.d>0?"Continue":"Start course")+' &rarr;</a></div></div>';
  }).join("");
  view().innerHTML=h; focusView(); updateTopProg();
}
function courseHome(c){
  const p=courseProg(c);
  let h='<div class="crumb"><a href="#/">Catalog</a> › '+esc(c.title)+'</div>';
  h+='<h2 class="lh">'+esc(c.title)+'</h2><div class="lmeta">'+esc(c.level)+' · '+esc(c.est)+'</div><p class="lbody" style="font-size:15px">'+esc(c.blurb)+'</p>';
  h+='<div class="bar" style="margin-top:14px"><i style="width:'+p.pct+'%"></i></div><div class="pc">'+p.d+' / '+p.n+' complete</div>';
  h+='<ol class="llist">';
  c.lessons.forEach((l,i)=>{const dn=done(c.id,l.id);
    h+='<li class="'+(dn?"done":"")+'"><span class="num">'+(dn?"✓":(i+1))+'</span><span class="lt"><b>'+esc(l.title)+'</b><span>'+esc(l.est)+(dn?" · completed":"")+'</span></span><a class="go" href="#/course/'+c.id+'/lesson/'+l.id+'">'+(dn?"Review":"Open")+' &rarr;</a></li>';
  });
  const fd=done(c.id,"FINAL");
  h+='<li class="final '+(fd?"done":"")+'"><span class="num">'+(fd?"✓":"★")+'</span><span class="lt"><b>Final assessment</b><span>'+Math.round((c.final.pass||PM)*100)+'% to pass · earn your certificate'+(fd?" · passed":"")+'</span></span><a class="go" href="#/course/'+c.id+'/final">'+(fd?"Review":"Take it")+' &rarr;</a></li>';
  h+='</ol>';
  view().innerHTML=h; focusView();
}
function quizHTML(questions,id){
  let h='';
  questions.forEach((q,qi)=>{
    h+='<div class="qq" data-qi="'+qi+'"><div class="qt"><span class="qn">Q'+(qi+1)+'.</span> '+esc(q.q)+'</div>';
    const name=id+"_q"+qi; const inp=q.type==="multi"?"checkbox":"radio";
    q.options.forEach((o,oi)=>{ h+='<label class="opt" data-oi="'+oi+'"><input type="'+inp+'" name="'+name+'" value="'+oi+'"> '+esc(o)+'</label>'; });
    h+='<div class="fb" role="status"></div></div>';
  });
  return h;
}
function gradeQuiz(root,questions){
  let correct=0;
  questions.forEach((q,qi)=>{
    const qel=root.querySelector('.qq[data-qi="'+qi+'"]');
    const chosen=[...qel.querySelectorAll('input:checked')].map(i=>+i.value);
    const ans=q.answer.slice().sort();
    const ok=chosen.length===ans.length&&chosen.slice().sort().every((v,k)=>v===ans[k]);
    if(ok)correct++;
    qel.querySelectorAll('.opt').forEach(op=>{const oi=+op.dataset.oi; op.classList.remove("correct","wrong","miss");
      if(q.answer.includes(oi)&&chosen.includes(oi))op.classList.add("correct");
      else if(!q.answer.includes(oi)&&chosen.includes(oi))op.classList.add("wrong");
      else if(q.answer.includes(oi)&&!chosen.includes(oi))op.classList.add("miss");
    });
    const fb=qel.querySelector('.fb'); fb.className="fb show "+(ok?"ok":"no"); fb.innerHTML=(ok?"✓ Correct. ":"✗ Not quite. ")+esc(q.explain);
  });
  return correct;
}
function lesson(c,lid){
  const li=c.lessons.findIndex(l=>l.id===lid); const l=c.lessons[li]; if(!l)return courseHome(c);
  let h='<div class="crumb"><a href="#/">Catalog</a> › <a href="#/course/'+c.id+'">'+esc(c.title)+'</a> › '+esc(l.title)+'</div>';
  h+='<h2 class="lh">'+esc(l.title)+'</h2><div class="lmeta">Lesson '+(li+1)+' of '+c.lessons.length+' · '+esc(l.est)+'</div>';
  h+='<div class="lbody">'+l.html+'</div>';
  h+='<div class="check" id="chk"><h3>✔ Knowledge check</h3><div class="ci">Answer, then check — you need '+Math.round(PM*100)+'% to complete the lesson. Feedback explains every answer.</div>'+quizHTML(l.check.questions,"l")+
     '<div class="qscore" id="qs"></div><div style="margin-top:14px"><button class="btn" id="checkbtn">Check answers</button> <button class="btn ghost" id="retry" style="display:none">Try again</button></div></div>';
  const prev=li>0?'<a class="btn ghost" href="#/course/'+c.id+'/lesson/'+c.lessons[li-1].id+'">&larr; Previous</a>':'<a class="btn ghost" href="#/course/'+c.id+'">&larr; Course</a>';
  const nextH=li<c.lessons.length-1?'#/course/'+c.id+'/lesson/'+c.lessons[li+1].id:'#/course/'+c.id+'/final';
  const nextL=li<c.lessons.length-1?'Next lesson &rarr;':'Final assessment &rarr;';
  h+='<div class="nav2">'+prev+'<a class="btn" id="nextbtn" href="'+nextH+'">'+nextL+'</a></div>';
  view().innerHTML=h; focusView();
  const root=document.getElementById("chk");
  document.getElementById("checkbtn").onclick=()=>{
    const correct=gradeQuiz(root,l.check.questions); const pct=correct/l.check.questions.length;
    const qs=document.getElementById("qs"); const passed=pct>=PM;
    qs.className="qscore show "+(passed?"pass":"fail"); qs.textContent=(passed?"✓ Passed — ":"Not yet — ")+correct+" / "+l.check.questions.length+" correct ("+Math.round(pct*100)+"%)."+(passed?" Lesson complete.":" Review the feedback and try again.");
    document.getElementById("retry").style.display="inline-block";
    if(passed){setDone(c.id,l.id,pct);updateTopProg();}
  };
  document.getElementById("retry").onclick=()=>{ root.querySelectorAll('input').forEach(i=>i.checked=false); root.querySelectorAll('.opt').forEach(o=>o.classList.remove("correct","wrong","miss")); root.querySelectorAll('.fb').forEach(f=>f.className="fb"); document.getElementById("qs").className="qscore"; window.scrollTo(0,document.getElementById("chk").offsetTop-20); };
}
function finalView(c){
  let h='<div class="crumb"><a href="#/">Catalog</a> › <a href="#/course/'+c.id+'">'+esc(c.title)+'</a> › Final assessment</div>';
  h+='<h2 class="lh">Final assessment — '+esc(c.title)+'</h2><div class="lmeta">'+c.final.questions.length+' questions · '+Math.round((c.final.pass||PM)*100)+'% to pass &amp; earn your certificate</div>';
  h+='<div class="check" id="chk">'+quizHTML(c.final.questions,"f")+'<div class="qscore" id="qs"></div><div style="margin-top:14px"><button class="btn gold" id="submitbtn">Submit assessment</button> <button class="btn ghost" id="retry" style="display:none">Retake</button></div></div>';
  h+='<div id="certwrap"></div>';
  h+='<div class="nav2"><a class="btn ghost" href="#/course/'+c.id+'">&larr; Course</a><a class="btn ghost" href="#/">All courses &rarr;</a></div>';
  view().innerHTML=h; focusView();
  const root=document.getElementById("chk"); const pass=c.final.pass||PM;
  document.getElementById("submitbtn").onclick=()=>{
    const correct=gradeQuiz(root,c.final.questions); const pct=correct/c.final.questions.length; const passed=pct>=pass;
    const qs=document.getElementById("qs"); qs.className="qscore show "+(passed?"pass":"fail"); qs.textContent=(passed?"✓ Passed! ":"Not yet — ")+correct+" / "+c.final.questions.length+" correct ("+Math.round(pct*100)+"%).";
    document.getElementById("retry").style.display="inline-block";
    if(passed){ setDone(c.id,"FINAL",pct); updateTopProg(); showCert(c,pct); } else { document.getElementById("certwrap").innerHTML=""; }
  };
  document.getElementById("retry").onclick=()=>{ root.querySelectorAll('input').forEach(i=>i.checked=false); root.querySelectorAll('.opt').forEach(o=>o.classList.remove("correct","wrong","miss")); root.querySelectorAll('.fb').forEach(f=>f.className="fb"); document.getElementById("qs").className="qscore"; document.getElementById("certwrap").innerHTML=""; window.scrollTo(0,0); };
}
function showCert(c,pct){
  const nm=(load().__name)||"";
  let h='<div class="cert"><div class="seal">❖</div><h2>Certificate of Completion</h2><p>This certifies that</p><div class="nm" id="certname">'+(nm?esc(nm):"________________")+'</div><p>has completed <b>'+esc(c.title)+'</b><br>with a score of <b>'+Math.round(pct*100)+'%</b>.</p><div class="meta">AI Operations for Biostatisticians · score recorded locally on this device</div><div style="margin-top:16px"><button class="btn ghost" id="setname">Enter your name</button> <button class="btn" id="printcert">Print / save PDF</button></div></div>';
  document.getElementById("certwrap").innerHTML=h;
  document.getElementById("setname").onclick=()=>{ const v=prompt("Name for the certificate:",nm); if(v!=null){const p=load();p.__name=v;save(p);document.getElementById("certname").textContent=v||"________________";} };
  document.getElementById("printcert").onclick=()=>window.print();
  document.getElementById("certwrap").scrollIntoView({behavior:"smooth"});
}
window.addEventListener("hashchange",render);
window.addEventListener("DOMContentLoaded",()=>{ if(!location.hash)location.hash="#/"; render(); });
`;

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${SERIES.title} — Training</title><style>${CSS}</style></head>
<body><a class="skip" href="#view">Skip to content</a>
<header class="top"><div class="eyebrow">TRAINING SERIES · FOR BIOSTATISTICIANS</div><h1>${SERIES.title}</h1><div class="sub">${SERIES.subtitle}</div><div class="prog" id="topprog">Loading…</div></header>
<main class="wrap"><div id="view" tabindex="-1"></div></main>
<script>${JS.replace("__SERIES__", JSON.stringify(SERIES))}</script>
</body></html>`;
fs.writeFileSync(__dirname + "/Biostatistics_AI_Training.html", html);
const nQ = SERIES.courses.reduce((n, c) => n + c.lessons.reduce((m, l) => m + l.check.questions.length, 0) + c.final.questions.length, 0);
console.log("WROTE Biostatistics_AI_Training.html (" + (html.length / 1024).toFixed(0) + " KB) — " + SERIES.courses.length + " courses, " + SERIES.courses.reduce((n, c) => n + c.lessons.length, 0) + " lessons, " + nQ + " quiz questions");
