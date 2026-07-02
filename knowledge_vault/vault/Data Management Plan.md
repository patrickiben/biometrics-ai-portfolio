---
title: Data Management Plan
study: CP-101
type: data
status: Active
owner: Data Management Lead
updated: 2026-06-25
aliases: [dmp]
tags: [data, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# Data Management Plan

Governs how CP-101 clinical data are captured, cleaned, transferred, and locked across the study lifecycle.

- **Scope:** Defines data-handling conventions, query management, coding dictionaries (MedDRA/WHODrug), self-evident corrections, and roles/responsibilities for the SAD/MAD database. Sits under the [[CP-101 Knowledge Hub]] as the controlling data document.
- **Owner:** Lead Data Manager, with Biostatistics sign-off; reviewed each amendment.
- **Connections:** Sets requirements that flow into the [[eCRF Specification]] and the [[EDC Build]], frames external feeds in [[Data Transfers]], and lays out entry/exit criteria for [[Database Lock]]. Edit-check logic and reconciliation expectations are referenced here and detailed downstream.

The DMP is the single source of truth for data process; any change to collection or cleaning conventions is reflected here first, then cascaded to dependent specs. No participant-level data or results live in this note — methods and ownership only.

## Related
- [[CP-101 Knowledge Hub]] — *study home*
- [[Data Transfers]] — *data management & flow*
- [[Database Lock]] — *process gate*
- [[EDC Build]] — *data management & flow*
- [[eCRF Specification]] — *study design & data collection*
