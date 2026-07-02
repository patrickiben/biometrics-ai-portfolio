/******************************************************************************
* TABLE     : t_exposure  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Extent of Study Drug Exposure by Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEX
* NOTE      : PSEUDOCODE. Single-sequence design: exposure is summarized BY
*             PERIOD (APERIOD/APERIODC) because the regimen differs across
*             periods (reference = victim alone; test = victim + perpetrator).
*             Columns = Period 1 (Reference) | Period 2 (Test) | Total. Each
*             period's denominator = participants DOSED in that period. Continuous
*             metric set (same as the R twin): Total dose administered, Duration
*             of exposure, Number of doses (n, Mean(SD), Median, Min-Max).
*             Categorical (same as R twin): Compliance n (%). All from ADEX.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, BYPERIOD=APERIOD APERIODC */

/*--- per-PERIOD column denominators: participants dosed in each period --------
* Build N by APERIODC from ADEX (a participant dosed in the period contributes to
* that period's denominator), plus a Total column. The period IS the column. */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y' group by APERIOD, APERIODC
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y';
quit;

data ex;
  set adam.adex(where=(SAFFL='Y'));
  /* exposure analysis variables from ADEX (no re-derivation):
     AVAL    = total dose administered (mg)  [dose param, matches R AVAL]
     TRTDURD = duration of exposure (days)
     NDOSES  = number of doses
     EXCMPLPC = compliance (administered / planned, %)                       */
run;

/*--- continuous exposure metrics, summarized within each period ----------*/
%macro contblk(var=, label=, dp=1, ord=);
  proc means data=ex noprint;
    class APERIOD APERIODC; var &var;
    output out=_d n=n mean=mean std=std median=med min=min max=max;
  run;
  proc means data=ex noprint;     /* Total column across periods */
    var &var;
    output out=_dt n=n mean=mean std=std median=med min=min max=max;
  run;
  data _dt; set _dt; APERIOD=9999; APERIODC='Total'; run;
  data _c_&var; set _d _dt;
    where _type_ ne 0 or APERIOD=9999;     /* keep period rows + total       */
    length charlbl $44 stat $20 value $40;
    charlbl="&label"; ord=&ord;
    stat='n';          value=put(n,5.);                              output;
    stat='Mean (SD)';  value=catx(' ',put(mean,8.%eval(&dp+1)),
                                  cats('(',put(std,8.%eval(&dp+2)),')')); output;
    stat='Median';     value=put(med,8.%eval(&dp+1));                output;
    stat='Min, Max';   value=catx(', ',put(min,8.&dp),put(max,8.&dp)); output;
  run;
%mend;
%contblk(var=AVAL,    label=Total dose administered (mg), dp=1, ord=1);
%contblk(var=TRTDURD, label=Duration of exposure (days),  dp=1, ord=2);
%contblk(var=NDOSES,  label=Number of doses,              dp=0, ord=3);

/*--- categorical: compliance band, by period (same as R twin) ------------*/
data exc; set ex;
  length compcat $24;
  if missing(EXCMPLPC) then compcat='Missing';
  else if 80<=EXCMPLPC<=120 then compcat='Compliant (80-120%)';
  else compcat='Non-compliant';
run;
proc sql;
  create table _comp as
    select APERIOD as trtn, APERIODC as trt length=200, compcat,
           count(distinct USUBJID) as nsubj
    from exc group by APERIOD, APERIODC, compcat
  union all
    select 9999 as trtn, 'Total' as trt, compcat, count(distinct USUBJID) as nsubj
    from exc group by compcat;
quit;
proc sql;
  create table _compd as select a.*, b.N from _comp a
    left join _bign b on a.trtn=b.trtn;
quit;
data _c_comp; set _compd; length charlbl $44 stat $24 value $40;
  charlbl='Compliance n (%)'; ord=4; stat=compcat;
  value=catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'));
run;

/*--- stack and transpose: rows = metric x stat ; columns = period + Total -*/
data _all; set _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide;
  by ord charlbl stat;  id APERIOD;  var value;   /* one column per period   */
run;

%tfltitle(num=14.1.4, type=Table, text=Extent of Study Drug Exposure by Period,
   pop=Safety Population,
   foot=%str(Period 1 = reference (victim alone); Period 2 = test (victim + perpetrator). Each period denominator = participants dosed in that period. Total dose, duration and number of doses from ADEX; Compliance = administered / planned doses. Percentages within period.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Study Period" _NAME_  /* Period1 | Period2 | Total */);
  define ord     / order noprint;
  define charlbl / order  'Exposure Metric' width=28 flow;
  define stat    / display 'Statistic'       width=16;
run;
