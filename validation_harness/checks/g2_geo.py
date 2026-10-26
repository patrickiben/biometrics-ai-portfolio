#!/usr/bin/env python3
"""G2 per-program check: geometric statistics on the log scale, program by program.

Called by validation_harness/run_harness.sh, from the repository root, as
    python3 validation_harness/checks/g2_geo.py r_tlf_pseudocode sas_tlf_pseudocode
It prints one line, <programs passing> <programs checked> <evidence text>, and the evidence text
starts with the same two numbers. run_harness.sh turns G2 red unless they are equal and not 0. A
failing pkstats() helper or %pkstats macro fails every program that relies on it, so the first
number is the gating count. It reads the code and runs nothing. Unit tests:
validation_harness/checks/tests/test_g2_geo.py.

Which programs. The set is derived from content, so it cannot drift from the library: every .R
file under the R directory (00_setup_helpers.R excepted; it is checked as the helper) whose code
calls pkstats(), uses the name geomean or geocv (bare, backticked or quoted), assigns a column
whose name matches "Geo Mean" or "Geometric Mean" (not "... Ratio") or "Geo CV", takes
exp(mean(...)) or 10^mean(...), or fits a model (lm, lmer, glmer, lme, gls, glm, aov, nls) whose
right-hand side names a dose, treatment, period or sequence term.

R rules. The file is tokenized: comments are dropped and string literals are never read as code
(a quoted name in name position, or a string inside the brackets of an assignment target, still
names the column assigned). Assignments are `=`, `<-`, `<<-`, `:=`, `->`, `->>`, targets such as
x$name, x[["name"]] and backticked or quoted names, every named argument (so mutate(),
summarise(), transmute() and rename() assign their columns), and across(cols, fn) or
*_at(cols, fn), which assign fn to each column cols names. An expression runs to the end of its
balanced call or statement, across lines.
  - log-derived names: assigned from an expression that calls log(), log10() or log2() (or passes
    one as a function, as in across(x, log)), uses another log-derived name, or calls a function
    defined in the file whose body is log-derived. This is transitive and flow-insensitive: one
    log-derived assignment anywhere in the file is enough. rename(new = old) propagates; in a$b
    only b counts.
  - geomean, and every Geo Mean column: NA, or contains exp() of a natural-log-derived value that
    is not a log-scale variance, or 10^ of a log10-derived value (2^ of log2 likewise), or calls a
    function defined in the file whose body does, or uses geomean or a name assigned from such an
    exp() or 10^ (or assigned only from such names).
  - geocv, and every Geo CV column: NA, or contains exp() of a log-scale variance (var(L),
    sd(L)^2 or sigma(model)^2 with L log-derived, or a name assigned from one of these, or the
    square of a name assigned from sd(L) or sigma(model)), or calls a function defined in the
    file whose body does, or uses geocv or a name assigned from such an exp() (or assigned only
    from such names).
  - every model fitted has a log-derived response (the formula's left side; a formula held in a
    name is followed to its assignment; a formula that cannot be found fails; one-sided formulas
    are skipped).
  - the program uses log, log10 or log2, or calls pkstats() and the helper passes.
  - pkstats() in 00_setup_helpers.R: its function body must assign geomean and geocv, each by the
    rules above, so sqrt(exp(sd(log(x))^2) - 1) is accepted.

SAS rules, for the twin at the same relative path (exact case) of each program in the set.
/* */ comments, `*` comment statements (at a statement start, including after a semicolon on the
same line, or at a line start), `%*` macro comments, quoted strings and %tfltitle(...) calls are
blanked first; the code is lowercased and split into statements at semicolons.
  - log-derived variables: assigned from log(), log10() or log2(), or from another log-derived
    variable. A PROC MEANS or PROC SUMMARY whose VAR statement lists a log-derived variable makes
    the matching MEAN= names of its OUTPUT statement (positional, or MEAN(var)=, or AUTONAME, or
    ODS OUTPUT SUMMARY=) geometric-mean names; STD=/STDDEV= and VAR= give log-scale SD and
    variance names.
  - every geomean assignment is exp(<geometric-mean name>) or missing (.); every geocv
    assignment contains exp(<log-scale SD name>**2) or exp(<log-scale variance name>) or is
    missing; a twin that calls %pkstats may use the macro's names. Every MODEL statement in a
    PROC MIXED, GLM, REG, GLIMMIX, GENMOD, ANOVA or HPMIXED step has a log-derived response.
  - the twin of an R program with geometric statistics (any signal above except the model one)
    must call %pkstats, whose macro body must assign geomean and geocv by these rules and
    back-transform its own geometric mean, or must apply exp() to one of its own geometric-mean
    names. The twin of an R program found only by its model must fit a MODEL.

Disclosed limits: log(x + c) counts as log-derived (the shift is not detected). The analysis is
flow-insensitive and stays within one file (the helper and the macro excepted). A formula built
from strings fails. Display rows built by row index or case_when() are not seen. A raw-scale
model in one of these programs would be flagged even if it were legitimate. SAS macro variables
(&x) are never log-derived.
"""
import os
import re
import sys

# ----------------------------------------------------------------------------- shared patterns
GEO_MEAN_COL = re.compile(r'(?i)\bgeo(?:metric)?\.?\s*mean\b(?!\s*ratio)')
GEO_CV_COL = re.compile(r'(?i)\bgeo(?:metric)?\.?\s*cv\b')
BEDP_TERM = re.compile(r'(?i)^(?:ln|log)?_?(?:dose\w*|trt\w*|treat\w*|per|period\w*|aperiod\w*|seq|sequence\w*)$')

