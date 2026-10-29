# Vaccine study analysis

[Open the module guide](index.html) · [Learning companion](learning.html) · [Reference ledger](REFERENCES.md) · [Point-and-click toolkit setup](../TOOLKIT_SETUP.html)

This client-neutral module provides six descriptive outputs from mapped analysis-ready CSVs. Run it through the downloaded toolkit's local control panel: create a private project, open the vaccine module, select outputs, map inputs, configure assumptions, preview, generate a revision and run its R analysis. The public website contains the guide and optional teaching material; private study analysis runs locally.

No command-line steps or code edits are required for the supported workflow. R must be available on the computer; the toolkit supplies checks, installation guidance and package-install controls. R is the execution engine. Native SAS exports remain unexecuted reference code and have not been reconciled against R.

## Try the synthetic example

Download [the synthetic settings profile](examples/example_profile.json) and deliberately import it with **Import profile** in the vaccine setup form. Review the fictional assay, thresholds and schedule. The profile contains settings only and leaves all review confirmations false.

In **Upload and map inputs**, choose **Use synthetic example** for participants, titers, doses and diary, or inspect the [participants](examples/participants.csv), [assay results](examples/titers.csv), [administered doses](examples/doses.csv) and [diary](examples/diary.csv) files directly. Confirm the reviewed assumptions, preview, generate and run. The example includes censored observations and incomplete diaries. Its numerical thresholds are teaching values, not protection cutoffs or recommendations for a study.

## Outputs

| ID | Result | Important condition |
| --- | --- | --- |
| `immunogenicity` | GMT/GMC by arm and visit, log-t confidence interval, inclusion/exclusion counts | One assay, antigen and unit combination per revision |
| `fold_rise` | Paired geometric mean fold rise and log-t interval | Baseline and post-baseline values for the same participant |
| `response` | Configured threshold, fold-rise or baseline-conditional response; exact Clopper–Pearson interval | Evaluable participant denominator and explicit rule |
| `titer_plot` | Descriptive geometric-mean visit trends | Visit ordering supplied; populations may differ by visit |
| `reactogenicity` | Participant/dose/symptom incidence and maximum recorded grade, with coverage counts | Declared day window, symptoms and denominator policy |
| `diary_profile` | Daily symptom and completeness counts | Actual administered-dose roster provides the expected denominator |

## Input contract

The forms map source names to these canonical fields. Required files depend on selected outputs.

| File role | Fields | Granularity |
| --- | --- | --- |
| Participants | `USUBJID`, `ARM`, `IMMFL`, `SAFEFL` | One row per participant; explicit population flags |
| Assay results | `USUBJID`, `ASSAY`, `ANTIGEN`, `UNIT`, `VISIT`, `AVAL`, `QUALIFIER`, `LLOQ`, `ULOQ` | One assigned result per participant/assay/antigen/unit/visit |
| Administered doses | `USUBJID`, `DOSE` | One row per actual participant/dose |
| Diary | `USUBJID`, `DOSE`, `DAY`, `SYMPTOM`, `GRADE` | One row per participant/dose/relative-day/symptom |

Canonical qualifiers are `EXACT`, `BLQ`, `ALQ` and `MISSING`; the forms map study source labels to them. `EXACT` requires a positive numeric result within any supplied limits. Leave `AVAL` blank for the other qualifiers. Supply `LLOQ` for BLQ and `ULOQ` for ALQ even when excluding those records. Use the setup schema and validation preview for types and selected-output requirements. Visit assignment is supplied and explicitly confirmed as prespecified. The module does not derive raw collection-time windows. Grades are supplied protocol assignments, not derived from raw temperatures or symptom measurements. A diary grade of `0` means observed absence; blank grades and absent records remain missing.

## Input capacity

Each CSV accepts at most 100,000 records and 16 MB. A revision supports up to 50 distinct arm labels, 50 follow-up visits, 50 dose labels and 50 symptoms; each expected participant/visit or diary grid is limited to 1,000,000 rows. Preview checks these bounds before execution. Select fewer visits, doses or symptoms in separate revisions while preserving the intended population and assessment window. Review the ARM mapping if participant identifiers were accidentally mapped as arm labels. Diary figures are divided by dose and into groups of at most four symptoms so large selections remain readable.

## Analysis definitions and assumptions

- The geometric mean is `exp(mean(log(x)))` for usable positive observations. The two-sided confidence interval is `exp(mean(log(x)) ± t_quantile * sd(log(x))/sqrt(n))`, with `n-1` degrees of freedom and the selected confidence level. All intervals are pointwise; no multiplicity adjustment is applied. The interval assumes independent participants and an appropriate log-scale distribution. For `n=1`, the point estimate is available and the interval is not estimable; for `n=0`, no estimate is available.
- Paired fold rise uses each participant's `log(post) - log(baseline)`. Summarising independent baseline and follow-up populations would answer a different question. Both records must be usable under the configured censoring policy.
- BLQ handling is exclusion, half-LLOQ, or LLOQ; ALQ handling is exclusion or ULOQ. Substitution is an explicit analysis assumption and can change means and response classifications. It does not estimate censored values or propagate assay-curve uncertainty.
- Response rules are explicitly configured: threshold means `post >= response_threshold`; fold rise means `post >= baseline * fold_threshold`. For a baseline-conditional response, `baseline < baseline_threshold` uses the post-value threshold, while baseline at or above that split uses the paired fold-rise rule. Threshold-only analysis needs a usable post value; fold-rise and conditional rules need a usable pair. No protection cutoff is supplied. A missing or excluded required result does not automatically count as a nonresponse. Proportions use an evaluable participant denominator and exact Clopper–Pearson intervals; conservative coverage does not resolve bias from informative missingness.
- Diary windows include both selected endpoints. The default **complete-window** policy requires an observed grade for every configured day for the participant/dose/symptom. The optional **observed** policy requires at least one assessed day and is labelled observed-reaction incidence. Incomplete and missing coverage are reported. Missing entries are never filled with grade zero.
- Maximum grade describes recorded observations in that window. Incomplete diaries can miss a higher unobserved grade. The configured integer grade scale is `0..maximum`, with maximum chosen from 1–5; it is not a seriousness classification.
- Visit plots are descriptive. This version does not fit longitudinal, efficacy, correlate-of-protection, assay calibration or immunobridging models, and does not perform treatment-comparison hypothesis tests or batch-effect adjustment.

Review the generated assumptions, inclusion/exclusion counts, completeness, warnings and per-output QC record before interpretation. Completion of a run is an execution result, not scientific approval.

## Learning companion

`learning.html` is an optional, illustrated explanation of the established biology and the distinctions among binding, neutralization, affinity, immunogenicity and reactogenicity. It includes a one-to-one equilibrium occupancy toy, a worked paired-data example, a three-question self-check and a complete print/save-as-PDF route. All teaching numbers are synthetic.

The original *Immunity as Active Inference* teaching page was used as conceptual source material and left unchanged. The public companion is a new, corrected presentation. It keeps active inference in an explicitly optional modelling section: it does not identify a cell membrane with a Markov blanket without conditional-independence assumptions, or label titers as measured beliefs, precision or protection. No corresponding model variable enters the analysis engine.

Both public pages use the toolkit's shared color tokens, theme storage and theme controls. They load no analytics, model service or participant-data endpoint. Navigation and explanatory content work without JavaScript; interactive toy/quiz feedback requires JavaScript. The provided print feature replaces the original page's links to unavailable companion files.
