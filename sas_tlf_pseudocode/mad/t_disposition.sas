/******************************************************************************
* TABLE     : t_disposition  (Multiple Ascending Dose)
* TITLE     : Participant Disposition
* POPULATION: All Enrolled Participants
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (distinct USUBJID). n (%) per
*             column; % denominator = enrolled N per column (from %bign).
*             MAD: parallel ascending-dose cohorts, ONE dose level per participant;
*             columns = TRT01A = assigned dose level (placebo often pooled
*             across cohorts). REPEATED daily dosing across a treatment period,
*             so disposition distinguishes participants who completed the full
*             multiple-dose regimen vs. discontinued ON treatment (and the
*             dosing day at discontinuation matters for steady-state/PK).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/* column denominators (N=) per dose level + Total : enrolled population.
   For MAD, TRT01A = assigned dose level; placebo may be pooled across cohorts. */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=ENRLFL, out=_bign);

data adsl; set adam.adsl(where=(ENRLFL='Y')); run;

/*--- disposition counts: each row = participants with the flag, distinct USUBJID -
* Pull population/disposition flags straight from ADSL (no re-derivation):
*   ENRLFL  = enrolled        RANDFL = randomized      SAFFL = treated/safety
*   COMPLFL = completed study  DCSREAS = discontinuation reason (verbatim/grp)
* MAD note: repeated dosing over a multi-day regimen; "Completed dosing regimen"
* (e.g. COMPDOSF) is a distinct milestone from "Completed study". PK steady-state
* population (PKSSFL) is shown alongside the overall PK population (PKFL).        */
%macro dispblk(flagexpr=, label=, ord=);
  proc sql;
    create table _d_&ord as
      select &TRTVAR as trt length=200, &TRTNVAR as trtn,
             count(distinct USUBJID) as nsubj
      from adsl where &flagexpr group by &TRTVAR, &TRTNVAR
    union all
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from adsl where &flagexpr;
  quit;
  data _r_&ord; set _d_&ord; length term $60 stat $40 value $40;
    term="&label"; ord=&ord; sub=0;
    /* value = n (%) using N per column from _bign : value="n (xx.x%)"        */
  run;
%mend dispblk;
%dispblk(flagexpr=%str(ENRLFL='Y'),  label=Participants enrolled,                    ord=1);
%dispblk(flagexpr=%str(RANDFL='Y'),  label=Participants randomized,                  ord=2);
%dispblk(flagexpr=%str(SAFFL='Y'),   label=Received >= 1 dose (Safety Pop),      ord=3);
%dispblk(flagexpr=%str(COMPDOSF='Y'),label=Completed full dosing regimen,        ord=4);
%dispblk(flagexpr=%str(PKFL='Y'),    label=Participants in PK Population,            ord=5);
%dispblk(flagexpr=%str(PKSSFL='Y'),  label=Participants in PK Steady-State Pop,      ord=6);
%dispblk(flagexpr=%str(COMPLFL='Y'), label=Completed study,                      ord=7);
%dispblk(flagexpr=%str(DCSFL='Y'),   label=Discontinued study,                   ord=8);

/*--- discontinuation reasons (sub-rows under "Discontinued"), DCSREAS ------*/
%catfreq(ds=adsl(where=(DCSFL='Y')), var=DCSREAS, class=&TRTVAR &TRTNVAR,
         denom=_bign, out=_dcr);
data _r_9; set _dcr; length term $60 stat $40 value $40;
  term='   '||strip(DCSREAS); ord=9; sub=1;        /* indent reasons        */
  /* value = catx(' ', put(count,4.), cats('(',put(pct,5.1),'%)'))          */
run;

/*--- stack, transpose to one column per dose level + Total ----------------*/
data _all; set _r_1 _r_2 _r_3 _r_4 _r_5 _r_6 _r_7 _r_8 _r_9; run;
proc sort data=_all; by ord sub term; run;
proc transpose data=_all out=_wide; by ord sub term; id trtn; var value; run;

%tfltitle(num=14.1.1, type=Table, text=Participant Disposition,
          pop=All Enrolled Participants,
          foot=%str(Column = assigned dose level (TRT01A); placebo may be pooled across cohorts. Multiple (repeated) dosing administered over the treatment period. Completed dosing regimen = COMPDOSF; PK steady-state population = PKSSFL. Percentages based on the number of enrolled participants per dose level. Discontinuation reasons from ADSL DCSREAS.));
proc report data=_wide nowd split='|';
  columns ord sub term ("Dose Level" /* dose cols + Total, _NAME_ */);
  define ord  / order noprint;
  define sub  / order noprint;
  define term / order 'Disposition' width=34 flow;
  /* define <each dose var>/display center "&header (N=&n)"; ordered ascending dose */
run;
