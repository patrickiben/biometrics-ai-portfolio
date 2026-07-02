/******************************************************************************
* TABLE     : t_disposition  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Participant Disposition
* POPULATION: All Enrolled Participants (ENRLFL='Y'; % denominator = enrolled N)
* INPUT     : ADSL
* NOTE      : PSEUDOCODE. Single-sequence design: every participant is the same
*             across periods (no randomized sequence), so disposition is
*             summarized ONCE per participant (distinct USUBJID) in a single
*             "Treatment Sequence" column + Total. Per-PERIOD completion is
*             shown via the period-completion flags (APERIOD/APERIODC) since
*             a participant may complete the reference period but discontinue
*             before/within the test period. Counts = PARTICIPANTS, % = N enrolled.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, BYPERIOD=APERIOD APERIODC */

/*--- column denominator: the single fixed sequence + Total ----------------
* In a fixed-sequence study the "treatment" column is the sequence label
* carried in ADSL (e.g. TRTSEQ = 'Drug A then Drug A + Drug B'). Population =
* ALL ENROLLED (ENRLFL='Y'); % based on the enrolled N so the numerator
* population (enrolled) and the % denominator are the SAME set.            */
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=&SEQVARN, popfl=ENRLFL, out=_bign);

data adsl; set adam.adsl(where=(ENRLFL='Y')); run;  /* all enrolled for disposition */

/*--- participant-level disposition categories (one row per participant) -----------
* Pull all status flags from ADSL; do NOT re-derive. EOSSTT/DCSREAS are the
* end-of-study status and primary reason for discontinuation.               */
%macro dispoblk(flagexpr=, label=, ord=, popfl=%str(1));
  proc sql noprint;
    create table _d_&ord as
      select &SEQVAR as trt length=200, &SEQVARN as trtn,
             count(distinct USUBJID) as nsubj
      from adsl where (&flagexpr) and (&popfl) group by &SEQVAR, &SEQVARN
    union all
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from adsl where (&flagexpr) and (&popfl);
  quit;
  data _d_&ord; set _d_&ord; length charlbl $60; charlbl="&label"; ord=&ord; run;
%mend;

%dispoblk(flagexpr=%str(1),            label=Participants enrolled,                 ord=1);
%dispoblk(flagexpr=%str(SAFFL='Y'),    label=Included in Safety Population,     ord=2);
%dispoblk(flagexpr=%str(PKFL='Y'),     label=Included in PK Population,         ord=3);
/* period-level dosing: participants dosed in the reference vs test period -------
* Reference period = victim alone (APERIOD=1); test period = victim+perpetrator
* (APERIOD=2). Period dosing flags live in ADSL (e.g. TR01SDT/TR02SDT) or are
* sourced from ADEX; here use ADSL period-start non-missing as "dosed".       */
%dispoblk(flagexpr=%str(not missing(TR01SDTM)), label=Dosed in reference period (Period 1), ord=4);
%dispoblk(flagexpr=%str(not missing(TR02SDTM)), label=Dosed in test period (Period 2),      ord=5);
%dispoblk(flagexpr=%str(EOSSTT='COMPLETED'),    label=Completed the study,                  ord=6);
%dispoblk(flagexpr=%str(EOSSTT='DISCONTINUED'), label=Discontinued the study,               ord=7);

/*--- discontinuation reasons (indented under "Discontinued") ---------------*/
proc sql;
  create table _dcr as
    select &SEQVAR as trt length=200, &SEQVARN as trtn, DCSREAS,
           count(distinct USUBJID) as nsubj
    from adsl where EOSSTT='DISCONTINUED' group by &SEQVAR, &SEQVARN, DCSREAS
  union all
    select 'Total' as trt, 9999 as trtn, DCSREAS, count(distinct USUBJID) as nsubj
    from adsl where EOSSTT='DISCONTINUED' group by DCSREAS;
quit;
data _dcr; set _dcr; length charlbl $60; charlbl='   '||strip(DCSREAS); ord=8; run;

/*--- stack, compute n (%) vs enrolled N, transpose to one col per group ----*/
data _all; set _d_: _dcr; run;
proc sql;                       /* attach column N (enrolled) as denominator  */
  create table _alln as select a.*, b.N
    from _all a left join _bign b on a.trtn=b.trtn;
quit;
data _disp; set _alln; length value $30;
  value = catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'));
run;
proc sort data=_disp; by ord charlbl; run;
proc transpose data=_disp out=_wide; by ord charlbl; id trtn; var value; run;

%tfltitle(num=14.1.1, type=Table, text=Participant Disposition,
   pop=All Enrolled Participants,
   foot=%str(Percentages based on the number of participants enrolled. Period 1 = reference (victim alone); Period 2 = test (victim + perpetrator). A participant discontinuing before Period 2 contributes to reference-period dosing only.));
proc report data=_wide nowd split='|';
  columns ord charlbl ("Treatment Sequence" _NAME_ /* sequence col + Total */);
  define ord     / order noprint;
  define charlbl / order 'Disposition' width=40 flow;
run;