# =============================================================================================== R
NA_LIT = {'NA', 'NA_real_', 'NA_integer_', 'NA_character_'}
KEYWORDS = {'if', 'else', 'for', 'while', 'repeat', 'function', 'in', 'next', 'break', 'return',
            'TRUE', 'FALSE', 'T', 'F', 'NULL', 'Inf', 'NaN'} | NA_LIT
LOGS = {'log': 'e', 'log10': '10', 'log2': '2'}
POW_BASE = {'10': '10', '10L': '10', '10.0': '10', '2': '2', '2L': '2', '2.0': '2'}
MODEL_FUNS = {'lm', 'lmer', 'glmer', 'lme', 'gls', 'glm', 'aov', 'nls'}
ACROSS_FUNS = {'across', 'mutate_at', 'summarise_at', 'summarize_at', 'transmute_at'}
OPENERS, CLOSERS = '([{', ')]}'
ASSIGN_LEFT = {'<-', '<<-', '=', ':='}
ASSIGN_RIGHT = {'->', '->>'}
BINARY = {'+', '-', '*', '/', '^', '**', '<', '>', '<=', '>=', '==', '!=', '&', '&&', '|', '||', '~',
          '|>', '!', '?', ':', '$', '@', '::', ':::', '\\'} | ASSIGN_LEFT | ASSIGN_RIGHT
_NUM = re.compile(r'0[xX][0-9a-fA-F]+[Li]?|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?[Li]?')
_NAME = re.compile(r'[A-Za-z.][A-Za-z0-9._]*')
_RAW = re.compile(r'[rR](["\'])(-*)([(\[{])')
_OPS = ('<<-', '->>', ':::', '|>', '<-', '->', '<=', '>=', '==', '!=', '&&', '||', '::', ':=', '**',
        '+', '-', '*', '/', '^', '<', '>', '!', '&', '|', '~', '?', ':', '=', '$', '@', '\\')


class Tok:
    __slots__ = ('k', 'v', 'bq', 'ln')

    def __init__(self, k, v, ln, bq=False):
        self.k, self.v, self.ln, self.bq = k, v, ln, bq

    def __repr__(self):
        return f'{self.k}:{self.v}'


def r_tokens(src):
    """R tokens; comments dropped; strings kept as 'str' tokens (never searched as code)."""
    toks, i, n, ln = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n':
            toks.append(Tok('nl', '\n', ln)); ln += 1; i += 1
        elif c in ' \t\r\f\v':
            i += 1
        elif c == '#':
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif _RAW.match(src, i):
            m = _RAW.match(src, i)
            close = {'(': ')', '[': ']', '{': '}'}[m.group(3)] + m.group(2) + m.group(1)
            j = src.find(close, m.end())
            j = n if j < 0 else j
            toks.append(Tok('str', src[m.end():j], ln)); ln += src.count('\n', i, j); i = j + len(close)
        elif c in '"\'':
            j, buf = i + 1, []
            while j < n and src[j] != c:
                if src[j] == '\\' and j + 1 < n:
                    buf.append(src[j + 1]); j += 2
                else:
                    buf.append(src[j]); j += 1
            toks.append(Tok('str', ''.join(buf), ln)); ln += src.count('\n', i, j); i = j + 1
        elif c == '`':
            j = src.find('`', i + 1)
            j = n if j < 0 else j
            toks.append(Tok('name', src[i + 1:j], ln, True)); i = j + 1
        elif c.isdigit() or (c == '.' and i + 1 < n and src[i + 1].isdigit()):
            m = _NUM.match(src, i)
            toks.append(Tok('num', m.group(0), ln)); i = m.end()
        elif c.isalpha() or c == '.':
            m = _NAME.match(src, i)
            toks.append(Tok('name', m.group(0), ln)); i = m.end()
        elif c == '%':
            j = src.find('%', i + 1)
            if j < 0 or '\n' in src[i:j]:
                j = i
            toks.append(Tok('op', src[i:j + 1], ln)); i = j + 1
        elif c in '()[]{},;':
            toks.append(Tok(c, c, ln)); i += 1
        else:
            for op in _OPS:
                if src.startswith(op, i):
                    toks.append(Tok('op', op, ln)); i += len(op)
                    break
            else:
                i += 1
    return toks


def matches(toks):
    M, st = [-1] * len(toks), []
    for i, t in enumerate(toks):
        if t.k in OPENERS:
            st.append(i)
        elif t.k in CLOSERS and st:
            o = st.pop()
            M[o], M[i] = i, o
    return M


def close_of(s, j):
    """index of the closer that matches the opener s[j] in a plain token list"""
    d = 0
    for k in range(j, len(s)):
        if s[k].k in OPENERS:
            d += 1
        elif s[k].k in CLOSERS:
            d -= 1
            if d == 0:
                return k
    return len(s) - 1


def is_op(t, *vals):
    return t is not None and t.k == 'op' and t.v in vals


def is_name(t, *vals):
    return t is not None and t.k == 'name' and not t.bq and (not vals or t.v in vals)


def continues(toks, M, j):
    """True when a line that ends with toks[j] is not yet a complete R expression"""
    t = toks[j]
    if t.k == 'op':
        return t.v in BINARY or (t.v.startswith('%') and len(t.v) > 1)
    if is_name(t, 'else', 'repeat', 'function'):
        return True
    if t.k == ')' and M[j] > 0:
        p = toks[M[j] - 1]
        return is_name(p, 'if', 'for', 'while', 'function') or is_op(p, '\\')
    return False


