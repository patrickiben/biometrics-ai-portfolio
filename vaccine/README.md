# Vaccine study analysis

[Run vaccine analyses in your browser](../apps/vaccine/) · [Module guide](index.html) · [Learning companion](learning.html) · [Reference ledger](REFERENCES.md)

Open the [browser application](../apps/vaccine/) to configure and run all six descriptive analyses from mapped, analysis-ready CSVs. No installation, account, toolkit download, command-line steps or code edits are required. R runs inside the browser and uses the same numerical core as the optional desktop toolkit. The initial application and runtime assets need to load before analysis begins.

The workspace starts without a client, study or selected outputs. Uploaded study files are processed in the browser session and are not sent to an analysis server. **Reset all** clears the loaded inputs and results; closing or reloading the app clears the session. Download any results you want to retain before leaving.

R is the execution engine. Configured native SAS exports remain unexecuted reference code and have not been reconciled against R. Successful execution does not provide scientific review or study approval.

## Use your study data

1. Enter a study identifier and select the outputs to compute. Define your population-flag values and confidence level.
2. Upload the required UTF-8 CSV files and review each source-column mapping. Blank templates can be downloaded from the Inputs tab; source headers do not need to match the canonical names.
3. Supply the assay, visit, quantification-limit and response definitions required by your selected outputs. For reaction analyses, specify the actual dose labels, symptoms, inclusive diary window, protocol grade scale and denominator policy.
4. Review the displayed configuration and manually confirm the applicable study definitions. Click **Validate this configuration**, resolve any reported issues, then **Run selected analyses**.
5. Explore the tables and figures, review missingness and assumptions, and download the results.

Changing study settings, confirmations, mappings or uploaded inputs invalidates earlier validation and results. Review and validate the current configuration before running again; old result downloads are removed. A loaded synthetic example also requires manual confirmations.

## Try the synthetic example

Click **Load synthetic example** in the browser application. This deliberately loads the fictional settings and all four example feeds, restores their canonical mappings, and leaves the review confirmations unchecked. Review the assay, thresholds, schedule and denominator policy, confirm the applicable definitions, validate and run.

You can inspect the [participants](examples/participants.csv), [assay results](examples/titers.csv), [administered doses](examples/doses.csv) and [diary](examples/diary.csv) files directly. The example includes censored observations and incomplete diaries. Its numerical thresholds are teaching values, not protection cutoffs or recommendations for a study. The [synthetic settings profile](examples/example_profile.json) is also available for the optional desktop workflow.

## Keep the complete result set

Use **Complete review package (.zip)**, extract the ZIP, then open `analysis_report.html`. The report index links to every output, complete paginated tables, and figure files. Downloading the index alone does not include its linked results.

The package includes complete table CSVs and RDS objects, figure PNGs and PDFs, input/population audits, settings and mappings, the configured SAS reference, software versions, source files, a file inventory and an R reproduction script. Individual files, the report index, setup profile and SAS reference can also be downloaded from the Results tab. Downloading a profile records settings; it does not preserve uploaded study data or restore an entire browser session.

Result CSVs protect formula-like text with an apostrophe; RDS objects preserve original values. Input CSVs are retained as data for reproduction and may contain the original text. The file inventory detects accidental changes and is not a signature or scientific validation. The exported R reproduction route is optional; the browser analysis itself requires no installed R.

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

| Limit | Browser application | Optional desktop toolkit |
| --- | --- | --- |
| Each uploaded CSV | 16 MiB; 200,000 records | 16 MiB; 100,000 records |
| Each expected participant/visit or diary grid | 250,000 assessments | 1,000,000 assessments |
| Diary-profile figures per run | 32 pages | No separate 32-page browser limit |
| Result download | 50 MiB of encoded payload per file or complete package, approximately 37.5 MiB of raw files | Local result package |

Both routes support up to 50 distinct arm labels, 50 follow-up visits, 50 dose labels and 50 symptoms. The expected grids include missing assessments, so they can be larger than the uploaded files. Diary figures use one dose per figure and at most four symptoms per page. The browser checks its limits before execution or download; available memory can also depend on the browser and device.

