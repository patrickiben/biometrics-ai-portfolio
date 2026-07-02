/******************************************************************************
* TABLE     : t_baseline_characteristics  (Crossover - 2x2 or Williams)
* TITLE     : Baseline Disease and Clinical Characteristics
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADSL (participant-level baselines); ADVS/ADLB BASE where parameter-level
* NOTE      : PSEUDOCODE. Continuous: n, Mean(SD), Median, Min-Max. Categorical:
*             n (%). In a crossover, "baseline" = STUDY baseline (pre-first-dose,
*             one value per participant), so columns = randomized SEQUENCE (TRTSEQP).
*             Period-specific pre-dose baselines (ABLFL by APERIOD) are NOT used
*             here -- those drive the within-participant CHG analyses in the PK/safety
*             tables, not this participant-level baseline summary.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP                          */

/* participant-level denominators per SEQUENCE + Total                           */
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=TRTSEQPN, popfl=SAFFL, out=_bign);

data adsl; set adam.adsl(where=(SAFFL='Y')); run;

/*--- continuous baseline measures carried on ADSL -----------------------*/
%macro contblk(var=, label=, dp=1, ord=);
  %descstat(ds=adsl, var=&var, class=&SEQVAR TRTSEQPN, dp=&dp, out=_d);
  data _c_&var; set _d; length charlbl $40 stat $20 value $40;
    charlbl="&label"; ord=&ord;
    stat='n';            value=put(n,5.);             output;
    stat='Mean (SD)';    value=catx(' ',cmean,csd);   output;
    stat='Median';       value=cmed;                  output;
    stat='Min, Max';     value=cminmax;               output;
  run;
%mend;
%contblk(var=HRBL,    label=Baseline Heart Rate (bpm),       dp=1, ord=1);
%contblk(var=SYSBPBL, label=Baseline Systolic BP (mmHg),     dp=1, ord=2);
%contblk(var=DIABPBL, label=Baseline Diastolic BP (mmHg),    dp=1, ord=3);
%contblk(var=QTCFBL,  label=Baseline QTcF (msec),            dp=1, ord=4);
%contblk(var=CRCLBL,  label=Baseline Creatinine Clearance (mL/min), dp=1, ord=5);

/*--- categorical baseline groupings -------------------------------------*/
%macro catblk(var=, label=, ord=);
  %catfreq(ds=adsl, var=&var, class=&SEQVAR TRTSEQPN, denom=_bign, out=_f);
  data _c_&var; set _f; length charlbl $40 stat $40 value $40;
    charlbl="&label"; ord=&ord; stat=vvalue(&var);
    value=catx(' ', put(count,5.), cats('(',put(pct,5.1),'%)'));
  run;
%mend;
%catblk(var=BMIGR1,  label=Baseline BMI Category n (%),         ord=6);
%catblk(var=RFGR1,   label=Baseline Renal Function n (%),       ord=7);
%catblk(var=SMOKSTAT,label=Smoking Status n (%),                ord=8);

/*--- stack, transpose to sequence columns, render ----------------------*/
data _all; set _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide;
  by ord charlbl stat;  id TRTSEQPN;  var value;   /* one col per sequence + Total */
run;

%tfltitle(num=14.1.3, type=Table, text=Baseline Disease and Clinical Characteristics,
          pop=Safety Population,
          foot=%str(Baseline = last assessment prior to first dose (study baseline). Columns are randomized treatment sequences (TRTSEQP). Percentages based on N in the Safety Population per sequence.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment Sequence" _NAME_  /* seq cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Characteristic' width=30 flow;
  define stat    / display 'Statistic'      width=14;
  /* define <each sequence var> / display center "&header (N=&n)";          */
run;
