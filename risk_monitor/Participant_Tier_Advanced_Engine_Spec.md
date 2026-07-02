# Participant-Tier Advanced Engine — Implementation Spec

### Optimal-Transport drift + nested Active Inference, on-device

**Scope.** This spec defines the *participant-tier* of the advanced early-warning engine in the Trial-Termination Early-Warning Dashboard: the **on-device**, zero-egress detector that surfaces emerging dose-limiting-toxicity (DLT) and safety risk **earlier and more continuously** than threshold rules, and recommends the most informative next assessment. It is written so a programmer can build it.

> **Governance (binding).** Everything here is **decision-support**. It produces *scores* and *suggestions* for the medical monitor / SRC — never a determination. The rule-based triggers (DLT criteria, Hy's-Law/eDISH, QTcF, PK-exposure caps) remain **authoritative**; the validated safety database owns every reported number. The active-inference "action" only ever recommends *what to observe* (an assessment), for human approval — it never changes dosing, escalation, or termination. The model and its reference barycenters must be **frozen and version-locked** before any use that informs a regulated decision. All participant-level computation runs on the local model with zero egress (Part 11 / ALCOA++ audit).

---

## 1. Where it runs and what it touches

| | |
|---|---|
| **Engine** | On-device / on-prem local LLM + a small numerical service (NumPy/SciPy-class). No participant-level data leaves the validated environment. |
| **Inputs (per participant, per cohort)** | Central-lab safety panel (LFTs: ALT, AST, ALP, total bilirubin; chem; heme), ECG (QTcF), PK exposure (Cmax, AUC vs NOAEL-scaled cap), vitals, AE/CTCAE grades, dosing/visit timing. All already on-device. |
| **Reference** | A **pooled Wasserstein barycenter** per analyte, built from prior cohorts/studies of the same compound/class (Section 4). Frozen per analysis. |
| **Outputs** | Three continuous scores per participant — `W_drift`, `F_surprise`, `EFE_action` — plus a localized "driver" attribution and a drafted, human-routed alert. Written to the dashboard Participant panel + feed with a Part-11 record. |
| **Cadence** | Re-score on every new safety/PK posting (near-real-time), and on a fixed daily sweep. |

**Authoritative-vs-advisory split (must be enforced in code):** the rule-based DLT/Hy's-Law/QTcF/exposure checks run **first and independently**; this engine runs alongside and can only *raise attention earlier*. A `W_drift`/`F` signal never suppresses or overrides a rule trigger.

---

## 2. Signal 1 — Wasserstein drift (Optimal Transport)

**Idea.** Instead of waiting for a value to cross a line, measure how far a participant's (or cohort's) *distribution* of an analyte has moved from the pooled reference, in the **ground metric of clinical severity**.

### 2.1 Ground metric
Define `d(x, y)` on each analyte's value space so distance reflects clinical danger, not raw units:
- **LFTs / continuous safety:** work in **×ULN** space (so the metric is comparable across analytes and aligned to the eDISH thresholds). Use `d(x,y) = |g(x) − g(y)|` with `g = log2(value/ULN)` so a doubling is one unit and tail moves toward Hy's-Law territory dominate.
- **QTcF:** `d` in ms (optionally asymmetric — penalize prolongation more than shortening).
- **PK exposure:** `d` in units of the NOAEL-scaled margin (multiples of the cap).
- **Ordinal CTCAE grade:** `d(i,j) = |i − j|` (or a convex, grade-escalation-weighted cost).

### 2.2 Distance
1-D Wasserstein-p has a closed form via the inverse CDF (a sort) — cheap and exact:

```
W_p(μ, ν) = ( ∫_0^1 | F_μ^{-1}(t) − F_ν^{-1}(t) |^p dt )^{1/p}        # 1-D: sort both samples, integrate quantile gap
```

Use **p = 2** (penalizes large moves — the dangerous ones — more than W₁). For the **multivariate** participant vector (LFT panel + QTcF + exposure jointly), use **sliced-Wasserstein**, which averages 1-D projections and stays light enough for on-device:

```
SW_2^2(μ, ν) = E_{θ ~ U(S^{d-1})} [ W_2^2( θ·μ , θ·ν ) ]   ≈  (1/L) Σ_{l=1..L} W_2^2( proj_{θ_l} μ , proj_{θ_l} ν )
```

with `L` fixed projection directions (e.g. L = 64), frozen with the model for reproducibility.

