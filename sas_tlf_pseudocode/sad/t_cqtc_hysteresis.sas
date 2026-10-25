/******************************************************************************
* TABLE     : t_cqtc_hysteresis  (Single Ascending Dose)
* TITLE     : Assessment of Delay between Concentration and ddQTcF before the
*             C-QTc Analysis: Mean Signed Loop Area on Direct-Effect Model
*             Residuals, by Dose
* POPULATION: C-QTc Analysis Set (PKFL='Y' and SAFFL='Y'), active doses
* INPUT     : ADEG (PARAMCD='QTCF'; CHG on Day 1, AVAL on Day -1, ATPTN),
*             ADPC (PARAMCD='CONC'; AVAL, AFRLT actual time, ATPTN)
* NOTE      : PSEUDOCODE. The prespecified hysteresis check (SAP text: see
*             cqtc_hysteresis/index.html). Steps:
*             1. ddQTcF = CHG minus the time-matched placebo mean CHG (placebo
*                pooled); concentrations time-matched on nominal time; each
*                participant's records ordered by ACTUAL time (AFRLT).
*             2. Fit the prespecified direct-effect model with NO time factor on
*                all active doses: ddQTcF = f(C) + b_i + e; f linear (PROC MIXED)
*                or Emax (PROC NLMIXED) if the SAP linearity check selects it
*                (&FORM). A time factor would absorb the delay looked for here.
*             3. r = ddQTcF - f-hat(C) - b-hat_i (conditional residual); x = C /
*                participant's Cmax.
*             4. A_i = 0.5 * sum_j (x_j r_(j+1) - x_(j+1) r_j), closed path
*                (index m+1 = 1); A_i > 0 = counterclockwise = effect lags.
*             5. Test mean(A_i) by participant-level sign flips in PROC IML:
*                exact (all 2**n sign vectors) when n <= 20, otherwise 9,999
*                random sign vectors, p = (1 + #{T* >= T}) / (9,999 + 1).
*                One- and two-sided.
*             6. Report beside it: A-bar with a t-based 95% CI, the tmax gap
*                (median time of peak ddQTcF minus median tmax; and the peak of
*                the mean profile minus median tmax) and the Day -1 pseudo-loop
*                check (Day -1 QTcF, centered and corrected the same way, paired
*                with Day 1 x). Rows: each active dose, then all active doses.
*             A significant result prompts an effect-compartment model; it does
*             not replace the C-QTc analysis. Twin of the R program.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

%let FORM  = LINEAR;     /* prespecified f: LINEAR, or EMAX if the SAP linearity check selects it */
%let SEED  = 20261025;   /* SAP-specified seed for the random sign vectors (n > 20)               */
%let NSIGN = 9999;       /* random sign vectors when n > 20                                        */

/*--- Day 1 dQTcF and the time-matched placebo mean ---------------------------*/
data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and PARAMCD='QTCF' and ADY=1 and CHG ne .));
  keep USUBJID &TRTVAR &TRTNVAR ATPTN CHG;
run;
proc means data=eg(where=(&TRTNVAR=0)) nway noprint;
  class ATPTN;  var CHG;  output out=_pbo(drop=_type_ _freq_) mean=pbo;
run;
proc sql;
  create table cq as
    select e.USUBJID, e.&TRTVAR as trt length=200, e.&TRTNVAR as dose, e.ATPTN,
           e.CHG - p.pbo as ddqtcf, c.AVAL as conc, c.AFRLT
    from eg as e
         inner join _pbo as p on e.ATPTN = p.ATPTN
         inner join adam.adpc(where=(PKFL='Y' and PARAMCD='CONC' and AVAL ne .)) as c
           on e.USUBJID = c.USUBJID and e.ATPTN = c.ATPTN
    where e.&TRTNVAR > 0
    order by USUBJID, AFRLT;                       /* time order = actual time   */
quit;

/*--- Day -1: centered QTcF, placebo-corrected the same way as Day 1 ----------*/
proc sql;
  create table _d1 as
    select USUBJID, &TRTNVAR as dose, ATPTN, AVAL - mean(AVAL) as qc
    from adam.adeg(where=(SAFFL='Y' and PARAMCD='QTCF' and ADY=-1 and AVAL ne .))
    group by USUBJID;
  create table _d1p as
    select ATPTN, mean(qc) as pqc from _d1 where dose=0 group by ATPTN;
  create table d1 as
    select a.USUBJID, a.ATPTN, a.qc - b.pqc as dm1
    from _d1 as a inner join _d1p as b on a.ATPTN = b.ATPTN
    where a.dose > 0;
