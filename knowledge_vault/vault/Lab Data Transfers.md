---
title: Lab Data Transfers
study: CP-101
type: data
status: Active
owner: Data Management Lead
updated: 2026-06-25
aliases: [lab-transfers]
tags: [data, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# Lab Data Transfers

Governs the operational handling of central laboratory data transfers into CP-101 (safety chemistry/hematology, urinalysis, and PK bioanalytical results).

- **Scope:** Covers transfer file layouts, units/LOINC conventions, expected visits, flag handling (normal ranges, reanalysis), and reconciliation of sample accountability against the schedule.
- **Ownership:** Data Management coordinates receipt and reconciliation; the [[Central Lab]] is responsible for transfer content, units, and re-issues.
- **Connections:** This is a specialization of [[Data Transfers]]. PK aliquot collection times and nominal sampling windows must align with the [[PK Sampling Plan]] so bioanalytical results map cleanly to nominal timepoints.

Sample-level discrepancies (missing draws, unscheduled samples) are queried back to the site and lab before any partial freeze. Transfer cadence steps up near key visits and ahead of lock.

## Related
- [[Central Lab]] — *people, standards & vendors*
- [[Data Transfers]] — *data management & flow*
- [[PK Sampling Plan]] — *study design & data collection*
