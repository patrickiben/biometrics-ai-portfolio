/******************************************************************************
* TABLE     : t_prior_con_meds  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Prior and Concomitant Medications by Drug Class and Preferred Term
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADCM
* NOTE      : PSEUDOCODE. Counts = PARTICIPANTS taking >=1 medication (distinct
*             USUBJID), NOT medication rows. BOTH a Prior block (PREFL='Y') and a
*             Concomitant block (CONFL='Y') are summarized. Single-sequence DDI
*             design: meds are shown BY PERIOD (APERIOD/APERIODC) so the
*             interacting perpetrator drug (present only in the test period,
*             Period 2) is visible against the reference period (Period 1).
*             Columns = Period 1 (Reference) | Period 2 (Test) | Total. WHO-DD
*             class (CMCLAS) and preferred term (CMDECOD). % = participants / N.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA, BYPERIOD=APERIOD APERIODC */

/*--- per-PERIOD denominators for the med columns --------------------------
* The perpetrator (interacting drug) is administered only in the test period,
* so medication exposure is most informative split by period.                */
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200, count(distinct USUBJID) as N
    from adam.adex where SAFFL='Y' group by APERIOD, APERIODC  /* per-period pop from ADEX */
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adsl where SAFFL='Y';
quit;

/*--- one block per medication-timing flag: PREFL (Prior) | CONFL (Concomitant)
* The macro builds the same any/class/class*PT structure BY PERIOD (+Total) for
* the supplied flag, tagging each block with &blk so both stack into one table. */
%macro cmblock(flag=, blk=, lbl=);
  data _cm; set adam.adcm(where=(SAFFL='Y' and &flag='Y')); run;

  /* 1) any medication, distinct participants, by period */
  proc sql;
    create table _any as
      select APERIOD as trtn, APERIODC as trt length=200, count(distinct USUBJID) as nsubj
      from _cm group by APERIOD, APERIODC
    union all
      select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as nsubj from _cm;
  quit;
  data _any; set _any; length term $200; term="Participants with any &lbl"; level=0; run;

  /* 2) by ATC/WHO-DD class (distinct participants within class, by period) */
  proc sql;
    create table _cls as
      select APERIOD as trtn, APERIODC as trt length=200, CMCLAS, count(distinct USUBJID) as nsubj
      from _cm group by APERIOD, APERIODC, CMCLAS
    union all
      select 9999 as trtn, 'Total' as trt, CMCLAS, count(distinct USUBJID) as nsubj
      from _cm group by CMCLAS;
  quit;
  data _cls; set _cls; length term $200; term=CMCLAS; level=1; run;

  /* 3) by class*preferred term (distinct participants, by period) */
  proc sql;
    create table _pt as
      select APERIOD as trtn, APERIODC as trt length=200, CMCLAS, CMDECOD, count(distinct USUBJID) as nsubj
      from _cm group by APERIOD, APERIODC, CMCLAS, CMDECOD
    union all
      select 9999 as trtn, 'Total' as trt, CMCLAS, CMDECOD, count(distinct USUBJID) as nsubj
      from _cm group by CMCLAS, CMDECOD;
  quit;
  data _pt; set _pt; length term $200; term='   '||strip(CMDECOD); level=2; run;

  data _blk_&blk; set _any _cls _pt; length block $24; block="&blk"; run;
%mend cmblock;

%cmblock(flag=PREFL, blk=Prior,        lbl=prior medication);
%cmblock(flag=CONFL, blk=Concomitant,  lbl=concomitant medication);

/*--- assemble both blocks, n (%) vs period N, transpose to period columns ----*/
data _rep; set _blk_Prior _blk_Concomitant; run;
proc sql;
  create table _repn as select a.*, b.N from _rep a left join _bign b on a.trtn=b.trtn;
quit;
data _repv; set _repn; length value $30;
  value=catx(' ', put(nsubj,4.), cats('(',put(100*nsubj/N,5.1),'%)'));
run;
/* order PT under class by Total-column count desc, then: */
proc sort data=_repv; by block level term; run;
proc transpose data=_repv out=_wide; by block level term; id trtn; var value; run;

%tfltitle(num=14.1.6, type=Table,
   text=%str(Prior and Concomitant Medications by Drug Class and Preferred Term),
   pop=Safety Population,
   foot=%str(A participant is counted once at each level per period. Prior = PREFL (before first dose); concomitant = CONFL (ongoing during treatment). Period 1 = reference (victim alone); Period 2 = test (victim + perpetrator); the perpetrator medication appears in Period 2. WHO Drug Dictionary; class = ATC level. Percentages within period N.));
proc report data=_wide nowd split='|';
  columns block level term ("Study Period" /* Period1 | Period2 | Total */);
  define block / order 'Medication Timing' width=16;
  define level / order noprint;
  define term  / order 'Drug Class|  Preferred Term' width=44 flow;
  break after block / skip;
run;
