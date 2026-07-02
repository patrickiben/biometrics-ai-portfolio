// Narration for a TRUE live screencast of the real interactive TRIALMON safety dashboard
// (TRIALMON_Dashboard.html) being driven on screen. Synthetic data, deterministic, no AI. 6 scenes.
// acts (consumed by tm_cast.mjs): which real interaction each scene performs.
module.exports = [
  // 0 - overview
  "This is the TRIALMON safety dashboard, on synthetic data. It is the covering biostatistician's morning view: every participant in the study screened against the pre-specified safety thresholds, with the worst flag surfaced first. No A-I; deterministic checks only.",
  // 1 - hepatic / eDISH
  "Open the hepatic view. This is the eDISH plane: peak A-L-T against peak bilirubin. The reference lines are three-times and two-times the upper limit, and the shaded upper-right is the Hy's-Law screening quadrant, where both limbs are elevated together.",
  // 2 - click a flagged participant
  "Click the participant sitting in that quadrant, and the evidence packet opens: the deterministic backbone first. The eDISH numbers, the QTcF screen, any adjudicated D-L-T, and the adverse-event counts, each with its own screening flag.",
  // 3 - per-visit trajectories
  "And underneath, the per-visit trajectories, drawn from the as-collected single-draw data: A-L-T and bilirubin climbing visit over visit, QTcF, hemoglobin, neutrophils. Every value here is a screening flag, never a reported number. The reported numbers come from the validated tools, Phoenix WinNonlin and Pinnacle 21.",
  // 4 - cardiac
  "The other views screen the rest of the protocol the same way. The cardiac view runs QTcF against the I-C-H E-14 thresholds, and the adverse-event view runs the three-plus-three dose-escalation state for each cohort.",
  // 5 - close
  "That is the whole idea. The dashboard detects, surfaces, and packages the evidence on a schedule; every clinical decision, causality, seriousness, dose, stays with the medical monitor and the safety review committee. It detects and pages; the humans decide.",
];
module.exports.acts = ['ov', 'hep', 'clickSubj', 'hold', 'card', 'ov'];
