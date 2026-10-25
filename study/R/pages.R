################################################################################
# study/R/pages.R: the stage index pages (03_adam/index.html, 04_analysis/index.html) and
# the step-by-step page study/index.html, written from the executed outputs so every
# number on them comes from this run. SYNTHETIC DATA ONLY.
################################################################################
DES <- jsonlite::read_json(sp("01_design", "design_parameters.json"))
QC  <- jsonlite::read_json(sp("05_qc", "qc_ledger.json"))
CSR <- jsonlite::read_json(sp("06_csr", "csr_check.json"))
SCN <- jsonlite::read_json(sp("03_adam", "sdtm", "scenarios.json"))
mchk <- utils::read.csv(sp("03_adam", "data", "metadata_checks.csv"))
pkg <- c("admiral", "metacore", "metatools", "xportr", "datasetjson", "PKNCA", "NonCompart", "PowerTOST", "blockrand",
         "rtables", "tern", "formatters", "r2rtf", "diffdf", "dplyr", "ggplot2", "knitr", "rmarkdown", "openxlsx", "renv")
VERS <- vapply(pkg, pkg_version, "")                       # CRAN form, as in renv.lock (PowerTOST 1.5-7)
v <- function(p) VERS[[p]]
cm <- be_results[be_results$PARAMCD == "CMAX", ]; au <- be_results[be_results$PARAMCD == "AUCLST", ]
p2 <- function(x) formatC(100 * x, format = "f", digits = 2)
n_csr_ok <- sum(vapply(CSR$paragraphs, function(x) identical(x$status, "DRAFT_OK"), logical(1)))

## --- 03_adam/index.html ---------------------------------------------------------------------------
sdtm_n <- vapply(c("dm", "ex", "pc", "ae", "vs", "ds", "pp"), function(d) nrow(utils::read.csv(sp("03_adam", "sdtm", paste0(d, ".csv")))), integer(1))
sdtm_tab <- data.frame(Domain = toupper(names(sdtm_n)), Records = sdtm_n,
  Content = c("Demographics and reference dates", "One record per dose (Test or Reference)", "Plasma concentrations at actual sampling times; BLQ as text",
              "Adverse events from the sim_lifecycle priors", "Screening height and weight", "Consent, randomization and disposition",
              "PK parameters from the NCA in stage 4 (derived, then fed back into ADPP)"),
  File = sprintf('%s.csv', names(sdtm_n)), check.names = FALSE)
adam_n <- c(ADSL = nrow(adsl), ADPC = nrow(adpc), ADPP = nrow(adpp), ADAE = nrow(adae))
adam_tab <- data.frame(Dataset = names(adam_n), Records = adam_n,
                       Variables = vapply(names(adam_n), function(d) ncol(get(tolower(d))), integer(1)),
                       Template = c("ad_adsl.R pattern; derive_vars_period() for the crossover", "ad_adpc.R, step by step (adaptations listed below)",
                                    "ad_adpp.R; SAP exclusion rules", "ad_adae.R pattern; period from create_period_dataset()"), check.names = FALSE)
links_adam <- paste0('<ul class="files">',
  paste(sprintf('<li><a href="data/%s.xpt">%s.xpt</a><span class="d">SAS XPORT v5 (xportr_write)</span> <a href="data/%s.csv">csv</a> <a href="data/json/%s.json">Dataset-JSON</a></li>',
                tolower(names(adam_n)), tolower(names(adam_n)), tolower(names(adam_n)), tolower(names(adam_n))), collapse = ""), '</ul>')
