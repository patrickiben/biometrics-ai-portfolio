---
title: Database Lock
study: CP-101
type: ops
status: Planned
owner: Project Manager
updated: 2026-06-25
aliases: [db-lock]
tags: [ops, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# Database Lock

Defines the readiness criteria and sequencing for CP-101 database lock(s), including any SAD/MAD interim locks ahead of the final lock.

- **Scope:** Lock checklist — all data entered, queries closed, [[Data Transfers]] received and reconciled, coding complete, and protocol deviations adjudicated (analysis-environment readiness is tracked separately, on the reporting side). Defines who signs the lock memo and freeze conventions.
- **Ownership:** Data Management drives the lock; Biostatistics confirms analysis-readiness and that [[TLF Shells]] are finalized against the locked structure before the final unblinded analysis.
- **Connections:** Lock criteria and the query-resolution standard derive from the [[Data Management Plan]]. Target lock dates are tracked on [[Milestones]]; status rolls up to the [[CP-101 Knowledge Hub]].

No TLF production runs against pre-lock data except dry-run shell checks. A documented lock memo gates the move to the final unblinded analysis. Interim safety/DSMB reviews during dose escalation are handled separately by the unblinded firewall (see [[Randomization & Blinding]]) and are independent of these locks.

## Related
- [[CP-101 Knowledge Hub]] — *study home*
- [[Data Management Plan]] — *data management & flow*
- [[Data Transfers]] — *data management & flow*
- [[Milestones]] — *deliverables & timeline*
- [[TLF Shells]] — *statistics & programming*
