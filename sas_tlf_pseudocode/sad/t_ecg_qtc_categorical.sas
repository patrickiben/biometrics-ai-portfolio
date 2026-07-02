/******************************************************************************
* TABLE     : t_ecg_qtc_categorical  (Single Ascending Dose)
* TITLE     : QTcF Interval and Change from Baseline - Categorical Outlier
*             Analysis by Dose
* POPULATION: Safety Population (SAFFL='Y'), on-treatment
* INPUT     : ADEG  (PARAMCD='QTCF'; AVAL, CHG, AVISITN; QTcF category
*             flags from ADaM where available)
* NOTE      : PSEUDOCODE. SAD: column = dose level (TRT01A), one (single) dose
*             per participant, placebo pooled per ADaM. Counts = PARTICIPANTS (distinct
*             USUBJID) meeting each threshold at any post-baseline timepoint;
*             % denominator = N per dose level (%bign). Standard QTcF outlier
*             categories: absolute value (>450, >480, >500 ms) and change from
*             baseline (>30, >60 ms). Dose ordering supports a dose-trend read.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/* column denominators (N=) per dose level + Total */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/*--- on-treatment post-baseline QTcF records -------------------------------*/
data qtcf;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0
                       and PARAMCD='QTCF'));
run;

/*--- per-participant worst-case flags (any post-baseline timepoint meets cutoff)-
* Prefer ADaM-derived category flags; thresholds shown for transparency.     */
proc sql;
  create table _subjflag as
    select USUBJID, &TRTVAR as trt length=200, &TRTNVAR as trtn,
           max(AVAL>450)         as a450,
           max(AVAL>480)         as a480,
           max(AVAL>500)         as a500,
           max(CHG >30)          as c30,
           max(CHG >60)          as c60
    from qtcf group by USUBJID, &TRTVAR, &TRTNVAR;
quit;

/*--- count PARTICIPANTS meeting each category per dose level (distinct USUBJID) -*/
%macro qcat(flag=, label=, ord=);
  proc sql;
    create table _q_&flag as
      select trt, trtn, "&label" as catlbl length=60, &ord as ord,
             sum(&flag) as nsubj
      from _subjflag group by trt, trtn
    union all
      select 'Total' as trt, 9999 as trtn, "&label" as catlbl, &ord as ord,
             sum(&flag) as nsubj
      from _subjflag;
  quit;
%mend qcat;
%qcat(flag=a450, label=Absolute QTcF > 450 ms,            ord=1);
%qcat(flag=a480, label=Absolute QTcF > 480 ms,            ord=2);
%qcat(flag=a500, label=Absolute QTcF > 500 ms,            ord=3);
%qcat(flag=c30,  label=Change from baseline > 30 ms,      ord=4);
%qcat(flag=c60,  label=Change from baseline > 60 ms,      ord=5);

/*--- attach denominators, build n (xx.x%) of PARTICIPANTS, transpose -----------*/
data _cat; set _q_:; run;
proc sql;
  create table _disp as
    select c.ord, c.catlbl, c.trtn, c.nsubj, b.N,
           catx(' ', put(c.nsubj,5.),
                cats('(', put(100*c.nsubj/b.N, 5.1), '%)')) as value length=20
    from _cat c left join _bign b on c.trtn=b.trtn;
quit;
proc sort data=_disp; by ord catlbl trtn; run;
proc transpose data=_disp out=_wide;
  by ord catlbl;  id trtn;  var value;     /* one col per dose level + Total  */
run;

%tfltitle(num=14.3.5.2, type=Table,
   text=%str(QTcF Interval and Change from Baseline - Categorical Outlier Analysis by Dose),
   pop=Safety Population,
   foot=%str(Counts = participants (distinct USUBJID) meeting the criterion at any post-baseline timepoint. Percentages based on N per dose level in the Safety Population. Single dose per participant. QTcF = Fridericia-corrected (ADaM).));
proc report data=_wide nowd split='|';
  columns ord catlbl ("Dose Level" _NAME_ /* dose cols + Total */);
  define ord    / order noprint;
  define catlbl / order 'QTcF Category' width=34;
  /* define <each dose var> / display center "&header (N=&n)"; */
run;