def expr_end(toks, M, i):
    """index just past the expression starting at i (balanced, multi-line)"""
    last, n = None, len(toks)
    while i < n:
        t = toks[i]
        if t.k in CLOSERS or t.k in (',', ';'):
            break
        if t.k == 'nl':
            if last is not None and not continues(toks, M, last):
                break
            i += 1
            continue
        if t.k in OPENERS:
            if M[i] < 0:
                return n
            i = M[i]
        last = i
        i += 1
    return i


def postfix_back(toks, M, j):
    """start of the target expression (name, x$name, x[...], f(x)[...]) that ends at toks[j]"""
    start = None
    while j >= 0:
        t = toks[j]
        if t.k in (')', ']'):
            if M[j] < 0:
                return None
            start, j = M[j], M[j] - 1
            if j >= 0 and toks[j].k in ('name', 'str', ')', ']'):
                continue
            return start
        if t.k in ('name', 'str'):
            start = j
            if j >= 2 and is_op(toks[j - 1], '$', '@', '::', ':::'):
                j -= 2
                continue
            return start
        return start
    return start


def postfix_fwd(toks, M, j):
    n = len(toks)
    if j >= n or toks[j].k not in ('name', 'str'):
        return j
    j += 1
    while j < n:
        t = toks[j]
        if is_op(t, '$', '@', '::', ':::') and j + 1 < n and toks[j + 1].k in ('name', 'str'):
            j += 2
        elif t.k in ('(', '[') and M[j] > 0:
            j = M[j] + 1
        else:
            break
    return j


def expr_start_back(toks, M, j):
    """start of the value expression to the left of a right assignment (->) at toks[j]"""
    first = j
    j -= 1
    while j >= 0:
        t = toks[j]
        if t.k in OPENERS or t.k in (',', ';') or is_op(t, *(ASSIGN_LEFT | ASSIGN_RIGHT)):
            break
        if t.k == 'nl':
            k = j - 1
            while k >= 0 and toks[k].k == 'nl':
                k -= 1
            if k >= 0 and continues(toks, M, k):
                j = k
                continue
            break
        if t.k in CLOSERS:
            if M[j] < 0:
                break
            j = M[j]
        first = j
        j -= 1
    return first


def lhs_targets(toks, M, a, b):
    """names an assignment target writes: x -> x; x$y[...] -> y; strings inside its brackets"""
    out, last, j = [], None, a
    while j < b:
        t = toks[j]
        if t.k in OPENERS and M[j] > 0:
            out += [toks[k].v for k in range(j + 1, M[j]) if toks[k].k == 'str']
            j = M[j] + 1
            continue
        if is_op(t, '$', '@') and j + 1 < b and toks[j + 1].k in ('name', 'str'):
            last = toks[j + 1].v
            j += 2
            continue
        j += 1
    if last is not None:
        out.append(last)
    elif toks[a].k in ('name', 'str'):
        out.append(toks[a].v)
    return out


def split_args(s):
    """top-level arguments of a call given as tokens '(' ... ')': [(name or None, tokens)]"""
    args, cur, j, end = [], [], 1, len(s) - 1
    while j < end:
        t = s[j]
        if t.k == ',':
            args.append(cur); cur = []; j += 1
            continue
        if t.k in OPENERS:
            k = close_of(s, j)
            cur.extend(s[j:k + 1]); j = k + 1
            continue
        cur.append(t); j += 1
    args.append(cur)
    out = []
    for a in args:
        a = [x for x in a if x.k != 'nl']
        if len(a) >= 2 and a[0].k in ('name', 'str') and is_op(a[1], '='):
            out.append((a[0].v, a[2:]))
        elif a:
            out.append((None, a))
    return out


def pick_arg(args, names, pos):
    for nm, a in args:
        if nm in names:
            return a
    p = [a for nm, a in args if nm is None]
    return p[pos] if len(p) > pos else None


class Rec:
    __slots__ = ('targets', 'expr', 'span', 'ln')

    def __init__(self, targets, expr, span, ln):
        self.targets = targets
        self.expr = [t for t in expr if t.k != 'nl']
        self.span, self.ln = span, ln


def r_assignments(toks, M):
    recs, n = [], len(toks)
    for i, t in enumerate(toks):
        if t.k != 'op':
            continue
        if t.v in ASSIGN_LEFT:
            if i == 0 or toks[i - 1].k == 'nl':
                continue
            a = postfix_back(toks, M, i - 1)
            if a is None:
                continue
            s = i + 1
            while s < n and toks[s].k == 'nl':
                s += 1
            e = expr_end(toks, M, s)
            recs.append(Rec(lhs_targets(toks, M, a, i), toks[s:e], (i, e), t.ln))
        elif t.v in ASSIGN_RIGHT:
            s = expr_start_back(toks, M, i)
            j = i + 1
            while j < n and toks[j].k == 'nl':
                j += 1
            e = postfix_fwd(toks, M, j)
            if e > j:
                recs.append(Rec(lhs_targets(toks, M, j, e), toks[s:i], (s, e), t.ln))
    # across(cols, fn) and *_at(cols, fn): fn is assigned to every column cols names
    for i, t in enumerate(toks):
        if not (is_name(t, *ACROSS_FUNS) and i + 1 < n and toks[i + 1].k == '(' and M[i + 1] > 0):
            continue
        if i > 0 and is_op(toks[i - 1], '$', '@'):
            continue
        call = toks[i + 1:M[i + 1] + 1]
        args = split_args(call)
        cols = pick_arg(args, ('.cols', '.vars'), 0)
        fns = pick_arg(args, ('.fns', '.funs'), 1)
        if not cols or not fns or is_name(fns[0], 'list'):
            continue
        targets = [c.v for k, c in enumerate(cols) if c.k in ('name', 'str')
                   and not (k + 1 < len(cols) and cols[k + 1].k == '(')
                   and not (c.k == 'name' and not c.bq and c.v in KEYWORDS)]
        self_names = {'.x', '.', '..1'}
        if len(fns) == 1 and fns[0].k == 'name':
            fns = [fns[0], Tok('(', '(', fns[0].ln), Tok('name', '.x', fns[0].ln), Tok(')', ')', fns[0].ln)]
        elif (is_name(fns[0], 'function') or is_op(fns[0], '\\')) and len(fns) > 3 and fns[1].k == '(' and fns[2].k == 'name':
            self_names.add(fns[2].v)
        for tg in targets:
            sub = [Tok('name', tg, x.ln, True) if (x.k == 'name' and x.v in self_names) else x for x in fns]
            recs.append(Rec([tg], sub, (i, M[i + 1] + 1), t.ln))
    return recs


