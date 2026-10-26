---
title: Naming Conventions
study: CP-101
type: reference
status: Active
owner: Statistical Programming
updated: 2026-06-25
aliases: [conventions]
tags: [reference, cp101, ops-only]
source: informational ops support — NOT a source of record
---

# Naming Conventions

Sets the file, dataset, variable, and output naming standards every CP-101 deliverable must follow.

- **Governs:** folder structure, program and log naming, TLF output IDs, and dataset/variable conventions (CDISC-aligned; USUBJID/SUBJID preserved verbatim). Defines version suffixes and the draft-vs-final marker so reviewers can tell state at a glance.
- **Owns:** the Lead Programmer maintains it; deviations require sign-off per the RACI in [[Roles & Responsibilities]].
- **Connects to:** terms used in names are defined in the [[Glossary]]; ADaM dataset and variable names must match the [[ADaM Specifications]] exactly, and this note is linked from the [[CP-101 Knowledge Hub]].

Apply consistently across SAD and MAD cohorts so outputs sort predictably and QC can be automated. When a new output type appears, register its naming pattern here before first use rather than improvising downstream.

## Related
- [[CP-101 Knowledge Hub]] — *study home*
- [[ADaM Specifications]] — *statistics & programming*
- [[Glossary]] — *people, standards & vendors*
- [[Roles & Responsibilities]] — *people, standards & vendors*
