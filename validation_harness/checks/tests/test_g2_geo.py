#!/usr/bin/env python3
"""Unit tests for validation_harness/checks/g2_geo.py (Python standard library only).

setUpClass copies r_tlf_pseudocode and sas_tlf_pseudocode to a temporary folder. Each case plants
one change in that copy (exact text that must occur exactly once), runs the check the way
run_harness.sh does (python3 g2_geo.py <R dir> <SAS dir>), restores the file and asserts:
  - the unmodified libraries pass every program;
  - every planted defect turns G2 red and names the program it is in;
  - every legitimate variant stays green;
  - the committed floor equals the program set, and a set below it turns G2 red.
Shared-helper cases mutate the actual called function bodies, keeping the same output checks.
The defect cases are the ones found in the four 2026-10-26 reviews of the per-program G2 (R01
to R18, S01 to S05, U01 to U05; then N01 to N08, N12 and N13, with N09, N18, N19, N27 and N28 from
the same probe; then E01 to E03 and the SAS missing-value cases, where an assignment of NA or `.`
alone made the arithmetic mean or CV count as geometric; then NE2, NE2b, ND4 to ND6 and ND6b,
where a data frame with a log column or a back-transformed value counted as log-derived, and ND1
to ND3 and NF1, where a program found only by its model left the set or a formula built from a
string went unread), registry defect D04, a pkstats() helper and a %pkstats macro without logs,
and logs that appear only in comments or string literals. The legitimate variants include P01 to
P09 and L01, L02, L04 to L09 from the reviews, ND2b, names that have an NA shell row and a
geometric assignment, and pull() or [[ ]] of a log column. Two disclosed limits are pinned so the
docs and the code cannot drift apart: log(x + c) counts as log-scale (passes), and a correct
formula built from a string (ND1c) fails.

Run: python3 validation_harness/checks/tests/test_g2_geo.py -v
"""
import csv
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
CHECK = os.path.join(REPO, 'validation_harness', 'checks', 'g2_geo.py')
REGISTRY = os.path.join(REPO, 'validation_harness', 'teeth', 'defects.csv')
R, SAS = 'r_tlf_pseudocode', 'sas_tlf_pseudocode'

# the 27 programs the earlier filename allowlist covered, plus mad/t_pd_summary.R (found by content)
EXPECTED = ['crossover/f_pk_conc_mean.R', 'crossover/t_ada_impact_pk.R', 'crossover/t_be_anova.R',
            'crossover/t_pk_conc_summary.R', 'crossover/t_pk_param_by_period.R', 'crossover/t_pk_param_summary.R',
            'mad/f_pk_conc_mean.R', 'mad/t_accumulation.R', 'mad/t_ada_impact_pk.R',
            'mad/t_dose_proportionality_ss.R', 'mad/t_pd_summary.R', 'mad/t_pk_conc_summary.R',
            'mad/t_pk_param_summary.R', 'parallel/f_pk_conc_mean.R', 'parallel/t_ada_impact_pk.R',
            'parallel/t_pk_conc_summary.R', 'parallel/t_pk_param_summary.R', 'sad/f_pk_conc_mean.R',
            'sad/t_ada_impact_pk.R', 'sad/t_dose_proportionality.R', 'sad/t_pk_conc_summary.R',
            'sad/t_pk_param_summary.R', 'single_sequence/f_pk_conc_mean.R', 'single_sequence/t_ada_impact_pk.R',
            'single_sequence/t_be_anova.R', 'single_sequence/t_pk_conc_summary.R',
            'single_sequence/t_pk_param_by_period.R', 'single_sequence/t_pk_param_summary.R']

CXP = R + '/crossover/t_pk_param_summary.R'
SADF = R + '/sad/f_pk_conc_mean.R'
PARF = R + '/parallel/f_pk_conc_mean.R'
ACC = R + '/mad/t_accumulation.R'
HELP = R + '/00_setup_helpers.R'
MAC = SAS + '/00_setup_macros.sas'
GEO_LINE = 'geomean = exp(mean(log(AVAL[AVAL > 0]))),'
PD = R + '/mad/t_pd_summary.R'
SADF_SAS = SAS + '/sad/f_pk_conc_mean.sas'
CXP_SAS = SAS + '/crossover/t_pk_param_summary.sas'
CXP_GEO = '`Geo Mean`      = sprintf("%.3g", geomean)'
CXP_CV = '`Geo CV%`       = sprintf("%.1f", geocv)'
CXP_PKSTATS = 'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%'
SAS_GM = 'geomean = exp(gmean_log);'
SAS_CV = 'geocv   = 100*sqrt(exp(gsd_log**2)-1);'
SAD_GEO = 'geomean = exp(mean(log(AVAL[AVAL > 0]))),      # geometric (semi-log panel)'
SAD_GROUPS = SAD_GEO + '\n            .groups = "drop") %>%'
HELP_GM = 'geomean = if(length(x)) exp(mean(log(x))) else NA_real_,'
HELP_CV = 'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,'
PKSTATS_USERS = 'relies on the failing pkstats() helper'
# an empty-data shell row: every value NA, so it must not make mean, sd or cv geometric names
SHELL = ('empty_cont <- tibble(n = 0L, mean = NA_real_, sd = NA_real_, cv = NA_real_, geomean = NA_real_, '
         'geocv = NA_real_)\n')
CXP_TMAX = '## --- Tmax: Median (Min, Max) ONLY'
MACRO_USER = 'crossover/t_ada_impact_pk.R'
FORMULA_TEXT = 'formula not written in code'


def d04():
    with open(REGISTRY, encoding='utf-8', newline='') as fh:
        row = next(r for r in csv.DictReader(fh) if r['id'] == 'D04')
    return [(row['file'], row['old_str'], row['new_str'])]