def log_base(s, j):
    """base of the log call at s[j]: 'e', '10', '2' or '?' (unknown)"""
    b = LOGS[s[j].v]
    if s[j].v != 'log' or j + 1 >= len(s) or s[j + 1].k != '(':
        return b
    args = split_args(s[j + 1:close_of(s, j + 1) + 1])
    base = pick_arg(args, ('base',), 1)
    if not base:
        return 'e'
    if len(base) == 1 and base[0].k == 'num':
        return POW_BASE.get(base[0].v, '?')
    if [x.v for x in base] == ['exp', '(', '1', ')']:
        return 'e'
    return '?'


def facts(s):
    """(refs, calls, log bases) of a token list with newlines removed"""
    refs, calls, logs, n = set(), set(), set(), len(s)
    for j, t in enumerate(s):
        if t.k != 'name':
            continue
        prv = s[j - 1] if j else None
        nxt = s[j + 1] if j + 1 < n else None
        if is_op(nxt, '::', ':::') or is_op(nxt, '='):
            continue
        if not t.bq and t.v in LOGS and not is_op(prv, '$', '@'):
            logs.add(log_base(s, j))
        if nxt is not None and nxt.k == '(':
            calls.add(t.v)
            continue
        if not t.bq and t.v in KEYWORDS:
            continue
        if is_op(nxt, '$', '@') and j + 2 < n and s[j + 2].k in ('name', 'str'):
            continue
        refs.add(t.v)
    return refs, calls, logs


def strip_parens(s):
    while len(s) >= 2 and s[0].k == '(' and close_of(s, 0) == len(s) - 1:
        s = s[1:-1]
    return s


def call_form(s):
    """(function name, first positional argument, tokens after the call) of [pkg::]f(...)..."""
    k = 2 if len(s) > 2 and s[0].k == 'name' and is_op(s[1], '::', ':::') else 0
    if len(s) > k + 1 and s[k].k == 'name' and s[k + 1].k == '(':
        c = close_of(s, k + 1)
        return s[k].v, pick_arg(split_args(s[k + 1:c + 1]), (), 0), s[c + 1:]
    return None, None, None


def squared(rest):
    return len(rest) == 2 and is_op(rest[0], '^', '**') and rest[1].k == 'num' and rest[1].v in ('2', '2L', '2.0')


def is_na(s):
    s = [t for t in s if t.k not in ('(', ')')]
    return bool(s) and all(t.k == 'name' and (t.v in NA_LIT or t.v in ('as.numeric', 'as.double')) for t in s) \
        and any(t.v in NA_LIT for t in s)


def operand(s, j):
    """tokens of the operand that starts at s[j] (for 10^x)"""
    n, k = len(s), j
    while k < n and is_op(s[k], '-', '+'):
        k += 1
    if k >= n:
        return []
    if s[k].k == '(':
        return s[k:close_of(s, k) + 1]
    if s[k].k in ('name', 'num', 'str'):
        e = k + 1
        while e < n:
            if is_op(s[e], '::', ':::', '$', '@') and e + 1 < n:
                e += 2
            elif s[e].k in ('(', '['):
                e = close_of(s, e) + 1
            else:
                break
        return s[k:e]
    return []