If a selected grid or figure set is too large, select fewer follow-up visits, doses or symptoms per run while retaining the full eligible population and prespecified assessment window. Do not remove participants or shorten the scientific window merely to fit a capacity limit. The optional desktop route can support larger expected grids when its separate CSV limits are satisfied. Review the ARM mapping if participant identifiers were accidentally mapped as arm labels.

If the complete browser package exceeds the encoded download limit, computed estimates are unchanged and individual-file downloads remain available within that limit. Keep all required companion files together to retain the linked reports and reproduction materials.

## Optional desktop route

The existing [point-and-click toolkit setup](../TOOLKIT_SETUP.html) remains available. Download the toolkit, create a private project, open the vaccine module, select and map inputs, configure assumptions, preview, generate a revision and run its R analysis through the local control panel. This route requires R on the computer; the toolkit provides checks, installation guidance and package-install controls. No command-line steps or code edits are required for that supported workflow. It uses the same analysis definitions below and retains the unexecuted SAS-reference qualification.

## Analysis definitions and assumptions

- The geometric mean is `exp(mean(log(x)))` for usable positive observations. The two-sided confidence interval is `exp(mean(log(x)) ± t_quantile * sd(log(x))/sqrt(n))`, with `n-1` degrees of freedom and the selected confidence level. All intervals are pointwise; no multiplicity adjustment is applied. The interval assumes independent participants and an appropriate log-scale distribution. For `n=1`, the point estimate is available and the interval is not estimable; for `n=0`, no estimate is available.
- Paired fold rise uses each participant's `log(post) - log(baseline)`. Summarising independent baseline and follow-up populations would answer a different question. Both records must be usable under the configured censoring policy.
- BLQ handling is exclusion, half-LLOQ, or LLOQ; ALQ handling is exclusion or ULOQ. Substitution is an explicit analysis assumption and can change means and response classifications. It does not estimate censored values or propagate assay-curve uncertainty.
- Response rules are explicitly configured: threshold means `post >= response_threshold`; fold rise means `post >= baseline * fold_threshold`. For a baseline-conditional response, `baseline < baseline_threshold` uses the post-value threshold, while baseline at or above that split uses the paired fold-rise rule. Threshold-only analysis needs a usable post value; fold-rise and conditional rules need a usable pair. No protection cutoff is supplied. A missing or excluded required result does not automatically count as a nonresponse. Proportions use an evaluable participant denominator and exact Clopper–Pearson intervals; conservative coverage does not resolve bias from informative missingness.
- Diary windows include both selected endpoints. The **complete-window** policy requires an observed grade for every configured day for the participant/dose/symptom. The **observed** policy requires at least one assessed day and is labelled observed-reaction incidence. The browser requires a deliberate policy selection; complete-window is the desktop form's default. Incomplete and missing coverage are reported. Missing entries are never filled with grade zero.
- Maximum grade describes recorded observations in that window. Incomplete diaries can miss a higher unobserved grade. The configured integer grade scale is `0..maximum`, with maximum chosen from 1–5; it is not a seriousness classification.
- Visit plots are descriptive. This version does not fit longitudinal, efficacy, correlate-of-protection, assay calibration or immunobridging models, and does not perform treatment-comparison hypothesis tests or batch-effect adjustment.

Review the generated assumptions, inclusion/exclusion counts, completeness, warnings and per-output QC record before interpretation. Completion of a run is an execution result, not scientific approval.

## Learning companion

`learning.html` is an optional, illustrated explanation of the established biology and the distinctions among binding, neutralization, affinity, immunogenicity and reactogenicity. It includes a one-to-one equilibrium occupancy toy, a worked paired-data example, a three-question self-check and a complete print/save-as-PDF route. All teaching numbers are synthetic.

The original *Immunity as Active Inference* teaching page was used as conceptual source material and left unchanged. The public companion is a new, corrected presentation. It keeps active inference in an explicitly optional modelling section: it does not identify a cell membrane with a Markov blanket without conditional-independence assumptions, or label titers as measured beliefs, precision or protection. No corresponding model variable enters the analysis engine.

Both public pages use the toolkit's shared color tokens, theme storage and theme controls. They load no analytics, model service or participant-data endpoint. Navigation and explanatory content work without JavaScript; interactive toy/quiz feedback requires JavaScript. The provided print feature replaces the original page's links to unavailable companion files.