scn_tab <- data.frame(Participant = vapply(SCN, function(s) s$usubjid, ""), Scenario = vapply(SCN, function(s) s$what, ""), check.names = FALSE)
body03 <- paste0(
  md(sprintf("SDTM-like source domains are simulated by `03_adam/01_sdtm.R`, which reuses the `sim_lifecycle/` priors and one-compartment model (N = 40, seed 2026) and takes each participant's sequence from the stage 1 randomization schedule. ADaM datasets are derived with admiral %s following its `ad_adsl.R`, `ad_adpc.R`, `ad_adpp.R` and `ad_adae.R` templates, checked against the specification with metacore %s and metatools %s, and written as SAS XPORT v5 with xportr %s.",
             v("admiral"), v("metacore"), v("metatools"), v("xportr"))),
  '<h2>SDTM-like inputs</h2>', html_table(transform(sdtm_tab, File = File)),
  md("Files: [dm.csv](sdtm/dm.csv), [ex.csv](sdtm/ex.csv), [pc.csv](sdtm/pc.csv), [ae.csv](sdtm/ae.csv), [vs.csv](sdtm/vs.csv), [ds.csv](sdtm/ds.csv), [pp.csv](sdtm/pp.csv), [scenarios.json](sdtm/scenarios.json). No LB domain: no output in this example needs laboratory data."),
  '<h3>Documented scenarios that exercise the SAP rules</h3>', html_table(scn_tab),
  '<h2>ADaM datasets</h2>', html_table(adam_tab), links_adam,
  md("### Template adaptations in ADPC (each one commented in `03_adam/03_adpc.R`)",
     "",
     "- The analyte name joins PC and EX, because EXTRT carries the formulation (`SIMDRUG TEST` or `SIMDRUG REFERENCE`).",
     "- A pre-dose sample belongs to the dose that follows it (ARRLT below 0, NRRLT = 0), as the template's DTYPE COPY records do for repeated dosing.",
     "- BLQ values are 0 in AVAL (SAP, ICH M13A); the template's LLOQ/2 records are not created.",
     "- The sample that was not collected stays in ADPC with ANL01FL not Y, so a listing can show it.",
     sprintf("- `derive_var_nfrlt()` and `convert_xxtpt_to_hours()` are labeled EXPERIMENTAL in admiral %s; NFRLT is re-derived by plain arithmetic in stage 5 (Q4).", v("admiral")),
     "",
     "## Specification",
     "",
     "[adam_spec.xlsx](spec/adam_spec.xlsx) uses the Pinnacle 21 specification layout (Study, Datasets, Variables, ValueLevel, WhereClauses, Codelists, Dictionaries, Methods, Comments, Documents), which `metacore::spec_to_metacore()` reads. [adam_spec.json](spec/adam_spec.json) holds the same tables for scripts and diffs. Both come from one definition in `03_adam/spec/build_spec.R`. Variable labels follow CDISC naming (for example USUBJID, \"Unique Subject Identifier\")."),
  '<h3>Metadata checks (executed)</h3>',
  html_table(transform(mchk, pass = ifelse(pass, "pass", "FAIL")), caption = "metatools checks, length and mandatory checks, and an XPT read-back for each dataset."),
  '<div class="not-covered"><p><strong>Gap: not authored here.</strong> No define.xml and no Analysis Data Reviewer\'s Guide (ADRG). No Pinnacle 21 or CDISC CORE conformance run: the checks above test the datasets against this study\'s own specification. The source domains are SDTM-like (no trial design domains, no SUPP datasets). The Dataset-JSON v1.1 copies are a demonstration: FDA has not accepted Dataset-JSON as of Oct 2026, and SAS XPORT v5 remains the submission format.</p></div>')
write_text(page_html(title = "ADaM Datasets and Specification", kicker = "Stage 3: data standards",
                     h1 = "SDTM-like inputs, ADaM with admiral, specification checks and XPT",
                     description = "Synthetic SDTM-like domains, ADaM datasets derived with admiral 1.5.0, a metacore-readable specification, metatools checks and XPT v5 from xportr.",
                     labels = paste0(lab("sup", "Supported (job): created or reviewed CDISC analysis specifications"), lab("tools", "Executed here"), lab("gap", "Gap: define.xml and ADRG not authored")),
                     body = body03, depth = 1), sp("03_adam", "index.html"))

## --- 04_analysis/index.html ------------------------------------------------------------------------
tl <- data.frame(Output = vapply(TLF, function(x) x$title, ""), Population = vapply(TLF, function(x) x$pop, ""),
                 HTML = sprintf("tlf/%s.html", names(TLF)), RTF = sprintf("tlf/%s.rtf", names(TLF)))