class RCtx:
    """log-derived, back-transformed and log-variance names of one R file (fixed points)"""

    def __init__(self, recs):
        self.recs = recs
        self.f = [facts(r.expr) for r in recs]
        self.local = {tg for r in recs if r.expr and (is_name(r.expr[0], 'function') or is_op(r.expr[0], '\\'))
                      for tg in r.targets}
        self.L = {b: set() for b in ('e', '10', '2', '?')}
        self._fix(self._add_log)
        self.LV, self.LSD = set(), set()
        self._fix(self._add_var)
        self.G, self.GCV = {'geomean'}, {'geocv'}
        self._fix(self._add_geo)

    def _fix(self, step):
        while any([step(r, f) for r, f in zip(self.recs, self.f)]):
            pass

    @staticmethod
    def _grow(dest, targets):
        new = set(targets) - dest
        dest |= new
        return bool(new)

    def _add_log(self, r, f):
        refs, calls, logs = f
        ch = False
        for b, names in self.L.items():
            if b in logs or refs & names or calls & self.local & names:
                ch |= self._grow(names, r.targets)
        return ch

    def _add_var(self, r, f):
        ch = False
        if self.is_logvar(r.expr):
            ch |= self._grow(self.LV, r.targets)
        if self.is_logsd(r.expr):
            ch |= self._grow(self.LSD, r.targets)
        return ch

    def _add_geo(self, r, f):
        refs = f[0]
        ch = False
        if self.bt(r.expr) or (refs and refs <= self.G):
            ch |= self._grow(self.G, r.targets)
        if self.expv(r.expr) or (refs and refs <= self.GCV):
            ch |= self._grow(self.GCV, r.targets)
        return ch

    def ld(self, base, s):
        refs, calls, logs = facts(s)
        names = self.L[base]
        return base in logs or bool(refs & names) or bool(calls & self.local & names)

    def ld_any(self, s):
        return any(self.ld(b, s) for b in self.L)

    def bt(self, s):
        """contains exp() of a natural-log-derived value (not a log-scale variance) or 10^ / 2^ of a
        log10- / log2-derived one"""
        for j, t in enumerate(s):
            if is_name(t, 'exp') and j + 1 < len(s) and s[j + 1].k == '(' and not (j and is_op(s[j - 1], '$', '@')):
                a = s[j + 2:close_of(s, j + 1)]
                if self.ld('e', a) and not self.is_logvar(a):     # exp(log variance) is a CV, not a mean
                    return True
            if t.k == 'num' and t.v in POW_BASE and j + 1 < len(s) and is_op(s[j + 1], '^', '**'):
                if self.ld(POW_BASE[t.v], operand(s, j + 2)):
                    return True
        return False

    def is_logvar(self, s):
        s = strip_parens(s)
        fn, a, rest = call_form(s)
        if fn == 'var' and a and not rest:
            return self.ld('e', a)
        if fn in ('sd', 'sigma') and a and squared(rest):
            return self.ld('e', a)
        if len(s) == 1 and s[0].k == 'name' and s[0].v in self.LV:
            return True
        return len(s) == 3 and s[0].k == 'name' and s[0].v in self.LSD and squared(s[1:])

    def is_logsd(self, s):
        s = strip_parens(s)
        fn, a, rest = call_form(s)
        if fn in ('sd', 'sigma') and a and not rest:
            return self.ld('e', a)
        return len(s) == 1 and s[0].k == 'name' and s[0].v in self.LSD

    def expv(self, s):
        """contains exp() of a log-scale variance"""
        for j, t in enumerate(s):
            if is_name(t, 'exp') and j + 1 < len(s) and s[j + 1].k == '(' and not (j and is_op(s[j - 1], '$', '@')):
                if self.is_logvar(s[j + 2:close_of(s, j + 1)]):
                    return True
        return False

    def ok_mean(self, s):
        refs, calls, _ = facts(s)
        return is_na(s) or self.bt(s) or bool(calls & self.local & self.G) or bool(refs & self.G)

    def ok_cv(self, s):
        refs, calls, _ = facts(s)
        return is_na(s) or self.expv(s) or bool(calls & self.local & self.GCV) or bool(refs & self.GCV)


class RFile:
    def __init__(self, path):
        with open(path, encoding='utf-8', errors='replace') as fh:
            self.toks = r_tokens(fh.read())
        self.M = matches(self.toks)
        self.recs = r_assignments(self.toks, self.M)
        self.ctx = RCtx(self.recs)

    def calls(self, name):
        t, n = self.toks, len(self.toks)
        return any(is_name(x, name) and i + 1 < n and t[i + 1].k == '(' and not (i and is_op(t[i - 1], '$', '@'))
                   for i, x in enumerate(t))

    def has_log(self):
        t = self.toks
        return any(is_name(x, *LOGS) and not (i and is_op(t[i - 1], '$', '@'))
                   and not (i + 1 < len(t) and is_op(t[i + 1], '=')) for i, x in enumerate(t))

    def models(self):
        """[(line, response tokens or None, rhs tokens)] for every model fit"""
        out, t, n = [], self.toks, len(self.toks)
        for i, x in enumerate(t):
            if not (is_name(x, *MODEL_FUNS) and i + 1 < n and t[i + 1].k == '(' and self.M[i + 1] > 0):
                continue
            if i and is_op(t[i - 1], '$', '@'):
                continue
            form = pick_arg(split_args(t[i + 1:self.M[i + 1] + 1]), ('formula', 'fixed'), 0) or []
            if len(form) == 1 and form[0].k == 'name':
                defs = [r.expr for r in self.recs if form[0].v in r.targets and any(is_op(y, '~') for y in r.expr)]
                form = defs[0] if defs else form
            d, k = 0, None
            for j, y in enumerate(form):
                d += y.k in OPENERS
                d -= y.k in CLOSERS
                if d == 0 and is_op(y, '~'):
                    k = j
                    break
            if k is None:
                out.append((x.ln, None, []))
            elif k > 0:
                out.append((x.ln, form[:k], form[k + 1:]))
        return out

    def geo_signal(self):
        """calls pkstats(), uses geomean/geocv, assigns a Geo Mean/Geo CV% column, or takes exp(mean(...))"""
        t, n = self.toks, len(self.toks)
        for i, x in enumerate(t):
            if is_name(x, 'pkstats') and i + 1 < n and t[i + 1].k == '(':
                return True
            if x.k in ('name', 'str') and x.v in ('geomean', 'geocv'):
                return True
            if is_name(x, 'exp') and i + 2 < n and t[i + 1].k == '(' and is_name(t[i + 2], 'mean'):
                return True
            if x.k == 'num' and x.v in POW_BASE and i + 2 < n and is_op(t[i + 1], '^', '**') and is_name(t[i + 2], 'mean'):
                return True
        return any(GEO_MEAN_COL.search(tg) or GEO_CV_COL.search(tg) for r in self.recs for tg in r.targets)

    def bedp_signal(self):
        """fits a model whose right-hand side names a dose, treatment, period or sequence term"""
        return any(lhs is not None and any(BEDP_TERM.match(v) for v in facts(rhs)[0]) for _, lhs, rhs in self.models())