# id: (edits [(file, old, new)], program that must fail, text the evidence must contain or None)
DEFECTS = {
    'R01 Geo Mean column shows the arithmetic mean': (
        [(CXP, '`Geo Mean`      = sprintf("%.3g", geomean)', '`Geo Mean`      = sprintf("%.3g", mean)')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'R02 Geo CV% column shows the arithmetic CV': (
        [(CXP, '`Geo CV%`       = sprintf("%.1f", geocv)', '`Geo CV%`       = sprintf("%.1f", cv)')],
        'crossover/t_pk_param_summary.R', '"Geo CV%"'),
    'R03 exp(mean(x)) under another name, then rename(geomean = gm)': (
        [(SADF, SAD_GROUPS, 'gm = exp(mean(AVAL[AVAL > 0])),\n            .groups = "drop") %>% rename(geomean = gm) %>%')],
        'sad/f_pk_conc_mean.R', None),
    'R04 exp(mean(x)) under another name; log( only in a footnote string': (
        [(SADF, SAD_GEO, 'gm = exp(mean(AVAL[AVAL > 0])),')], 'sad/f_pk_conc_mean.R', 'no log() call'),
    'R05 log10 inside exp()': (
        [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))', 'exp(mean(log10(AVAL[AVAL > 0])))')], 'sad/f_pk_conc_mean.R', None),
    'R07 in-program helper without logs': (
        [(SADF, GEO_LINE, 'geomean = gmean(AVAL),'),
         (SADF, 'prof <- pc %>%', 'gmean <- function(x) exp(mean(x[x > 0]))\nprof <- pc %>%')],
        'sad/f_pk_conc_mean.R', None),
    'R08 base-R prof$geomean <- exp(prof$mean)': (
        [(SADF, 'ttl <- tfl_titles(', 'prof$geomean <- exp(prof$mean)\nttl <- tfl_titles(')],
        'sad/f_pk_conc_mean.R', 'geomean at line'),
    'R09 Geo Mean row overwritten with the Mean (SD) row': (
        [(CXP, '## --- Tmax: Median (Min, Max) ONLY',
          'cont$value[cont$stat == "Geo Mean"] <- cont$value[cont$stat == "Mean (SD)"]\n## --- Tmax: Median (Min, Max) ONLY')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'R10 mean of logs reported without exp()': ([('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geometric_mean = mean(log(AVAL[is.finite(AVAL) & AVAL > 0])),')],
         'mad/t_accumulation.R',
         '"geometric_mean" at line'),
    'R11 geocv from the raw scale': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,',
           'geocv = 100 * sd(x) / mean(x),')],
         'crossover/t_pk_param_summary.R',
         'relies on the failing pkstats() helper'),
    'R12 Rac without the back-transform': ([('r_tlf_pseudocode/01_analysis_models.R', 'ratio = exp(mean_delta),', 'ratio = mean_delta,')],
         'mad/t_accumulation.R',
         'ratio at line'),
    'R13 backticked `geomean` from exp(mean(x))': (
        [(SADF, GEO_LINE, '`geomean` = exp(mean(AVAL[AVAL > 0])),')], 'sad/f_pk_conc_mean.R', None),
    'R14 D04 through across()': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
           'mutate(across(geomean, ~ exp(mean))) %>%')],
         'crossover/t_pk_param_summary.R',
         'geomean at line'),
    'R15 trailing comment before a line that has log(': (
        [(SADF, SAD_GROUPS, '.groups = "drop",\n            geomean = exp(mean(AVAL[AVAL > 0])))   # geometric\n'
          'prof <- prof %>% mutate(lgm = log(geomean)) %>%')], 'sad/f_pk_conc_mean.R', 'geomean at line'),
    'R16 helper geomean = exp(mean(x))': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geomean = if(length(x)) exp(mean(log(x))) else NA_real_,',
           'geomean = exp(mean(x)),')],
         'crossover/t_pk_param_summary.R',
         'relies on the failing pkstats() helper'),
    'R17 helper geomean arithmetic, exp(mean(log())) kept in another column': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geomean = if(length(x)) exp(mean(log(x))) else NA_real_,',
           'lgm = exp(mean(log(x))), geomean = mean(x),')],
         'crossover/t_pk_param_summary.R',
         'relies on the failing pkstats() helper'),
    'R18 helper geocv = sd(log(x))': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,',
           'geocv   = 100 * sd(log(x)),')],
         'crossover/t_pk_param_summary.R',
         'relies on the failing pkstats() helper'),
    'R19 Geo Mean column shows geocv': (
        [(CXP, '`Geo Mean`      = sprintf("%.3g", geomean)', '`Geo Mean`      = sprintf("%.3g", geocv)')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'R20 Geo CV% column shows geomean': (
        [(CXP, '`Geo CV%`       = sprintf("%.1f", geocv)', '`Geo CV%`       = sprintf("%.1f", geomean)')],
        'crossover/t_pk_param_summary.R', '"Geo CV%"'),
    'R21 trough geometric_mean shows geocv computed beside it': ([('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geocv = 100 * sqrt(expm1(var(log(AVAL[AVAL > 0])))), geometric_mean = geocv,')],
         'mad/t_accumulation.R',
         '"geometric_mean" at line'),
    'helper without logs (geomean and geocv)': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geomean = if(length(x)) exp(mean(log(x))) else NA_real_,',
           'geomean = exp(mean(x)),'),
          ('r_tlf_pseudocode/00_setup_helpers.R',
           'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,',
           'geocv   = 100 * sd(x) / mean(x),')],
         'sad/t_pk_param_summary.R',
         'pkstats() FAILS'),
    'comment-only log in R': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])),   # was exp(mean(log(AVAL)))')],
        'parallel/f_pk_conc_mean.R', 'no log() call'),
    'string-literal-only log in R': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])), note = "log(AVAL)",')],
        'parallel/f_pk_conc_mean.R', 'no log() call'),
    'HD1 second pkstats() definition (R runs the last one)': (
        [(R + '/00_setup_helpers.R', '## --- titles / footnotes banner',
          'pkstats <- function(df, var = "AVAL", by) {\n  df %>% group_by(across(all_of(by))) %>%\n'
          '    summarise(geomean = exp(mean(.data[[var]])), geocv = 100 * sd(.data[[var]]) / mean(.data[[var]]),'
          ' .groups = "drop")\n}\n\n## --- titles / footnotes banner')],
        'crossover/t_pk_param_summary.R', 'defined 2 times'),
    'HD2 second %pkstats macro definition (SAS compiles the last one)': (
        [(MAC, '%mend pkstats;',
          '%mend pkstats;\n%macro pkstats(ds=, var=AVAL, class=TRTA PARAMCD, where=%str(1), out=_pk);\n'
          '  proc means data=&ds noprint; class &class; var &var; output out=&out mean=geomean; run;\n%mend pkstats;')],
        MACRO_USER, 'defined 2 times'),
    'S01 data step geomean = exp(amean) next to a %pkstats call': (
        [(SAS + '/crossover/t_ada_impact_pk.sas', '%pkstats(', 'data _x; set _pk; geomean = exp(amean); run;\n%pkstats(')],
        'crossover/t_ada_impact_pk.R', 'SAS geomean = exp(amean)'),
    'S02 geometric PROC MEANS on raw AVAL': (
        [(SAS + '/crossover/t_pk_param_summary.sas', 'class &TRTVAR &TRTNVAR PARAMCD; var logv;',
          'class &TRTVAR &TRTNVAR PARAMCD; var AVAL;')], 'crossover/t_pk_param_summary.R', 'SAS'),
    'S03 macro geomean = amean': (
        [(MAC, 'geomean = exp(meanlog);', 'geomean = amean;')], MACRO_USER, 'the macro FAILS'),
    'S04 data step geomean = exp(amean), log( elsewhere': (
        [(SAS + '/sad/f_pk_conc_mean.sas', 'geomean = exp(gmean_log);', 'geomean = exp(amean);')],
        'sad/f_pk_conc_mean.R', 'SAS geomean = exp(amean)'),
    'S05 macro PROC MEANS var &var instead of logv': (
        [(MAC, 'class &class;  var logv;', 'class &class;  var &var;')], MACRO_USER, 'the macro FAILS'),
    'macro without logs': (
        [(MAC, 'logv=log(&var);', 'logv=&var;')], MACRO_USER, 'the macro FAILS'),
    'comment-only log in SAS (%* macro comment)': (
        [(SAS + '/crossover/t_pk_param_summary.sas', 'if AVAL>0 then logv = log(AVAL);',
          'if AVAL>0 then logv = AVAL; %* was log(AVAL);')], 'crossover/t_pk_param_summary.R', 'SAS'),
    'comment-only log in SAS (* statement after a semicolon)': (
        [(SAS + '/crossover/t_pk_param_summary.sas', 'if AVAL>0 then logv = log(AVAL);',
          'if AVAL>0 then logv = AVAL; * logv was log(AVAL);')], 'crossover/t_pk_param_summary.R', 'SAS'),
    'SAS %pkstats call only inside a %* macro comment': (
        [(SAS + '/crossover/t_ada_impact_pk.sas', '%pkstats(', '%* %pkstats(')], MACRO_USER, 'no passing %pkstats'),
    'SAS %pkstats call only inside a * statement after a semicolon': (
        [(SAS + '/crossover/t_ada_impact_pk.sas', '%pkstats(', 'options nonotes; * %pkstats(')], MACRO_USER,
        'no passing %pkstats'),
    'SAS %pkstats call only inside a /* */ comment': (
        [(SAS + '/crossover/t_ada_impact_pk.sas', '%pkstats(', '/* %pkstats(')], MACRO_USER, 'no passing %pkstats'),
    'comment-only log in SAS (/* */ block)': (
        [(SAS + '/crossover/t_pk_param_summary.sas', 'if AVAL>0 then logv = log(AVAL);',
          'if AVAL>0 then logv = AVAL /* log(AVAL) */;')], 'crossover/t_pk_param_summary.R', 'SAS'),
    'U01 dose proportionality: parameter not logged': ([('r_tlf_pseudocode/01_analysis_models.R',
           'fit <- lm(log(value) ~ log(dose), data = d)',
           'fit <- lm(value ~ log(dose), data = d)')],
         'sad/t_dose_proportionality.R',
         'not log-derived'),
    'U02 BE model fitted on raw AVAL, lnval line kept': ([('r_tlf_pseudocode/01_analysis_models.R',
           'formula <- lnval ~ seq + per + trt + (1 | subj)',
           'formula <- AVAL ~ seq + per + trt + (1 | subj)')],
         'crossover/t_be_anova.R',
         'not log-derived'),
    'U03 exp(mean(x)) under another name (parallel)': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])),')], 'parallel/f_pk_conc_mean.R', 'no log() call'),
    'U04 exp(mean(x)) under another name, footnote reworded': (
        [(SADF, SAD_GEO, 'gm = exp(mean(AVAL[AVAL > 0])),'), (SADF, '"log(concentration) over', '"ln concentration over')],
        'sad/f_pk_conc_mean.R', 'no log() call'),
    'U05 a to_log( call does not count as log(': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])), lab = to_log(1),')], 'parallel/f_pk_conc_mean.R',
        'no log() call'),
    'D04 registry defect (exp(mean) overwrites the pkstats geometric mean)': (d04(), 'crossover/t_pk_param_summary.R', 'geomean at line'),
    # second review, 2026-10-26: wrong orders, fallbacks to the arithmetic mean, the SAS log base
    'N01 trough geometric_mean = mean(exp(log(AVAL))), the arithmetic mean': ([('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geometric_mean = mean(exp(log(AVAL[is.finite(AVAL) & AVAL > 0]))),')],
         'mad/t_accumulation.R',
         '"geometric_mean" at line'),
    'N02 geomean = exp(log(mean(x))), the arithmetic mean': (
        [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))', 'exp(log(mean(AVAL[AVAL > 0])))')], 'sad/f_pk_conc_mean.R',
        'geomean at line'),
    'N03 helper geomean = exp(log(mean(x)))': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geomean = if(length(x)) exp(mean(log(x))) else NA_real_,',
           'geomean = exp(log(mean(x))),')],
         'crossover/t_pk_param_summary.R',
         'pkstats() FAILS'),
    'N04 helper geomean = mean(exp(log(x)))': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geomean = if(length(x)) exp(mean(log(x))) else NA_real_,',
           'geomean = mean(exp(log(x))),')],
         'sad/t_pk_param_summary.R',
         'pkstats() FAILS'),
    'N05 PD trough geomean falls back to the arithmetic mean': ([('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else mean(AVAL),')],
         'mad/t_pd_summary.R',
         '"geometric_mean" at line'),
    'N06 Geo Mean column coalesce(geomean, mean)': (
        [(CXP, CXP_GEO, '`Geo Mean`      = sprintf("%.3g", coalesce(geomean, mean))')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'N07 geomean <- ifelse(n < 3, mean, geomean) after pkstats()': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
           'mutate(geomean = ifelse(n < 3, mean, geomean)) %>%')],
         'crossover/t_pk_param_summary.R',
         'geomean at line'),
    'N08 exp(mean(log(x)) + var(log(x)) / 2), the lognormal estimate of the arithmetic mean': (
        [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))',
          'exp(mean(log(AVAL[AVAL > 0])) + var(log(AVAL[AVAL > 0])) / 2)')], 'sad/f_pk_conc_mean.R', 'geomean at line'),
    'N09 helper geocv with a misplaced parenthesis, 100 * sqrt(exp(v)) - 1': ([('r_tlf_pseudocode/00_setup_helpers.R',
           'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,',
           'geocv   = 100 * sqrt(exp(stats::var(log(x)))) - 1,')],
         'crossover/t_pk_param_summary.R',
         'pkstats() FAILS'),
    'N19 combined Geo Mean (Geo CV%) column shows the arithmetic CV': (
        [(CXP, CXP_GEO, '`Geo Mean (Geo CV%)` = sprintf("%.3g (%.1f)", geomean, cv)')],
        'crossover/t_pk_param_summary.R', '"Geo Mean (Geo CV%)"'),
    'N27 prof[["geomean"]] <- prof[["mean"]]': (
        [(SADF, 'ttl <- tfl_titles(', 'prof[["geomean"]] <- prof[["mean"]]\nttl <- tfl_titles(')],
        'sad/f_pk_conc_mean.R', 'geomean at line'),
    'N28 prof[, "geomean"] <- prof[, "mean"]': (
        [(SADF, 'ttl <- tfl_titles(', 'prof[, "geomean"] <- prof[, "mean"]\nttl <- tfl_titles(')],
        'sad/f_pk_conc_mean.R', 'geomean at line'),
    'combined column pasted from the arithmetic mean (paste0 arguments are all values)': (
        [(CXP, CXP_GEO, '`Geo Mean (Geo CV%)` = paste0(sprintf("%.3g", mean), " (", sprintf("%.1f", geocv), ")")')],
        'crossover/t_pk_param_summary.R', '"Geo Mean (Geo CV%)"'),
    'pmax(geomean, mean, na.rm = TRUE)': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
           'mutate(geomean = pmax(geomean, mean, na.rm = TRUE)) %>%')],
         'crossover/t_pk_param_summary.R',
         'geomean at line'),
    '10^ of a natural-log mean': (
        [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))', '10^mean(log(AVAL[AVAL > 0]))')], 'sad/f_pk_conc_mean.R',
        'geomean at line'),
    'N12 SAS log10 logs back-transformed with exp()': (
        [(SADF_SAS, 'logv = log(AVAL);', 'logv = log10(AVAL);')], 'sad/f_pk_conc_mean.R', 'SAS geomean = exp(gmean_log)'),
    'N13 SAS else fallback geomean = mean': (
        [(CXP_SAS, '  ' + SAS_GM, '  if n>=3 then geomean = exp(gmean_log); else geomean = mean;')],
        'crossover/t_pk_param_summary.R', 'SAS geomean = mean'),
    'SAS when/otherwise fallback geomean = mean': (
        [(CXP_SAS, '  ' + SAS_GM, '  select; when (n>=3) geomean = exp(gmean_log); otherwise geomean = mean; end;')],
        'crossover/t_pk_param_summary.R', 'SAS geomean = mean'),
    'N18 SAS geocv missing the - 1': (
        [(CXP_SAS, SAS_CV, 'geocv   = 100*sqrt(exp(gsd_log**2));')], 'crossover/t_pk_param_summary.R', 'SAS geocv'),
    'SAS log10 logs, 10** mean, but geocv not scaled by log(10)': (
        [(CXP_SAS, 'if AVAL>0 then logv = log(AVAL);', 'if AVAL>0 then logv = log10(AVAL);'),
         (CXP_SAS, SAS_GM, 'geomean = 10**gmean_log;')], 'crossover/t_pk_param_summary.R', 'SAS geocv'),
    'SAS macro geomean = exp(log(amean))': (
        [(MAC, 'geomean = exp(meanlog);', 'geomean = exp(log(amean));')], MACRO_USER, 'the macro FAILS'),
    # third review, 2026-10-26: an assignment of NA (R) or . (SAS) alone made its target geometric
    'E01 empty-data shell row of NA values, Geo Mean column shows the arithmetic mean': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'empty_cont <- tibble(n = 0L, mean = NA_real_, sd = NA_real_, cv = NA_real_, geomean = NA_real_, geocv = '
           'NA_real_)\n'
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%'),
          ('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           '`Geo Mean`      = sprintf("%.3g", geomean)',
           '`Geo Mean`      = sprintf("%.3g", mean)')],
         'crossover/t_pk_param_summary.R',
         '"Geo Mean"'),
    'E02 empty-data shell row of NA values, Geo CV% column shows the arithmetic CV': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'empty_cont <- tibble(n = 0L, mean = NA_real_, sd = NA_real_, cv = NA_real_, geomean = NA_real_, geocv = '
           'NA_real_)\n'
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%'),
          ('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           '`Geo CV%`       = sprintf("%.1f", geocv)',
           '`Geo CV%`       = sprintf("%.1f", cv)')],
         'crossover/t_pk_param_summary.R',
         '"Geo CV%"'),
    'E03 cont$mean[cont$n == 0] <- NA_real_, Geo Mean column shows the arithmetic mean': (
        [(CXP, CXP_TMAX, 'cont$mean[cont$n == 0] <- NA_real_\n' + CXP_TMAX),
         (CXP, CXP_GEO, '`Geo Mean`      = sprintf("%.3g", mean)')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'E04 empty-data shell row, then mutate(geomean = mean, geocv = cv) after pkstats()': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'empty_cont <- tibble(n = 0L, mean = NA_real_, sd = NA_real_, cv = NA_real_, geomean = NA_real_, geocv = '
           'NA_real_)\n'
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
           'mutate(geomean = mean, geocv = cv) %>%')],
         'crossover/t_pk_param_summary.R',
         'geomean at line'),
    'E05 across(c(mean, cv), ~ NA_real_), Geo Mean column shows the arithmetic mean': ([('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
           'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
           'mutate(across(c(mean, cv), ~ NA_real_)) %>%'),
          ('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
           '`Geo Mean`      = sprintf("%.3g", geomean)',
           '`Geo Mean`      = sprintf("%.3g", mean)')],
         'crossover/t_pk_param_summary.R',
         '"Geo Mean"'),
    'E06 SAS if n=0 then mean = .; then the N13 fallback else geomean = mean': (
        [(CXP_SAS, '  ' + SAS_GM, '  if n=0 then mean = .;\n  if n>=3 then geomean = exp(gmean_log); else geomean = mean;')],
        'crossover/t_pk_param_summary.R', 'SAS geomean = mean'),
    'E07 SAS if n<2 then cv = .; then geocv = cv': (
        [(CXP_SAS, SAS_CV, 'if n<2 then cv = .;\n  geocv = cv;')], 'crossover/t_pk_param_summary.R', 'SAS geocv = cv'),
    'E08 SAS mean = round(., 0.01) for empty groups, then geomean = mean': (
        [(CXP_SAS, '  ' + SAS_GM, '  if n=0 then mean = round(., 0.01);\n  geomean = mean;')],
        'crossover/t_pk_param_summary.R', 'SAS geomean = mean'),
    # fourth review, 2026-10-26: a data frame with a log column, or a back-transformed value, still
    # counted as log-derived, so exp(mean(<raw values>)) passed
    'NE2 pull() of raw AVAL from a data frame that carries a log column, piped to mean() and exp()': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  trough <- d %>% transmute(day = ADY, AVAL, ln_tr = log(AVAL))\n'
           '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", trough %>% pull(AVAL) %>% mean() %>% '
           'exp()))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
         'mad/t_accumulation.R',
         '"Overall Trough Geo Mean"'),
    'NE2b exp(mean(trough[["AVAL"]])) from that data frame': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  trough <- d %>% transmute(day = ADY, AVAL, ln_tr = log(AVAL))\n'
           '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", exp(mean(trough[["AVAL"]]))))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
         'mad/t_accumulation.R',
         '"Overall Trough Geo Mean"'),
    'NE2c exp(mean(trough$AVAL)) from that data frame (control)': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  trough <- d %>% transmute(day = ADY, AVAL, ln_tr = log(AVAL))\n'
           '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", exp(mean(trough$AVAL))))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
         'mad/t_accumulation.R',
         '"Overall Trough Geo Mean"'),
    'exp(mean(trough[, "AVAL"])) from that data frame': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  trough <- d %>% transmute(day = ADY, AVAL, ln_tr = log(AVAL))\n'
           '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", exp(mean(trough[, "AVAL"]))))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
         'mad/t_accumulation.R',
         '"Overall Trough Geo Mean"'),
    'select(trough, AVAL) unlisted, then mean() and exp()': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  trough <- d %>% transmute(day = ADY, AVAL, ln_tr = log(AVAL))\n'
           '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", exp(mean(unlist(select(trough, '
           'AVAL))))))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
         'mad/t_accumulation.R',
         '"Overall Trough Geo Mean"'),
    'ND6 geomean = exp(mean(trough[["day"]])), a raw column of that data frame': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  trough <- d %>% transmute(day = ADY, ln_tr = log(AVAL))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise('),
          ('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geometric_mean = exp(mean(trough[["day"]])),')],
         'mad/t_accumulation.R',
         '"geometric_mean" at line'),
    'ND6b base-R subset exp(mean(pp[pp$AVAL > 0, "AVAL"])) of a data frame that carries lnval': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  # Launcher maps the supplied reference/test labels to these canonical labels.',
           '  pp <- pp %>% mutate(lnval = log(AVAL))\n'
           '  gm_all <- exp(mean(pp[pp$AVAL > 0, "AVAL"]))\n'
           '  # Launcher maps the supplied reference/test labels to these canonical labels.'),
          ('r_tlf_pseudocode/01_analysis_models.R',
           'df_method = "Satterthwaite (lmerTest)", status = fitted$status)',
           'df_method = "Satterthwaite (lmerTest)", status = fitted$status, `Geo Mean (all)` = sprintf("%.2f", '
           'gm_all))')],
         'crossover/t_be_anova.R',
         '"Geo Mean (all)"'),
    'ND5 trough back-transformed per record (ctr = exp(ln_tr)), then exp(mean(ctr))': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  d <- d %>% mutate(ln_tr = log(AVAL), ctr = exp(ln_tr))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise('),
          ('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geometric_mean = exp(mean(ctr)),')],
         'mad/t_accumulation.R',
         '"geometric_mean" at line'),
    'exp passed as a function: ctr = sapply(ln_tr, exp), then exp(mean(ctr))': ([('r_tlf_pseudocode/01_analysis_models.R',
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
           '  d <- d %>% mutate(ln_tr = log(AVAL), ctr = sapply(ln_tr, exp))\n'
           '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise('),
          ('r_tlf_pseudocode/01_analysis_models.R',
           'geometric_mean = if (any(is.finite(AVAL) & AVAL > 0)) exp(mean(log(AVAL[is.finite(AVAL) & AVAL > 0]))) '
           'else NA_real_,',
           'geometric_mean = exp(mean(ctr)),')],
         'mad/t_accumulation.R',
         '"geometric_mean" at line'),
    'ND4 ln_ratio = exp(ln_dN - ln_d1), so Rac = exp(mean(raw ratio))': ([('r_tlf_pseudocode/01_analysis_models.R',
           'delta <- log(last[ok]) - log(first[ok]);',
           'delta <- exp(log(last[ok]) - log(first[ok]));')],
         'mad/t_accumulation.R',
         'ratio at line'),
    # fourth review: a program found only by its model left the set when its formula was built from a
    # string or no right-hand-side name matched the dose, treatment, period or sequence pattern
    'ND1 BE model formula built from a string, raw AVAL response': ([('r_tlf_pseudocode/01_analysis_models.R',
           'lmerTest::lmer(formula, data = d, REML = TRUE)',
           'lmerTest::lmer(as.formula("AVAL ~ seq + per + trt + (1 | subj)"), data = d, REML = TRUE)')],
         'crossover/t_be_anova.R',
         'formula not written in code'),
    'ND1b BE model formula from reformulate(..., response = "AVAL")': ([('r_tlf_pseudocode/01_analysis_models.R',
           'lmerTest::lmer(formula, data = d, REML = TRUE)',
           'lmerTest::lmer(reformulate(c("seq", "per", "trt", "(1 | subj)"), response = "AVAL"), data = d, REML = '
           'TRUE)')],
         'crossover/t_be_anova.R',
         'formula not written in code'),
    'ND2 log dose renamed ldose and the dose-proportionality model fitted on raw value': ([('r_tlf_pseudocode/01_analysis_models.R',
           'fit <- lm(log(value) ~ log(dose), data = d)',
           'd <- d %>% mutate(lnval = log(value), ldose = log(dose))\n  fit <- lm(value ~ ldose, data = d)'),
          ('r_tlf_pseudocode/01_analysis_models.R',
           'confint(fit, "log(dose)", level = confidence)',
           'confint(fit, "ldose", level = confidence)')],
         'sad/t_dose_proportionality.R',
         'not log-derived'),
    'ND3 BE model on raw AVAL with terms named sq, pd and form': ([('r_tlf_pseudocode/01_analysis_models.R',
           'lmerTest::lmer(formula, data = d, REML = TRUE)',
           'lmerTest::lmer(AVAL ~ sq + pd + form + (1 | subj), data = d, REML = TRUE)')],
         'crossover/t_be_anova.R',
         'not log-derived'),
    'NF1 string formula in a program found by its geometric statistics': ([('r_tlf_pseudocode/01_analysis_models.R',
           'lmerTest::lmer(log(AVAL) ~ ADY + (1 | USUBJID), data = d, REML = TRUE)',
           'lmerTest::lmer(as.formula("log(AVAL) ~ ADY + (1 | USUBJID)"), data = d, REML = TRUE)')],
         'mad/t_accumulation.R',
         'formula not written in code'),
}

