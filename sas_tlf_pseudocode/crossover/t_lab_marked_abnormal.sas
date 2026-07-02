/******************************************************************************
* TABLE     : t_lab_marked_abnormal  (Crossover - 2x2 or Williams)
* TITLE     : Participants with Markedly Abnormal Post-Baseline Laboratory Values
* POPULATION: Safety Population (SAFFL='Y')
* INPUT     : ADLB (PARAM/PARAMCD, AVAL, ANRIND, A1HI/A1LO, ATOXGR, BTOXGR,
*             TRTA/TRTAN, APERIODC, TRTSEQP)
* NOTE      : PSEUDOCODE. Counts PARTICIPANTS (distinct USUBJID) with >=1 markedly
*             abnormal post-baseline value per parameter, split Low / High.
*             "Markedly abnormal" = ADaM marked-abnormal/PCS flag where present,
*             else a worst post-baseline toxicity grade >=3 (ATOXGR), or a
*             value beyond the marked-range multiple of the normal limit.
*             % denominator = N per treatment (from %bign). Within-participant
*             crossover -> columns = analysis treatment TRTA; each participant
*             contributes per treatment received. APERIODC retained for an
*             optional by-period breakout.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/* column denominators (N=) per treatment + Total (Safety Population) */
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=SAFFL, out=_bign);

/* post-baseline analysis records; identify markedly-abnormal values         */
data lb;
  set adam.adlb(where=(SAFFL='Y' and ANL01FL='Y' and AVISITN>0));
  length mdir $4;
  /* prefer an ADaM marked/PCS flag; else grade>=3; else beyond marked limit  */
  marked = (coalescec(CRIT1FL,'')='Y')                       /* PCS criterion  */
           or (not missing(ATOXGR) and input(ATOXGR,?? best.)>=3)
           or (not missing(A1HI) and AVAL > 1.5*A1HI)        /* high placeholder */
           or (not missing(A1LO) and AVAL < 0.5*A1LO);       /* low  placeholder */
  /* guard missing limits: in SAS missing is smallest, so a bare AVAL>=A1HI    *
   * with A1HI missing would be TRUE and mislabel every value 'High'.          */
       if not missing(A1HI) and AVAL >= A1HI then mdir='High';
  else if not missing(A1LO) and AVAL <= A1LO then mdir='Low';
  else mdir = ifc(upcase(ANRIND)='HIGH','High','Low');
  if marked;                          /* keep only markedly-abnormal records   */
  /* Treatment/period/sequence taken straight from ADaM - no re-derivation     */
run;

/*--- participants with >=1 marked value, per treatment x parameter x direction --*
* Counts = DISTINCT USUBJID (participants), not records. CLASS carries &TRTVAR    *
* (=TRTA) so each treatment received is its own column. Add APERIODC to the    *
* group for a by-period breakout.                                            */
proc sql;
  create table _mark as
    select &TRTVAR as trt length=200, &TRTNVAR as trtn,
           PARAMCD, PARAM, mdir,
           count(distinct USUBJID) as nsubj
    from lb
    group by &TRTVAR, &TRTNVAR, PARAMCD, PARAM, mdir
  union all  /* Total column */
    select 'Total' as trt, 9999 as trtn, PARAMCD, PARAM, mdir,
           count(distinct USUBJID) as nsubj
    from lb group by PARAMCD, PARAM, mdir;
quit;
/* merge _bign by trtn -> pct = nsubj/N*100 ; value = "n (xx.x%)"             */

proc sort data=_mark; by PARAMCD PARAM mdir trtn; run;
proc transpose data=_mark out=_wide;
  by PARAMCD PARAM mdir;
  id trtn; var nsubj;             /* one col per treatment + Total            */
run;

%tfltitle(num=14.3.4.3, type=Table,
   text=%str(Participants with Markedly Abnormal Post-Baseline Laboratory Values),
   pop=Safety Population,
   foot=%str(Counts = participants (distinct USUBJID) with at least one markedly abnormal post-baseline value. Marked = ADaM PCS/marked-abnormal criterion (else worst grade >= 3). % = n / N in the Safety Population per treatment. Participants contribute per treatment received (crossover).));
proc report data=_wide nowd split='|';
  columns PARAM mdir ("Treatment" /* trt cols + Total */);
  define PARAM / order 'Laboratory|Parameter' width=24 flow;
  define mdir  / display 'Direction'           width=10;   /* Low / High      */
  /* define <each treatment var> / display center "&header (N=&n)";           */
  break after PARAM / skip;
run;
