# Fictional vaccine example data

These CSV files are synthetic test data. They contain no participants from a real study and do not specify recommended clinical thresholds or an approved analysis plan.

Use **Download template** to start with headers only, or **Use synthetic example** to add a fictional CSV through the same validation and mapping flow as an upload. Example buttons do not change the study settings. Enter the settings below explicitly, or download [the example setup profile](example_profile.json) and deliberately import it through the guided setup's profile controls. The profile contains no CSV data and leaves all review confirmations unchecked.

| Setting | Example value |
| --- | --- |
| Study identifier | VAX-DEMO |
| Assay / antigen / unit | Assay-A / Antigen-A / AU/mL |
| Baseline visit | Baseline |
| Follow-up visits | Day 28 and Day 56, on separate lines |
| Confidence level | 0.95 |
| Below-limit handling | Half the lower limit |
| Above-limit handling | Upper limit |
| Response rule | Conditional |
| Response threshold / fold threshold / baseline threshold | 40 / 4 / 10 |
| Dose labels | Dose 1 and Dose 2, on separate lines |
| Symptoms | Pain and Fatigue, on separate lines |
| Diary days / maximum grade | 0 through 6 / 3 |
| Reactogenicity denominator | Complete diary |

The settings in [example_settings.json](example_settings.json) are also used by automated QC. Their values are chosen to exercise software branches, including censoring and missingness; they are not claims about vaccine protection or a grading scale for use in a study.

The files contain:

- **participants.csv:** 12 fictional participants, six per arm. VAX006 is excluded from the immunogenicity population; VAX012 is excluded from the safety population.
- **titers.csv:** 36 records across Baseline, Day 28 and Day 56. VAX003 and VAX010 have below-limit records; VAX004 has an above-limit record; VAX005 and VAX011 have missing records. Limits accompany records so alternative censoring rules can be inspected.
- **doses.csv:** 23 administered doses. VAX006 received Dose 1 only. Expected diaries are based on this roster, not a presumed two-dose schedule for every participant.
- **diary.csv:** 314 symptom-day records, including observed zero grades. The Comparator arm has no observed reactions. VAX010 has only days 0–2 for Dose 2; VAX011 has an all-missing Dose 1 diary; VAX008 has one missing Fatigue grade on Dose 1 day 6. Blank grades and absent rows are missing observations, not zeroes.

All `*_template.csv` files contain headers only. Preserve participant identifiers consistently across the input files. Replace the example settings and data with the definitions and inputs intended for the study, then review the preview, exclusions and QC before using any results.
