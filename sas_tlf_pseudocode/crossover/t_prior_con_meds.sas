/******************************************************************************
* TABLE     : t_prior_con_meds  (Crossover - 2x2 or Williams)
* TITLE     : Prior and Concomitant Medications by ATC Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADCM
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS taking >=1 medication (distinct
*             USUBJID), NOT medication rows. PRIOR (PREFL='Y') and CONCOMITANT
*             (ONTRTFL='Y') summarized separately. In a crossover, concomitant
*             meds can fall in different PERIODS; the main columns are randomized
*             SEQUENCE (TRTSEQP, participant counted once) and a supportive panel
*             attributes concomitant meds to the period treatment (TRTA) using
*             ADCM ONTRTFL/APERIOD. % denominator = Safety N per sequence (%bign).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* SEQVAR=TRTSEQP TRTVAR=TRTA BYPERIOD=APERIOD */

/* participant-level denominators per randomized SEQUENCE + Total                */
%bign(ds=adam.adsl, trtvar=&SEQVAR, trtn=TRTSEQPN, popfl=SAFFL, out=_bign);

/* ADCM with sequence (participant-level) attached for the main panel            */
data cm;
  merge adam.adcm(in=c where=(SAFFL='Y'))
        adam.adsl(keep=USUBJID &SEQVAR TRTSEQPN);
  by USUBJID; if c;
run;

/*--- counting macro: distinct participants per sequence at a coding level -----
* medflag = PREFL='Y' (prior) or ONTRTFL='Y' (concomitant)                   */
%macro cmcount(medflag=, byvars=, level=, ord0=);
  proc sql;
    create table _cc_&ord0 as
      select &SEQVAR as seq length=200, TRTSEQPN as seqn, %unquote(&byvars),
             count(distinct USUBJID) as nsubj
      from cm where &medflag group by &SEQVAR, TRTSEQPN, %unquote(&byvars)
    union all
      select 'Total' as seq, 9999 as seqn, %unquote(&byvars),
             count(distinct USUBJID) as nsubj
      from cm where &medflag group by %unquote(&byvars);
  quit;
  data _cc_&ord0; set _cc_&ord0; length term $200; level=&level;
    %if &level=0 %then %do; term='Participants with any medication'; %end;
    %else %if &level=1 %then %do; term=CMCLAS; %end;     /* ATC class        */
    %else %do; term='   '||CMDECOD; %end;                /* preferred term   */
  run;
%mend;

/*================= PRIOR MEDICATIONS (PREFL='Y') ========================*/
%cmcount(medflag=%str(PREFL='Y'),  byvars=%str(_dummy),         level=0, ord0=p0);
%cmcount(medflag=%str(PREFL='Y'),  byvars=%str(CMCLAS),         level=1, ord0=p1);
%cmcount(medflag=%str(PREFL='Y'),  byvars=%str(CMCLAS CMDECOD), level=2, ord0=p2);

/*============= CONCOMITANT MEDICATIONS (ONTRTFL='Y') ===================*/
%cmcount(medflag=%str(ONTRTFL='Y'), byvars=%str(_dummy),         level=0, ord0=c0);
%cmcount(medflag=%str(ONTRTFL='Y'), byvars=%str(CMCLAS),         level=1, ord0=c1);
%cmcount(medflag=%str(ONTRTFL='Y'), byvars=%str(CMCLAS CMDECOD), level=2, ord0=c2);

/*--- supportive: concomitant meds attributed to PERIOD treatment (TRTA) ---
* For meds with ONTRTFL='Y', ADCM carries APERIOD/TRTA of the active period;
* this panel shows concomitant-med participants by TRTA so period imbalance is
* visible alongside the by-sequence main table.                              */
proc sql;
  create table _bytrt as
    select TRTA, CMCLAS, count(distinct USUBJID) as nsubj
    from adam.adcm where SAFFL='Y' and ONTRTFL='Y' and TRTA ne ''
    group by TRTA, CMCLAS;
quit;

/*--- assemble each block (prior / concomitant), order, format, transpose --*/
%macro assemble(prefix=, secord=, sectitle=);
  data _blk; set _cc_&prefix.0 _cc_&prefix.1 _cc_&prefix.2; run;
  proc sql;  /* ATC sorted by Total participants desc; PT within ATC desc        */
    create table _clord as select CMCLAS, sum(nsubj) as cn from _cc_&prefix.1
      where seq='Total' group by CMCLAS;
    create table _rep as
      select b.*, d.N as denom, &secord as secord,
             catx(' ', put(b.nsubj,4.), cats('(',put(100*b.nsubj/d.N,5.1),'%)')) as value length=20
      from _blk b left join _bign d on b.seqn=d.trtn;
  quit;
  data _rep; set _rep; length section $40; section="&sectitle"; run;
  proc append base=_repall data=_rep force; run;
%mend;
%assemble(prefix=p, secord=1, sectitle=Prior Medications);
%assemble(prefix=c, secord=2, sectitle=Concomitant Medications);

proc sort data=_repall; by secord level term; run;
proc transpose data=_repall out=_wide; by secord section level term; id seqn; var value; run;

%tfltitle(num=14.1.6, type=Table,
   text=%str(Prior and Concomitant Medications by ATC Class and Preferred Term),
   pop=Safety Population,
   foot=%str(A participant is counted once at each coding level. Columns are randomized treatment sequences (TRTSEQP). Coded with WHO Drug. Prior = before first dose; Concomitant = on treatment. Percentages based on Safety N per sequence.));
proc report data=_wide nowd split='|';
  columns secord section level term ("Treatment Sequence" _NAME_  /* seq cols + Total */);
  define secord  / order noprint;
  define section / order 'Medication Timing' width=16 flow;
  define level   / order noprint;
  define term    / order 'ATC Class / Preferred Term' width=40 flow;
  /* define <each sequence var> / display center "&seqhdr (N=&n)";          */
run;
