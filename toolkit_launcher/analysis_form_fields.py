"""Study-specific controls shared by both open-source analysis entry points."""
import math
import re

DOSE_OUTPUTS = {
    ('sad', 't_dose_proportionality'), ('mad', 't_dose_proportionality_ss'),
    ('mad', 't_accumulation'), ('mad', 't_pd_summary'), ('mad', 't_ada_impact_pk'),
    *{(d, s) for d in ('sad', 'mad') for s in ('t_cqtc_hysteresis', 'f_cqtc_hysteresis')},
}


def fields(make):
    f = make
    reporting = [
        f('related_values', 'Related AE source values', default='RELATED, POSSIBLE, PROBABLE, DEFINITE', description='Comma-separated AREL values classified as related. Use the prespecified study relationship categories.'),
        f('baseline_continuous', 'Continuous baseline columns', default='SBPBL, DBPBL, PULSEBL', description='Comma-separated numeric ADSL column identifiers (including study-specific covariates) for the baseline characteristics table. Leave blank if none.'),
        f('baseline_categorical', 'Categorical baseline columns', default='SMOKSTAT, ALCOHOL', description='Comma-separated categorical ADSL column identifiers (including study-specific covariates) for the baseline characteristics table. Leave blank if none.'),
        f('lab_grade_min', 'Minimum laboratory toxicity grade to flag', 'number', 3, min=0, max=10, step=1),
        f('lab_high_limits', 'Marked high laboratory limits', 'textarea', 'ALT=3\nAST=3\nBILI=2\nALP=3\nCREAT=1.5\nBUN=2\nGLUC=1.5\nK=1.1\nNA=1.05\nHGB=1.2\nWBC=2\nPLAT=1.5', description='One PARAMCD=multiple of ULN per line. Prespecify clinical thresholds; these are editable examples.'),
        f('lab_low_limits', 'Marked low laboratory limits', 'textarea', '\n'.join(p+'=0.5' for p in ('ALT','AST','BILI','ALP','CREAT','BUN','GLUC','K','NA','HGB','WBC','PLAT')), description='One PARAMCD=multiple of LLN per line. Prespecify clinical thresholds; these are editable examples.'),
    ]
    model = [
        f('pk_parameters', 'PK model parameters', default='CMAX, AUCLST, AUCIFO', description='Comma-separated PARAMCD values for BE and single-dose power models.'),
        f('mad_pk_parameters', 'MAD PK model parameters', default='CMAXSS, AUCTAU'),
        f('ada_rac_parameters', 'ADA accumulation ratio parameters', default='RACMAX, RACAUC'),
        f('dose_map', 'Actual doses by treatment label', 'textarea', '', description='Required for dose, accumulation, MAD PD/ADA and concentration–QTc models. One exact source treatment label=actual numeric dose per line. Include placebo=0 where present; treatment ordering codes are not doses.'),
        f('dose_unit', 'Common dose unit', default='mg'),
        f('placebo_label', 'Placebo treatment label', default='Placebo', description='SAD ADA comparisons exclude this source treatment label. Concentration–QTc requires this label at zero dose and active treatments at positive doses.'),
        f('be_confidence', 'BE confidence level', 'number', .9, min=.000001, max=.999999, step=.01),
        f('be_lower', 'Lower BE ratio bound', 'number', .8, min=.000001, max=.999999),
        f('be_upper', 'Upper BE ratio bound', 'number', 1.25, min=1.000001, max=10000),
        f('dose_confidence', 'Dose-model confidence level', 'number', .9, min=.000001, max=.999999, step=.01),
        f('dose_lower', 'Lower dose-proportionality ratio bound', 'number', .8, min=.000001, max=.999999),
        f('dose_upper', 'Upper dose-proportionality ratio bound', 'number', 1.25, min=1.000001, max=10000),
        f('analysis_day', 'Selected MAD analysis day', 'number', 14, min=1, max=10000, step=1),
        f('accumulation_first_day', 'First accumulation comparison day', 'number', 1, min=1, max=10000, step=1),
        f('accumulation_last_day', 'Last accumulation comparison day', 'number', 14, min=1, max=10000, step=1),
        f('accumulation_cmax_first', 'First-day Cmax PARAMCD', default='CMAX'),
        f('accumulation_cmax_last', 'Last-day Cmax PARAMCD', default='CMAXSS'),
        f('accumulation_auc_first', 'First-day AUC PARAMCD', default='AUCLST'),
        f('accumulation_auc_last', 'Last-day AUC PARAMCD', default='AUCTAU'),
        f('accumulation_auc_comparable', 'I confirm the first/last AUC intervals are comparable', 'checkbox', False, description='The AUC ratio is withheld until comparable integration intervals are confirmed. Cmax ratios can still be computed.'),
        f('accumulation_confidence', 'Accumulation confidence level', 'number', .95, min=.000001, max=.999999, step=.01),
        f('trough_last_day', 'Last trough assessment day', 'number', 14, min=1, max=10000, step=1),
    ]
    return reporting, model


