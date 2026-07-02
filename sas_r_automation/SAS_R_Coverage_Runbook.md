# Monitoring Coverage Runbook — Study CP-101

**Purpose.** Keep trial monitoring running and self-escalating while the lead biostatistician is on leave. This one page tells the covering colleague (the *support*) and the manager exactly what arrives, what it means, and who does what. It is handed over before departure and committed to version control.

> **The one honest rule.** Every email below reports that a **number crossed a pre-specified line**. That is a *prompt to look* — **not** a clinical interpretation. The covering biostatistician, the medical monitor, and the DSMB/SRC make every judgement. The system only **detects, pages, and packages**.

## What runs, and when (all under service account `SVC-BIOSTAT`, not a personal login)

| Job | When | Output |
|---|---|---|
| Data refresh + **freshness gate** + integrity | 02:00 daily | confirms every feed updated; raises a flag if a source went stale |
| Safety scan | 06:00 daily | AE/SAE · Hy's-Law/eDISH · QTcF · labs · cohort DLT tally |
| **Routine digest → support** | 07:00 daily | GREEN/AMBER summary + **heartbeat** |
| Weekly status pack → support · one-pager → manager | Fri 16:00 | enrollment, escalation status, disposition |
| **Threshold ALERT** | on event | KRI/QTL/DLT/SAE → urgent email + escalation |

## What the colours mean — and who does what

- 🟢 **GREEN** — all checks within limits. **No action.** (The heartbeat still confirms the run happened on fresh data.)
- 🟡 **AMBER** — an operational / quality KRI crossed (e.g. enrollment below plan, query backlog, a deviation trend). **Support reviews and acts** (e.g. raise a site action with the PM). Stays in the routine channel; the manager's Friday one-pager shows *flagged → being handled*.
- 🔴 **RED** — a safety threshold (DLT-defining grade, SAE, Hy's-Law lab pattern, QTcF crossing, stopping-rule count). **Support acknowledges within 30 minutes, then CONTACTS THE MEDICAL MONITOR.** The evidence packet is attached; do not wait to assemble data.

## Escalation matrix

| Role | Name / contact | When |
|---|---|---|
| Support (primary) | *[covering biostatistician]* | all emails; acts on AMBER; acknowledges RED ≤30 min |
| Support (backup) | *[second biostatistician / PM]* | if primary doesn't acknowledge a RED within the SLA |
| Role alias | `biostat-cover@…` | every RED also lands here, so it never depends on one inbox |
| Medical monitor | *Dr. R. Okafor, +1-…* | called by support on any RED (safety adjudication) |
| Project manager | *[PM]* | cc on AMBER/RED; owns operational actions |
| Lead (on leave) | *[contact only for true emergencies]* | reachable per the agreed emergency protocol only |

## If you receive **no** email (the dead-man's switch)

"No news" is **never** "all clear." A successful run always sends *something* — at minimum a GREEN digest with a heartbeat. **If the 07:00 digest does not arrive by 09:00**, the independent watcher should already have paged; if it hasn't, treat the monitoring system as **down** and notify IT/the backup immediately. A silent system is a RED condition.

## Reportable vs signal-only

Everything in these emails is **signal-only** (single-program, human-confirmed) — it surfaces validated outputs early. Anything that will be **formally reported** (an SRC/DSMB pack, a sponsor deliverable, a submission figure) is still **independently double-programmed and QC'd** exactly as normal before it goes out. The monitor never relaxes that standard.

*Deterministic SAS/R, inside the validated environment. No AI, no new vendor, no PHI in email bodies. Companion to the SAS/R Trial-Monitoring Automation wiki.*
