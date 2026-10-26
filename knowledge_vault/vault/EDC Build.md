---
title: EDC Build
study: CP-101
type: data
status: Active
owner: Data Management Lead
updated: 2026-06-25
aliases: [edc-build]
tags: [data, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# EDC Build

Tracks configuration of the CP-101 EDC system from approved specs through go-live and migration control.

- **Scope:** Builds screens, forms, and visit structure to match the [[eCRF Specification]], implements dynamics and derivations, and enforces conventions set in the [[Data Management Plan]]. Includes role-based access, audit trail, and a documented UAT cycle before production release.
- **Owner:** EDC Build lead / Clinical Programming, with DM and Biostat reviewers signing UAT.
- **Connections:** Hosts the validation logic described in [[Edit Checks]]; field names, formats, and code lists are aligned to support downstream [[ADaM Specifications]] so analysis datasets map cleanly to collected variables.

Post-go-live changes are version-controlled and migrated under change control with re-test evidence. This note records build status, UAT milestones, and ownership only — no captured data or results.

## Related
- [[ADaM Specifications]] — *statistics & programming*
- [[Data Management Plan]] — *data management & flow*
- [[Edit Checks]] — *data management & flow*
- [[eCRF Specification]] — *study design & data collection*
