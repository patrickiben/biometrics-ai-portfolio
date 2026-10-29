window.TOOLKIT_CATALOG = {
  "schema": 1,
  "updated": "2026-10-28",
  "title": "Trial biostatistics toolkit",
  "project_label": "Create private project from examples",
  "description": "One private copy includes all local modules and their fictional starter data. The external eCRF apps remain a separate repository.",
  "modules": [
    {
      "id": "open-tracker",
      "title": "Open Study Tracker",
      "summary": "Track deliverables, stable IDs, owners, dates, status and change history. Choose an offline workspace or the guided shared tracker.",
      "category": "Operations",
      "kind": "browser",
      "runtime": "Browser; Python 3.10+ for shared setup",
      "docs": [
        {
          "label": "Open offline workspace",
          "path": "open_tracker/index.html"
        },
        {
          "label": "Shared setup guide",
          "path": "open_tracker/SETUP.html"
        },
        {
          "label": "File workflow",
          "path": "open_tracker/README.md"
        },
        {
          "label": "Example status import",
          "path": "open_tracker/examples/status.csv"
        }
      ],
      "workspace_paths": [
        "open_tracker"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "tracker.offline",
          "label": "Open offline tracker",
          "type": "open",
          "path": "open_tracker/index.html"
        },
        {
          "id": "tracker.setup",
          "label": "Start shared-tracker setup",
          "type": "tracker"
        }
      ],
      "outputs": [],
      "persistence": "Offline edits stay in this browser until exported as JSON/CSV. Shared mode stores its database and settings outside the toolkit workspace ZIP; preserve them through the tracker’s separate backup controls.",
      "customization": "Create your own task records in the browser. For shared use, the existing wizard configures accounts, access and optional email.",
      "limits": "Operational records only. Offline imports use the last supplied values; shared editing checks row versions. SMTP delivery and shared hosting need your own settings."
    },
    {
      "id": "continuity",
      "title": "Continuity and handoff workspace",
      "summary": "Turn recurring jobs, owners, backups and runbooks into coverage risks and a handoff packet.",
      "category": "Operations",
      "kind": "browser",
      "runtime": "Browser only",
      "docs": [
        {
          "label": "Open workspace",
          "path": "sasr_onleave_wiki/Continuity_Toolkit.html"
        },
        {
          "label": "CSV template",
          "path": "sasr_onleave_wiki/continuity_jobs_template.csv"
        }
      ],
      "workspace_paths": [
        "sasr_onleave_wiki"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "continuity.open",
          "label": "Open continuity workspace",
          "type": "open",
          "path": "sasr_onleave_wiki/Continuity_Toolkit.html"
        }
      ],
      "outputs": [],
      "persistence": "Uses browser localStorage. Export JSON or CSV before changing browser, machine or project; browser storage is not a project backup.",
      "customization": "Enter or import your job inventory, choose the coverage scenario, and print or download the handoff packet.",
      "limits": "The page makes no network requests. Browser storage is tied to the browser and origin; use exports to keep projects separate."
    },
    {
      "id": "trialmon",
      "title": "TRIALMON safety review",
      "summary": "Explore synthetic safety screens, participant worklists and the Safety Review Committee example.",
      "category": "Interactive apps",
      "kind": "shiny",
      "runtime": "R 4.1+ and app packages",
      "docs": [
        {
          "label": "Guide",
          "path": "sasr_monitoring_wiki/index.html"
        },
        {
          "label": "Setup and inputs",
          "path": "sasr_monitoring_wiki/trialmon_shiny/README.md"
        }
      ],
      "workspace_paths": [
        "sasr_monitoring_wiki/trialmon_shiny"
      ],
      "inputs": [
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/adsl.csv",
          "label": "adsl.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "STUDYID",
            "USUBJID",
            "COHORT",
            "DOSEMG",
            "AGE",
            "SEX",
            "SAFFL",
            "TRTSDY",
            "TRTEDY",
            "EOTSTT",
            "DCTREAS",
            "EOSSTT",
            "LSTVISDY",
            "DLTEVLFL",
            "DLTFL",
            "DLTADJ",
            "DLTDESC"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/adlb.csv",
          "label": "adlb.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "STUDYID",
            "USUBJID",
            "PARAMCD",
            "PARAM",
            "AVISIT",
            "ADY",
            "AVAL",
            "AVALU",
            "ANRLO",
            "ANRHI",
            "BASE",
            "ABLFL"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/adeg.csv",
          "label": "adeg.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "STUDYID",
            "USUBJID",
            "PARAMCD",
            "PARAM",
            "AVISIT",
            "ATPT",
            "ADY",
            "AVAL",
            "BASE",
            "CHG",
            "ABLFL"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/adae.csv",
          "label": "adae.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "STUDYID",
            "USUBJID",
            "AEDECOD",
            "AEBODSYS",
            "AETOXGR",
            "AESER",
            "AREL",
            "ASTDY",
            "AENDY",
            "TRTEMFL"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/cohorts.csv",
          "label": "cohorts.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "COHORT",
            "DOSEMG",
            "STATUS",
            "DLTWIN"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/study_kri.csv",
          "label": "study_kri.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "ID",
            "INDICATOR",
            "CATEGORY",
            "VALUE",
            "UNIT",
            "WORSE",
            "AMBER",
            "RED",
            "DETAIL"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/notes.csv",
          "label": "notes.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "USUBJID",
            "NOTE"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/labs_long.csv",
          "label": "labs_long.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "STUDYID",
            "USUBJID",
            "PARAMCD",
            "PARAM",
            "AVISIT",
            "ADY",
            "AVAL",
            "AVALU",
            "ANRLO",
            "ANRHI",
            "BASE",
            "ABLFL"
          ]
        },
        {
          "path": "sasr_monitoring_wiki/trialmon_shiny/data/narrative_flags.csv",
          "label": "narrative_flags.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "USUBJID",
            "SOURCE",
            "STATUS",
            "NARRATIVE"
          ]
        }
      ],
      "actions": [
        {
          "id": "shiny.trialmon.check",
          "label": "Check R and packages",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.trialmon.install",
          "label": "Install app packages",
          "type": "job",
          "description": "Downloads missing or incompatible packages into this project’s private library.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.trialmon.run",
          "label": "Start local app",
          "type": "job",
          "description": "Uses the selected private project and opens a local browser session.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [],
      "persistence": "Selections and settings last for the running session. Download the worklist CSV; input files remain in the private project.",
      "customization": "Replace the listed CSVs in your private project, preserving their input contract. Review thresholds and verify known cases before study use.",
      "limits": "A review aid with synthetic thresholds. It does not diagnose liver injury, adjudicate DLTs or decide escalation. Planted teaching cases are separate from the dosed participants.",
      "app_id": "trialmon",
      "demo_url": "https://patrickiben.github.io/biometrics-ai-portfolio/apps/trialmon/"
    },
    {
      "id": "lifecycle",
      "title": "Study Lifecycle Monitor",
      "summary": "Review a study portfolio, milestones, delivery progress and transparent operational scores.",
      "category": "Interactive apps",
      "kind": "shiny",
      "runtime": "R 4.1+ and app packages",
      "docs": [
        {
          "label": "Guide",
          "path": "lifecycle_dashboard/quarto/lifecycle-guide.html"
        },
        {
          "label": "Setup and inputs",
          "path": "lifecycle_dashboard/shiny/README.md"
        }
      ],
      "workspace_paths": [
        "lifecycle_dashboard/shiny"
      ],
      "inputs": [
        {
          "path": "lifecycle_dashboard/shiny/data/studies.csv",
          "label": "studies.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "id",
            "name",
            "phase",
            "design",
            "owner",
            "target",
            "enrolled",
            "sites",
            "days_to_dbl",
            "open_queries",
            "clean_pct",
            "sdv_pct",
            "tlf_planned",
            "tlf_programmed",
            "tlf_qcd",
            "tlf_finalized",
            "dbl_prog_pct",
            "discrep"
          ]
        },
        {
          "path": "lifecycle_dashboard/shiny/data/milestones.csv",
          "label": "milestones.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "study_id",
            "milestone",
            "date",
            "status"
          ]
        },
        {
          "path": "lifecycle_dashboard/shiny/data/deliverables.csv",
          "label": "deliverables.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "study_id",
            "phase",
            "done",
            "total"
          ]
        },
        {
          "path": "lifecycle_dashboard/shiny/data/query_trend.csv",
          "label": "query_trend.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "study_id",
            "week",
            "open_queries"
          ]
        }
      ],
      "actions": [
        {
          "id": "shiny.lifecycle.check",
          "label": "Check R and packages",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.lifecycle.install",
          "label": "Install app packages",
          "type": "job",
          "description": "Downloads missing or incompatible packages into this project’s private library.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.lifecycle.run",
          "label": "Start local app",
          "type": "job",
          "description": "Uses the selected private project and opens a local browser session.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [],
      "persistence": "What-if sliders do not write back to the input CSVs. Preserve revised source inputs in the private project.",
      "customization": "Replace the listed CSVs in your private project, preserving their input contract. Review thresholds and verify known cases before study use.",
      "limits": "Operational signals only. Source-system connectors are not included. Read-only CSV exports must follow the documented schema.",
      "app_id": "lifecycle",
      "demo_url": "https://patrickiben.github.io/biometrics-ai-portfolio/apps/lifecycle_dashboard/"
    },
    {
      "id": "uat",
      "title": "IRT / RTSM UAT tracker",
      "summary": "Review test scripts, trace requirements, record test results and inspect the sign-off gate.",
      "category": "Interactive apps",
      "kind": "shiny",
      "runtime": "R 4.1+ and app packages",
      "docs": [
        {
          "label": "Guide",
          "path": "uat_irt/quarto/uat-guide.html"
        },
        {
          "label": "Setup and inputs",
          "path": "uat_irt/shiny/README.md"
        },
        {
          "label": "UAT workbook",
          "path": "uat_irt/UAT_IRT_RTSM_Workbook.xlsx"
        }
      ],
      "workspace_paths": [
        "uat_irt/shiny"
      ],
      "inputs": [
        {
          "path": "uat_irt/templates/test_scripts.csv",
          "label": "test_scripts.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "TestID",
            "Area",
            "RequirementID",
            "TestTitle",
            "Priority",
            "Steps",
            "ExpectedResult",
            "Status",
            "LinkedDefect"
          ]
        },
        {
          "path": "uat_irt/templates/defect_log.csv",
          "label": "defect_log.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "DefectID",
            "Severity",
            "Status",
            "FoundInTest",
            "Description",
            "DateRaised",
            "Resolution"
          ]
        },
        {
          "path": "uat_irt/templates/traceability_matrix.csv",
          "label": "traceability_matrix.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "RequirementID",
            "RequirementDescription",
            "CoveringTests",
            "Covered"
          ]
        }
      ],
      "actions": [
        {
          "id": "shiny.uat.check",
          "label": "Check R and packages",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.uat.install",
          "label": "Install app packages",
          "type": "job",
          "description": "Downloads missing or incompatible packages into this project’s private library.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.uat.run",
          "label": "Start local app",
          "type": "job",
          "description": "Uses the selected private project and opens a local browser session.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [],
      "persistence": "Edits last for the session. The CSV download saves test results only; preserve defect and traceability changes separately.",
      "customization": "Use the listed parent templates for local R. A browser rebuild also needs matching copies in uat_irt/shiny/templates; local project uploads target the parent templates.",
      "limits": "The gate packages evidence for a named human reviewer; it does not approve an IRT system. The workbook and Shiny checks are separate.",
      "app_id": "uat",
      "demo_url": "https://patrickiben.github.io/biometrics-ai-portfolio/apps/uat_irt/"
    },
    {
      "id": "risk",
      "title": "Operational risk signals",
      "summary": "Inspect weighted participant and study signal tiers and try what-if changes.",
      "category": "Interactive apps",
      "kind": "shiny",
      "runtime": "R 4.1+ and app packages",
      "docs": [
        {
          "label": "Guide",
          "path": "risk_monitor/quarto/risk-guide.html"
        },
        {
          "label": "Setup and inputs",
          "path": "risk_monitor/shiny/README.md"
        }
      ],
      "workspace_paths": [
        "risk_monitor/shiny"
      ],
      "inputs": [
        {
          "path": "risk_monitor/shiny/data/signals.csv",
          "label": "signals.csv",
          "description": "Replace with a reviewed input that preserves the documented columns, types and units.",
          "columns": [
            "tier",
            "id",
            "signal",
            "category",
            "level",
            "weight",
            "advanced",
            "detail"
          ]
        }
      ],
      "actions": [
        {
          "id": "shiny.risk.check",
          "label": "Check R and packages",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.risk.install",
          "label": "Install app packages",
          "type": "job",
          "description": "Downloads missing or incompatible packages into this project’s private library.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.risk.run",
          "label": "Start local app",
          "type": "job",
          "description": "Uses the selected private project and opens a local browser session.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [],
      "persistence": "What-if changes are session-only and do not update signals.csv. There is no complete session-state export.",
      "customization": "Replace the listed CSVs in your private project, preserving their input contract. Review thresholds and verify known cases before study use.",
      "limits": "This is a synthetic operational illustration. Signal values, weights and thresholds need review for the intended study. No Shinylive build is included.",
      "app_id": "risk"
    },
    {
      "id": "hours",
      "title": "Find Hours reconciliation",
      "summary": "Compare planned, actual and forecast effort, then allocate an out-of-scope ask against slack and contingency.",
      "category": "Interactive apps",
      "kind": "shiny",
      "runtime": "R 4.1+ and app packages",
      "docs": [
        {
          "label": "Guide",
          "path": "budget_reconciliation/quarto/hours-guide.html"
        },
        {
          "label": "Setup and inputs",
          "path": "budget_reconciliation/shiny/README.md"
        },
        {
          "label": "Hours workbook",
          "path": "budget_reconciliation/Hours_Budget_Reconciliation_Workbook.xlsx"
        }
      ],
      "workspace_paths": [
        "budget_reconciliation/shiny"
      ],
      "inputs": [
        {
          "path": "budget_reconciliation/templates/project_hours_ledger.csv",
          "label": "Hours ledger",
          "description": "Keep the CONTINGENCY and TOTAL rows and the column names; supply planned, actual and estimated-at-completion hours.",
          "columns": [
            "Deliverable",
            "PlannedHours",
            "ActualToDate",
            "PctComplete",
            "EAC",
            "Variance",
            "Notes"
          ]
        }
      ],
      "actions": [
        {
          "id": "shiny.hours.check",
          "label": "Check R and packages",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.hours.install",
          "label": "Install app packages",
          "type": "job",
          "description": "Downloads missing or incompatible packages into this project’s private library.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "shiny.hours.run",
          "label": "Start local app",
          "type": "job",
          "description": "Uses the selected private project and opens a local browser session.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [],
      "persistence": "Edits last for the session. Download the ledger CSV and change-order text before closing. Upload a saved ledger to the private project for a later run.",
      "customization": "Replace the listed CSVs in your private project, preserving their input contract. Review thresholds and verify known cases before study use.",
      "limits": "Hours and effort only: no prices, rates or headcount. No connection to budgets or timesheets; no Shinylive build is included.",
      "app_id": "hours"
    },
    {
      "id": "study",
      "title": "Worked bioequivalence study",
      "summary": "Reproduce six stages of a synthetic 2x2 crossover: design, SAP, ADaM, analysis, QC and number-checked CSR text.",
      "category": "Analyses and methods",
      "kind": "job",
      "runtime": "R, study package lockfile and Quarto",
      "docs": [
        {
          "label": "Worked study",
          "path": "study/index.html"
        },
        {
          "label": "Methods and reproduction",
          "path": "study/README.md"
        },
        {
          "label": "Results report",
          "path": "study/04_analysis/report/report.html"
        },
        {
          "label": "Generated SAP settings",
          "path": "study/02_sap/analysis_parameters.json"
        }
      ],
      "workspace_paths": [
        "study",
        "sim_lifecycle",
        "tlf_interpret"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "study.check",
          "label": "Check study environment",
          "type": "job",
          "needs": [
            "r",
            "quarto"
          ]
        },
        {
          "id": "study.install",
          "label": "Restore study packages",
          "type": "job",
          "description": "Restores the study lockfile; this may download and compile packages.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "study.run",
          "label": "Run synthetic study",
          "type": "job",
          "description": "Regenerates the selected private project’s synthetic outputs.",
          "needs": [
            "r",
            "quarto"
          ]
        }
      ],
      "outputs": [
        {
          "label": "Analysis report",
          "path": "study/04_analysis/report/report.html"
        },
        {
          "label": "QC ledger",
          "path": "study/05_qc/qc_ledger.html"
        },
        {
          "label": "CSR text",
          "path": "study/06_csr/csr_section11.html"
        }
      ],
      "persistence": "Stage output files and run logs stay in your private project; export the project to retain the input, code and results together.",
      "customization": "Start with reproduction. The SAP settings JSON is generated and overwritten by run_all.R; use Open folder or Open in editor to review and adapt the source R code before implementing a new design or source-data mapping.",
      "limits": "The study is synthetic and always regenerates its example data. QC is same-author re-derivation. No conformant SDTM, define.xml, ADRG or submission package is produced.",
      "runner_id": "study"
    },
    {
      "id": "sandbox",
      "title": "PK, NCA and bioequivalence sandbox",
      "summary": "Generate eight ADaM-shaped domains and calculate PK, NCA, bioequivalence and safety summaries on a seeded example.",
      "category": "Analyses and methods",
      "kind": "job",
      "runtime": "Base R",
      "docs": [
        {
          "label": "Sandbox",
          "path": "sim_lifecycle/index.html"
        },
        {
          "label": "Inputs and conventions",
          "path": "sim_lifecycle/README.md"
        }
      ],
      "workspace_paths": [
        "sim_lifecycle",
        "tlf_interpret"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "sandbox.run",
          "label": "Run synthetic sandbox",
          "type": "job",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [
        {
          "label": "Summary CSV",
          "path": "sim_lifecycle/out/results_summary.csv"
        },
        {
          "label": "Output folder",
          "path": "sim_lifecycle/out"
        }
      ],
      "persistence": "Generated CSVs and the job log stay in the private project.",
      "customization": "Open the project code to review priors and the simulation design. The run button regenerates the documented example; it is not a general source-data analysis form.",
      "limits": "Synthetic ADaM-shaped data with home-grown checks. NCA conventions and the simple model have stated limits; this is not CDISC conformance or a validated analysis.",
      "runner_id": "sandbox"
    },
    {
      "id": "carryover",
      "title": "Residual carryover study",
      "summary": "Reproduce the synthetic operating-characteristics grid for washout and the ICH M13A 5% predose rule.",
      "category": "Analyses and methods",
      "kind": "job",
      "runtime": "Base R; optional PKNCA cross-check",
      "docs": [
        {
          "label": "Methods and results",
          "path": "sim_lifecycle/carryover_oc/index.html"
        },
        {
          "label": "Run details",
          "path": "sim_lifecycle/carryover_oc/README.md"
        }
      ],
      "workspace_paths": [
        "sim_lifecycle"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "carryover.check",
          "label": "Check carryover known answers",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "carryover.run",
          "label": "Run carryover study",
          "type": "job",
          "description": "Runs the grid and rebuilds the tables and figures.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [
        {
          "label": "Operating characteristics",
          "path": "sim_lifecycle/carryover_oc/out/oc_results.csv"
        },
        {
          "label": "Known-answer checks",
          "path": "sim_lifecycle/carryover_oc/out/known_answer_checks.csv"
        },
        {
          "label": "Study page",
          "path": "sim_lifecycle/carryover_oc/index.html"
        }
      ],
      "persistence": "CSV results, figures and regenerated page stay in the private project.",
      "customization": "Inspect the source configuration and Monte Carlo precision through Open folder before changing scenarios. Retain the original example as the baseline.",
      "limits": "Exploratory synthetic method study. Residual subtraction is a sensitivity analysis, not a regulatory recommendation.",
      "runner_id": "carryover"
    },
    {
      "id": "cqtc",
      "title": "C-QTc hysteresis study",
      "summary": "Reproduce the synthetic scenarios and operating characteristics for a prespecified concentration–QTc hysteresis check.",
      "category": "Analyses and methods",
      "kind": "job",
      "runtime": "Base R; nlme for a test cross-check",
      "docs": [
        {
          "label": "Method and results",
          "path": "cqtc_hysteresis/index.html"
        }
      ],
      "workspace_paths": [
        "cqtc_hysteresis"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "cqtc.check",
          "label": "Check C-QTc known answers",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "cqtc.run",
          "label": "Run C-QTc study",
          "type": "job",
          "description": "The full simulation can take several minutes.",
          "needs": [
            "r"
          ]
        }
      ],
      "outputs": [
        {
          "label": "Operating characteristics",
          "path": "cqtc_hysteresis/out/oc_results.csv"
        },
        {
          "label": "Method page",
          "path": "cqtc_hysteresis/index.html"
        }
      ],
      "persistence": "Results and the regenerated method page stay in the private project.",
      "customization": "Review scenarios and model assumptions in the project source. The button reproduces the existing synthetic study.",
      "limits": "An exploratory synthetic method study. It does not replace a prespecified clinical C-QTc analysis or regulatory review.",
      "runner_id": "cqtc"
    },
    {
      "id": "vaccine",
      "title": "Vaccine immunogenicity and reactogenicity",
      "summary": "Configure antibody summaries, response definitions and solicited reaction summaries with guided study settings and synthetic examples.",
      "category": "Templates and references",
      "kind": "templates",
      "runtime": "R 4.4+; packages installed through the local toolkit",
      "docs": [
        {
          "label": "Vaccine analysis guide",
          "path": "vaccine/index.html"
        },
        {
          "label": "Immunity learning companion",
          "path": "vaccine/learning.html"
        }
      ],
      "workspace_paths": [
        "vaccine"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "vaccine",
          "module_id": "vaccine",
          "label": "Set up vaccine analyses",
          "type": "guided"
        }
      ],
      "outputs": [],
      "persistence": "Mapped inputs and settings stay in the private project. Each generated revision and analysis run has its own downloadable package and QC record.",
      "customization": "Choose outputs and study-specific assay, response and reaction settings in guided forms. Download input templates or try fictional data, map CSV columns, preview and run.",
      "limits": "Review assay handling, populations, response definitions, observation windows and missing data for each study. Software execution and QC do not establish protection, clinical safety or study approval. Native SAS reference exports are unexecuted.",
      "runner_id": "vaccine"
    },
    {
      "id": "tlf-libraries",
      "title": "Paired SAS and R TLF libraries",
      "summary": "Configure and run 221 R table, listing and figure programs across five study designs, with SAS reference exports.",
      "category": "Templates and references",
      "kind": "templates",
      "runtime": "R 4.4+; packages installed through the local toolkit",
      "docs": [
        {
          "label": "SAS library",
          "path": "sas_tlf_pseudocode/index.html"
        },
        {
          "label": "R library",
          "path": "r_tlf_pseudocode/index.html"
        },
        {
          "label": "SAS setup",
          "path": "sas_tlf_pseudocode/README.md"
        },
        {
          "label": "R setup",
          "path": "r_tlf_pseudocode/README.md"
        }
      ],
      "workspace_paths": [
        "sas_tlf_pseudocode",
        "r_tlf_pseudocode"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "tlf.sas",
          "label": "Browse SAS templates",
          "type": "open",
          "path": "sas_tlf_pseudocode/index.html"
        },
        {
          "id": "tlf.r",
          "label": "Browse R templates",
          "type": "open",
          "path": "r_tlf_pseudocode/index.html"
        },
        {
          "id": "r_tlf.check",
          "label": "Parse R templates",
          "type": "job",
          "description": "Checks syntax only; no analysis is executed.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "sas_tlf",
          "label": "Set up SAS study outputs",
          "type": "guided"
        },
        {
          "id": "r_tlf",
          "label": "Set up R study outputs",
          "type": "guided"
        }
      ],
      "outputs": [],
      "persistence": "Inputs, profiles and immutable setup packages stay in the private project. Every run has a separate HTML report, complete CSV/RDS tables, PDF/PNG figures, QC record, software versions and ZIP download.",
      "customization": "Choose design, outputs, populations, parameters, dose values, comparison labels and analysis windows; map CSV columns, preview, generate, check packages and run. Save profiles to reuse settings.",
      "limits": "Software QC uses synthetic fixtures and known answers. Review methods, exclusions, units and model assumptions for each study. Native SAS reference code has not been executed; execution success is separate from study approval.",
      "runner_id": "r_tlf"
    },
    {
      "id": "harness",
      "title": "Validation harness",
      "summary": "Run the repository’s automatic structural and numerical checks and inspect its evidence ledger.",
      "category": "QC and reporting",
      "kind": "job",
      "runtime": "R and Python",
      "docs": [
        {
          "label": "Harness and ledger",
          "path": "validation_harness/index.html"
        },
        {
          "label": "Gate definitions",
          "path": "validation_harness/README.md"
        }
      ],
      "workspace_paths": [
        "validation_harness"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "harness.run",
          "label": "Run QC harness",
          "type": "job",
          "description": "Checks the complete selected private project.",
          "needs": [
            "r",
            "python"
          ]
        }
      ],
      "outputs": [
        {
          "label": "Evidence ledger",
          "path": "validation_harness/EVIDENCE_LEDGER.md"
        },
        {
          "label": "Machine ledger",
          "path": "validation_harness/ledger.json"
        }
      ],
      "persistence": "The evidence ledger and logs stay in the private project.",
      "customization": "Run the original example first. After adaptation, review which gates and reference outputs remain applicable.",
      "limits": "A passing example does not validate a new study. Manual QC and AI-use sign-off remain separate; SAS/R parity is structural, not independently reconciled execution.",
      "runner_id": "harness"
    },
    {
      "id": "teeth",
      "title": "Seeded-defect check",
      "summary": "Measure what the QC harness catches by planting registered defects in throwaway copies of the example.",
      "category": "QC and reporting",
      "kind": "job",
      "runtime": "R and Python; test packages for seeded defects",
      "docs": [
        {
          "label": "What it catches",
          "path": "validation_harness/index.html#teeth"
        },
        {
          "label": "Registered defects",
          "path": "validation_harness/teeth/defects.csv"
        }
      ],
      "workspace_paths": [
        "validation_harness"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "teeth.check",
          "label": "Check defect-test environment",
          "type": "job",
          "needs": [
            "r",
            "python"
          ]
        },
        {
          "id": "teeth.install",
          "label": "Install defect-test packages",
          "type": "job",
          "needs": [
            "r"
          ]
        },
        {
          "id": "teeth.run",
          "label": "Run seeded-defect check",
          "type": "job",
          "description": "This longer job can take around 13 minutes; its log shows progress.",
          "needs": [
            "r",
            "python"
          ]
        }
      ],
      "outputs": [
        {
          "label": "Run summary",
          "path": "validation_harness/teeth/results/summary.json"
        }
      ],
      "persistence": "Results and logs stay in the private project; the registered defects are applied to temporary copies.",
      "customization": "Inspect the registered list and known scope before running. Changes to the registry require its documented freeze and review process.",
      "limits": "Counts describe a hand-picked list, not an estimated defect-detection rate. A change with no effect on shipped data may be classified equivalent.",
      "runner_id": "teeth"
    },
    {
      "id": "interpretation",
      "title": "TLF text number validator",
      "summary": "Map AE-overview or PK-summary results, preview deterministic facts and review a draft without configuring a model.",
      "category": "QC and reporting",
      "kind": "job",
      "runtime": "Browser and local toolkit for guided previews; R/Quarto for optional report regeneration",
      "docs": [
        {
          "label": "Validator and skeleton",
          "path": "tlf_interpret/index.html"
        },
        {
          "label": "Implementation guide",
          "path": "tlf_interpret/README.md"
        }
      ],
      "workspace_paths": [
        "tlf_interpret"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "interpretation.check",
          "label": "Run number-validator self-test",
          "type": "job",
          "description": "Tests the deterministic validator without a language model.",
          "needs": [
            "r"
          ]
        },
        {
          "id": "interpretation",
          "label": "Set up TLF draft report",
          "type": "guided"
        }
      ],
      "outputs": [],
      "persistence": "Inputs, profiles, draft reports and audit evidence stay in the private project; export the package to retain a reviewed version.",
      "customization": "Choose AE overview or PK summary, upload aggregate results and map columns. Preview the extracted facts, edit draft text, inspect number/claim checks and generate a report package.",
      "limits": "Supports the documented AE-overview and PK-summary contracts. Number checks do not establish that a number supports the right clinical claim. Generated drafts remain unapproved and require human review.",
      "runner_id": "interpretation"
    },
    {
      "id": "sas_monitor",
      "title": "SAS/R monitoring automation",
      "summary": "Select monitoring checks, map study feeds and set thresholds through a guided form.",
      "category": "Templates and references",
      "kind": "templates",
      "runtime": "R and jsonlite for local checks; scheduler and SMTP configured separately",
      "docs": [
        {
          "label": "Monitoring guide",
          "path": "sas_r_automation/SAS_R_Trial_Monitoring_Automation.html"
        },
        {
          "label": "Macro library setup",
          "path": "sas_r_automation/macro_library/README.md"
        },
        {
          "label": "Runbook",
          "path": "sas_r_automation/SAS_R_Coverage_Runbook.pdf"
        }
      ],
      "workspace_paths": [
        "sas_r_automation"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "sas_monitor",
          "label": "Set up monitoring checks",
          "type": "guided"
        },
        {
          "id": "sas_monitor.guide",
          "label": "Open monitoring guide",
          "type": "open",
          "path": "sas_r_automation/SAS_R_Trial_Monitoring_Automation.html"
        }
      ],
      "outputs": [],
      "persistence": "Inputs and settings remain in the private project. Each run retains separate outputs, diagnostics, software versions and a ZIP download.",
      "customization": "Select checks, map CSV columns, set thresholds and a visit analysis date, then preview and generate. Check packages and run from the revision card. Save reusable profiles.",
      "limits": "Eight mapped-CSV checks run locally through the generated revision. Native SAS exports remain unexecuted; scheduling, live feed connections and monitoring emails remain separate."
    },
    {
      "id": "monitoring-wiki",
      "title": "SAS/R monitoring coverage wiki",
      "summary": "Read the monitoring coverage reference and its worked examples alongside the runnable TRIALMON card.",
      "category": "Templates and references",
      "kind": "reference",
      "runtime": "Browser or PDF reader",
      "docs": [
        {
          "label": "Coverage wiki",
          "path": "sasr_monitoring_wiki/SASR_Monitoring_Coverage_Wiki.html"
        }
      ],
      "workspace_paths": [
        "sasr_monitoring_wiki"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "monitoring-wiki.open",
          "label": "Open coverage wiki",
          "type": "open",
          "path": "sasr_monitoring_wiki/SASR_Monitoring_Coverage_Wiki.html"
        }
      ],
      "outputs": [],
      "persistence": "The reference and supporting files are included in the private project.",
      "customization": "Use the reference to write a study-specific monitoring and coverage plan; use TRIALMON for the synthetic interactive example.",
      "limits": "Reference material and examples do not configure feeds or authorize clinical decisions."
    },
    {
      "id": "playbook",
      "title": "Coverage playbook and runbook",
      "summary": "Plan planned leave, unplanned absence, role handoff, taking over and single-owner exposure.",
      "category": "Templates and references",
      "kind": "reference",
      "runtime": "Browser or PDF reader",
      "docs": [
        {
          "label": "Playbook",
          "path": "sasr_onleave_wiki/On_Leave_Coverage_Playbook.html"
        },
        {
          "label": "Printable runbook",
          "path": "sasr_onleave_wiki/OnLeave_Coverage_Runbook.pdf"
        }
      ],
      "workspace_paths": [
        "sasr_onleave_wiki"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "playbook.open",
          "label": "Open coverage playbook",
          "type": "open",
          "path": "sasr_onleave_wiki/On_Leave_Coverage_Playbook.html"
        }
      ],
      "outputs": [],
      "persistence": "Save your completed handoff through the separate continuity workspace’s JSON/CSV/print controls.",
      "customization": "Choose a scenario and populate your named owners, backups, schedules and escalation contacts in the continuity workspace.",
      "limits": "The playbook is a reference. It does not automatically provide cover, schedule jobs or send messages."
    },
    {
      "id": "localmind",
      "title": "LOCALMIND SAS/R helpers",
      "summary": "Map findings and prepare controlled language-review inputs with explicit human approval.",
      "category": "Templates and references",
      "kind": "templates",
      "runtime": "Licensed SAS or R with httr2/jsonlite; separately installed local model service",
      "docs": [
        {
          "label": "Library and setup",
          "path": "slm_wiki/macro_library/README.md"
        }
      ],
      "workspace_paths": [
        "slm_wiki"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "localmind",
          "label": "Set up language review",
          "type": "guided"
        },
        {
          "id": "localmind.guide",
          "label": "Open helper guide",
          "type": "open",
          "path": "slm_wiki/macro_library/README.md"
        }
      ],
      "outputs": [],
      "persistence": "Inputs, saved profiles and generated review packages stay in the private project. Keep model identity and reviewed outputs with any later evaluation.",
      "customization": "Upload findings, map identifiers/rules/text, choose allowed labels and enter local-model settings. Generate an unapproved review queue plus configured SAS/R helpers. Generation never contacts a model.",
      "limits": "All generated findings start unapproved. Installing a model service and evaluating its outputs remain separate. A configured helper is not evidence of model quality."
    },
    {
      "id": "pipeline",
      "title": "Biostatistics deliverables register",
      "summary": "Explore 132 early-phase deliverables, their owners, inputs, outputs, standards and QC methods.",
      "category": "Templates and references",
      "kind": "reference",
      "runtime": "Browser, PDF reader or spreadsheet application",
      "docs": [
        {
          "label": "Pipeline document",
          "path": "biostat_pipeline/EarlyPhase_Biostat_Pipeline.pdf"
        },
        {
          "label": "Deliverables register",
          "path": "biostat_pipeline/EarlyPhase_Biostat_Pipeline_Register.xlsx"
        },
        {
          "label": "One-page map",
          "path": "biostat_pipeline/EarlyPhase_Biostat_Pipeline_Map.pdf"
        }
      ],
      "workspace_paths": [
        "biostat_pipeline"
      ],
      "inputs": [],
      "actions": [
        {
          "id": "pipeline.register",
          "label": "Open deliverables register",
          "type": "open",
          "path": "biostat_pipeline/EarlyPhase_Biostat_Pipeline_Register.xlsx"
        },
        {
          "id": "pipeline.map",
          "label": "Open pipeline map",
          "type": "open",
          "path": "biostat_pipeline/EarlyPhase_Biostat_Pipeline_Map.pdf"
        }
      ],
      "outputs": [],
      "persistence": "Save edited workbook/document copies within the private project and export it.",
      "customization": "Open the register in your spreadsheet application and adapt deliverables, ownership and evidence for the intended study.",
      "limits": "A reference map, not a record of completed study work or a generated submission package."
    },
    {
      "id": "ecrf",
      "title": "eCRF assist apps",
      "summary": "Open four separately hosted Python demos: coding QC, de-identification review, participant risk and central monitoring.",
      "category": "External browser demos",
      "kind": "external",
      "runtime": "Browser; separately hosted Python runtime downloads on first use",
      "docs": [
        {
          "label": "Apps and setup",
          "path": "https://patrickiben.github.io/ecrf-pipeline-apps/"
        },
        {
          "label": "Separate source repository",
          "path": "https://github.com/patrickiben/ecrf-pipeline-apps"
        }
      ],
      "workspace_paths": [],
      "inputs": [],
      "actions": [
        {
          "id": "ecrf.open",
          "label": "Open eCRF demos",
          "type": "open",
          "path": "https://patrickiben.github.io/ecrf-pipeline-apps/"
        }
      ],
      "outputs": [],
      "persistence": "Separate demo site; its code and runtime are not included in this toolkit project ZIP.",
      "customization": "Use the synthetic public demos. For local adaptation, download that separate repository and follow its own setup guide.",
      "limits": "Uploads are disabled in the public demos. Placeholder coding is not MedDRA. The host/CDN sees your IP address; this is not a validated or Part 11 system.",
      "demo_url": "https://patrickiben.github.io/ecrf-pipeline-apps/"
    },
    {
      "id": "sibling",
      "title": "Within-sibling coding evaluation",
      "summary": "Read the separate eCRF coding-assist evaluation, including its within-sibling comparison and observed failures.",
      "category": "External browser demos",
      "kind": "external",
      "runtime": "Browser",
      "docs": [
        {
          "label": "Evaluation",
          "path": "https://patrickiben.github.io/ecrf-pipeline-apps/evaluation.html#within-sibling-discrimination"
        }
      ],
      "workspace_paths": [],
      "inputs": [],
      "actions": [
        {
          "id": "sibling.open",
          "label": "Open evaluation",
          "type": "open",
          "path": "https://patrickiben.github.io/ecrf-pipeline-apps/evaluation.html#within-sibling-discrimination"
        }
      ],
      "outputs": [],
      "persistence": "Read-only external evidence; reproduction belongs to the separately downloaded eCRF repository.",
      "customization": "Read the evaluation before adapting the coding-assist example. Retain its human review and test assumptions in any new work.",
      "limits": "Synthetic evaluation results do not establish performance on a new study or coding dictionary.",
      "demo_url": "https://patrickiben.github.io/ecrf-pipeline-apps/evaluation.html#within-sibling-discrimination"
    }
  ]
};