def mapping(text, key, error, *, parameter=False):
    if not isinstance(text, str) or len(text) > 16000:
        error(key, 'Use a text list of at most 16000 characters.'); return {}
    result = {}
    for line in text.splitlines():
        if not line.strip(): continue
        parts = line.rsplit('=', 1)
        if len(parts) != 2:
            error(key, 'Use one label=number entry per line.'); continue
        label, raw = (part.strip() for part in parts)
        try:
            number = float(raw)
            if not label or len(label) > 200 or any(ord(c) < 32 for c in label) or label in result or not math.isfinite(number) or number < 0:
                raise ValueError()
            if parameter and not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]{0,39}', label): raise ValueError()
            result[label] = number
        except (ValueError, OverflowError):
            error(key, 'Use unique nonempty labels and finite nonnegative numbers.')
    return result


def active_fields(v):
    outputs, design = set(v.get('outputs', [])), v.get('design')
    keys = set()
    if 't_baseline_characteristics' in outputs: keys.update(('baseline_continuous', 'baseline_categorical'))
    if any('ae' in s for s in outputs): keys.add('related_values')
    if any('lab' in s for s in outputs): keys.update(('lab_grade_min', 'lab_high_limits', 'lab_low_limits'))
    if 't_be_anova' in outputs: keys.update(('pk_parameters', 'be_confidence', 'be_lower', 'be_upper'))
    if any((design, s) in DOSE_OUTPUTS for s in outputs): keys.update(('dose_map', 'dose_unit', 'dose_confidence', 'dose_lower', 'dose_upper'))
    if any('cqtc_hysteresis' in s for s in outputs) or design == 'sad' and 't_ada_impact_pk' in outputs: keys.add('placebo_label')
    if design == 'sad' and 't_dose_proportionality' in outputs: keys.add('pk_parameters')
    if design == 'mad' and outputs & {'t_dose_proportionality_ss', 't_ada_impact_pk'}: keys.update(('mad_pk_parameters', 'analysis_day'))
    if design == 'mad' and 't_pd_summary' in outputs: keys.update(('analysis_day', 'trough_last_day'))
    if design == 'mad' and 't_ada_impact_pk' in outputs: keys.add('ada_rac_parameters')
    if 't_accumulation' in outputs:
        keys.update(('accumulation_first_day', 'accumulation_last_day', 'accumulation_cmax_first', 'accumulation_cmax_last', 'accumulation_auc_first', 'accumulation_auc_last', 'accumulation_auc_comparable', 'accumulation_confidence', 'trough_last_day'))
    return keys


