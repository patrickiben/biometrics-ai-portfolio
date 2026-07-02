# Clinical Biostatistics × Safe‑AI in Biometrics — Portfolio

A self‑contained body of work in **early‑phase clinical‑pharmacology biostatistics** and
**human‑in‑the‑loop AI for biometrics**. Everything here runs offline from static files — open
[`index.html`](index.html) in a browser (or [`START_HERE.html`](START_HERE.html) for the full
one‑page index). All data is **100% synthetic**; there is no PHI and no participant‑level clinical data.

**Author:** Patrick Iben

---

## What's inside

**Statistical programming (SAS + R)**
- **ADaM‑based TLF pseudocode libraries** — 217 Table/Listing/Figure programs **each** in SAS and R
  (pharmaverse: `dplyr` + `rtables` + `ggplot2` + `emmeans`), across every early‑phase design
  (parallel, crossover, single/fixed‑sequence, SAD, MAD). **Cross‑validated SAS↔R for parity**;
  all R parses. Geometric PK on the log scale, distinct‑participant counts, period denominators.
  → [`sas_tlf_pseudocode/`](sas_tlf_pseudocode/index.html) · [`r_tlf_pseudocode/`](r_tlf_pseudocode/index.html)
- **Synthetic ADaM generator + study‑lifecycle sandbox** — a self‑contained R generator (one‑compartment
  oral PK + NCA, a 2×2 bioequivalence crossover, per‑period safety domains) that emits 8 ADaM domains and
  runs demographics / PK‑NCA / BE‑ANOVA end‑to‑end. → [`sim_lifecycle/`](sim_lifecycle/index.html)
- **Protocol→CSR deliverables pipeline** and a **TLF‑interpretation drafter** (a small‑model skeleton that
  never sources a number). → [`biostat_pipeline/`](biostat_pipeline/) · [`tlf_interpret/`](tlf_interpret/index.html)

**Operational tooling (no AI required)**
- **Deterministic SAS/R monitoring + on‑leave coverage** — scheduled, reproducible checks that detect,
  package, and page humans; zero PHI egress. → [`sas_r_automation/`](sas_r_automation/) · [`sasr_monitoring_wiki/`](sasr_monitoring_wiki/)
- **Self‑updating trackers & knowledge bases** — Smartsheet‑from‑SAS/R, a no‑GUI Outlook→KB pipeline, and a
  navigable knowledge‑graph vault. → [`smartsheet_sasr/`](smartsheet_sasr/) · [`study_kb_nogui/`](study_kb_nogui/index.html) · [`knowledge_vault/`](knowledge_vault/)

**Interactive dashboards** (self‑contained HTML, synthetic data)
- Participant‑safety monitoring (**TRIALMON**), trial‑risk early‑warning, and a study‑lifecycle monitor.
  → [`sasr_monitoring_wiki/TRIALMON_Dashboard.html`](sasr_monitoring_wiki/TRIALMON_Dashboard.html) · [`risk_monitor/`](risk_monitor/) · [`lifecycle_dashboard/`](lifecycle_dashboard/)

**Safe‑AI architecture** (design + methodology)
- The **hybrid** (cloud + on‑prem) and **on‑device small‑model** operating patterns, and a short training
  course. → [`hybrid_ops_wiki/`](hybrid_ops_wiki/) · [`slm_wiki/`](slm_wiki/) · [`slm_operating_wiki/`](slm_operating_wiki/) · [`courses/`](courses/Biostatistics_AI_Training.html)

---

## Principles the work is built on

- **Validated tools own every reported number** (Phoenix WinNonlin, Pinnacle 21, the EDC) — an LLM never
  produces a regulated number; AI drafts the words *around* a number, behind a human gate.
- **Operations‑only** — no PHI, no participant‑level data, no unblinded assignments in any AI/shared tool.
- **"Participant," not "subject"** in prose; CDISC variables (`USUBJID`/`SUBJID`) preserved exactly.
- **A qualified human signs every output.** AI and automation draft and check; they never decide.
- **On‑prem where sovereignty/reproducibility matter**; a pinned, frozen model for anything regulated.

---

## Notes

- **Synthetic data only.** The generator's *design structure* is informed by public early‑phase
  registration patterns on ClinicalTrials.gov; all participant‑level data is simulated from generic
  domain priors. Nothing here is real trial data.
- The AI‑built artifacts (TLF libraries, drafter, sandbox) are **skeletons and proofs‑of‑capability**
  that jump‑start a validated build — not validated production systems.
- The static site is deployable as‑is (see [`netlify.toml`](netlify.toml)); it also runs fully offline.

## License

MIT — see [`LICENSE`](LICENSE).