quit;

/*--- prespecified direct-effect model, no time factor, all active doses ------*/
%macro fitf;
  %if &FORM=LINEAR %then %do;
    proc mixed data=cq method=reml;
      class USUBJID;
      model ddqtcf = conc / solution outp=_res;   /* OUTP: conditional on b-hat_i */
      random intercept / subject=USUBJID;
    run;
    data _res; set _res; resid = ddqtcf - Pred; run;
  %end;
  %else %do;
    proc sql noprint; select median(conc) into :medc trimmed from cq where conc > 0; quit;
    proc nlmixed data=cq;
      parms e0=0 emax=20 ec50=&medc s2e=25 s2b=4;  /* starting values per SAP     */
      pred = e0 + b + emax*conc/(ec50 + conc);
      model ddqtcf ~ normal(pred, s2e);
      random b ~ normal(0, s2b) subject=USUBJID;
      predict pred out=_res;                       /* uses empirical Bayes b-hat_i */
    run;
    data _res; set _res; resid = ddqtcf - Pred; run;
  %end;
%mend fitf;
%fitf;

/*--- x = C / participant Cmax; add the Day -1 series ---------------------------*/
proc sql;
  create table _r2 as
    select r.*, r.conc / max(r.conc) as x, d.dm1
    from _res as r left join d1 as d on r.USUBJID = d.USUBJID and r.ATPTN = d.ATPTN
    group by r.USUBJID
    order by r.USUBJID, r.AFRLT;
quit;

/*--- per-participant closed-path signed areas (Day 1 residual and Day -1) -----*/
data _area(keep=USUBJID trt dose A Adm1);
  set _r2;  by USUBJID;
  retain x1 r1 d1 xp rp dp A Adm1;
  if first.USUBJID then do; x1=x; r1=resid; d1=dm1; A=0; Adm1=0; end;
  else do;
    A    = A    + 0.5*(xp*resid - x*rp);
    Adm1 = Adm1 + 0.5*(xp*dm1   - x*dp);           /* missing if Day -1 incomplete */
  end;
  xp=x; rp=resid; dp=dm1;
  if last.USUBJID then do;
    A    = A    + 0.5*(x*r1 - x1*resid);           /* closing segment: m -> 1     */
    Adm1 = Adm1 + 0.5*(x*d1 - x1*dm1);
    output;
  end;
run;

/*--- per-participant tmax and time of peak ddQTcF; mean profile per dose -------*/
proc sort data=_r2 out=_s1; by USUBJID descending conc ATPTN; run;
data _tmax(keep=USUBJID tmax); set _s1; by USUBJID; if first.USUBJID; tmax=ATPTN; run;
proc sort data=_r2 out=_s2; by USUBJID descending ddqtcf ATPTN; run;
data _tpk(keep=USUBJID tpeak); set _s2; by USUBJID; if first.USUBJID; tpeak=ATPTN; run;
data _part; merge _area _tmax _tpk; by USUBJID; run;
proc means data=_r2 nway noprint;                  /* mean ddQTcF profile         */
  class dose ATPTN; var ddqtcf; output out=_prof(drop=_type_ _freq_) mean=mdd;
run;
proc means data=_r2 nway noprint;                  /* pooled over active doses    */
  class ATPTN; var ddqtcf; output out=_profall(drop=_type_ _freq_) mean=mdd;
run;
data _profall; set _profall; dose=9999; run;       /* 9999 = all active doses     */
data _prof; set _prof _profall; run;