### 2.3 Drift score and localization
`W_drift(participant) = SW_2( participant_window , reference_barycenter )`, computed over a rolling window (e.g. the participant's on-treatment trajectory to date).

**Localization (why the flag is actionable):** the 1-D optimal coupling on the *worst* slice is a monotone rearrangement; report the analyte(s) and the value band contributing most to the distance — e.g. *"drift driven by the upper-tail of ALT (×ULN), day 7→9."* This is what the medical monitor reads.

### 2.4 Trigger
Maintain a **control band** for `W_drift` from the reference (Section 4): flag when `W_drift` leaves the band **and** is trending toward worsening (sign of the tail move). Bands are per-analyte and per-cohort-position (later cohorts expect more drift as dose climbs — encoded in the reference).

```python
def w_drift(participant_window, ref_bary, dirs, p=2):
    # participant_window, ref_bary: arrays in ground-metric space (×ULN, ms, margin-multiples)
    s = sliced_wasserstein(participant_window, ref_bary, dirs, p)        # SW_2
    driver = worst_slice_attribution(participant_window, ref_bary, dirs) # analyte + value band
    return s, driver

def drift_flag(s, band, trend):
    return (s > band.upper) and (trend > 0)   # advisory only; never suppresses a rule trigger
```

---

## 3. Signal 2+3 — Active Inference (free-energy surprise + EFE action)

**Generative model (per participant).** A small state-space model of the *expected* on-treatment trajectory: latent health state `s_t`, observations `o_t` (the analyte vector), transition `p(s_t | s_{t-1})` and likelihood `p(o_t | s_t)` whose parameters are the **pooled priors** (Section 4). The **preferred observations** `C` encode the safety/quality tolerances (QTLs, exposure caps, expected analyte ranges).

### 3.1 Signal 2 — Variational free energy = surprise (early warning)
On each new observation, update beliefs `q(s)` by minimizing free energy (variational Bayesian belief-updating). The **same F has two equal forms** — one shows the bound, one is what you compute:

```
F = D_KL[ q(s) ‖ p(s | o) ] − ln p(o)   ≥   − ln p(o)        # the bound (KL ≥ 0): F upper-bounds the surprisal
  = D_KL[ q(s) ‖ p(s) ]      − E_q[ ln p(o | s) ]            # complexity − accuracy  (what you compute)
```

Under exact inference the bound is tight (`F = −ln p(o)` when `q = p(s|o)`); with a restricted family it is a generally non-tight upper bound. Either way, **`F_surprise` rising = the participant is doing something the model didn't expect** — an anticipatory deviation signal, *before* a frank threshold event. Precision-weight per participant; flag when `F` exceeds its rolling band.

> Watch **two** distinct things: **surprise** (`F` rising — unexpected) and **preference-divergence** (outcomes drifting from the preferred QTL state, scored against `C`). They usually move together, but a trajectory can drift toward a fully *predicted* bad state (low surprise, high preference-divergence) — catch both.

### 3.2 Signal 3 — Expected Free Energy = what to monitor next
Choose the next monitoring/data-collection action (e.g. an unscheduled LFT/ECG/PK draw) by **minimizing expected free energy** over candidate observations:

```
π* = argmin_π  G(π),   G(π) = −E[ information gain ]  −  E_q[ ln p(o | C) ]
                                └ epistemic ┘            └ pragmatic (utility) ┘
```

The agent **minimizes G**; because both terms are negated, that **maximizes** expected information gain (the epistemic term — pick the assessment that most reduces uncertainty about emerging DLT risk) and the expected log-preference `ln p(o|C)` (the pragmatic term — favor reaching the safe, on-track state; `C` is the utility). Output: the highest-value assessment, surfaced to the medical monitor **as a suggestion to approve**, with its expected information gain shown.

```python
def free_energy(q, prior_s, loglik):          # F = complexity − accuracy
    return kl(q, prior_s) - expect(q, loglik)

def efe(candidate_obs, q, model, C):          # rank candidate assessments
    scored = []
    for a in candidate_obs:                    # e.g. {LFT, ECG, PK draw}
        epistemic = expected_info_gain(a, q, model)         # mutual information
        pragmatic = expected_log_pref(a, q, model, C)       # E_q[ ln p(o|C) ]
        G = -(epistemic) - (pragmatic)
        scored.append((a, G, epistemic))
    a_star, G_star, ig = min(scored, key=lambda r: r[1])    # minimize G
    return Recommendation(action=a_star, value_of_info=ig)  # human approves; never auto-ordered
```

---

## 4. The pooled reference (prior-cohort priors)

The participant tier is the **lowest of the three early-warning tiers** (participant → study → client). Its priors are **supplied from above** and **pooled across studies**:

- **Reference barycenter.** Per analyte, `μ̄_ref = argmin_μ Σ_k λ_k W₂²(μ, ν_k)` over prior cohorts `ν_k` (Wasserstein-2 barycenter). This is the distribution a new participant/cohort is scored against. The **control bands** in §2.4 / §3 are derived from the spread of `{ν_k}` around `μ̄_ref`.
- **Generative-model priors.** Transition/likelihood parameters and the preferred set `C` are empirical-Bayes estimates pooled across prior cohorts/studies (a **hyperprior**). The higher tier *supplies* the prior to the participant tier; what is *pooled* from the population is the hyperprior — so a new cohort starts **population-informed**, not from scratch, and recalibrates as each study completes.
- **Coupling up.** A participant `W_drift`/`F` excursion is a bottom-up prediction error that propagates to the study tier (raising cohort-level risk) — the coupling across tiers, not three separate dashboards.
- **Optional unifier.** A *Wasserstein-regularized objective* (OT cost in place of/alongside the KL term) makes the belief-updating geometry-aware and lets the barycenter prior enter directly. **Caveat:** once KL→W it is no longer the strict variational free energy, so the "upper bound on surprisal" guarantee relaxes — a deliberate, advanced option, off by default.

```python
def fit_reference(prior_cohorts):              # one-time, frozen per analysis
    bary  = wasserstein_barycenter(prior_cohorts, p=2)     # μ̄_ref per analyte
    bands = control_bands(prior_cohorts, bary)             # W_drift / F bands
    prior = empirical_bayes_hyperprior(prior_cohorts)      # transition/likelihood + C
    return frozen(Reference(bary, bands, prior))           # version-locked artifact
```

---

## 5. Roll-up, output, and the alert

For each participant: `participant_score = w( W_drift, F_surprise, pref_divergence )` with **fixed, documented weights** (not a learned black box) → maps to the Participant-panel RAG. Any amber/red:
1. localizes the driver (analyte + value band + day),
2. pulls the rule-based context (current DLT tally vs the design's stopping rule, eDISH position, QTcF, exposure vs cap) **from the validated tools**,
3. drafts the alert and routes it to the **medical monitor / SRC chair** *ahead* of the scheduled cohort review, with the EFE-recommended next assessment attached,
4. writes a Part-11 record; a human dispositions it. Nothing is paused/escalated by the system.

---

## 6. Validation plan (before any regulated use)

| Step | What | Acceptance |
|---|---|---|
| **Freeze** | Lock model weights, the L projection directions, `μ̄_ref`, control bands, roll-up weights as a versioned artifact. | Re-run on the same inputs is bit-stable. |
| **Back-test / lead-time** | Replay completed cohorts; measure how many days *earlier* `W_drift`/`F` flagged a confirmed DLT/Hy's-Law vs the rule trigger. | Median lead-time > 0; documented per analyte. |
| **Operating characteristics** | On historical data, estimate sensitivity / false-alert rate / alerts-per-cohort-week at the chosen bands. | Alert burden acceptable to the medical monitor; sensitivity ≥ agreed floor. |
| **Concordance** | Confirm the engine never *suppresses* a rule trigger; agreement of "driver" attribution with adjudicated cause. | 100% rule-trigger pass-through; attribution reviewed. |
| **Human-factors** | Medical monitor reviews drafted alerts + EFE suggestions for usefulness and non-coercion. | Suggestions read as advisory; no auto-action path exists. |
| **Documentation** | Spec, validation report, frozen-artifact hash, Part-11 lineage. | Submission-grade package. |

---

## 7. Build order

1. **Ground metrics + 1-D / sliced Wasserstein** on one analyte family (LFTs), reference barycenter from prior cohorts, `W_drift` + driver attribution, control bands. *(Cheap, high-value, fully on-device.)*
2. **Free-energy detector** (`F_surprise`) on the same participant state-space model; add preference-divergence vs `C`.
3. **EFE recommender** (`π*`) over the protocol-allowed assessment set; wire the human-approval queue.
4. **Roll-up + alert drafting + Part-11 record + dashboard write.** Extend metrics to QTcF and PK exposure.
5. **Freeze + validation (Section 6).** Only then does any output inform a regulated decision.

*Companion to the Trial-Termination Early-Warning Dashboard (`Trial_Risk_EarlyWarning_Dashboard.html`, page “🧮 Advanced engine”). Decision-support; advanced; the rules and the humans remain authoritative.*