tl_html <- paste0('<div class="tblwrap"><table class="data"><thead><tr><th>Output</th><th>Population</th><th>Files</th></tr></thead><tbody>',
                  paste(sprintf('<tr><td><a href="%s">%s</a></td><td>%s</td><td><a href="%s">RTF</a> <a href="%s">cells (csv)</a></td></tr>',
                                tl$HTML, esc(tl$Output), esc(tl$Population), tl$RTF, sub("\\.html$", ".csv", tl$HTML)), collapse = ""),
                  '</tbody></table></div>')
body04 <- paste0(
  '<ul class="kv">',
  sprintf('<li><span class="k">Cmax ratio T/R</span><span class="v">%s%%</span> 90%% CI %s to %s</li>', p2(cm$ratio), p2(cm$lower), p2(cm$upper)),
  sprintf('<li><span class="k">AUC(0-t) ratio T/R</span><span class="v">%s%%</span> 90%% CI %s to %s</li>', p2(au$ratio), p2(au$lower), p2(au$upper)),
  sprintf('<li><span class="k">Bioequivalence set</span><span class="v">%d</span> of %d participants</li>', cm$n, nrow(adsl)),
  sprintf('<li><span class="k">Conclusion</span><span class="v">%s</span> on unrounded limits</li>', if (be_pass) "BE shown" else "BE not shown"), '</ul>',
  md(sprintf("NCA with PKNCA %s, configured per the SAP: actual times, linear-up/log-down AUC, `conc.blq = list(first = \"keep\", middle = \"keep\", last = \"keep\")` so BLQ counts as zero everywhere (ICH M13A), lambda z from at least 3 points after tmax. The bioequivalence model is the ICH M13A general linear model (sequence, participant within sequence, period, formulation). Tables use rtables %s and tern %s; RTF comes from `formatters::export_as_rtf()` (formatters %s with r2rtf %s).",
             v("PKNCA"), v("rtables"), v("tern"), v("formatters"), v("r2rtf"))),
  '<h2>Results report</h2>',
  md("[report/report.html](report/report.html): the Quarto report (rendered by `run_all.R`) with the figures, every table, the exclusions and the ICH M13A acceptability checks."),
  '<h2>Tables</h2>', tl_html,
  '<h2>Figures</h2>',
  '<figure><img src="tlf/f_14_4_2_1a_mean_linear.png" alt="Mean plasma SIMDRUG concentrations by nominal time for Test and Reference, linear scale" width="880" height="550" loading="lazy"><figcaption>Figure 14.4.2.1a, mean concentrations (linear). Also <a href="tlf/f_14_4_2_1b_mean_semilog.png">semi-log</a> and <a href="tlf/f_14_4_2_2_individual.png">individual profiles (actual times)</a>.</figcaption></figure>',
  '<h2>Result files</h2>',
  md("[nca_parameters.csv](nca_parameters.csv) (one row per profile), [nca_settings.json](nca_settings.json), [be_results.csv](be_results.csv), [be_results.json](be_results.json), [be_anova.csv](be_anova.csv), [be_supplementary.csv](be_supplementary.csv), [pk_checks.csv](pk_checks.csv), [analysis_sets.csv](analysis_sets.csv). Programs: `01_nca.R`, `02_be.R`, `03_tlf.R`, `report/report.qmd`."),
  '<div class="not-covered"><p><strong>Not covered here.</strong> SAS was not used in this example; the SAS twins in the TLF library are not executed (no license). Phoenix WinNonlin was not used. These outputs are executed on synthetic data and are not validated deliverables.</p></div>')
write_text(page_html(title = "Analysis Outputs", kicker = "Stage 4: analysis", h1 = "NCA, bioequivalence analysis and executed tables",
                     description = "Executed NCA (PKNCA), ICH M13A bioequivalence analysis and rtables/tern tables with RTF export for a synthetic 2x2 crossover.",
                     labels = paste0(lab("led", "Led (job): PK analyses for crossover and BE studies"), lab("sup", "Supported (job): TLF review"), lab("tools", "Executed here")),
                     body = body04, depth = 1), sp("04_analysis", "index.html"))

