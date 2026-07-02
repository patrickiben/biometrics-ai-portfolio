/******************************************************************************
* TABLE     : t_be_anova  (Single-/fixed-sequence - e.g. DDI)
* TITLE     : Statistical Comparison of PK Exposure (Test vs Reference Period)
*             Geometric Mean Ratios and 90% Confidence Intervals
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO)
* NOTE      : PSEUDOCODE. THIS is the file that differs by design. Single-/
*             fixed-sequence DDI: the SAME participants receive the victim alone in
*             the REFERENCE period, then victim+perpetrator in the TEST period,
*             in a fixed order. There is NO randomized sequence, so the mixed
*             model carries NO sequence term: fixed effect = treatment (period
*             aliases with treatment under a fixed single-sequence design, so a
*             separate period term is not estimable and is dropped); random
*             effect = participant. The contrast is the Test PERIOD vs the
*             designated REFERENCE PERIOD. GMR = exp(LSMdiff); 90% CI =
*             exp(LSMdiff +/- t*SE). For DDI the no-interaction reference window
*             is typically 80-125%; report the CI and let the interaction call
*             be made against the prespecified window.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SINGLESEQ);     /* TRTA + APERIOD/APERIODC; SEQVAR empty     */

data pp;
  set adam.adpp(where=(PKFL='Y' and PARAMCD in ('CMAX','AUCLST','AUCIFO') and AVAL>0));
  lnval = log(AVAL);
  trt   = &TRTVAR;          /* Test (victim+perpetrator) / Reference (victim)   */
  per   = APERIOD;          /* dosing period; aliases with trt under fixed seq  */
  subj  = USUBJID;
  /* NO sequence variable: single-/fixed-sequence has no randomized sequence    */
run;

%macro be(param=);
  /*--- mixed model per parameter on the log scale (NO sequence term) ----*/
  proc mixed data=pp(where=(PARAMCD="&param")) method=reml;
    class subj trt;
    model lnval = trt / ddfm=kr;          /* fixed: treatment only (no seq)     */
    random subj;                           /* participant as own control            */
    /* Test vs Reference difference of LS-means on log scale + 90% CI            */
    lsmeans trt / cl alpha=0.10 diff;
    ods output diffs=_d_&param lsmeans=_ls_&param;
  run;
  data _be_&param; set _d_&param;
    where (upcase(trt)='TEST' and upcase(_trt)='REFERENCE')
       or (upcase(trt)='REFERENCE' and upcase(_trt)='TEST');
    length param $20 gmr ci $24 within $3;
    param   = "&param";
    gmr     = put(100*exp(Estimate), 6.2);                 /* GMR %             */
    ci      = catx(' - ', put(100*exp(Lower),6.2), put(100*exp(Upper),6.2));
    within  = ifc(100*exp(Lower)>=80 and 100*exp(Upper)<=125, 'Yes','No');
    intracv = .;   /* 100*sqrt(exp(ResidualVar)-1) from CovParms if needed       */
  run;
%mend;
%be(param=CMAX);  %be(param=AUCLST);  %be(param=AUCIFO);

data _be; set _be_:; run;

%tfltitle(num=14.4.3.1, type=Table,
   text=%str(Geometric Mean Ratios and 90% Confidence Intervals: Test vs Reference Period),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Single-/fixed-sequence: mixed model ln(parameter) = treatment (NO sequence term; period aliases with treatment), random participant. GMR=exp(LS-mean difference), Test period vs designated reference period. 90% CI back-transformed. No-interaction window typically 80-125%.));
proc report data=_be nowd split='|';
  columns param gmr ('90% CI (%)' ci) ('Within 80-125%' within) ('Intra-participant CV%' intracv);
  define param   / display 'PK Parameter' width=20;
  define gmr     / display 'GMR (Test/Ref) %' center width=16;
  define ci      / display center width=18;
  define within  / display center width=14;
  define intracv / display center width=16;
run;
