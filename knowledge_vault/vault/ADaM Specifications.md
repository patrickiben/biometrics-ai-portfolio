---
title: ADaM Specifications
study: CP-101
type: stats
status: Draft
owner: Statistical Programming
updated: 2026-06-25
aliases: [adam]
tags: [stats, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# ADaM Specifications

Analysis dataset specifications for CP-101 — the ADaM-level metadata defining derived variables, parameters, and traceability from collected data to analysis-ready structures.

- **Governs:** dataset shells (ADSL and the relevant BDS/OCCDS domains), derivation logic, parameter and flag definitions, and value-level metadata. It specifies structure and derivations, not data values.
- **Owner:** statistical programming with biostatistics review; currently **Draft**, tracking SAP maturity.
- **Connections:** derivations implement the methods in the [[Statistical Analysis Plan]] and supply the inputs each shell in [[TLF Shells]] expects. Source variables map back to the collection structures in the [[EDC Build]], and all dataset/variable names follow the [[Naming Conventions]] standard.

Finalize ahead of the dry-run so programming and validation work from a stable spec; any EDC or SAP change is reconciled here before specs are locked.

## Related
- [[EDC Build]] — *data management & flow*
- [[Naming Conventions]] — *people, standards & vendors*
- [[Statistical Analysis Plan]] — *statistics & programming*
- [[TLF Shells]] — *statistics & programming*
