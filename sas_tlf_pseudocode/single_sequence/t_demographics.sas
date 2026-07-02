/******************************************************************************
* TABLE     : t_demographics  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Demographic and Baseline Characteristics
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. Continuous: n, Mean(SD), Median, Min-Max.
*             Categorical: n (%). Single-sequence design: each participant receives
*             the SAME fixed sequence (no randomized arm/sequence), so
*             demographics are summarized in ONE column (the treatment
*             sequence) + Total. Variables come from ADSL (no re-derivation).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, TRTNVAR=TRTAN, SEQVAR=    */

/* column denominator: single fixed sequence + Total -----------------------*/
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=&SEQVARN, popfl=SAFFL, out=_bign);

data adsl; set adam.adsl(where=(SAFFL='Y')); run;

/*--- continuous characteristics: AGE, WEIGHTBL, HEIGHTBL, BMIBL -----------*/
%macro contblk(var=, label=, dp=1, ord=);
  %descstat(ds=adsl, var=&var, class=&SEQVAR &SEQVARN, dp=&dp, out=_d);
  data _c_&var; set _d; length charlbl $40 stat $20 value $40;
    charlbl="&label"; ord=&ord;
    stat='n';            value=put(n,5.);              output;
    stat='Mean (SD)';    value=catx(' ',cmean,csd);    output;
    stat='Median';       value=cmed;                   output;
    stat='Min, Max';     value=cminmax;                output;
  run;
%mend;
%contblk(var=AGE,      label=Age (years),    dp=0, ord=1);
%contblk(var=WEIGHTBL, label=Weight (kg),    dp=1, ord=2);
%contblk(var=HEIGHTBL, label=Height (cm),    dp=1, ord=3);
%contblk(var=BMIBL,    label=BMI (kg/m^2),   dp=1, ord=4);

/*--- categorical characteristics: SEX, RACE, ETHNIC, AGEGR1 --------------*/
%macro catblk(var=, label=, ord=);
  %catfreq(ds=adsl, var=&var, class=&SEQVAR &SEQVARN, denom=_bign, out=_f);
  data _c_&var; set _f; length charlbl $40 stat $40 value $40;
    charlbl="&label"; ord=&ord; stat=vvalue(&var);
    value=catx(' ', put(count,5.), cats('(',put(pct,5.1),'%)'));  /* n (xx.x%) */
  run;
%mend;
%catblk(var=SEX,    label=Sex n (%),         ord=5);
%catblk(var=RACE,   label=Race n (%),        ord=6);
%catblk(var=ETHNIC, label=Ethnicity n (%),   ord=7);
%catblk(var=AGEGR1, label=Age group n (%),   ord=8);

/*--- stack, transpose to one column per sequence + Total, render ---------*/
data _all; set _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide;
  by ord charlbl stat;  id &SEQVARN;  var value;     /* sequence col + Total */
run;

%tfltitle(num=14.1.2, type=Table, text=Demographic and Baseline Characteristics,
          pop=Safety Population,
          foot=%str(Percentages based on the number of participants in the Safety Population. All participants receive the same fixed treatment sequence (no randomized sequence).));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment Sequence" _NAME_  /* sequence col + Total */);
  define ord     / order noprint;
  define charlbl / order  'Characteristic' width=24;
  define stat    / display 'Statistic'      width=16;
run;
