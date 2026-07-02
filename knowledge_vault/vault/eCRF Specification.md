---
title: eCRF Specification
study: CP-101
type: design
status: Final
owner: Data Management Lead
updated: 2026-06-25
aliases: [ecrf]
tags: [design, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# eCRF Specification

Field-level specification for CP-101 electronic data capture: forms, variables, controlled terminology, and edit-check intent.

- **Governs:** form layout, variable definitions, codelists, and visit-form mapping; it is the contract between protocol-required data and what the EDC actually collects.
- **Owner:** Data Management, with Biostatistics reviewing for analysis-readiness and CDISC alignment.
- It traces to the [[Protocol]] for required data and mirrors the [[Schedule of Assessments]] for visit-form assignment.
- Conventions and handling rules live in the [[Data Management Plan]]; the build and validation of these forms in the system are executed per the [[EDC Build]]. Spec changes are version-controlled and cross-checked against the build before release.

## Related
- [[Data Management Plan]] — *data management & flow*
- [[EDC Build]] — *data management & flow*
- [[Protocol]] — *study design & data collection*
- [[Schedule of Assessments]] — *study design & data collection*