# The model refactor must keep both BE branches and every transitive helper visible.
MODEL = R + '/01_analysis_models.R'
DEFECTS.update({
    'shared BE fixed-sequence branch fitted on raw AVAL': (
        [(MODEL, 'formula <- lnval ~ trt + (1 | subj)', 'formula <- AVAL ~ trt + (1 | subj)')],
        'single_sequence/t_be_anova.R', 'not log-derived'),
    'shared BE geometric ratio loses back-transform': (
        [(MODEL, 'gmr = exp(ci$estimate),', 'gmr = ci$estimate,')],
        'crossover/t_be_anova.R', 'gmr at line'),
    'shared BE lower limit loses back-transform': (
        [(MODEL, 'lower = exp(ci$lower.CL),', 'lower = ci$lower.CL,')],
        'single_sequence/t_be_anova.R', 'lower at line'),
    'shared paired upper limit loses back-transform': (
        [(MODEL, 'upper = exp(mean_delta + half),', 'upper = mean_delta + half,')],
        'mad/t_accumulation.R', 'upper at line'),
    'shared paired helper missing while caller remains': (
        [(MODEL, 'tfl_model_paired <- function(first, last, confidence = .95)',
          'tfl_model_removed_paired <- function(first, last, confidence = .95)')],
        'mad/t_accumulation.R', 'tfl_model_paired has 0 definitions'),
    'shared paired helper redefined after original': (
        [(MODEL, 'tfl_model_trend <- function(d, confidence = .95)',
          'tfl_model_paired <- function(first, last, confidence = .95) tibble(ratio = mean(last / first))\n'
          'tfl_model_trend <- function(d, confidence = .95)')],
        'mad/t_accumulation.R', 'tfl_model_paired has 2 definitions'),
    'shared power response defect reaches the MAD PD caller': (
        [(MODEL, 'fit <- lm(log(value) ~ log(dose), data = d)', 'fit <- lm(value ~ log(dose), data = d)')],
        'mad/t_pd_summary.R', 'not log-derived'),
    'shared power response defect reaches the MAD ADA caller': (
        [(MODEL, 'fit <- lm(log(value) ~ log(dose), data = d)', 'fit <- lm(value ~ log(dose), data = d)')],
        'mad/t_ada_impact_pk.R', 'not log-derived'),
})

