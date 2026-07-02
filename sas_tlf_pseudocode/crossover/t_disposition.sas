/******************************************************************************
* TABLE     : t_disposition  (Crossover - 2x2 or Williams)
* TITLE     : Participant Disposition
* POPULATION: All Enrolled / Safety Population (SAFFL='Y')
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS (distinct USUBJID). In a crossover
*             each participant contributes one randomized SEQUENCE; the disposition
*             columns are therefore the SEQUENCE groups (TRTSEQP) + Total, NOT
*             the period-level treatment TRTA. Discontinuations may occur in a
*             given period (DCPERIOD/last-completed-period) -> shown as a
*             supportive by-period block. % denominator = N per sequence column.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN SEQVAR=TRTSEQP
                                      BYPERIOD=APERIOD APERIODC                */

/* Crossover disposition columns = randomized SEQUENCE (one per participant).
   Use TRTSEQP/TRTSEQPN as the column variable so each participant is counted once.*/
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=TRTSEQPN, popfl=RANDFL, out=_bign);

data adsl; set adam.adsl; run;

/*--- disposition categories (ADSL one-record-per-participant flags) ----------*/
%macro dispblk(flagexpr=, label=, ord=, denomfl=RANDFL);
  proc sql;
    create table _d_&ord as
      select &SEQVAR as seq length=200, TRTSEQPN as seqn,
             count(distinct USUBJID) as nsubj
      from adsl where &denomfl='Y' and (&flagexpr)
      group by &SEQVAR, TRTSEQPN
    union all
      select 'Total' as seq, 9999 as seqn, count(distinct USUBJID) as nsubj
      from adsl where &denomfl='Y' and (&flagexpr);
  quit;
  data _d_&ord; set _d_&ord; length displbl $60; displbl="&label"; ord=&ord; run;
%mend dispblk;

/* enrolled / randomized / treated / population flags                        */
%dispblk(flagexpr=%str(ENRLFL='Y'),               label=Enrolled,                          ord=1, denomfl=ENRLFL);
%dispblk(flagexpr=%str(RANDFL='Y'),               label=Randomized to a Sequence,          ord=2);
%dispblk(flagexpr=%str(SAFFL='Y'),                label=Safety Population,                  ord=3);
%dispblk(flagexpr=%str(PKFL='Y'),                 label=PK Population,                      ord=4);
/* completion / discontinuation of the full crossover                        */
%dispblk(flagexpr=%str(COMPLFL='Y'),              label=Completed All Periods,             ord=5);
%dispblk(flagexpr=%str(DCSREAS ne '' ),           label=Discontinued (any period),         ord=6);

/*--- discontinuation reasons (ADSL DCSREAS) -----------------------------*/
%macro dcreason(reason=, label=, ord=);
  proc sql;
    create table _r_&ord as
      select &SEQVAR as seq length=200, TRTSEQPN as seqn,
             count(distinct USUBJID) as nsubj
      from adsl where RANDFL='Y' and upcase(DCSREAS)=upcase("&reason")
      group by &SEQVAR, TRTSEQPN
    union all
      select 'Total' as seq, 9999 as seqn, count(distinct USUBJID) as nsubj
      from adsl where RANDFL='Y' and upcase(DCSREAS)=upcase("&reason");
  quit;
  data _r_&ord; set _r_&ord; length displbl $60; displbl="   &label"; ord=&ord; run;
%mend dcreason;
%dcreason(reason=ADVERSE EVENT,        label=Adverse Event,             ord=61);
%dcreason(reason=WITHDRAWAL BY PARTICIPANT,label=Withdrawal by Participant,     ord=62);
%dcreason(reason=LOST TO FOLLOW-UP,    label=Lost to Follow-up,         ord=63);
%dcreason(reason=PROTOCOL DEVIATION,   label=Protocol Deviation,        ord=64);
%dcreason(reason=PHYSICIAN DECISION,   label=Physician Decision,        ord=65);
%dcreason(reason=OTHER,                label=Other,                     ord=66);

/*--- supportive: discontinuations by PERIOD in which they occurred --------*/
proc sql;
  create table _byper as
    select &SEQVAR as seq length=200, TRTSEQPN as seqn, DCPERIOD as period,
           count(distinct USUBJID) as nsubj
    from adsl where RANDFL='Y' and DCSREAS ne '' and DCPERIOD ne .
    group by &SEQVAR, TRTSEQPN, DCPERIOD;
quit;
/* render as a small footnote-block / second panel keyed by APERIOD          */

/*--- stack, attach denominators, format n (%), transpose to seq columns ---*/
data _all; set _d_: _r_:; run;
proc sql;
  create table _rep as
    select a.*, b.N as denom,
           catx(' ', put(a.nsubj,4.), cats('(',put(100*a.nsubj/b.N,5.1),'%)')) as value length=20
    from _all a left join _bign b on a.seqn=b.trtn;
quit;
proc sort data=_rep; by ord displbl; run;
proc transpose data=_rep out=_wide; by ord displbl; id seqn; var value; run;  /* one col per sequence + Total */

%tfltitle(num=14.1.1, type=Table, text=Participant Disposition,
          pop=All Randomized Participants,
          foot=%str(Columns are randomized treatment sequences (TRTSEQP). A participant is counted once per category. Percentages based on N randomized per sequence.));
proc report data=_wide nowd split='|';
  columns ord displbl ("Treatment Sequence" _NAME_ /* seq cols + Total */);
  define ord    / order noprint;
  define displbl/ order 'Disposition'  width=34 flow;
  /* define <each sequence var> / display center "&seqhdr (N=&n)";          */
run;
