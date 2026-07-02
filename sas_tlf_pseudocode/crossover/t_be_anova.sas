/******************************************************************************
* TABLE     : t_be_anova  (Crossover - 2x2 or Williams)
* TITLE     : Statistical Comparison of PK Exposure (Test vs Reference)
*             Geometric Mean Ratios and 90% Confidence Intervals
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (PARAMCD = CMAX, AUCLST, AUCIFO)
* NOTE      : PSEUDOCODE. THIS is the file that differs by design. Mixed model
*             on ln-transformed exposure with fixed effects sequence, period,
*             treatment and random participant(sequence). GMR = exp(LSMdiff);
*             90% CI = exp(LSMdiff +/- t*SE). BE concluded if CI within 80-125%.
*             Single-/fixed-sequence variant: drop SEQUENCE, ratio vs the
*             designated reference PERIOD (see single_sequence/t_be_anova.sas).
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTA + APERIOD + TRTSEQP available    */

data pp;
  set adam.adpp(where=(PKFL='Y' and PARAMCD in ('CMAX','AUCLST','AUCIFO') and AVAL>0));
  lnval = log(AVAL);
  trt   = TRTA;          /* Test / Reference (analysis treatment)           */
  seq   = TRTSEQP;       /* e.g. 'TR' / 'RT'                                 */
  per   = APERIOD;       /* 1 / 2 (or 1..k for Williams)                     */
  subj  = USUBJID;
run;

%macro be(param=);
  /*--- mixed model per parameter on the log scale ----------------------*/
  proc mixed data=pp(where=(PARAMCD="&param")) method=reml;
    class subj seq per trt;
    model lnval = seq per trt / ddfm=kr;
    random subj(seq);
    /* Test vs Reference difference of LS-means on log scale + 90% CI       */
    lsmeans trt / cl alpha=0.10 diff;
    ods output diffs=_d_&param lsmeans=_ls_&param;
  run;
  data _be_&param; set _d_&param;
    where (upcase(trt)='TEST' and upcase(_trt)='REFERENCE')
       or (upcase(trt)='REFERENCE' and upcase(_trt)='TEST');
    length param $20 gmr ci $24;
    param   = "&param";
    gmr     = put(100*exp(Estimate), 6.2);                 /* GMR %         */
    ci      = catx(' - ', put(100*exp(Lower),6.2), put(100*exp(Upper),6.2));
    within  = ifc(100*exp(Lower)>=80 and 100*exp(Upper)<=125, 'Yes','No');
    intracv = .;   /* 100*sqrt(exp(ResidualVar)-1) from CovParms if needed   */
  run;
%mend;
%be(param=CMAX);  %be(param=AUCLST);  %be(param=AUCIFO);

data _be; set _be_:; run;

%tfltitle(num=14.4.3.1, type=Table,
   text=%str(Geometric Mean Ratios and 90% Confidence Intervals: Test vs Reference),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Mixed model: ln(parameter) = sequence period treatment, random participant(sequence). GMR=exp(LS-mean difference). 90% CI back-transformed. Reference = designated reference treatment.));
proc report data=_be nowd split='|';
  columns param gmr ('90% CI (%)' ci)
          ('Within 80-125%' within) ('Intra-participant CV%' intracv);
  define param   / display 'PK Parameter' width=20;
  define gmr     / display 'GMR (Test/Ref) %' center width=14;
  define ci      / display center width=18;
  define within  / display center width=12;
  define intracv / display center width=12;
run;
