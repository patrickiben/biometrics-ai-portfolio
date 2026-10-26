#!/usr/bin/env python3
"""Unit tests for validation_harness/checks/g2_geo.py (Python standard library only).

setUpClass copies r_tlf_pseudocode and sas_tlf_pseudocode to a temporary folder. Each case plants
one change in that copy (exact text that must occur exactly once), runs the check the way
run_harness.sh does (python3 g2_geo.py <R dir> <SAS dir>), restores the file and asserts:
  - the unmodified libraries pass every program;
  - every planted defect turns G2 red and names the program it is in;
  - every legitimate variant stays green.
The defect cases are the ones found in the two 2026-10-26 reviews of the per-program G2 (R01 to
R18, S01 to S05, U01 to U05; then N01 to N08, N12 and N13, with N09, N18, N19, N27 and N28 from
the same probe), registry defect D04, a pkstats() helper and a %pkstats macro without logs, and
logs that appear only in comments or string literals. The legitimate variants include P01 to
P09 and L01, L02, L04 to L09 from the reviews. The known limit (log(x + c) counts as log-scale)
is pinned as a passing case so the docs and the code cannot drift apart.

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
CXP_PKSTATS = 'cont <- pkstats(pp %>% filter(PARAMCD != "TMAX"), var = "AVAL", by = by) %>%'
SAS_GM = 'geomean = exp(gmean_log);'
SAS_CV = 'geocv   = 100*sqrt(exp(gsd_log**2)-1);'
SAD_GEO = 'geomean = exp(mean(log(AVAL[AVAL > 0]))),      # geometric (semi-log panel)'
SAD_GROUPS = SAD_GEO + '\n            .groups = "drop") %>%'
HELP_GM = 'geomean = exp(mean(log(.data[[var]]))),'
HELP_CV = 'geocv   = 100 * sqrt(exp(stats::var(log(.data[[var]]))) - 1),'
PKSTATS_USERS = 'relies on the failing pkstats() helper'
MACRO_USER = 'crossover/t_ada_impact_pk.R'


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
    'R10 mean of logs reported without exp()': (
        [(ACC, 'geomean  = exp(mean(ln_tr)),', 'geomean  = mean(ln_tr),')], 'mad/t_accumulation.R', 'geomean at line'),
    'R11 geocv from the raw scale': (
        [(ACC, 'geocv    = 100 * sqrt(exp(stats::var(ln_tr)) - 1),',
          'geocv    = 100 * sd(exp(ln_tr)) / mean(exp(ln_tr)),')], 'mad/t_accumulation.R', 'geocv at line'),
    'R12 Rac without the back-transform': (
        [(ACC, 'rac   = exp(mlogr),', 'rac   = mlogr,')], 'mad/t_accumulation.R', '"Rac (Geo Mean)"'),
    'R13 backticked `geomean` from exp(mean(x))': (
        [(SADF, GEO_LINE, '`geomean` = exp(mean(AVAL[AVAL > 0])),')], 'sad/f_pk_conc_mean.R', None),
    'R14 D04 through across()': (
        [(CXP, 'cont <- pkstats(pp %>% filter(PARAMCD != "TMAX"), var = "AVAL", by = by) %>%',
          'cont <- pkstats(pp %>% filter(PARAMCD != "TMAX"), var = "AVAL", by = by) %>% '
          'mutate(across(geomean, ~ exp(mean))) %>%')], 'crossover/t_pk_param_summary.R', 'geomean at line'),
    'R15 trailing comment before a line that has log(': (
        [(SADF, SAD_GROUPS, '.groups = "drop",\n            geomean = exp(mean(AVAL[AVAL > 0])))   # geometric\n'
          'prof <- prof %>% mutate(lgm = log(geomean)) %>%')], 'sad/f_pk_conc_mean.R', 'geomean at line'),
    'R16 helper geomean = exp(mean(x))': (
        [(HELP, HELP_GM, 'geomean = exp(mean(.data[[var]])),')], 'crossover/t_pk_param_summary.R', PKSTATS_USERS),
    'R17 helper geomean arithmetic, exp(mean(log())) kept in another column': (
        [(HELP, HELP_GM, 'lgm = exp(mean(log(.data[[var]]))), geomean = mean(.data[[var]]),')],
        'crossover/t_pk_param_summary.R', PKSTATS_USERS),
    'R18 helper geocv = sd(log(x))': (
        [(HELP, HELP_CV, 'geocv   = 100 * sd(log(.data[[var]])),')], 'crossover/t_pk_param_summary.R', PKSTATS_USERS),
    'R19 Geo Mean column shows geocv': (
        [(CXP, '`Geo Mean`      = sprintf("%.3g", geomean)', '`Geo Mean`      = sprintf("%.3g", geocv)')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'R20 Geo CV% column shows geomean': (
        [(CXP, '`Geo CV%`       = sprintf("%.1f", geocv)', '`Geo CV%`       = sprintf("%.1f", geomean)')],
        'crossover/t_pk_param_summary.R', '"Geo CV%"'),
    'R21 Trough Geo Mean column shows geocv, which the program computes': (
        [(ACC, '`Trough Geo Mean` = sprintf("%.3g", geomean)', '`Trough Geo Mean` = sprintf("%.3g", geocv)')],
        'mad/t_accumulation.R', '"Trough Geo Mean"'),
    'helper without logs (geomean and geocv)': (
        [(HELP, HELP_GM, 'geomean = exp(mean(.data[[var]])),'),
         (HELP, HELP_CV, 'geocv   = 100 * sd(.data[[var]]) / mean(.data[[var]]),')],
        'sad/t_pk_param_summary.R', 'pkstats() FAILS'),
    'comment-only log in R': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])),   # was exp(mean(log(AVAL)))')],
        'parallel/f_pk_conc_mean.R', 'no log() call'),
    'string-literal-only log in R': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])), note = "log(AVAL)",')],
        'parallel/f_pk_conc_mean.R', 'no log() call'),
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
    'U01 dose proportionality: parameter not logged': (
        [(R + '/sad/t_dose_proportionality.R', 'mutate(lnval  = log(AVAL),', 'mutate(lnval  = AVAL,')],
        'sad/t_dose_proportionality.R', 'not log-derived'),
    'U02 BE model fitted on raw AVAL, lnval line kept': (
        [(R + '/crossover/t_be_anova.R', 'lmer(lnval ~ seq', 'lmer(AVAL ~ seq')], 'crossover/t_be_anova.R',
        'not log-derived'),
    'U03 exp(mean(x)) under another name (parallel)': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])),')], 'parallel/f_pk_conc_mean.R', 'no log() call'),
    'U04 exp(mean(x)) under another name, footnote reworded': (
        [(SADF, SAD_GEO, 'gm = exp(mean(AVAL[AVAL > 0])),'), (SADF, '"log(concentration) over', '"ln concentration over')],
        'sad/f_pk_conc_mean.R', 'no log() call'),
    'U05 a to_log( call does not count as log(': (
        [(PARF, GEO_LINE, 'gm = exp(mean(AVAL[AVAL > 0])), lab = to_log(1),')], 'parallel/f_pk_conc_mean.R',
        'no log() call'),
    'D04 registry defect (exp(mean) overwrites the pkstats geometric mean)': (
        d04(), 'crossover/t_pk_param_summary.R', 'geomean at line'),
    # second review, 2026-10-26: wrong orders, fallbacks to the arithmetic mean, the SAS log base
    'N01 trough geomean = mean(exp(ln_tr)), the arithmetic mean': (
        [(ACC, 'geomean  = exp(mean(ln_tr)),', 'geomean  = mean(exp(ln_tr)),')], 'mad/t_accumulation.R',
        'geomean at line'),
    'N02 geomean = exp(log(mean(x))), the arithmetic mean': (
        [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))', 'exp(log(mean(AVAL[AVAL > 0])))')], 'sad/f_pk_conc_mean.R',
        'geomean at line'),
    'N03 helper geomean = exp(log(mean(x)))': (
        [(HELP, HELP_GM, 'geomean = exp(log(mean(.data[[var]]))),')], 'crossover/t_pk_param_summary.R',
        'pkstats() FAILS'),
    'N04 helper geomean = mean(exp(log(x)))': (
        [(HELP, HELP_GM, 'geomean = mean(exp(log(.data[[var]]))),')], 'sad/t_pk_param_summary.R', 'pkstats() FAILS'),
    'N05 PD trough geomean falls back to the arithmetic mean': (
        [(PD, 'exp(mean(log(AVAL))) else NA_real_,', 'exp(mean(log(AVAL))) else mean(AVAL),')], 'mad/t_pd_summary.R',
        'geomean at line'),
    'N06 Geo Mean column coalesce(geomean, mean)': (
        [(CXP, CXP_GEO, '`Geo Mean`      = sprintf("%.3g", coalesce(geomean, mean))')],
        'crossover/t_pk_param_summary.R', '"Geo Mean"'),
    'N07 geomean <- ifelse(n < 3, mean, geomean) after pkstats()': (
        [(CXP, CXP_PKSTATS, CXP_PKSTATS[:-4] + ' %>% mutate(geomean = ifelse(n < 3, mean, geomean)) %>%')],
        'crossover/t_pk_param_summary.R', 'geomean at line'),
    'N08 exp(mean(log(x)) + var(log(x)) / 2), the lognormal estimate of the arithmetic mean': (
        [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))',
          'exp(mean(log(AVAL[AVAL > 0])) + var(log(AVAL[AVAL > 0])) / 2)')], 'sad/f_pk_conc_mean.R', 'geomean at line'),
    'N09 helper geocv with a misplaced parenthesis, 100 * sqrt(exp(v)) - 1': (
        [(HELP, HELP_CV, 'geocv   = 100 * sqrt(exp(stats::var(log(.data[[var]])))) - 1,')],
        'crossover/t_pk_param_summary.R', 'pkstats() FAILS'),
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
    'pmax(geomean, mean, na.rm = TRUE)': (
        [(CXP, CXP_PKSTATS, CXP_PKSTATS[:-4] + ' %>% mutate(geomean = pmax(geomean, mean, na.rm = TRUE)) %>%')],
        'crossover/t_pk_param_summary.R', 'geomean at line'),
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
}

VARIANTS = {
    'P01 geomean = 10^mean(log10(x))': [(SADF, 'exp(mean(log(AVAL[AVAL > 0])))', '10^mean(log10(AVAL[AVAL > 0]))')],
    'P02 multi-line exp(': [(SADF, GEO_LINE, 'geomean = exp(\n              mean(log(AVAL[AVAL > 0]))),')],
    'P03 gm = exp(mean(log(x))) then rename(geomean = gm)': [
        (SADF, SAD_GROUPS, 'gm = exp(mean(log(AVAL[AVAL > 0]))),\n            .groups = "drop") %>% rename(geomean = gm) %>%')],
    'P04 geomean from a log-derived column made earlier': [
        (SADF, GEO_LINE, 'geomean = exp(mean(lav)),'),
        (SADF, 'prof <- pc %>%', 'pc <- pc %>% mutate(lav = log(AVAL))\nprof <- pc %>%')],
    'NA_real_ fallback for an empty table': [
        (ACC, '## --- descriptive trough trend per cohort x dosing day (geometric) ----------',
         '## --- descriptive trough trend per cohort x dosing day (geometric) ----------\n'
         'empty_desc <- tibble(n = 0L, geomean = NA_real_, geocv = NA_real_)')],
    'P05 helper geocv as sqrt(exp(sd(log(x))^2) - 1)': [
        (HELP, HELP_CV, 'geocv   = 100 * sqrt(exp(sd(log(.data[[var]]))^2) - 1),')],
    'P06 helper closing brace with a trailing comment': [
        (HELP, '      .groups = "drop")\n}\n', '      .groups = "drop")\n}  # end pkstats\n')],
    'P07 helper closing brace on the last line': [(HELP, '      .groups = "drop")\n}\n', '      .groups = "drop") }\n')],
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
    'L04 helper geocv as sqrt(expm1(var(log(x))))': [
        (HELP, HELP_CV, 'geocv   = 100 * sqrt(expm1(stats::var(log(.data[[var]])))),')],
    'combined Geo Mean (Geo CV%) column from geomean and geocv': [
        (CXP, CXP_GEO, '`Geo Mean (Geo CV%)` = sprintf("%.3g (%.1f)", geomean, geocv)')],
    'combined column pasted from geomean and geocv': [
        (CXP, CXP_GEO, '`Geo Mean (Geo CV%)` = paste0(sprintf("%.3g", geomean), " (", sprintf("%.1f", geocv), ")")')],
    'if_else(n >= 3, geomean, NA_real_) after pkstats()': [
        (CXP, CXP_PKSTATS, CXP_PKSTATS[:-4] + ' %>% mutate(geomean = if_else(n >= 3, geomean, NA_real_)) %>%')],
    'case_when(n >= 3 ~ geomean, .default = NA_real_) after pkstats()': [
        (CXP, CXP_PKSTATS, CXP_PKSTATS[:-4] + ' %>% mutate(geomean = case_when(n >= 3 ~ geomean, '
         '.default = NA_real_)) %>%')],
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
    'SAS log10 logs with 10** mean and the log(10)-scaled geocv': [
        (CXP_SAS, 'if AVAL>0 then logv = log(AVAL);', 'if AVAL>0 then logv = log10(AVAL);'),
        (CXP_SAS, SAS_GM, 'geomean = 10**gmean_log;'),
        (CXP_SAS, SAS_CV, 'geocv   = 100*sqrt(exp((log(10)*gsd_log)**2)-1);')],
}


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
        spec = importlib.util.spec_from_file_location('g2_geo', CHECK)
        g2 = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(g2)
        found = [rel.replace(os.sep, '/') for rel, _, _ in g2.find_programs(os.path.join(self.tmp, R))]
        self.assertEqual(found, EXPECTED)

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