/*--- sign-flip test, CI and summaries by dose and pooled (PROC IML) ------------*/
proc iml;
  start signflip(A) global(nsign, seed);
    n = nrow(A);  T0 = A[:];  tol = 1e-10 * abs(A)[:];
    if n <= 20 then do;                            /* exact: all 2**n signed sums */
      s = {0};
      do i = 1 to n;  s = (s + A[i]) // (s - A[i]);  end;
      Ts = s / n;
      p1 = (Ts >= T0 - tol)[:];  p2 = (abs(Ts) >= abs(T0) - tol)[:];
    end;
    else do;
      call randseed(seed);
      S = j(nsign, n);  call randgen(S, "Bernoulli", 0.5);  S = 2*S - 1;
      Ts = S * A / n;
      p1 = (1 + sum(Ts >= T0 - tol)) / (nsign + 1);
      p2 = (1 + sum(abs(Ts) >= abs(T0) - tol)) / (nsign + 1);
    end;
    return (p1 || p2);
  finish;
  nsign = &NSIGN;  seed = &SEED;
  use _part;  read all var {dose A Adm1 tmax tpeak} into M;  close _part;
  use _prof;  read all var {dose ATPTN mdd} into P;  close _prof;
  doses = unique(M[,1]) || 9999;                   /* each active dose, then all  */
  R = j(ncol(doses), 11, .);
  do k = 1 to ncol(doses);
    if doses[k] = 9999 then idx = 1:nrow(M);  else idx = loc(M[,1] = doses[k]);
    A = M[idx, 2];  n = nrow(A);
    half = quantile("T", 0.975, n - 1) * std(A) / sqrt(n);
    p = signflip(A);
    pr = P[loc(P[,1] = doses[k]), ];
    tmaxmed = median(M[idx, 4]);
    a1 = M[idx, 3];  ok = loc(a1 ^= .);               /* Day -1 evaluable participants */
    if ncol(ok) > 1 then do;  a1 = a1[ok];  pd = signflip(a1);  end;
    else do;  a1 = {.};  pd = {. .};  end;
    R[k, ] = doses[k] || n || A[:] || (A[:] - half) || (A[:] + half) || p ||
             (median(M[idx, 5]) - tmaxmed) ||               /* tmax gap, individual   */
             (pr[pr[,3][<:>], 2] - tmaxmed) ||              /* tmax gap, mean profile */
             a1[:] || pd[2];
  end;
  create _hyst from R[colname={"dose" "n" "abar" "lcl" "ucl" "p1" "p2"
                                "gap_ind" "gap_mean" "abar_dm1" "p2_dm1"}];
  append from R;  close _hyst;
quit;

/*--- display values ------------------------------------------------------------*/
proc sql;
  create table _lbl as select distinct dose, trt from _part order by dose;
quit;
data _disp;
  merge _hyst _lbl;  by dose;
  length dosec $40 abarci $40 p1c p2c gapi gapm $12 dm1c $30 fc $10;
  if dose = 9999 then dosec = 'All active doses';  else dosec = trt;
  abarci = cats(put(abar, 8.2), ' (', put(lcl, 8.2), ', ', put(ucl, 8.2), ')');
  p1c  = put(p1, 6.4);   p2c = put(p2, 6.4);
  gapi = put(gap_ind, 5.1);  gapm = put(gap_mean, 5.1);
  if abar_dm1 = . then dm1c = 'NE';
  else dm1c = cats(put(abar_dm1, 8.2), ' (', put(p2_dm1, 6.4), ')');
  fc = ifc("&FORM" = "LINEAR", 'Linear', 'Emax');
run;

%tfltitle(num=14.3.5.5, type=Table,
   text=%str(Assessment of Delay between Concentration and ddQTcF: Mean Signed Loop Area on Direct-Effect Model Residuals, by Dose),
   pop=C-QTc Analysis Set,
   foot=%str(Area = signed area of each participant's closed path of (concentration / participant Cmax, residual ddQTcF) in time order; positive = counterclockwise = effect lags concentration. Residuals from the prespecified direct-effect model (no time factor, participant random intercept) fitted to all active doses. p: participant-level sign-flip test, exact for n <= 20, otherwise 9,999 random sign vectors. tmax gap: median time of peak ddQTcF (individual) or time of peak mean ddQTcF (mean profile) minus median tmax; > 1 h is flagged in the SAP. Day -1: Day -1 time-matched QTcF, centered and placebo-corrected as on Day 1, paired with Day 1 concentrations; no drug, so any area reflects timing alone. NE = not evaluable. A significant result prompts an effect-compartment model; it does not replace the C-QTc analysis.));
proc report data=_disp nowd split='|';
  columns dose dosec n abarci p1c p2c gapi gapm dm1c fc;
  define dose   / order noprint;
  define dosec  / display 'Dose' width=20 flow;
  define n      / display 'n';
  define abarci / display 'Mean Area, ms|(95% CI)';
  define p1c    / display 'p|One-sided';
  define p2c    / display 'p|Two-sided';
  define gapi   / display 'tmax Gap, h|(Individual)';
  define gapm   / display 'tmax Gap, h|(Mean Profile)';
  define dm1c   / display 'Day -1 Mean Area, ms|(p Two-sided)';
  define fc     / display 'Model|for f';
run;
