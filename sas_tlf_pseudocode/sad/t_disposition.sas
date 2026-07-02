/******************************************************************************
* TABLE     : t_disposition  (Single Ascending Dose)
* TITLE     : Participant Disposition by Dose Cohort
* POPULATION: All Enrolled Participants
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (distinct USUBJID). n (%) per
*             column for EVERY row, including enrolled and randomized (enrolled =
*             100% of its own denominator); the %dispblk macro is uniform.
*             % denominator = enrolled N per column (from %bign).
*             SAD: parallel ascending-dose cohorts, ONE treatment per participant;
*             columns = TRT01A = assigned dose level. Single dose only -> no
*             on-treatment dropout from repeat dosing; discontinuations are
*             post-single-dose.
*             PLACEBO-POOLING CONTRACT (must match the R twin): TRT01A already
*             collapses all placebo cohorts into a single "Placebo" level in
*             ADaM, so grouping by raw TRT01A/TRT01AN here yields one pooled
*             "Placebo" column. The R twin applies an IDEMPOTENT in-code collapse
*             (a no-op given pooled ADaM), so both languages produce the SAME
*             column set, ordered ascending by TRT01AN with Total last.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);                      /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN */

/* column denominators (N=) per dose level + Total : enrolled population.
   For SAD, TRT01A = assigned dose level; ADaM TRT01A already pools placebo across
   cohorts into one "Placebo" level, so grouping by &TRTVAR/&TRTNVAR gives the same
   pooled-Placebo columns as the R twin (idempotent collapse). */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=ENRLFL, out=_bign);

data adsl; set adam.adsl(where=(ENRLFL='Y')); run;

/*--- disposition counts: each row = participants with the flag, distinct USUBJID -
* Pull population/disposition flags straight from ADSL (no re-derivation):
*   ENRLFL  = enrolled        RANDFL = randomized      SAFFL = treated/safety
*   COMPLFL = completed study  DCSREAS = discontinuation reason (verbatim/grp)
* SAD note: a single dose is administered; "Received single dose" replaces any
* multi-dose exposure milestone. PK population from PKFL.                       */
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
%dispblk(flagexpr=%str(ENRLFL='Y'),  label=Participants enrolled,                ord=1);
%dispblk(flagexpr=%str(RANDFL='Y'),  label=Participants randomized,              ord=2);
%dispblk(flagexpr=%str(SAFFL='Y'),   label=Received single dose (Safety Population),ord=3);
%dispblk(flagexpr=%str(PKFL='Y'),    label=Included in PK Population,             ord=4);
%dispblk(flagexpr=%str(COMPLFL='Y'), label=Completed study,                  ord=5);
%dispblk(flagexpr=%str(DCSFL='Y'),   label=Discontinued study,               ord=6);

/*--- discontinuation reasons (sub-rows under "Discontinued"), DCSREAS ------*/
%catfreq(ds=adsl(where=(DCSFL='Y')), var=DCSREAS, class=&TRTVAR &TRTNVAR,
         denom=_bign, out=_dcr);
data _r_7; set _dcr; length term $60 stat $40 value $40;
  term='   '||strip(DCSREAS); ord=7; sub=1;        /* indent reasons        */
  /* value = catx(' ', put(count,4.), cats('(',put(pct,5.1),'%)'))          */
run;

/*--- stack, transpose to one column per dose level + Total ----------------*/
data _all; set _r_1 _r_2 _r_3 _r_4 _r_5 _r_6 _r_7; run;
proc sort data=_all; by ord sub term; run;
proc transpose data=_all out=_wide; by ord sub term; id trtn; var value; run;

%tfltitle(num=14.1.1, type=Table, text=Participant Disposition by Dose Cohort,
          pop=All Enrolled Participants,
          foot=%str(SAD: columns = ascending dose cohorts (TRT01A) with placebo pooled. Single dose administered. Percentages based on the number of enrolled participants per dose level. Discontinued = DCSFL='Y'; discontinuation reasons from ADSL DCSREAS.));
proc report data=_wide nowd split='|';
  columns ord sub term ("Dose Level" /* dose cols + Total, _NAME_ */);
  define ord  / order noprint;
  define sub  / order noprint;
  define term / order 'Disposition' width=34 flow;
  /* define <each dose var>/display center "&header (N=&n)"; */
run;
