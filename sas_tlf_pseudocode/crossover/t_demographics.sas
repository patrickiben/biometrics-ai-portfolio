/******************************************************************************
* TABLE     : t_demographics  (Crossover - 2x2 or Williams)
* TITLE     : Demographic and Baseline Characteristics
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. Continuous: n, Mean(SD), Median, Min-Max.
*             Categorical: n (%). Demographics are PARTICIPANT-level and fixed for
*             the whole study, so columns = randomized SEQUENCE (TRTSEQP) +
*             Total -- NOT the period treatment TRTA (which would double-count
*             a participant across periods). One record per participant from ADSL.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA SEQVAR=TRTSEQP BYPERIOD=...  */

/* column denominators (N=) per SEQUENCE + Total (participant-level, count once) */
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=TRTSEQPN, popfl=SAFFL, out=_bign);

data adsl; set adam.adsl(where=(SAFFL='Y')); run;

/*--- continuous characteristics: AGE, WEIGHTBL, HEIGHTBL, BMIBL ----------*/
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
%contblk(var=AGE,      label=Age (years),     dp=0, ord=1);
%contblk(var=WEIGHTBL, label=Weight (kg),     dp=1, ord=2);
%contblk(var=HEIGHTBL, label=Height (cm),     dp=1, ord=3);
%contblk(var=BMIBL,    label=BMI (kg/m^2),    dp=1, ord=4);

/*--- categorical characteristics: SEX, RACE, ETHNIC, AGEGR1 -------------*/
%macro catblk(var=, label=, ord=);
  %catfreq(ds=adsl, var=&var, class=&SEQVAR TRTSEQPN, denom=_bign, out=_f);
  data _c_&var; set _f; length charlbl $40 stat $40 value $40;
    charlbl="&label"; ord=&ord; stat=vvalue(&var);
    value=catx(' ', put(count,5.), cats('(',put(pct,5.1),'%)'));  /* n (xx.x%) */
  run;
%mend;
%catblk(var=SEX,    label=Sex n (%),        ord=5);
%catblk(var=RACE,   label=Race n (%),       ord=6);
%catblk(var=ETHNIC, label=Ethnicity n (%),  ord=7);
%catblk(var=AGEGR1, label=Age Group n (%),  ord=8);

/*--- stack, transpose to one column per sequence, render ----------------*/
data _all; set _c_:; run;
proc sort data=_all; by ord charlbl stat; run;
proc transpose data=_all out=_wide;
  by ord charlbl stat;  id TRTSEQPN;  var value;   /* one col per sequence + Total */
run;

%tfltitle(num=14.1.2, type=Table, text=Demographic and Baseline Characteristics,
          pop=Safety Population,
          foot=%str(Columns are randomized treatment sequences (TRTSEQP). Participant-level characteristics counted once per participant. Percentages based on N in the Safety Population per sequence.));
proc report data=_wide nowd split='|';
  columns ord charlbl stat ("Treatment Sequence" _NAME_  /* seq cols + Total */);
  define ord     / order noprint;
  define charlbl / order  'Characteristic' width=24;
  define stat    / display 'Statistic'      width=14;
  /* define <each sequence var> / display center "&header (N=&n)";          */
run;
