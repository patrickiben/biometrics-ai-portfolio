---
title: Edit Checks
study: CP-101
type: data
status: Active
owner: Data Management Lead
updated: 2026-06-25
aliases: [edit-checks]
tags: [data, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# Edit Checks

Specifies the automated and manual data-validation rules applied in the CP-101 EDC to flag discrepancies at or near entry.

- **Scope:** Catalogs programmed checks (range, consistency, missing-required, cross-form) plus manual/listing-based reviews, with severity, query text, and firing conditions. Logic is implemented within the [[EDC Build]] and tested during UAT.
- **Owner:** Data Management defines and maintains the check library; Clinical Programming implements; Biostat reviews safety-relevant checks.
- **Connections:** Conventions and coding requirements trace to the [[Data Management Plan]]; check changes follow the same change-control and re-test path as the build.

This note governs the check inventory and its rationale, not query outcomes or participant data. Updates are versioned alongside spec amendments so the active rule set always matches the production database.

## Related
- [[Data Management Plan]] — *data management & flow*
- [[EDC Build]] — *data management & flow*
