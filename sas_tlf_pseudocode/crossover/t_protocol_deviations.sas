/******************************************************************************
* TABLE     : t_protocol_deviations  (Crossover - 2x2 or Williams)
* TITLE     : Important Protocol Deviations by Category
* POPULATION: All Randomized Participants (RANDFL='Y')
* INPUT     : ADSL (deviation flags) and/or ADDV (deviation-level dataset)
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS with >=1 deviation (distinct
*             USUBJID), NOT deviation rows. Columns = randomized SEQUENCE
*             (TRTSEQP) + Total since deviations are attributed to the participant's
*             enrollment, not a period treatment. Important crossover-specific
*             deviations (e.g. dosed out of randomized sequence, washout too
*             short, wrong period) are listed as their own categories. A
*             supportive by-PERIOD (APERIOD) count shows when each occurred.
*             % denominator = N randomized per sequence (%bign).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP BYPERIOD=APERIOD APERIODC */

/* column denominators per randomized SEQUENCE + Total                       */
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=TRTSEQPN, popfl=RANDFL, out=_bign);

/* deviation-level analysis dataset (ADDV); merge sequence from ADSL         */
data dv;
  merge adam.addv(in=d where=(IMPDVFL='Y'))               /* important devs   */
        adam.adsl(keep=USUBJID &SEQVAR TRTSEQPN RANDFL APERIOD APERIODC);
  by USUBJID;
  if d and RANDFL='Y';
run;

/*--- 1) Any important deviation (distinct participants) ---------------------*/
proc sql;
  create table _any as
    select &SEQVAR as seq length=200, TRTSEQPN as seqn,
           count(distinct USUBJID) as nsubj
    from dv group by &SEQVAR, TRTSEQPN
  union all
    select 'Total' as seq, 9999 as seqn, count(distinct USUBJID) as nsubj from dv;
quit;
data _any; set _any; length term $80; term='Participants with any important deviation';
  level=0; ord=0; run;

/*--- 2) by deviation CATEGORY (distinct participants within category) -------
* DVCAT/DVDECOD include study-wide categories + crossover-specific ones:
*   - Dosed out of randomized sequence
*   - Insufficient washout between periods
*   - Treatment administered in wrong period                                 */
proc sql;
  create table _cat as
    select DVCAT, &SEQVAR as seq length=200, TRTSEQPN as seqn,
           count(distinct USUBJID) as nsubj
    from dv group by DVCAT, &SEQVAR, TRTSEQPN
  union all
    select DVCAT, 'Total' as seq, 9999 as seqn, count(distinct USUBJID) as nsubj
    from dv group by DVCAT;
quit;
data _cat; set _cat; length term $80; term=DVCAT; level=1;
  /* ordering key: Total-column participant count desc (set after merge)         */
run;

/*--- supportive: deviations by PERIOD in which they occurred -------------*/
proc sql;
  create table _byper as
    select APERIODC, DVCAT, count(distinct USUBJID) as nsubj
    from dv where APERIOD ne . group by APERIODC, DVCAT;
quit;

/*--- assemble, attach denominators, format n (%), transpose -------------*/
data _rep0; set _any _cat; run;
proc sql;
  create table _ord as
    select DVCAT, sum(nsubj) as catn from _cat where seq='Total' group by DVCAT;
  create table _rep as
    select r.*, b.N as denom,
           catx(' ', put(r.nsubj,4.), cats('(',put(100*r.nsubj/b.N,5.1),'%)')) as value length=20
    from _rep0 r left join _bign b on r.seqn=b.trtn;
quit;
proc sort data=_rep; by ord level term; run;
proc transpose data=_rep out=_wide; by ord level term; id seqn; var value; run;  /* seq cols + Total */

%tfltitle(num=14.1.5, type=Table, text=Important Protocol Deviations by Category,
          pop=All Randomized Participants,
          foot=%str(A participant is counted once per category. Columns are randomized treatment sequences (TRTSEQP). Crossover-specific categories include out-of-sequence dosing and insufficient washout. Percentages based on N randomized per sequence.));
proc report data=_wide nowd split='|';
  columns ord level term ("Treatment Sequence" _NAME_  /* seq cols + Total */);
  define ord   / order noprint;
  define level / order noprint;
  define term  / order 'Deviation Category' width=44 flow;
  /* define <each sequence var> / display center "&seqhdr (N=&n)";          */
run;