def normalize(v, error, adsl_columns, numeric):
    """Normalize finite form values before constructing dynamic input contracts."""
    active = active_fields(v)
    for key in ('baseline_continuous', 'baseline_categorical', 'pk_parameters', 'mad_pk_parameters', 'ada_rac_parameters'):
        if key not in active: continue
        text = v.get(key)
        if not isinstance(text, str) or len(text) > 1000:
            error(key, 'Use a comma-separated list of column/parameter identifiers.'); v[key] = ''; continue
        codes = list(dict.fromkeys(x.strip().upper() for x in text.split(',') if x.strip()))
        if any(not re.fullmatch(r'[A-Z][A-Z0-9_]{0,39}', x) for x in codes):
            error(key, 'Use canonical identifiers separated by commas.'); codes = []
        if len(codes) > 100: error(key, 'Select at most 100 columns or parameters.')
        if not key.startswith('baseline_') and not codes:
            error(key, 'Select at least one parameter code.')
        v[key] = ', '.join(codes)
    if 'baseline_continuous' in active and not v.get('baseline_continuous') and not v.get('baseline_categorical'):
        error('baseline_continuous', 'Choose at least one continuous or categorical baseline column.')
    if 'baseline_continuous' in active:
        continuous = set(v['baseline_continuous'].split(', ')) - {''}
        categorical = set(v['baseline_categorical'].split(', ')) - {''}
        if continuous & categorical: error('baseline_categorical', 'A baseline column cannot be both continuous and categorical.')
        if (continuous & (adsl_columns - numeric)) or (categorical & numeric): error('baseline_continuous', 'Existing canonical ADSL columns must retain their declared numeric or character type.')
    for key in ('dose_unit', 'placebo_label', 'related_values', 'accumulation_cmax_first', 'accumulation_cmax_last', 'accumulation_auc_first', 'accumulation_auc_last'):
        if key not in active: continue
        text = v.get(key)
        if not isinstance(text, str) or not text.strip() or len(text) > 500 or any(ord(c) < 32 for c in text):
            error(key, 'Enter a nonempty single line of at most 500 characters.'); v[key] = ''; continue
        v[key] = text.strip()
        if key.startswith('accumulation_') and not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,39}', text): error(key, 'Use a valid PARAMCD identifier.')
    for key in ('be_confidence', 'dose_confidence', 'accumulation_confidence', 'be_lower', 'be_upper', 'dose_lower', 'dose_upper', 'analysis_day', 'accumulation_first_day', 'accumulation_last_day', 'trough_last_day', 'lab_grade_min'):
        if key not in active: continue
        raw = v.get(key)
        try:
            number = float(raw)
            if isinstance(raw, bool) or not math.isfinite(number): raise ValueError()
            if key.endswith('_confidence') or key.endswith('_lower'):
                if not 0 < number < 1: raise ValueError()
            elif key.endswith('_upper'):
                if not 1 < number <= 10000: raise ValueError()
            elif not number.is_integer() or not (0 if key == 'lab_grade_min' else 1) <= number <= (10 if key == 'lab_grade_min' else 10000): raise ValueError()
            v[key] = int(number) if key.endswith('_day') or key == 'lab_grade_min' else number
        except (TypeError, ValueError, OverflowError):
            error(key, 'Enter a finite value within the displayed limits; days and grades must be integers.')
    for first, last in (('accumulation_first_day', 'accumulation_last_day'), ('steady_state_first_day', 'trough_last_day')):
        if last in active and isinstance(v.get(first), (int, float)) and isinstance(v.get(last), (int, float)) and v[first] >= v[last]: error(last, 'The last day must be later than the first day.')
    if 'accumulation_auc_comparable' in active and type(v.get('accumulation_auc_comparable')) is not bool: error('accumulation_auc_comparable', 'Use the confirmation checkbox.')
    doses = mapping(v.get('dose_map'), 'dose_map', error) if 'dose_map' in active else {}
    for key in ('lab_high_limits', 'lab_low_limits'):
        if key in active and not mapping(v.get(key), key, error, parameter=True): error(key, 'Enter at least one prespecified parameter threshold.')
    if any((v.get('design'), stem) in DOSE_OUTPUTS for stem in v.get('outputs', [])) and not doses:
        error('dose_map', 'Enter actual treatment doses for the selected models.')
    return doses
