# eCRF review tools: guided browser use

Start at the [eCRF workspace](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/) inside the [Trial Biostatistics Toolkit](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html). Choose a tool, upload CSVs and complete its forms. No code editing, command-line steps or local installation is needed for the browser workflow.

## 1. Start and save a workspace

Every tool starts blank. **Load synthetic example** deliberately loads fictional data; it is an optional way to learn the controls. Upload your study files to use your own data. **Reset workspace** clears the session. Closing or reloading the tab clears its files and results, so download the complete review package first.

Use UTF-8 CSV files with unique nonblank headers and the same number of fields in every row. Keep leading zeros in identifiers. The forms report file/row limits; they reject malformed CSV, invalid encoding, path-like filenames, ambiguous duplicate headers and unsupported numeric values. Map your actual column names rather than renaming source data or editing Python. Changing inputs or settings clears old results and downloads.

Light/dark mode uses the toolkit's shared preference. App software is downloaded on first use; study files are processed inside the browser tab. The tools do not submit those files to a server. Outputs are local downloads under your control.

## 2. Choose the tool

| Need | Open | Required input |
|---|---|---|
| Candidate terminology for reported events | [Coding QC assist](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/meddra.html) | Study CSVs plus your dictionary CSV |
| Review/redact identifiers in selected fields | [De-identification review assist](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/phi.html) | Study CSVs; no dictionary |
| Participant screening from safety domains | [Participant risk screening](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/risk.html) | One study's AE/lab/ECG/vitals/physical-exam CSVs, as available |
| Numeric outliers and bounded distribution comparisons | [Anomaly and drift screening](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/app/anomaly.html) | One wide CSV with participant IDs and complete selected measurements |

These tools support review. They do not replace study-specific programming, medical coding, privacy review or clinical judgment.

## 3. Coding QC assist

1. Use **Upload study CSV files** and **Upload dictionary CSV**. Your data must use your supplied dictionary; the example dictionary is never a fallback. Supply terminology you are entitled to use. No licensed MedDRA dictionary is included.
2. For each study file, choose its **Verbatim column** and optional study, participant and event identifiers. Arbitrary column names are supported. Source filename and row number always qualify the output, including repeated identifiers.
3. Map **Dictionary term** and **Preferred-term name**. Optional mappings carry term/PT codes, high-level terms, high-level groups and system organ class. If the dictionary has an active/currency column, map it and state its active values. Conflicting mappings for a code are rejected. Codes are retained as strings.
4. Record a dictionary name/version if available. Set the **Review-score threshold**. This only highlights candidate scores; it never approves a code.
5. Click **Run coding suggestions**. Review the proposed terms, source rows, lexical cosine and weighted review score.
6. Download the candidates CSV, audit or **complete coding package**. The ZIP also contains lossless JSON, mapped dictionary and selected input fields for review. Unmapped study columns are excluded.

Every output row is `UNREVIEWED_CANDIDATE`, even an exact match. Lexical matching can miss semantic equivalents and cannot resolve negation or clinical context. A review score is not a probability. No SDTM write-back or clinical approval occurs. Blank verbatims are skipped and counted through the selected input/run audit. The browser batch permits up to 10,000 nonblank rows and 1,000 distinct verbatims, with a dictionary of up to 100,000 rows within the file limit.

## 4. De-identification review assist

1. Upload your study CSVs. In **Fields to scan**, choose the fields to review. All fields are selectable, including numeric-looking identifiers; a numeric appearance does not make an identifier safe.
2. Choose **Fields to include in redacted export** from those scanned fields. Only those selected fields are exported in the redacted tables. No original column is appended beside its replacement.
3. Select the identifier pattern categories to apply. Add literal names/identifiers the patterns may miss under **Additional literal terms to redact (one per line)**. These are case-insensitive literal matches, not regular expressions.
4. Choose the **Redaction gate**, then **Run de-identification review**. The gate applies to the existing rule scores, which are not calibrated probabilities. User-entered literal terms are masked directly.
5. Review the redacted field copies and download individual CSVs or **Download redacted package**. That package excludes originals, matched span text and your custom literal terms; it includes the effective categories, settings, counts and hashes in the audit.
6. If needed, expand **Sensitive review details** and deliberately download the separate sensitive-review package. It contains original selected fields, matched identifier spans and your literal terms. Handle it as sensitive data, separately from the redacted package.

Redaction is incomplete by design: patterns can miss identifiers or mask text unnecessarily, and remaining headers/values can still identify a person. A field with no flag is not certified identifier-free. Review results before disclosure or downstream use. The tool does not certify HIPAA Safe Harbor, complete anonymization or compliance with an organization's privacy policy.

## 5. Participant risk screening