def check_r(rf, helper_ok):
    """(problems, counts) for one R program"""
    c, prob = {'assign': 0, 'col': 0, 'model': 0}, []
    x = rf.ctx
    for r in rf.recs:
        for tg in r.targets:
            if tg in ('geomean', 'geocv'):
                c['assign'] += 1
                if not (x.ok_mean(r.expr) if tg == 'geomean' else x.ok_cv(r.expr)):
                    prob.append(f'{tg} at line {r.ln} is not a log-scale back-transform')
            elif GEO_MEAN_COL.search(tg) or GEO_CV_COL.search(tg):
                c['col'] += 1
                if not (x.ok_mean(r.expr) if GEO_MEAN_COL.search(tg) else x.ok_cv(r.expr)):
                    prob.append(f'"{tg}" at line {r.ln} uses no geometric statistic')
    for ln, lhs, _ in rf.models():
        c['model'] += 1
        if lhs is None:
            prob.append(f'model at line {ln}: formula not found')
        elif not x.ld_any(lhs):
            prob.append(f'model at line {ln} has a response that is not log-derived')
    uses_pk = rf.calls('pkstats')
    if not (rf.has_log() or uses_pk):
        prob.append('no log() call in code and no pkstats()')
    if uses_pk and not helper_ok:
        prob.append('relies on the failing pkstats() helper')
    return prob, c


def check_r_helper(path):
    """(ok, problems) for pkstats() in 00_setup_helpers.R"""
    if not os.path.isfile(path):
        return False, ['00_setup_helpers.R not found']
    rf = RFile(path)
    defs = [r for r in rf.recs if 'pkstats' in r.targets and r.expr and is_name(r.expr[0], 'function')]
    if not defs:
        return False, ['no pkstats <- function(...) definition']
    lo, hi = defs[0].span
    prob, seen = [], {'geomean': 0, 'geocv': 0}
    for r in rf.recs:
        if not (lo < r.span[0] < hi):
            continue
        for tg in r.targets:
            if tg in seen:
                seen[tg] += 1
                if not (rf.ctx.ok_mean(r.expr) if tg == 'geomean' else rf.ctx.ok_cv(r.expr)):
                    prob.append(f'pkstats() {tg} at line {r.ln} is not a log-scale back-transform')
    prob += [f'pkstats() assigns no {k}' for k, v in seen.items() if not v]
    return not prob, prob


# ============================================================================================= SAS
SAS_MODEL_PROCS = {'mixed', 'glm', 'reg', 'glimmix', 'genmod', 'anova', 'hpmixed'}
SAS_STATS = {'mean', 'std', 'stddev', 'var', 'n', 'nmiss', 'median', 'min', 'max', 'cv', 'sum', 'stderr',
             'q1', 'q3', 'p5', 'p95', 'lclm', 'uclm', 'range'}
SAS_ASSIGN = re.compile(r'^(?:(?:else\s+)?if\b.*?\bthen\s+)?([a-z_][a-z0-9_]*)\s*=(?!=)\s*(.+)$', re.S)
SAS_WORD = re.compile(r'(&?)\b([a-z_][a-z0-9_]*)\b(\s*\()?')
SAS_OPT = re.compile(r'\b([a-z_][a-z0-9_]*)\s*(?:\(([^)]*)\))?\s*=')


def sas_clean(src):
    """blank comments and quoted strings, keeping newlines and semicolons that end code"""
    out, i, n = [], 0, len(src)
    stmt_start = line_start = True

    def blank(x):
        return re.sub(r'[^\n]', ' ', x)
    while i < n:
        c = src[i]
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(blank(src[i:j])); i = j
            continue
        if c == '%' and i + 1 < n and src[i + 1] in '\'"':      # %' and %" inside %str()
            out.append('  '); i += 2
            continue
        if c in '\'"':
            j = i + 1
            while j < n:
                if src[j] == c:
                    if j + 1 < n and src[j + 1] == c:
                        j += 2
                        continue
                    break
                j += 1
            j = min(j + 1, n)
            out.append(blank(src[i:j])); i = j
            stmt_start = line_start = False
            continue
        if src.startswith('%*', i) or (c == '*' and (stmt_start or line_start)):
            j = src.find(';', i)
            j = n if j < 0 else j + 1
            out.append(blank(src[i:j])); i = j
            stmt_start = True
            continue
        out.append(c)
        if c == ';':
            stmt_start = True
        elif c == '\n':
            line_start = True
        elif not c.isspace():
            stmt_start = line_start = False
        i += 1
    return ''.join(out)


def strip_call(text, name):
    """blank every name(...) call (balanced parentheses)"""
    out, i = [], 0
    for m in re.finditer(re.escape(name) + r'\s*\(', text):
        if m.start() < i:
            continue
        j, d = m.end() - 1, 0
        while j < len(text):
            d += text[j] == '('
            d -= text[j] == ')'
            if d == 0:
                break
            j += 1
        out.append(text[i:m.start()]); out.append(re.sub(r'[^\n]', ' ', text[m.start():j + 1])); i = j + 1
    out.append(text[i:])
    return ''.join(out)


