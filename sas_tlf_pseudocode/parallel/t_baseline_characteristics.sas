/******************************************************************************
* TABLE     : t_baseline_characteristics  (Parallel-group)
* TITLE     : Baseline Disease and Participant Characteristics
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADSL  (baseline participant-level characteristics)
* NOTE      : PSEUDOCODE. Complements t_demographics with disease/clinical
*             baseline characteristics. Continuous: n, Mean(SD), Median,
*             Min-Max. Categorical: n (%). Columns = TRT01A arms + Total.
*             Parallel: one treatment per participant; % denom = SAFFL N per arm.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=PARALLEL);                 /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

data adsl; set adam.adsl(where=(SAFFL='Y')); run;

/*--- continuous baseline characteristics (ADSL baseline vars) -------------*
* Examples: BSACRBL (BSA), EGFRBL (baseline eGFR), SBPBL/DBPBL, QTCFBL,
* baseline biomarker; choose per protocol. n, Mean(SD), Median, Min-Max.     */
%macro contblk(var=, label=, dp=1, ord=);
  %descstat(ds=adsl, var=&var, class=&TRTVAR &TRTNVAR, dp=&dp, out=_d);
  data _c_&var; set _d; length charlbl $40 stat $20 value $40;
    charlbl="&label"; ord=&ord;
    stat='n';         value=put(n,5.);            output;
    stat='Mean (SD)'; value=catx(' ',cmean,csd);  output;
    stat='Median';    value=cmed;                 output;
    stat='Min, Max';  value=cminmax;              output;
  run;
%mend;
%contblk(var=BSACRBL,  label=Body surface area (m^2),       dp=2, ord=1);
%contblk(var=EGFRBL,   label=eGFR (mL/min/1.73m^2),         dp=1, ord=2);
%contblk(var=SBPBL,    label=Systolic BP (mmHg),            dp=1, ord=3);
%contblk(var=QTCFBL,   label=QTcF (msec),                   dp=1, ord=4);

/*--- categorical baseline characteristics --------------------------------*
* Examples: AGEGR1 (age group), BMIGR1 (BMI category), RENALGR (renal func.
* category), HBSTATFL (e.g. CYP phenotype/genotype group), SMOKSTAT.         */
%macro catblk(var=, label=, ord=);
  %catfreq(ds=adsl, var=&var, class=&TRTVAR &TRTNVAR, denom=_bign, out=_f);
  data _c_&var; set _f; length charlbl $40 stat $40 value $40;
    charlbl="&label"; ord=&ord; stat=vvalue(&var);
    value=catx(' ', put(count,5.), cats('(',put(pct,5.1),'%)'));  /* n (xx.x%) */
  run;
%mend;
%catblk(var=AGEGR1,   label=Age group n (%),               ord=5);
%catblk(var=BMIGR1,   label=BMI category n (%),            ord=6);
%catblk(var=RENALGR,  label=Renal function n (%),          ord=7);
%catblk(var=CYPPHENO, label=CYP2D6 phenotype n (%),        ord=8);

/*--- stack, transpose to one column per treatment + Total, render --------*/
data _all; set _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide;
  by ord charlbl stat; id &TRTNVAR; var value;     /* one col per arm + Total */
run;

%tfltitle(num=14.1.3, type=Table, text=Baseline Disease and Participant Characteristics,
          pop=Safety Population,
          foot=%str(Percentages based on the number of participants in the Safety Population per arm. Baseline characteristics from ADSL.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment" _NAME_ /* arm cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Characteristic' width=24;
  define stat    / display 'Statistic'      width=14;
  /* define <each arm var>/display center "&header (N=&n)"; */
run;
