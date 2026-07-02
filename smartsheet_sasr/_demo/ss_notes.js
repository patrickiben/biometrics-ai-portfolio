// Narration for the Smartsheet × SAS/R worked-example screencast (7 scenes, two panels:
// the real R job on the left, the Smartsheet tracker on the right). Package voice. No AI.
module.exports = [
  // 0 - the loop
  "Here is how a biostatistician keeps a Smartsheet program tracker perfectly current without ever touching it, and without any A-I. On the left, a scheduled SAS or R job; on the right, the tracker it drives. The job writes the truthful operational status to the sheet by a stable key, and Smartsheet's own built-in workflow sends the alerts. Code owns the data; Smartsheet owns the notifications.",
  // 1 - the library
  "This is the shipped library — plain, readable R, double-programmed and version-controlled like any study program. The flagship is one idempotent upsert: it matches every row by the Task code you own, updates the ones that already exist, and appends only the genuinely new — so re-running it converges to the same sheet. And before anything leaves the environment, a coded allowlist blocks any non-operational column.",
  // 2 - read
  "Beat one: the job reads the sheet first. It pulls a fresh column map — because the column ids are the only stable address — and reads the existing rows, keyed on the Task code. Now the job knows exactly which rows already exist, so it can update them in place instead of blindly appending.",
  // 3 - write by key (the money shot)
  "Beat two: it writes the new status by key, and you watch the cells flip. Enrollment drops to At Risk; the data cut moves to Watch and its date slips two days; the dependent dry-run tables date cascades with it; the spec ticks up to eighty-five percent; and one genuinely new row is appended. Every write is matched on the Task code — that idempotence is the whole reason this is safe to automate.",
  // 4 - attach + alert
  "Beats three and four: the job attaches last night's one-page status PDF to the data-cut row, and then it steps back. It does not send a single email. The instant the status cell changed to At Risk, the Smartsheet workflow you configured once fired the alert to the project manager. SAS or R wrote the fact; Smartsheet decided who to tell.",
  // 5 - safeguards
  "Two safeguards make this trustworthy. Re-run the very same job and it reports zero rows added — matched by key, it can never duplicate. And when a stray, non-operational column tries to ride along, the allowlist blocks it in code, so no participant-level or reported clinical number can ever reach the cloud. The token is read from a secret at runtime, and the job is rate-limit aware and fails loud.",
  // 6 - close
  "That is the whole idea. Your tracker is always current, the alerts are automatic, and you never copy and paste a status again — all with validated SAS and R you already own. The macro library ships ready to use: drop in your sheet id, your key, and your allowlist, and schedule it.",
];