def sas_words(expr):
    """variable names an expression uses (not functions, not macro variables)"""
    return {m.group(2) for m in SAS_WORD.finditer(expr) if not m.group(1) and not m.group(3)}


def balanced_args(expr, fn):
    """argument text of every fn( ... ) call in expr"""
    out = []
    for m in re.finditer(r'\b' + fn + r'\s*\(', expr):
        j, d = m.end() - 1, 0
        while j < len(expr):
            d += expr[j] == '('
            d -= expr[j] == ')'
            if d == 0:
                break
            j += 1
        out.append(expr[m.end():j])
    return out


class SasCode:
    """log-derived variables, PROC MEANS output names, models and assignments of SAS code"""

    def __init__(self, text):
        self.stmts = [s.strip() for s in text.split(';')]
        self.assigns = []
        for s in self.stmts:
            m = SAS_ASSIGN.match(s)
            if m and not re.match(r'(?:(?:proc|data|output|model|class|var|by|set|merge|where)\b|%)', s):
                self.assigns.append((m.group(1), ' '.join(m.group(2).split())))
        self.L = {'e': set(), '10': set(), '2': set()}
        pats = {'e': r'\blog\s*\(', '10': r'\blog10\s*\(', '2': r'\blog2\s*\('}
        changed = True
        while changed:
            changed = False
            for tg, ex in self.assigns:
                w = sas_words(ex)
                for b, names in self.L.items():
                    if tg not in names and (re.search(pats[b], ex) or w & names):
                        names.add(tg)
                        changed = True
        self.GM, self.LSD, self.LV, self.models = set(), set(), set(), []
        proc, block = None, []
        for s in self.stmts + ['run']:
            m = re.match(r'(proc|data)\s+(\w+)|(run|quit)\b|%mend\b', s)
            if m:
                self._block(proc, block)
                proc, block = (m.group(2) if m.group(1) == 'proc' else None), []
            elif proc:
                block.append(s)
        self.feeds = any(sas_words(a) & self.GM for _, ex in self.assigns for a in balanced_args(ex, 'exp'))
        self.calls_pkstats = any(re.search(r'%pkstats\s*\(', s) for s in self.stmts)

    def logvar(self, v):
        return any(v in names for names in self.L.values())

    def _block(self, proc, block):
        if proc in ('means', 'summary'):
            vars_ = []
            for s in block:
                m = re.match(r'var\s+(.+)$', s, re.S)
                if m:
                    vars_ += m.group(1).split()
            for s in block:
                if not re.match(r'output\b', s):
                    continue
                body = s.split('/', 1)
                opts = list(SAS_OPT.finditer(body[0]))
                auto = len(body) > 1 and 'autoname' in body[1]
                for k, m in enumerate(opts):
                    stat = m.group(1)
                    if stat not in SAS_STATS:
                        continue
                    end = opts[k + 1].start() if k + 1 < len(opts) else len(body[0])
                    names = body[0][m.end():end].split()
                    vs = m.group(2).split() if m.group(2) else vars_
                    if not names and auto:
                        names = [f'{v}_{stat}' for v in vs]
                    for v, nm in zip(vs, names):
                        if self.logvar(v):
                            {'mean': self.GM, 'std': self.LSD, 'stddev': self.LSD, 'var': self.LV}.get(stat, set()).add(nm)
            for s in block:
                if re.match(r'ods\s+output\s+summary\s*=', s):
                    for v in vars_:
                        if self.logvar(v):
                            self.GM.add(f'{v}_mean'); self.LSD.add(f'{v}_stddev')
        elif proc in SAS_MODEL_PROCS:
            for s in block:
                m = re.match(r'model\s+(.+?)\s*=', s, re.S)
                if m:
                    resp = m.group(1)
                    self.models.append((resp, bool(re.search(r'\blog(?:10|2)?\s*\(', resp))
                                        or all(self.logvar(v) for v in resp.replace('/', ' ').split())))

    def geomean_ok(self, ex, gm):
        m = re.fullmatch(r'\(*\s*exp\s*\(\s*([a-z_][a-z0-9_]*)\s*\)\s*\)*', ex)
        return ex == '.' or bool(m and m.group(1) in gm)

    def geocv_ok(self, ex, lsd, lv):
        if ex == '.':
            return True
        for a in balanced_args(ex, 'exp'):
            a = a.strip()
            m = re.fullmatch(r'\(?\s*([a-z_][a-z0-9_]*)\s*\)?\s*\*\*\s*2', a)
            if (m and m.group(1) in lsd) or a in lv:
                return True
        return False


