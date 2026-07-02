// Narration for the SAS/R Smartsheet OVERVIEW screencast — a true live capture of the real
// interactive CP-101 tracker demo (CP101_Tracker_Demo.html) being driven on screen. Package voice.
// Concept-level (the deep version is SAS_R_Smartsheet_Example_narrated.mp4). 6 scenes.
// Each scene's `act` (consumed by ss_overview_cast.mjs) drives the real page.
module.exports = [
  // 0 - intro (static, initial state)
  "Keeping a Smartsheet program tracker current is usually a manual chore. Here is a tool that does it for you, from the validated SAS or R you already run on a schedule, with no A-I and no copy and paste. This is a representative demo of the C-P one-oh-one program tracker. Click run, and watch a single night's job.",
  // 1 - run (click Run)
  "One scheduled run. The job reads the sheet, computes tonight's operational status, and writes it back to each row by a stable key. Enrollment drops to At Risk; the database cut moves to Watch and its date slips; the spec ticks up to eighty-five percent; and one genuinely new row is appended, all in a single idempotent upsert.",
  // 2 - the log + the alert (settled)
  "Look at the log on the right: real reads and writes to the Smartsheet A-P-I, then the status attachment. And the instant the status cell changed to At Risk, Smartsheet's own workflow, the one a project manager configured once, emailed them. The code wrote the fact; Smartsheet decided who to tell.",
  // 3 - re-run idempotent (click Re-run)
  "Run the very same job again. Nothing duplicates, because every row is matched by its key, so it reports rows updated and zero added. Re-running is always safe; the sheet just converges to the same truthful state.",
  // 4 - the guard (click Try a non-ops column)
  "And the safety boundary is in code, not policy. When a non-operational column tries to ride along, the ops-only allowlist blocks it and the job stops, so no participant-level data and no reported clinical number can ever reach the cloud.",
  // 5 - close (settled)
  "That is the whole idea. Your tracker is always current, the alerts are automatic, and you never paste a status again, all from validated SAS and R you already own. The library ships ready to use: drop in your sheet, your key, and your allowlist, and schedule it.",
];
// action map (by scene index) for the cast driver
module.exports.acts = ['none', 'run', 'none', 'rerun', 'guard', 'none'];
