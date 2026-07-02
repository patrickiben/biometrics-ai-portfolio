---
title: PK Sampling Plan
study: CP-101
type: design
status: Final
owner: Clinical Pharmacology Lead
updated: 2026-06-25
aliases: [pk-sampling]
tags: [design, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# PK Sampling Plan

Defines the PK blood-sampling strategy for CP-101 across the SAD and MAD cohorts, including nominal timepoints, window tolerances, and handling of deviations.

- **Governs:** nominal sampling times relative to dose, allowable collection windows, sparse vs. rich profiling by cohort, and conventions for actual-vs-nominal time capture. It does not report concentrations or PK parameters.
- **Owner:** PK scientist with biostatistics sign-off; aligned to the dosing and assessment windows in the [[Schedule of Assessments]].
- **Connections:** the analysis populations, derivations, and NCA conventions that consume these samples are specified in the [[Statistical Analysis Plan]]; concentration data arrive via the vendor feed described in [[Lab Data Transfers]], so any window or timepoint change here must be reconciled with both before lock.

Keep this note synchronized whenever the protocol amends dosing or visit timing; deviations are tracked operationally and adjudicated case-by-case ahead of database lock.

## Related
- [[Lab Data Transfers]] — *data management & flow*
- [[Schedule of Assessments]] — *study design & data collection*
- [[Statistical Analysis Plan]] — *statistics & programming*
