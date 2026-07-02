/******************************************************************************
* TABLE     : t_dose_proportionality_ss  (MAD - Multiple Ascending Dose)
*             [DESIGN-SPECIFIC]
* TITLE     : Assessment of Dose Proportionality at Steady State (Power Model):
*             Slope (beta) and 90% Confidence Interval
* POPULATION: PK Parameter Population (PKFL='Y')
* INPUT     : ADPP (steady-state Day-N parameters: CMAXSS, AUCTAU, CAVGSS;
*             numeric assigned dose from TRT01AN, matching the R twin)
* NOTE      : PSEUDOCODE. THIS is a file that differs by design (MAD only). Across
*             ascending dose cohorts, assess whether STEADY-STATE exposure rises in
*             proportion to dose using the POWER MODEL on the log scale:
*                   ln(parameter,ss) = alpha + beta * ln(dose) + error
*             Dose proportionality is concluded when the entire 90% CI for the
*             slope beta lies within the predefined critical region derived from
*             the dose range (theta = [1 + ln(rho_low)/ln(r), 1 + ln(rho_high)/ln(r)]
*             where r = highest/lowest dose, rho the acceptance bounds e.g.
*             0.80-1.25; beta = 1 = exact proportionality).
*             Parameters assessed at STEADY STATE: Cmax,ss, AUCtau,ss, Cavg,ss.
*             Parallel cohorts -> one steady-state value per participant; no
*             within-participant term. Active arms only; placebo (dose 0)
*             excluded. Complements t_accumulation (which quantifies Day-1 ->
*             steady-state accumulation within dose). Geometric stats / power
*             model require parameter>0 and dose>0.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);                       /* dose = TRT01A / TRT01AN     */

%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=PKFL, out=_bign);

/*--- steady-state exposure parameters + numeric dose (log scale) ---------
   Active arms only: exclude placebo (dose=0) so ln(dose) is defined and the
   dose-range ratio r = max/min dose never divides by a zero dose. Matches the
   R twin (filter TRT01AN>0) and the SAD sibling (if dose>0).                  */
data pp;
  set adam.adpp(where=(PKFL='Y' and AVAL>0
                       and PARAMCD in ('CMAXSS','AUCTAU','CAVGSS')));
  dose   = TRT01AN;         /* numeric assigned dose (mg) from ADPP/ADSL hint  */
  if dose>0;               /* active doses only - placebo (dose 0) excluded    */
  lndose = log(dose);
  lnval  = log(AVAL);
run;

/*--- predefined critical region for beta from the dose range -------------*/
proc sql noprint;
  select max(dose)/min(dose) into :doser trimmed from pp where dose>0; /* r = high/low dose */
quit;
%let rholo=0.80; %let rhohi=1.25;   /* acceptance bounds for proportionality   */
data _null_;                         /* derive the critical region for beta     */
  call symputx('thetalo', 1 + log(&rholo)/log(&doser));
  call symputx('thetahi', 1 + log(&rhohi)/log(&doser));
run;

/*--- power model per steady-state parameter ------------------------------*/
%macro powerss(param=, lbl=);
  /* per-parameter n (records) and number of distinct dose levels for display  */
  proc sql noprint;
    select count(*), count(distinct dose)
      into :n_&param trimmed, :ndose_&param trimmed
      from pp where PARAMCD="&param";
  quit;
  proc mixed data=pp(where=(PARAMCD="&param")) method=reml;
    model lnval = lndose / solution cl alpha=0.10;   /* beta = slope on lndose; 90% CI */
    ods output SolutionF=_sf_&param FitStatistics=_fit_&param;
  run;
  data _dp_&param; set _sf_&param;
    where upcase(Effect)='LNDOSE';                    /* the slope row           */
    length param $20 n ndose $8 beta ci critreg expratio conclude $24;
    param = "&lbl";
    n     = "&&n_&param";                             /* records in the fit      */
    ndose = "&&ndose_&param";                         /* distinct dose levels    */
    beta  = put(Estimate, 6.3);                       /* slope estimate          */
    ci    = catx(' - ', put(Lower,6.3), put(Upper,6.3));  /* 90% CI of beta      */
    /* predefined critical region [theta_low, theta_high] for beta (vs slope=1)  */
    critreg  = catx(' - ', put(&thetalo,6.3), put(&thetahi,6.3));
    /* dose-proportional if the whole beta 90% CI lies within the critical region */
    conclude = ifc(Lower>=&thetalo and Upper<=&thetahi,
                   'Dose proportional','Not concluded');
    /* exposure ratio implied by the slope across the observed dose range = r^beta */
    expratio = put(&doser**Estimate, 6.2);
  run;
%mend;
%powerss(param=CMAXSS, lbl=%str(Cmax,ss));
%powerss(param=AUCTAU, lbl=%str(AUCtau,ss));
%powerss(param=CAVGSS, lbl=%str(Cavg,ss));

data _dp; set _dp_:; run;

%tfltitle(num=14.4.5.2, type=Table,
   text=%str(Assessment of Dose Proportionality at Steady State (Power Model)),
   pop=Pharmacokinetic Parameter Population,
   foot=%str(Power model: ln(parameter at steady state) = alpha + beta*ln(dose); slope = beta. Dose proportionality is concluded when the entire 90%% CI for beta lies within the predefined critical region [1 + ln(0.80)/ln(r), 1 + ln(1.25)/ln(r)], r = highest/lowest dose. Steady-state parameters: Cmax,ss, AUCtau,ss, Cavg,ss. Exposure Ratio = r^beta (ratio across the observed dose range). Parallel ascending cohorts (between-participant); one steady-state value per participant. Active arms only; placebo (dose 0) excluded.));
proc report data=_dp nowd split='|';
  columns param n ndose beta ('90% CI (beta)' ci) ('Critical|Region' critreg)
          conclude ('Exposure Ratio|(max/min dose)' expratio);
  define param    / display 'Steady-State Parameter' width=22;
  define n        / display 'n' center width=6;
  define ndose    / display '# Dose|Levels' center width=8;
  define beta     / display 'Slope (beta)' center width=12;
  define ci       / display center width=18;
  define critreg  / display center width=16;
  define conclude / display 'Conclusion' center width=18;
  define expratio / display center width=14;
run;