## --- study/index.html: one section per stage --------------------------------------------------------
stage_sec <- function(num, name, labels, executed, links, gap = NULL) paste0(
  '<section class="stage" id="stage', num, '"><p class="kicker">Stage ', num, '</p><h2>', esc(name), '</h2><p class="meta">', labels, '</p>',
  '<h3>What was executed</h3><ul>', paste0("<li>", executed, "</li>", collapse = ""), '</ul>',
  '<h3>Artifacts</h3><ul class="files">', paste0("<li>", links, "</li>", collapse = ""), '</ul>',
  if (!is.null(gap)) paste0('<p class="small"><strong>Not covered:</strong> ', gap, '</p>') else "", '</section>')
L <- function(href, text, d) sprintf('<a href="%s">%s</a><span class="d">%s</span>', href, esc(text), esc(d))
P <- DES$planning
body_idx <- paste0(
  md("One synthetic early-phase bioequivalence study, taken from sample size to clinical study report text. Every number on this page and on the pages it links to comes from one script, `study/run_all.R`, run on synthetic data. The study builds on the `sim_lifecycle/` sandbox (same priors and model, a 2x2 crossover, N = 40, seed 2026)."),
  '<ol class="flow">',
  '<li><a href="#stage1">Design</a></li><li><a href="#stage2">SAP and shells</a></li><li><a href="#stage3">ADaM</a></li>',
  '<li><a href="#stage4">Analysis and TLFs</a></li><li><a href="#stage5">QC</a></li><li><a href="#stage6">CSR text</a></li></ol>',
  '<ul class="legend"><li><span class="lab led">Led</span> the resume says owned, wrote or led</li><li><span class="lab sup">Supported</span> reviewed, contributed, or created or reviewed</li>',
  '<li><span class="lab tools">Tools built</span> shown only by code here</li><li><span class="lab gap">Gap</span> no job evidence and no artifact</li></ul>',
  stage_sec(1, "Design: sample size and randomization",
    paste0(lab("led", "Led (job): protocol statistical sections and randomization schedules"), lab("tools", "Tools built: runs here")),
    c(sprintf("PowerTOST %s, exact method: CV %s%%, ratio %s%%, limits 80.00%% to 125.00%%: <strong>%s evaluable for 80%% power, %s for 90%%</strong>; 5%% allowance for non-evaluable participants gives %s enrolled.",
              v("PowerTOST"), P$cv_pct, P$gmr_pct, P$n_evaluable_80, P$n_evaluable_90, P$n_enrolled),
      "Sensitivity grid of N and power over CV 15% to 35% and ratio 0.90 to 1.05; pa.ABE() limits of the assumptions.",
      sprintf("blockrand %s, seed %s: permuted blocks of 4, sequences TR and RT %s : %s; balance check passed (largest running imbalance %s).",
              v("blockrand"), DES$randomization$seed, DES$randomization$n_TR, DES$randomization$n_RT, DES$randomization$max_running_imbalance),
      "Protocol statistical-section excerpt with ICH M11 headings (estimand, analysis sets, model, missing data, sample size)."),
    c(L("01_design/protocol_statistics.html", "protocol_statistics.html", "M11-headed excerpt, sensitivity tables, schedule check"),
      L("01_design/randomization_schedule.csv", "randomization_schedule.csv", "40 sequence assignments"),
      L("01_design/sensitivity_n.csv", "sensitivity_n.csv", "N over CV and ratio"),
      L("01_design/design_parameters.json", "design_parameters.json", "machine-readable design")),
    "BOIN/CRM dose-escalation designs, adaptive or group-sequential designs."),
  stage_sec(2, "Statistical analysis plan and mock shells",
    paste0(lab("led", "Led (job): analysis plans and mock tables, listings and figures"), lab("tools", "Tools built: settings drive the code")),
    c("Estimand with the five ICH E9(R1) attributes; each intercurrent event mapped to a strategy, and why the other four strategies do not apply.",
      "Analysis sets with their ADaM flags; the ICH M13A model, the tests to report, the decision on unrounded limits.",
      "BLQ and missing-data rules per ICH M13A; the settings are written to analysis_parameters.json, which the NCA, exclusion and BE programs read.",
      "Mock shells for the six executed tables."),
    c(L("02_sap/sap_excerpt.html", "sap_excerpt.html", "statistical methods excerpt"),
      L("02_sap/mock_shells.html", "mock_shells.html", "six table shells"),
      L("02_sap/analysis_parameters.json", "analysis_parameters.json", "settings the code reads"))),
  stage_sec(3, "SDTM-like inputs, ADaM, specification and XPT",
    paste0(lab("sup", "Supported (job): created or reviewed CDISC analysis specifications"), lab("tools", "Tools built: runs here"), lab("gap", "Gap: define.xml, ADRG")),
    c(sprintf("Simulated DM, EX, PC, AE, VS and DS (%d concentration records at actual times) with five documented scenarios: a withdrawal, emesis, a pre-dose carry-over value, a missed sample and a late sample.", sum(adpc$PARAMCD == "SIMDRUG")),
      sprintf("ADSL, ADPC, ADPP and ADAE with admiral %s following its ad_adpc.R and ad_adpp.R templates (NFRLT, AFRLT, NRRLT, ARRLT), adaptations listed.", v("admiral")),
      sprintf("Specification in Pinnacle 21 layout (xlsx) and JSON, read by metacore::spec_to_metacore(); <strong>%d of %d metadata checks passed</strong> (metatools check_variables, check_ct_data, check_unique_keys, lengths, mandatory values, XPT read-back).", sum(mchk$pass), nrow(mchk)),
      sprintf("SAS XPORT v5 with labels and lengths from xportr %s; Dataset-JSON v1.1 copies from datasetjson %s, which FDA has not accepted as of Oct 2026.", v("xportr"), v("datasetjson"))),
    c(L("03_adam/index.html", "ADaM page", "datasets, spec, checks, adaptations"),
      L("03_adam/spec/adam_spec.xlsx", "adam_spec.xlsx", "P21-layout specification"),
      L("03_adam/spec/adam_spec.json", "adam_spec.json", "machine-readable specification"),
      L("03_adam/data/adpc.xpt", "adpc.xpt", "one of four XPT v5 files")),
    "define.xml and the ADRG are not authored; no Pinnacle 21 or CDISC CORE run; the inputs are SDTM-like, not conformant SDTM."),
  stage_sec(4, "NCA, bioequivalence analysis and TLFs",
    paste0(lab("led", "Led (job): lead biostatistician on crossover and BE studies; PK analyses"), lab("sup", "Supported (job): TLF review"), lab("tools", "Tools built: runs here")),
    c(sprintf("PKNCA %s NCA on actual times with BLQ kept as zero in every position (ICH M13A): %d profiles.", v("PKNCA"), nrow(nca_wide)),
      sprintf("ICH M13A GLM: <strong>Cmax ratio %s%% (90%% CI %s to %s), AUC(0-t) ratio %s%% (90%% CI %s to %s)</strong> in %d participants; %s.",
              p2(cm$ratio), p2(cm$lower), p2(cm$upper), p2(au$ratio), p2(au$lower), p2(au$upper), cm$n, if (be_pass) "bioequivalence shown" else "bioequivalence not shown"),
      sprintf("Six tables with rtables %s and tern %s, each exported to RTF with formatters::export_as_rtf() and to HTML; three figures; a Quarto results report.", v("rtables"), v("tern"))),
    c(L("04_analysis/index.html", "Analysis page", "tables, figures, result files"),
      L("04_analysis/report/report.html", "report.html", "Quarto results report"),
      L("04_analysis/tlf/t_14_4_3_1.html", "Table 14.4.3.1", "bioequivalence result (RTF alongside)"),
      L("04_analysis/be_results.csv", "be_results.csv", "unrounded estimates")),
    "Phoenix WinNonlin and SAS were not used."),
  stage_sec(5, "QC: re-derivation by a second method",
    paste0(lab("sup", "Supported (job): reviewed outputs"), lab("tools", "Tools built: same-author re-derivation"), lab("gap", "Gap: independent double programming")),
    c(sprintf("<strong>%d of %d checks passed</strong> (%d values compared with diffdf %s at stated tolerances).", QC$pass, QC$checks, QC$values_compared, v("diffdf")),
      sprintf("NonCompart %s vs PKNCA for every NCA parameter; the BE model refit as a closed-form period-difference t-test and with nlme::lme().", v("NonCompart")),
      "ADPC times (including the experimental derive_var_nfrlt()), ADSL population flags and the adverse-event counts rebuilt in base R from the SDTM-like data.",
      "A planted 0.1% change is found exactly once, so the comparison is shown to fail when it should."),
    c(L("05_qc/qc_ledger.html", "qc_ledger.html", "executed ledger with pass/fail counts"),
      L("05_qc/qc_ledger.csv", "qc_ledger.csv", "one row per compared variable"),
      L("05_qc/qc_nca_side_by_side.csv", "qc_nca_side_by_side.csv", "both engines, every profile")),
    "This is same-author re-derivation: the same person wrote both routes. No second programmer re-derived the results."),
  stage_sec(6, "CSR section 11-style text, checked against the outputs",
    paste0(lab("sup", "Supported (job): statistical input to CSRs"), lab("led", "Led (job): final statistical reports"), lab("tools", "Tools built: number check")),
    c("Section 11-style text (data sets analyzed, demographics, compliance, PK and BE results, missing data, conclusions), with every number read from an output file.",
      sprintf("The tlf_interpret number-grounding validator, unchanged: <strong>%d of %d paragraphs</strong> have every number found in the outputs.", n_csr_ok, length(CSR$paragraphs)),
      "Controls: an altered number is rejected; a wrong statement built from real numbers passes, which is the known limitation; 'well tolerated' is flagged for review."),
    c(L("06_csr/csr_section11.html", "csr_section11.html", "text, check results, controls"),
      L("06_csr/csr_section11.txt", "csr_section11.txt", "plain text"),
      L("06_csr/csr_check.json", "csr_check.json", "validator output")),
    "The validator checks that numbers exist in the outputs, not that statements are correct. No language model runs in this pipeline; the text is filled into fixed sentence templates (written with an AI coding assistant) and still needs a statistician's review."),
  '<h2>Rerun it</h2>',
  md("```sh",
     "Rscript -e 'install.packages(\"renv\"); renv::restore(project = \"study\", prompt = FALSE)'  # packages pinned in study/renv.lock",
     "Rscript study/run_all.R        # from the repository root; regenerates every output above",
     "```",
     "",
     sprintf("[run_all.R](run_all.R) runs the stages in order and renders the report with Quarto. [renv.lock](renv.lock) pins R %s and the package versions below. Two consecutive local runs produced byte-identical files. The CI workflow `.github/workflows/study.yml` (r-lib/actions v2) runs it on Ubuntu and fails if a committed output changes; the figures and the rendered report are excluded from that byte check because PNG rendering depends on system fonts. The workflow has not yet run on GitHub.", paste(R.version$major, R.version$minor, sep = "."))),
  html_table(data.frame(Package = names(VERS), Version = unname(VERS)), caption = "Package versions used by this run (pinned in renv.lock)."),
  '<div class="not-covered"><p><strong>Not covered by this example.</strong> define.xml and ADRG authoring; Pinnacle 21 or CDISC CORE conformance; conformant SDTM; independent double programming by a second person; a validated (21 CFR Part 11) system; a regulatory submission package; interim analyses and a DMC. The study, product and every participant are simulated.</p></div>')
write_text(page_html(title = "Flagship Worked Example", kicker = "Worked example: one synthetic BE study",
                     h1 = "A synthetic bioequivalence study, from sample size to CSR text",
                     description = "One synthetic 2x2 crossover bioequivalence study taken through design, SAP, ADaM, NCA and BE analysis, QC and CSR text, reproducible from one script.",
                     labels = paste0(lab("tools", "Runs: study/run_all.R"), lab("tools", "Synthetic data")),
                     body = body_idx, depth = 0), sp("index.html"))
cat("[pages] study/index.html, 03_adam/index.html, 04_analysis/index.html written\n")