# disclosed limits that turn G2 red although the code is correct: id -> (edits, program, text)
LIMITS_RED = {
    'ND1c a correct log-response formula built from a string fails (disclosed)': ([('r_tlf_pseudocode/01_analysis_models.R',
           'lmerTest::lmer(formula, data = d, REML = TRUE)',
           'lmerTest::lmer(as.formula("lnval ~ seq + per + trt + (1 | subj)"), data = d, REML = TRUE)')],
         'crossover/t_be_anova.R',
         'formula not written in code'),
}

VARIANTS = {
    'P01 geomean = 10^mean(log10(x))': [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))', '10^mean(log10(AVAL[AVAL > 0]))')],
    'P02 multi-line exp(': [(SADF, GEO_LINE, 'geomean = exp(\n              mean(log(AVAL[AVAL > 0]))),')],
    'P03 gm = exp(mean(log(x))) then rename(geomean = gm)': [
        (SADF, SAD_GROUPS, 'gm = exp(mean(log(AVAL[AVAL > 0]))),\n            .groups = "drop") %>% rename(geomean = gm) %>%')],
    'P04 geomean from a log-derived column made earlier': [
        (SADF, GEO_LINE, 'geomean = exp(mean(lav)),'),
        (SADF, 'prof <- pc %>%', 'pc <- pc %>% mutate(lav = log(AVAL))\nprof <- pc %>%')],
    'NA_real_ fallback for an empty table': [('r_tlf_pseudocode/01_analysis_models.R',
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
          '  empty_desc <- tibble(n = 0L, geomean = NA_real_, geocv = NA_real_)\n'
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
    'P05 helper geocv as sqrt(exp(sd(log(x))^2) - 1)': [('r_tlf_pseudocode/00_setup_helpers.R',
          'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,',
          'geocv   = 100 * sqrt(exp(sd(log(x))^2) - 1),')],
    'P06 helper closing brace with a trailing comment': [('r_tlf_pseudocode/00_setup_helpers.R',
          '    }) %>% ungroup()\n}\n',
          '    }) %>% ungroup()\n}  # end pkstats\n')],
    'P07 helper closing brace on the last line': [('r_tlf_pseudocode/00_setup_helpers.R', '    }) %>% ungroup()\n}\n', '    }) %>% ungroup() }\n')],
    'P08 %pkstats (ds=...) with a space': [(SAS + '/crossover/t_ada_impact_pk.sas', '%pkstats(', '%pkstats (')],
    'P09 in-program helper defined with logs': [
        (SADF, GEO_LINE, 'geomean = gmean_log(AVAL),'),
        (SADF, 'prof <- pc %>%', 'gmean_log <- function(x) exp(mean(log(x[x > 0])))\nprof <- pc %>%')],
    'geomean rounded in place with <-': [
        (SADF, 'ttl <- tfl_titles(', 'prof$geomean <- signif(prof$geomean, 4)\nttl <- tfl_titles(')],
    'quoted "geomean" column name': [(SADF, GEO_LINE, '"geomean" = exp(mean(log(AVAL[AVAL > 0]))),')],
    'known limit: log(x + c) counts as log-scale (disclosed)': [
        (SADF, 'exp(mean(log(AVAL[AVAL > 0])))', 'exp(mean(log(AVAL + 1)))')],
    'L01 native pipe x |> log() |> mean() |> exp()': [
        (SADF, GEO_LINE, 'geomean = AVAL[AVAL > 0] |> log() |> mean() |> exp(),')],
    'L02 magrittr pipe x %>% log() %>% mean() %>% exp()': [
        (SADF, GEO_LINE, 'geomean = AVAL[AVAL > 0] %>% log() %>% mean() %>% exp(),')],
    'L04 helper geocv as sqrt(expm1(var(log(x))))': [('r_tlf_pseudocode/00_setup_helpers.R',
          'geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,',
          'geocv   = 100 * sqrt(expm1(stats::var(log(x)))),')],
    'combined Geo Mean (Geo CV%) column from geomean and geocv': [
        (CXP, CXP_GEO, '`Geo Mean (Geo CV%)` = sprintf("%.3g (%.1f)", geomean, geocv)')],
    'combined column pasted from geomean and geocv': [
        (CXP, CXP_GEO, '`Geo Mean (Geo CV%)` = paste0(sprintf("%.3g", geomean), " (", sprintf("%.1f", geocv), ")")')],
    'if_else(n >= 3, geomean, NA_real_) after pkstats()': [('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
          'mutate(geomean = if_else(n >= 3, geomean, NA_real_)) %>%')],
    'case_when(n >= 3 ~ geomean, .default = NA_real_) after pkstats()': [('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% '
          'mutate(geomean = case_when(n >= 3 ~ geomean, .default = NA_real_)) %>%')],
    'Geo Mean column rounded with round(geomean, 3)': [
        (CXP, CXP_GEO, '`Geo Mean`      = format(round(geomean, 3), nsmall = 3)')],
    'mean of logs held in a name, then exp(mlog)': [
        (SADF, GEO_LINE, 'mlog = mean(log(AVAL[AVAL > 0])), geomean = exp(mlog),')],
    'L05 SAS geomean = round(exp(gmean_log), 0.001)': [(SADF_SAS, SAS_GM, 'geomean = round(exp(gmean_log), 0.001);')],
    'L06 SAS geomean rounded in a later statement': [
        (SADF_SAS, SAS_GM, 'geomean = exp(gmean_log); geomean = round(geomean, 0.001);')],
    'L07 SAS geocv with gsd_log*gsd_log': [(CXP_SAS, SAS_CV, 'geocv   = 100*sqrt(exp(gsd_log*gsd_log)-1);')],
    'L08 SAS log10 logs back-transformed with 10**': [
        (SADF_SAS, 'logv = log(AVAL);', 'logv = log10(AVAL);'), (SADF_SAS, SAS_GM, 'geomean = 10**gmean_log;')],
    'L09 SAS if/else with missing': [(SADF_SAS, SAS_GM, 'if n>0 then geomean = exp(gmean_log); else geomean = .;')],
    'L09b SAS geomean = gm where gm = exp(gmean_log)': [(SADF_SAS, SAS_GM, 'gm = exp(gmean_log); geomean = gm;')],
    'a name with an NA shell row and a geometric assignment stays geometric': [
        (SADF, GEO_LINE, 'gm = exp(mean(log(AVAL[AVAL > 0]))), geomean = gm,'),
        (SADF, 'prof <- pc %>%', 'empty_prof <- tibble(gm = NA_real_, geomean = NA_real_)\nprof <- pc %>%')],
    'Geo Mean column from a name with a geometric branch and an NA branch': [('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>% mutate(gm = '
          'if_else(n >= 3, geomean, NA_real_)) %>%'),
         ('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
          '`Geo Mean`      = sprintf("%.3g", geomean)',
          '`Geo Mean`      = sprintf("%.3g", gm)')],
    'empty-data shell row next to the unchanged Geo Mean and Geo CV% columns': [('r_tlf_pseudocode/crossover/t_pk_param_summary.R',
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%',
          'empty_cont <- tibble(n = 0L, mean = NA_real_, sd = NA_real_, cv = NA_real_, geomean = NA_real_, geocv = '
          'NA_real_)\n'
          'cont <- pkstats(pp %>% filter(!PARAMCD %in% c("TMAX","TMAXSS")), var = "AVAL", by = by) %>%')],
    'SAS gm missing for empty groups, else exp(gmean_log); geomean = gm': [
        (SADF_SAS, SAS_GM, 'if n=0 then gm = .; else gm = exp(gmean_log); geomean = gm;')],
    'SAS log10 logs with 10** mean and the log(10)-scaled geocv': [
        (CXP_SAS, 'if AVAL>0 then logv = log(AVAL);', 'if AVAL>0 then logv = log10(AVAL);'),
        (CXP_SAS, SAS_GM, 'geomean = 10**gmean_log;'),
        (CXP_SAS, SAS_CV, 'geocv   = 100*sqrt(exp((log(10)*gsd_log)**2)-1);')],
    'pull() of the log column, piped to mean() and exp()': [('r_tlf_pseudocode/01_analysis_models.R',
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
          '  trough <- d %>% transmute(day = ADY, ln_tr = log(AVAL))\n'
          '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", trough %>% pull(ln_tr) %>% mean() %>% '
          'exp()))\n'
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
    'exp(mean(trough[["ln_tr"]])) of the log column': [('r_tlf_pseudocode/01_analysis_models.R',
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
          '  trough <- d %>% transmute(day = ADY, ln_tr = log(AVAL))\n'
          '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", exp(mean(trough[["ln_tr"]]))))\n'
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
    'exp(mean(trough[, "ln_tr"])) of the log column': [('r_tlf_pseudocode/01_analysis_models.R',
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(',
          '  trough <- d %>% transmute(day = ADY, ln_tr = log(AVAL))\n'
          '  overall <- tibble(`Overall Trough Geo Mean` = sprintf("%.3g", exp(mean(trough[, "ln_tr"]))))\n'
          '  summary <- d %>% group_by(TRT01A, ADY) %>% summarise(')],
    'ND2b log dose renamed ldose (the program stays in the set and passes)': [('r_tlf_pseudocode/01_analysis_models.R',
          'fit <- lm(log(value) ~ log(dose), data = d)',
          'd <- d %>% mutate(lnval = log(value), ldose = log(dose))\n  fit <- lm(lnval ~ ldose, data = d)'),
         ('r_tlf_pseudocode/01_analysis_models.R',
          'confint(fit, "log(dose)", level = confidence)',
          'confint(fit, "ldose", level = confidence)')],
    'BE model terms renamed sq, pd and form, log response (stays in the set: it reads ADPP)': [('r_tlf_pseudocode/01_analysis_models.R',
          'lmerTest::lmer(formula, data = d, REML = TRUE)',
          'lmerTest::lmer(lnval ~ sq + pd + form + (1 | subj), data = d, REML = TRUE)')],
    'BE model formula held in a name': [('r_tlf_pseudocode/01_analysis_models.R',
          '    fitted <- tfl_model_fit(function() lmerTest::lmer(formula, data = d, REML = TRUE))',
          '    f_be <- lnval ~ seq + per + trt + (1 | subj)\n'
          '    fitted <- tfl_model_fit(function() lmerTest::lmer(f_be, data = d, REML = TRUE))')],
}


def load_g2():
    spec = importlib.util.spec_from_file_location('g2_geo', CHECK)
    g2 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(g2)
    return g2


class G2GeoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='g2geo-')
        for d in (R, SAS):
            shutil.copytree(os.path.join(REPO, d), os.path.join(cls.tmp, d))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_check(self):
        out = subprocess.run([sys.executable, CHECK, os.path.join(self.tmp, R), os.path.join(self.tmp, SAS)],
                             capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        ok, n, ev = out.stdout.strip().split(' ', 2)
        self.assertTrue(ev.startswith(f'{ok} of {n} '), 'the evidence count must be the gating count')
        return int(ok), int(n), ev

    def planted(self, edits):
        """apply edits (each old text must occur once), run the check, restore the files"""
        saved = {}
        try:
            for f, old, new in edits:
                p = os.path.join(self.tmp, f)
                if p not in saved:
                    with open(p, encoding='utf-8', newline='') as fh:
                        saved[p] = fh.read()
                with open(p, encoding='utf-8', newline='') as fh:
                    t = fh.read()
                self.assertEqual(t.count(old), 1, f'{f}: the text to replace must occur exactly once: {old!r}')
                with open(p, 'w', encoding='utf-8', newline='') as fh:
                    fh.write(t.replace(old, new))
            return self.run_check()
        finally:
            for p, t in saved.items():
                with open(p, 'w', encoding='utf-8', newline='') as fh:
                    fh.write(t)

    def test_unmodified_tree_passes(self):
        ok, n, ev = self.run_check()
        self.assertEqual((ok, n), (len(EXPECTED), len(EXPECTED)), ev)
        self.assertNotIn('failing', ev)

    def test_program_set_is_derived_from_content(self):
        g2 = load_g2()
        found = [rel.replace(os.sep, '/') for rel, _, _ in g2.find_programs(os.path.join(self.tmp, R))]
        self.assertEqual(found, EXPECTED)

    def test_na_only_assignments_make_no_geometric_name(self):
        """names the library assigns only NA (R) or . (SAS) are not geometric; real ones still are"""
        g2 = load_g2()
        functions = g2.shared_model_functions(os.path.join(self.tmp, R))
        paired = functions['tfl_model_paired'][0].ctx
        trough = functions['tfl_model_trough'][0].ctx
        trend = functions['tfl_model_trend'][0].ctx
        for ctx in (paired, trough, trend):
            for names in (ctx.G, ctx.GCV):
                self.assertFalse({'mean', 'slope', 'n', 'beta', 'lcl90', 'ucl90', 'ss_attained'} & names, names)
        self.assertIn('ratio', paired.G)
        self.assertIn('geometric_mean', trough.G)
        helper = g2.RFile(os.path.join(self.tmp, HELP)).ctx
        self.assertIn('geocv', helper.GCV)
        accumulation = g2.RProgram(os.path.join(self.tmp, ACC), functions)
        self.assertTrue({'tfl_model_paired', 'tfl_model_trough', 'tfl_model_trend'} <= set(accumulation.dependencies))
        pd = g2.RProgram(os.path.join(self.tmp, PD), functions)
        self.assertIn('tfl_model_trough', pd.dependencies)
        for f, var in (('crossover/f_pk_conc_mean.sas', 'lo'), ('crossover/t_be_anova.sas', 'intracv')):
            sc = g2.SasCode(g2.sas_code(os.path.join(self.tmp, SAS, f)))
            g = sc.aliases(lambda ex, names: g2.sas_mean_ok(ex, sc.GM, names), {'geomean'})
            gcv = sc.aliases(lambda ex, names: g2.sas_cv_ok(ex, sc.LSD, sc.LV, names), {'geocv'})
            self.assertNotIn(var, g | gcv, f)

    def test_every_review_defect_is_caught(self):
        base_n = len(EXPECTED)
        for name, (edits, prog, text) in DEFECTS.items():
            with self.subTest(name):
                ok, n, ev = self.planted(edits)
                self.assertEqual(n, base_n, ev)
                self.assertLess(ok, n, f'{name} was not caught: {ev}')
                failing = ev.split('; failing: ', 1)[1] if '; failing: ' in ev else ''
                self.assertIn(prog, failing, ev)
                if text:
                    self.assertIn(text, ev)

    def test_disclosed_limits_that_fail(self):
        for name, (edits, prog, text) in LIMITS_RED.items():
            with self.subTest(name):
                ok, n, ev = self.planted(edits)
                self.assertEqual(n, len(EXPECTED), ev)
                self.assertLess(ok, n, ev)
                self.assertIn(prog, ev.split('; failing: ', 1)[1], ev)
                self.assertIn(text, ev)

    def test_floor_matches_the_program_set(self):
        self.assertEqual(load_g2().FLOOR, len(EXPECTED))

    def test_set_below_the_floor_fails(self):
        """a program that leaves the set (here deleted with its twin) counts as failing"""
        moved = []
        try:
            for d, ext in ((R, '.R'), (SAS, '.sas')):
                p = os.path.join(self.tmp, d, 'crossover', 't_be_anova' + ext)
                os.rename(p, p + '.off')
                moved.append(p)
            ok, n, ev = self.run_check()
            self.assertEqual((ok, n), (len(EXPECTED) - 1, len(EXPECTED)), ev)
            self.assertIn(f'{len(EXPECTED) - 1} found by content', ev)
            self.assertIn('committed floor', ev.split('; failing: ', 1)[1])
        finally:
            for p in moved:
                os.rename(p + '.off', p)

    def test_model_program_with_unreadable_formula_joins_the_set(self):
        """a new program whose only model has a formula built from a string is checked and fails"""
        p = os.path.join(self.tmp, R, 'sad', 't_new_model.R')
        q = os.path.join(self.tmp, SAS, 'sad', 't_new_model.sas')
        try:
            with open(p, 'w', encoding='utf-8') as fh:
                fh.write('m <- lm(as.formula(paste("AVAL", "~ x")), data = d)\n')
            with open(q, 'w', encoding='utf-8') as fh:
                fh.write('proc mixed data=d; model logv = x; run;\n')
            ok, n, ev = self.run_check()
            self.assertEqual((ok, n), (len(EXPECTED), len(EXPECTED) + 1), ev)
            self.assertIn('sad/t_new_model.R (model at line 1: ' + FORMULA_TEXT, ev)
        finally:
            for f in (p, q):
                if os.path.exists(f):
                    os.remove(f)

    def test_legitimate_variants_pass(self):
        for name, edits in VARIANTS.items():
            with self.subTest(name):
                ok, n, ev = self.planted(edits)
                self.assertEqual((ok, n), (len(EXPECTED), len(EXPECTED)), f'{name} turned G2 red: {ev}')

    def test_new_program_without_logs_is_picked_up(self):
        p = os.path.join(self.tmp, R, 'sad', 't_new_geo.R')
        q = os.path.join(self.tmp, SAS, 'sad', 't_new_geo.sas')
        try:
            with open(p, 'w', encoding='utf-8') as fh:
                fh.write('x <- pp %>% summarise(geomean = exp(mean(AVAL)))\n')
            with open(q, 'w', encoding='utf-8') as fh:
                fh.write('data x; set pp; run;\n')
            ok, n, ev = self.run_check()
            self.assertEqual(n, len(EXPECTED) + 1, ev)
            self.assertIn('sad/t_new_geo.R', ev)
            self.assertEqual(ok, len(EXPECTED), ev)
        finally:
            for f in (p, q):
                if os.path.exists(f):
                    os.remove(f)

    def test_shared_helper_discovery_uses_actual_call_graph(self):
        """Uncalled bodies do not contaminate callers; a new actual call enters the checked set."""
        helper = os.path.join(self.tmp, R, '01_analysis_models.R')
        wrapper = os.path.join(self.tmp, R, 'sad', 't_new_shared_geo.R')
        twin = os.path.join(self.tmp, SAS, 'sad', 't_new_shared_geo.sas')
        with open(helper, 'rb') as stream:
            saved = stream.read()
        try:
            with open(helper, 'ab') as stream:
                stream.write(b'\ntfl_model_unused <- function(d) {\n'
                             b'  d %>% summarise(geomean = exp(mean(AVAL)))\n}\n')
            ok, n, ev = self.run_check()
            self.assertEqual((ok, n), (len(EXPECTED), len(EXPECTED)), ev)
            with open(wrapper, 'w', encoding='utf-8') as stream:
                stream.write('result <- tfl_model_unused(d)\n')
            with open(twin, 'w', encoding='utf-8') as stream:
                stream.write('data result; set d; geomean = exp(AVAL); run;\n')
            ok, n, ev = self.run_check()
            self.assertEqual((ok, n), (len(EXPECTED), len(EXPECTED) + 1), ev)
            self.assertIn('sad/t_new_shared_geo.R', ev.split('; failing: ', 1)[1])
            self.assertIn('01_analysis_models.R::tfl_model_unused', ev)
        finally:
            with open(helper, 'wb') as stream:
                stream.write(saved)
            for path in (wrapper, twin):
                if os.path.exists(path):
                    os.remove(path)

    def test_missing_sas_twin_fails(self):
        p = os.path.join(self.tmp, SAS, 'sad', 't_pk_conc_summary.sas')
        os.rename(p, p + '.off')
        try:
            ok, n, ev = self.run_check()
            self.assertLess(ok, n)
            self.assertIn('sad/t_pk_conc_summary.R (no SAS twin at the same path)', ev)
        finally:
            os.rename(p + '.off', p)


if __name__ == '__main__':
    unittest.main()
