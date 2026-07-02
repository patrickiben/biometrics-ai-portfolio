/******************************************************************************
* TABLE     : t_baseline_characteristics  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Baseline Disease and Clinical Characteristics
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADSL (study-level baselines) + ADVS/ADLB BASE where param-level
* NOTE      : PSEUDOCODE. Baseline = pre-first-dose (Period 1 / reference
*             period) values. Single-sequence design: ONE column (treatment
*             sequence) + Total; baseline taken before the reference period so
*             it is shared across both periods. Continuous: n, Mean(SD),
*             Median, Min-Max. Categorical: n (%). All values from ADaM.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, BYPERIOD=APERIOD APERIODC */

%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=&SEQVARN, popfl=SAFFL, out=_bign);

data adsl; set adam.adsl(where=(SAFFL='Y')); run;

/*--- study-level baseline continuous characteristics from ADSL -----------
* e.g. baseline eGFR, baseline systolic/diastolic BP, baseline QTcF, baseline
* hepatic markers as carried on ADSL. Use the ADSL baseline variables, not a
* re-pull of the raw domains.                                                */
%macro contblk(var=, label=, dp=1, ord=);
  %descstat(ds=adsl, var=&var, class=&SEQVAR &SEQVARN, dp=&dp, out=_d);
  data _c_&var; set _d; length charlbl $50 stat $20 value $40;
    charlbl="&label"; ord=&ord;
    stat='n';            value=put(n,5.);              output;
    stat='Mean (SD)';    value=catx(' ',cmean,csd);    output;
    stat='Median';       value=cmed;                   output;
    stat='Min, Max';     value=cminmax;                output;
  run;
%mend;
%contblk(var=EGFRBL,   label=Baseline eGFR (mL/min/1.73m^2), dp=1, ord=1);
%contblk(var=SYSBPBL,  label=Baseline Systolic BP (mmHg),    dp=1, ord=2);
%contblk(var=DIABPBL,  label=Baseline Diastolic BP (mmHg),   dp=1, ord=3);
%contblk(var=QTCFBL,   label=Baseline QTcF (msec),           dp=1, ord=4);

/*--- categorical baseline characteristics --------------------------------
* e.g. baseline renal function category, hepatic function (Child-Pugh) class,
* smoking status, CYP genotype/phenotype (relevant for DDI). All on ADSL.    */
%macro catblk(var=, label=, ord=);
  %catfreq(ds=adsl, var=&var, class=&SEQVAR &SEQVARN, denom=_bign, out=_f);
  data _c_&var; set _f; length charlbl $50 stat $40 value $40;
    charlbl="&label"; ord=&ord; stat=vvalue(&var);
    value=catx(' ', put(count,5.), cats('(',put(pct,5.1),'%)'));
  run;
%mend;
%catblk(var=RENALGR1, label=Baseline renal function n (%),    ord=5);
%catblk(var=HEPATGR1, label=Baseline hepatic function n (%),  ord=6);
%catblk(var=SMOKSTAT, label=Smoking status n (%),             ord=7);
%catblk(var=CYPPHENO, label=CYP metabolizer phenotype n (%),  ord=8);  /* DDI-relevant */

/*--- stack, transpose, render -------------------------------------------*/
data _all; set _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide;
  by ord charlbl stat;  id &SEQVARN;  var value;
run;

%tfltitle(num=14.1.3, type=Table, text=Baseline Disease and Clinical Characteristics,
          pop=Safety Population,
          foot=%str(Baseline = last value before first dose in the reference period (Period 1). CYP phenotype shown given relevance to the drug-drug interaction assessment. Percentages based on Safety Population N.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment Sequence" _NAME_);
  define ord     / order noprint;
  define charlbl / order  'Characteristic' width=28 flow;
  define stat    / display 'Statistic'      width=16;
run;
