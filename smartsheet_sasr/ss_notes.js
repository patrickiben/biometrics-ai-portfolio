// Narration for the Smartsheet-from-SAS/R worked example (8 slides). No AI in the loop.
module.exports = [
  // 1 - title
  `Here is how a biostatistician keeps a Smartsheet program tracker perfectly current without ever touching it, and without any A-I. A scheduled SAS or R job writes the truthful operational status to the sheet by a stable key. Smartsheet's own built-in workflow then sends the alerts. Code owns the data; Smartsheet owns the notifications.`,
  // 2 - architecture
  `The loop has four parts. A scheduler fires the program every night, the same way your validated reports already run. The program reads last night's validated extract, computes the operational status, and pushes only ops-only columns to the sheet. Then a Smartsheet automation you set up once watches those cells and notifies the right people. Nothing sensitive leaves the environment, and there is no new tool to validate.`,
  // 3 - beat 1, read
  `Beat one: the job reads the sheet first. It pulls a fresh column map, because the column ids are the only stable address, and it reads the existing rows keyed on the Task code you own. Now the job knows exactly which rows already exist, so it can update in place instead of blindly appending.`,
  // 4 - beat 2, update status
  `Beat two: the job writes the new status by key. Database lock has slipped to At Risk; the tables row moves to Watch. Because every write is matched on the Task code, re-running the job ten times a night converges to the same sheet. It never creates a duplicate row. That idempotence is the whole reason this is safe to automate.`,
  // 5 - beat 3, cascade
  `Beat three: one upsert call carries the whole batch. The job hands Smartsheet a single array of rows, splits cleanly into updates for keys that already exist and appends for the new ones, and every affected milestone flips at once. This is plain, readable SAS or R, double-programmed and version-controlled like any study program.`,
  // 6 - beats 4 and 5, attach and notify
  `Beats four and five: the job attaches last night's one-page status PDF to the summary row, and then steps back. It does not send a single email. The instant the status cell changed to At Risk, the Smartsheet workflow you configured once fired the alert to the project manager, on whatever channel they chose. SAS wrote the fact; Smartsheet decided who to tell.`,
  // 7 - safeguards
  `Four safeguards make this trustworthy. The upsert is idempotent, matched by key, so it can never duplicate. A coded allowlist blocks any non-operational column, so no participant-level or reported clinical number can ever reach the cloud. The token is read from a secret at runtime, never hard-coded and never logged. And the job is rate-limit aware and fails loud, so a stale tracker announces itself instead of pretending to be fresh.`,
  // 8 - close
  `That is the whole idea. Your tracker is always current, the alerts are automatic, and you never copy and paste a status again, all with validated SAS and R you already own. The macro library ships ready to use: drop in your sheet id, your key, and your allowlist, and schedule it.`,
];
