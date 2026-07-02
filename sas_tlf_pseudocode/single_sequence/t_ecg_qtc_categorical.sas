/******************************************************************************
* TABLE     : t_ecg_qtc_categorical  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Categorical Summary of QTcF: Maximum Post-Baseline Value
*             and Maximum Change from Baseline
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEG (PARAMCD='QTCF')
* NOTE      : PSEUDOCODE. Number (%) of PARTICIPANTS meeting standard QTc outlier
*             categories, by treatment PERIOD (APERIODC). Single-/fixed-sequence
*             (fixed order; NO randomized sequence) -> each participant counted under
*             every period received. Absolute QTcF: >450, >480, >500 msec. Change
*             from within-period baseline: >30, >60 msec. Categories are
*             cumulative worst-case per participant per period. Denominator = N per
*             period (Safety Population) from ADEX where SAFFL='Y' (APERIOD is a
*             BDS per-record var, so the per-period N cannot come from ADSL).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA ; BYPERIOD=APERIOD APERIODC ; no SEQVAR */

/*--- header denominators = N per PERIOD column. APERIOD/APERIODC are
* BDS per-record vars (not on ADSL), so the per-period N is built from the
* period-bearing source ADEX (mirror t_exposure.sas), keyed on APERIOD so the
* denominator joins to the period columns (NOT to a treatment code).       */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y' group by APERIOD, APERIODC;
quit;

data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y'
                       and PARAMCD='QTCF' and AVISITN>0));
run;

/*--- per-participant-per-PERIOD worst case (single-/fixed-sequence) ---------*
* Max post-baseline AVAL and max CHG within each treatment period a participant got.*/
proc means data=eg nway noprint;
  class APERIOD APERIODC USUBJID;
  var AVAL CHG;
  output out=_peak max(AVAL)=maxqtc max(CHG)=maxchg;
run;

/*--- flag each participant into the outlier categories ----------------------*/
data _flag;
  set _peak;
  /* absolute QTcF thresholds (msec) */
  v450 = (maxqtc > 450);
  v480 = (maxqtc > 480);
  v500 = (maxqtc > 500);
  /* change-from-baseline thresholds (msec) */
  c30  = (maxchg > 30);
  c60  = (maxchg > 60);
run;

/* count distinct participants per period meeting each category */
proc means data=_flag nway noprint;
  class APERIOD APERIODC;
  var v450 v480 v500 c30 c60;
  output out=_cnt sum=n450 n480 n500 n30 n60;
run;

/* reshape to one row per category, merge denominator, format n (xx.x%).
   Denominator joined on period (APERIOD) since columns are by period. */
proc transpose data=_cnt out=_long(rename=(col1=count _name_=catcd));
  by APERIOD APERIODC;  var n450 n480 n500 n30 n60;
run;
proc sql;
  create table _rpt as
    select l.*, b.N as denom,
           catx(' ', put(l.count,5.), cats('(',put(100*l.count/b.N,5.1),'%)')) as value length=20
    from _long l left join _bign b
      on l.APERIOD = b.trtn;   /* denominator keyed on APERIOD (b.trtn holds APERIOD, not a treatment code) */
quit;
data _rpt; set _rpt;
  length grp catlbl $48;
  select(catcd);
    when('n450') do; grp='Absolute QTcF (msec)';        catlbl='> 450';  ord=1; sub=1; end;
    when('n480') do; grp='Absolute QTcF (msec)';        catlbl='> 480';  ord=1; sub=2; end;
    when('n500') do; grp='Absolute QTcF (msec)';        catlbl='> 500';  ord=1; sub=3; end;
    when('n30')  do; grp='Change from Baseline (msec)'; catlbl='> 30';   ord=2; sub=1; end;
    when('n60')  do; grp='Change from Baseline (msec)'; catlbl='> 60';   ord=2; sub=2; end;
    otherwise;
  end;
run;
proc sort data=_rpt; by ord grp sub catlbl APERIOD; run;
proc transpose data=_rpt out=_wide;
  by ord grp sub catlbl;  id APERIOD;  var value;     /* one col / period */
run;

%tfltitle(num=14.3.8.2, type=Table,
   text=%str(Categorical Summary of QTcF: Maximum Post-Baseline Value and Maximum Change from Baseline),
   pop=Safety Population,
   foot=%str(n = participants with worst post-baseline QTcF (or change) in the category, per treatment period. Categories are not mutually exclusive. Percentages based on N per period (Safety Population). Single-/fixed-sequence: each participant counted under each period received.));
proc report data=_wide nowd split='|';
  columns ord grp sub catlbl ("Treatment Period" _NAME_ /* period cols */);
  define ord    / order noprint;
  define sub    / order noprint;
  define grp    / order 'Category'   width=28;
  define catlbl / display 'Threshold' width=12;
  /* define <each period var> / display center "&periodlbl (N=&n)"; */
run;