def sas_code(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = sas_clean(fh.read()).lower()
    return strip_call(text, '%tfltitle')


def check_sas_macro(path):
    """(ok, problems, SasCode of the %pkstats body)"""
    if not os.path.isfile(path):
        return False, ['00_setup_macros.sas not found'], None
    m = re.search(r'%macro\s+pkstats\b.*?%mend\b', sas_code(path), re.S)
    if not m:
        return False, ['no %macro pkstats ... %mend'], None
    sc = SasCode(m.group(0))
    prob = []
    for tg in ('geomean', 'geocv'):
        ex = [e for t, e in sc.assigns if t == tg]
        if not ex:
            prob.append(f'%pkstats assigns no {tg}')
        for e in ex:
            if not (sc.geomean_ok(e, sc.GM) if tg == 'geomean' else sc.geocv_ok(e, sc.LSD, sc.LV)):
                prob.append(f'%pkstats {tg} = {e} is not exp() of a log-scale PROC MEANS statistic')
    if not (sc.GM and sc.feeds):
        prob.append('%pkstats has no PROC MEANS of a log-derived variable back-transformed with exp()')
    return not prob, prob, sc


def exact_file(path):
    d, b = os.path.split(path)
    return os.path.isdir(d) and b in os.listdir(d)


def check_sas(path, macro, r_geo, r_models):
    """(problems, route) for one SAS twin; route is 'pkstats', 'means' or 'model'. A twin of an R
    program with geometric statistics needs %pkstats or its own back-transformed PROC MEANS; a twin
    of an R program that only fits models needs a MODEL (every MODEL response must be log-derived)"""
    if not exact_file(path):
        return ['no SAS twin at the same path'], None
    sc = sas_code(path)
    sc = SasCode(sc)
    mok, _, msc = macro
    gm, lsd, lv = set(sc.GM), set(sc.LSD), set(sc.LV)
    if sc.calls_pkstats and msc is not None:
        gm |= msc.GM; lsd |= msc.LSD; lv |= msc.LV
    prob = []
    for tg, ex in sc.assigns:
        if tg == 'geomean' and not sc.geomean_ok(ex, gm):
            prob.append(f'SAS geomean = {ex} is not exp() of a log-scale PROC MEANS mean')
        if tg == 'geocv' and not sc.geocv_ok(ex, lsd, lv):
            prob.append(f'SAS geocv = {ex} is not exp() of a log-scale variance')
    for resp, ok in sc.models:
        if not ok:
            prob.append(f'SAS MODEL response {resp} is not log-derived')
    route = None
    if r_geo:
        if sc.calls_pkstats and mok:
            route = 'pkstats'
        elif sc.GM and sc.feeds:
            route = 'means'
        else:
            prob.append('SAS twin has no passing %pkstats call and no PROC MEANS of a log-derived variable'
                        ' back-transformed with exp()')
    elif r_models:
        if sc.models:
            route = 'model'
        else:
            prob.append('SAS twin fits no MODEL')
    return prob, route


# ============================================================================================ main
def count(k, one, many):
    return f'{k} {one if k == 1 else many}'


def find_programs(R):
    """[(path relative to R, RFile, has geometric statistics)] of the R programs G2 checks"""
    out = []
    for d, dirs, files in os.walk(R):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(d, f)
            rel = os.path.relpath(p, R)
            if f.endswith('.R') and rel != '00_setup_helpers.R':
                rf = RFile(p)
                geo = rf.geo_signal()
                if geo or rf.bedp_signal():
                    out.append((rel, rf, geo))
    return out


def run(R, SAS):
    """(programs passing, programs checked, evidence text)"""
    helper_ok, helper_prob = check_r_helper(os.path.join(R, '00_setup_helpers.R'))
    macro = check_sas_macro(os.path.join(SAS, '00_setup_macros.sas'))
    progs = find_programs(R)
    tot = {'assign': 0, 'col': 0, 'model': 0}
    routes = {'pkstats': 0, 'means': 0, 'model': 0}
    bad = []
    for rel, rf, geo in progs:
        rprob, c = check_r(rf, helper_ok)
        for k in tot:
            tot[k] += c[k]
        sprob, route = check_sas(os.path.join(SAS, rel)[:-2] + '.sas', macro, geo, c['model'] > 0)
        if route:
            routes[route] += 1
        if rprob or sprob:
            bad.append(f'{rel} (' + '; '.join(rprob + sprob) + ')')
    n, ok = len(progs), len(progs) - len(bad)
    helper = 'pkstats() passes the same rules' if helper_ok else 'pkstats() FAILS: ' + '; '.join(helper_prob)
    mac = 'the macro passes the same rules' if macro[0] else 'the macro FAILS: ' + '; '.join(macro[1])
    ev = (f'{ok} of {n} R programs pass (found by content: they call pkstats(), use geomean or geocv, '
          f'assign a Geo Mean or Geo CV% column, take exp(mean()) or 10^mean(), or fit a model with a dose, '
          f'treatment, period or sequence term); comments are ignored and strings are never read as code. '
          f'R: {tot["assign"]} geomean/geocv assignments and {tot["col"]} Geo Mean/Geo CV% columns are exp() or '
          f'10^ of a log-derived value (CV: exp() of a log-scale variance), use a name assigned that way, or are '
          f'NA; {tot["model"]} models have a log-derived response; and each program uses log() (or log10/log2) '
          f'or calls pkstats() ({helper}). SAS twin at the same path: geomean only as exp() of a PROC MEANS mean '
          f'of a log-derived variable, geocv only from exp() of its log-scale SD or variance, every MODEL '
          f'response log-derived; {count(routes["pkstats"], "twin calls", "twins call")} %pkstats ({mac}), '
          f'{count(routes["means"], "back-transforms its", "back-transform their")} own such mean with exp(), '
          f'{count(routes["model"], "model-only twin fits", "model-only twins fit")} a MODEL. Static check: '
          f'nothing is run, and log(x + c) counts as log-scale')
    if bad:
        ev += '; failing: ' + ', '.join(bad)
    return ok, n, ev.replace('\n', ' ').replace('|', '/')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: g2_geo.py <R library dir> <SAS library dir>')
    ok, n, ev = run(sys.argv[1], sys.argv[2])
    print(ok, n, ev)
