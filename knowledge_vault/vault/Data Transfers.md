---
title: Data Transfers
study: CP-101
type: data
status: Active
owner: Data Management Lead
updated: 2026-06-25
aliases: [data-transfers]
tags: [data, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# Data Transfers

Governs how external data reaches CP-101's clinical database, including transfer formats, frequency, file naming, and reconciliation.

- **Scope:** Defines all inbound transfers (lab, ePRO, PK bioanalytical, randomization vendor) — transfer agreements, expected formats (SAS/CSV/CDISC-aligned), cadence, and reconciliation checkpoints against source.
- **Ownership:** Data Management owns the transfer specs and runs reconciliation; Biostatistics signs off on analysis-ready structure.
- **Connections:** Transfer specifications are documented in the [[Data Management Plan]]; laboratory-specific mechanics live in [[Lab Data Transfers]]; vendor contacts and SLAs are tracked under [[Vendors]]. All transfers must be received, reconciled, and frozen ahead of [[Database Lock]].

No transfer is considered final until reconciliation discrepancies are resolved and signed off. Re-transfers follow the same versioning and audit conventions as initial loads.

## Related
- [[Data Management Plan]] — *data management & flow*
- [[Database Lock]] — *process gate*
- [[Lab Data Transfers]] — *data management & flow*
- [[Vendors]] — *people, standards & vendors*