1. Upload one study's safety CSVs. Choose each file's safety domain and map the required fields. Files with similar names remain distinct; the app does not silently overwrite one domain with another.
2. Map the participant and optional study identifier. Resolve mixed studies before screening. Map your category values explicitly—for example severity, seriousness, relationship and actual fatal outcome. A life-threatening event is not automatically a death.
3. Confirm units. Lab results and ULN must use compatible units; QTc uses milliseconds, blood pressure mmHg and temperature °C. If a unit column is supplied, verify its expected value.
4. Review analyte-specific ULN multiples and **Screening thresholds and category cuts**. Defaults are illustrative starting values, not a client protocol or SAP. Rule weights remain the documented source coefficients.
5. Confirm the mapping/units/criteria/scope checkbox and click **Run screening**. Review scores alongside contributing signals and input coverage.
6. Download the **complete review package** to retain tables, normalized inputs, effective settings and audit.

Safety and discontinuation scores are capped weighted screening indices, not probabilities or trained predictions. The tool supports declared high-threshold lab/QTc/BP/temperature checks; it does not infer all clinically relevant low/high abnormalities. Missing domains are not assessed. Repeated observations contribute under the canonical caps. QTc uses each participant's maximum. Review coverage and criteria before interpreting the ordering.

## 6. Anomaly and drift screening

1. Upload one wide CSV for one study. Map participant ID, optional study ID, optional visit/time and optional lab/site. Choose numeric measurement fields and any text fields.
2. State the units of each numeric measurement, or explicitly use `unitless`. Resolve missing/nonfinite measurements before running; they are not silently treated as normal values.
3. For a paired comparison, choose numeric time or ISO dates and explicitly select **Reference visit** and **Current visit**. Current must follow reference. Each participant needs exactly one complete row at both chosen visits and a constant lab/site assignment. Without a time field, use one row per participant.
4. Review screening thresholds and category cuts. Between-lab comparisons require at least three eligible participants per included lab. The app reports its input coverage rather than quietly extrapolating to unsupported comparisons.
5. Confirm the review checkbox, **Run screening**, review all tables, then download the complete package.

Numeric outliers use median/MAD robust z scores. Browser drift uses the existing 200-point quantile-grid approximation, scaled by 1.349 × the reference IQR with documented SD/1 fallbacks. It is not an exact optimal-transport calculation or a standardized-SD effect size. Text isolation uses bag-of-words features. These bounded screens do not replace a longitudinal model or estimate clinical accuracy.

## 7. Read exports and retained evidence

CSV exports escape text that could otherwise execute as spreadsheet formulas. Coding JSON and the PHI sensitive-review JSON preserve their selected original strings. Audit files record the mappings, effective thresholds, algorithm and input hashes; they are ordinary CSV/JSON records, not protected audit trails or electronic signatures.

The [historical evaluation](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/evaluation.html) and [worked examples](https://patrickiben.github.io/biometrics-ai-portfolio/ecrf_pipeline/docs/case-study.html) preserve the original synthetic/native measurements. Their automatic-commit and original-plus-sanitized columns describe that earlier/native output contract. They do not validate this browser flow for a client's study, dictionary or settings. The original native QC and evaluation remain available under `tests/` and `eval/`.

## 8. Optional native operation

Use local operation only if you need filesystem folders, SAS `.sas7bdat`, licensed `.asc` dictionary releases or the optional learned models. From `ecrf_pipeline/`, macOS users may double-click the appropriate `Launch … .command`; Windows users may use its `.bat`. The launcher installs a local Python environment and opens Streamlit. The `.sh` launchers and `requirements.txt` are also available for technical users.

In the native UI, set a cut folder or use file upload, choose the output folder and confirm the pre-flight fields before Execute. Coding accepts a flattened dictionary CSV or a licensed ASCII release; optional model setup is in [eval/README.md](eval/README.md). The native output contract is preserved: coding may report `AUTO_COMMIT_TO_SDTM` under its historical gate, while PHI exports may contain original fields beside `SAN_<field>` and matched identifiers in `phi_flags.csv`. Those files need appropriate human review and sensitive-data handling.

A public Streamlit **server demo** can use `ECRF_HOSTED=1`. It locks inputs to synthetic examples and remains fail-closed. This server policy is separate from browser execution: `ECRF_BROWSER=1` alone does not enable own-data browser mode on an ordinary server. Server operators also need an upload-size limit because Streamlit can receive crafted upload requests even when the displayed uploader is disabled. No server setup is required to use the integrated browser workspace.

Apache-2.0 applies to this module; retain [LICENSE](LICENSE) and [NOTICE](NOTICE). No licensed MedDRA dictionary is distributed.
