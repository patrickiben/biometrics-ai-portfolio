/******************************************************************************
* TABLE     : t_ada_summary  (Single-/Fixed-Sequence, e.g. DDI)
* TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Period
* POPULATION: Immunogenicity / ADA Evaluable Population (ADAFL='Y')
* INPUT     : ADIS (immunogenicity analysis: PARAMCD = ADA result flags such
*             as ADA status, treatment-induced/-boosted, NAb; AVALC/AVAL,
*             baseline vs post-baseline ADA)
* NOTE      : PSEUDOCODE. Single-/fixed-sequence (no randomized sequence): each
*             participant passes the fixed PERIODS in the same order, so the column
*             variable is APERIODC/APERIOD (Period 1 = reference, subsequent
*             period(s) = test), NOT a treatment arm. Counts = PARTICIPANTS
*             (distinct USUBJID), NOT records; % denominator = ADA-evaluable N
*             per period (from ADIS where ADAFL='Y'; APERIOD is a BDS per-record
*             var, so the per-period N cannot come from ADSL). Categories: baseline-
*             positive, treatment-emergent (induced + boosted), persistent/
*             transient, NAb-positive.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTVAR=TRTA; BYPERIOD=APERIOD APERIODC */

/*--- header denominators: ADA-evaluable N per PERIOD column ---------------
* Single-sequence immunogenicity is summarized BY PERIOD (fixed order, no
* sequence), so the "column" variable is APERIODC, not the treatment arm.
* APERIOD/APERIODC are BDS per-record vars (not on ADSL), so the per-period
* ADA-evaluable N is built from the period-bearing source ADIS (mirror
* t_exposure.sas): distinct participants ADA-evaluable in the period, plus a Total.*/
proc sql noprint;
  create table _bign as
    select APERIOD as trtn, APERIODC as trt length=200,
           count(distinct USUBJID) as N
    from adam.adis where ADAFL='Y' group by APERIOD, APERIODC
  union all
    select 9999 as trtn, 'Total' as trt, count(distinct USUBJID) as N
    from adam.adis where ADAFL='Y';
quit;

/*--- ADA status records per participant x period (participant-level flags from ADIS)
* ADIS carries the derived immunogenicity flags; select the analysis records
* (e.g. PARAMCD for overall ADA status / NAb status), retaining APERIODC so a
* participant is counted within each fixed period.                              */
data ada;
  set adam.adis(where=(ADAFL='Y'));
  length cat $40;
  /* derive ADA category from ADaM-provided immunogenicity flags (no
     re-derivation of the assay result; map flags to display categories):
       baseline ADA-positive            <- ADIS baseline-positive flag
       treatment-induced ADA-positive   <- ADIS induced flag
       treatment-boosted  ADA-positive  <- ADIS boosted flag
       treatment-emergent ADA-positive  <- induced OR boosted
       persistent ADA                   <- ADIS persistence flag
       transient  ADA                   <- ADIS transient flag
       NAb-positive (among ADA+)        <- ADIS NAb flag                     */
run;

/*--- participant counts per ADA category x period (distinct USUBJID) ----------
* Counts are PARTICIPANTS, % over ADA-evaluable N per period.                    */
proc sql;
  create table _ada as
    select APERIODC as trt length=200, APERIOD as trtn, cat,
           count(distinct USUBJID) as nsubj
    from ada
    group by APERIODC, APERIOD, cat
  union all   /* Total column */
    select 'Total' as trt, 9999 as trtn, cat,
           count(distinct USUBJID) as nsubj
    from ada group by cat;
quit;

/*--- merge denominators -> n (%) of PARTICIPANTS per period column -----------*/
proc sql;
  create table _disp as
    select a.trt, a.trtn, a.cat, a.nsubj, b.N,
           cats(put(a.nsubj,4.),' (',put(100*a.nsubj/b.N,5.1),'%)') as value length=20
    from _ada a left join _bign b on a.trtn=b.trtn;
quit;

proc sort data=_disp; by cat trtn; run;
proc transpose data=_disp out=_wide(drop=_name_); by cat; id trtn; var value; run;

%tfltitle(num=14.5.1.1, type=Table,
   text=%str(Summary of Anti-Drug Antibody (ADA) Incidence by Period),
   pop=Immunogenicity (ADA Evaluable) Population,
   foot=%str(Counts = participants (distinct USUBJID); % = participants / ADA-evaluable N per period. Treatment-emergent = induced or boosted. NAb = neutralizing antibody (among ADA-positive). Single-/fixed-sequence: column = APERIODC (Period 1 = reference; subsequent period(s) = test).));
proc report data=_wide nowd split='|';
  columns cat ("By Period" /* period cols: P1=Reference, P2=Test... + Total */);
  define cat / order 'ADA Category' width=40 flow;
run;
