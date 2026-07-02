/******************************************************************************
* TABLE     : t_exposure  (Crossover - 2x2 or Williams)
* TITLE     : Extent of Study Drug Exposure by Treatment and Period
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADEX
* NOTE      : PSEUDOCODE. In a crossover each participant is dosed with EACH analysis
*             treatment, one per period, so exposure is summarized by the period
*             treatment TRTA (and supportively by APERIOD). Columns = TRTA + Total.
*             Counts of participants dosed = distinct USUBJID within TRTA. Continuous
*             exposure (dose, duration, cumulative dose) = n, Mean(SD), Median,
*             Min-Max. % denominator = Safety N per treatment column (%bign).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC */

/* exposure columns = analysis treatment actually administered (TRTA) per period.
   Denominator N = participants dosed with that treatment (counted within TRTA).   */
%bign(ds=adam.adex, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

data ex; set adam.adex(where=(SAFFL='Y')); run;

/*--- participants dosed (distinct USUBJID) per treatment --------------------*/
proc sql;
  create table _dosed as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn,
           count(distinct USUBJID) as nsubj
    from ex group by &TRTVAR, &TRTNVAR
  union all
    select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
    from ex;
quit;
data _c0; set _dosed; length charlbl $44 stat $20 value $40;
  charlbl='Participants Dosed'; ord=1; stat='n (%)';
  /* value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N_from_bign,5.1),'%)')) */
run;

/*--- continuous exposure measures (ADEX analysis values) ----------------
* AVAL by PARAMCD: planned/actual dose (mg), treatment duration (DURD),
* cumulative dose (CUMDOSE), number of doses administered (NDOSE).            */
%macro contblk(paramcd=, label=, dp=1, ord=);
  %descstat(ds=ex, var=AVAL, class=&TRTVAR &TRTNVAR,
            where=%str(PARAMCD="&paramcd"), dp=&dp, out=_d);
  data _c_&ord; set _d; length charlbl $44 stat $20 value $40;
    charlbl="&label"; ord=&ord;
    stat='n';            value=put(n,5.);             output;
    stat='Mean (SD)';    value=catx(' ',cmean,csd);   output;
    stat='Median';       value=cmed;                  output;
    stat='Min, Max';     value=cminmax;               output;
  run;
%mend;
%contblk(paramcd=DOSE,    label=Administered Dose (mg),          dp=1, ord=2);
%contblk(paramcd=DURD,    label=Duration of Exposure (days),     dp=1, ord=3);
%contblk(paramcd=CUMDOSE, label=Cumulative Dose (mg),            dp=1, ord=4);
%contblk(paramcd=NDOSE,   label=Number of Doses Administered,    dp=0, ord=5);

/*--- supportive: participants dosed by PERIOD (APERIOD x TRTA crosstab) -------
* Confirms each period contributes the expected treatment per sequence; a
* by-period panel (APERIODC down, TRTA across) sits beneath the main table.   */
proc sql;
  create table _byper as
    select APERIODC, &TRTVAR as trt length=200,
           count(distinct USUBJID) as nsubj
    from ex group by APERIODC, &TRTVAR;
quit;

/*--- stack, transpose to treatment columns, render ----------------------*/
data _all; set _c0 _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide; by ord charlbl stat; id trtn; var value; run;  /* TRTA cols + Total */

%tfltitle(num=14.1.4, type=Table, text=Extent of Study Drug Exposure by Treatment,
          pop=Safety Population,
          foot=%str(Columns are analysis treatments administered (TRTA); each participant contributes once per treatment received. Percentages based on N dosed per treatment. Supportive by-period (APERIOD) panel follows.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment" _NAME_  /* TRTA cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Exposure Measure' width=28 flow;
  define stat    / display 'Statistic'        width=12;
  /* define <each TRTA var> / display center "&header (N=&n)";              */
run;
