# Early-phase biostatistics deliverables pipeline

Every statistics deliverable of an early-phase clinical-pharmacology study, from protocol development to the clinical
study report, results posting and archiving. Each deliverable lists its owner and contributors, what it needs, what it
feeds, the milestones in which it is produced, the standard that governs it, how it is checked and the mistakes that
cost time later. Design modules cover single and multiple ascending dose escalation, bioequivalence (ICH M13A), relative
bioavailability, food effect, drug interactions (ICH M12), QT and concentration-QTc, and renal and hepatic impairment.

**Open it:** [interactive explorer](index.html) (map, trace a change, list by stage, standards) ·
[handbook](EarlyPhase_Biostat_Pipeline.pdf) (PDF) · [poster map](EarlyPhase_Biostat_Pipeline_Map.pdf) (36 x 24 in PDF) ·
[Excel register](EarlyPhase_Biostat_Pipeline_Register.xlsx) · [register workspace](../browser_modules/register/index.html)
(plan your own study in the browser) · [data](pipeline.json).

This is a planning reference, not a record of client work or an SOP. Adapt it to the study's protocol, the client's SOPs
and the regulations that apply. The worked bioequivalence study it links to uses synthetic data.

## Sources

`pipeline.json` is the single source. Its `refs` list names each standard with its issuer, identifier, version, date,
status and URL; `refs_checked_on` records when every entry was checked against its primary source. CDISC implementation
guide texts need a CDISC account and were not opened, so their section numbers are not verified. Check the current
version of any standard before relying on it.

## Rebuild

```bash
python3 biostat_pipeline/build_v2.py          # validate pipeline.json, then write the derived files
python3 biostat_pipeline/build_v2.py --pdf    # also print the handbook and poster PDFs (needs Google Chrome)
python3 biostat_pipeline/build_v2.py --check  # fail if a derived text file is out of date
```

The validator checks the field values against the lists in `pipeline.json`, that every dependency exists and the graph
has no cycles, that every cited standard is in the reference list, that every toolkit link points to a file in the
repository, and the writing rules (American spelling, "participant", no em dashes).

Derived files: `pipeline_data.js` (explorer data), `_register.json` (starter rows for the register workspace), the
facts line in `index.html`, `EarlyPhase_Biostat_Pipeline_Register.xlsx` (built by `make_xlsx.js`, needs node and zip)
and, with `--pdf`, the two PDFs (from print sources written to a temporary folder by `build_print.py`).
