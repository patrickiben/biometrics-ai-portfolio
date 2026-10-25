/******************************************************************************
* TABLE     : t_cqtc_hysteresis  (Multiple Ascending Dose)
* TITLE     : Assessment of Delay between Concentration and ddQTcF before the
*             C-QTc Analysis: Mean Signed Loop Area on Direct-Effect Model
*             Residuals, by Dose and Profile Day
* POPULATION: C-QTc Analysis Set (PKFL='Y' and SAFFL='Y'), active doses;
*             placebo participants (pooled) for the time-matched placebo mean
* INPUT     : ADEG (PARAMCD='QTCF'; CHG on the profile days, AVAL on Day -1,
*             ADY, ATPTN), ADPC (PARAMCD='CONC'; AVAL, ARRLT actual time from
*             the most recent dose, ADY, ATPTN)
* NOTE      : PSEUDOCODE. The prespecified hysteresis check (SAP text: see
*             cqtc_hysteresis/index.html), run separately on each full-profile
*             day (Day 1 and the steady-state day, &PROFDAYS). Steps:
*             1. ddQTcF = CHG minus the time-matched placebo mean CHG on the
*                same day (placebo pooled); concentrations time-matched on day
*                and nominal time; records ordered by ACTUAL time since the most
*                recent dose (ARRLT) within each participant and day.
*             2. Fit the prespecified direct-effect model with NO time factor on
*                all active doses and profile days: ddQTcF = f(C) + b_i + e; f
*                linear (PROC MIXED)
*                or Emax (PROC NLMIXED) if the SAP linearity check selects it
*                (&FORM). A time factor would absorb the delay looked for here.
*             3. r = ddQTcF - f-hat(C) - b-hat_i (conditional residual); x = C /
*                the participant's Cmax on that day (trough start at steady state).
*             4. A_i = 0.5 * sum_j (x_j r_(j+1) - x_(j+1) r_j), closed path
*                (index m+1 = 1); A_i > 0 = counterclockwise = effect lags.
*             5. Every A_i shares the placebo-mean noise, so the test adds it
*                (PROC IML): h_k = signed area of placebo participant k's CHG
*                minus the placebo mean on that day, against the mean x of the
*                row's active participants at each nominal time. t = mean(A)/SE,
*                SE**2 = var(A)/n + var(h)/n_pbo, Welch-Satterthwaite df;
*                one- and two-sided p, and the 95% CI from the same SE and df.
*                (A one-sample sign-flip test of the A_i ignores the shared term
*                and rejects too often. Use it only if each participant's ddQTcF
*                is corrected by their own placebo period: signflip_test() in
*                cqtc_hysteresis/R/area.R.)
*             6. Report beside it: the tmax gap (median time of peak ddQTcF
*                minus median tmax; and the peak of the mean profile minus
*                median tmax) and the Day -1 pseudo-loop check (Day -1 QTcF,
*                centered and corrected the same way, paired with that day's x,
*                and tested the same way). Rows per day: each active dose, then all.
*             A significant result prompts an effect-compartment model; it does
*             not replace the C-QTc analysis. Twin of the R program.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

%let PROFDAYS = 1 14;    /* full-profile days per the SAP (Day 1 and steady state)                 */
%let FORM  = LINEAR;     /* prespecified f: LINEAR, or EMAX if the SAP linearity check selects it */

/*--- profile-day dQTcF and the time-matched placebo mean ----------------------*/
data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and PARAMCD='QTCF'
                       and ADY in (&PROFDAYS) and CHG ne .));
  keep USUBJID &TRTVAR &TRTNVAR ADY ATPTN CHG;
run;
proc means data=eg(where=(&TRTNVAR=0)) nway noprint;
  class ADY ATPTN;  var CHG;  output out=_pbo(drop=_type_ _freq_) mean=pbo;
run;
proc sql;
  create table cq as
    select e.USUBJID, e.&TRTVAR as trt length=200, e.&TRTNVAR as dose, e.ADY, e.ATPTN,
           e.CHG - p.pbo as ddqtcf, c.AVAL as conc, c.ARRLT
    from eg as e
         inner join _pbo as p on e.ADY = p.ADY and e.ATPTN = p.ATPTN
         inner join adam.adpc(where=(PKFL='Y' and PARAMCD='CONC' and AVAL ne .)) as c
           on e.USUBJID = c.USUBJID and e.ADY = c.ADY and e.ATPTN = c.ATPTN
    where e.&TRTNVAR > 0
    order by USUBJID, ADY, ARRLT;                  /* time order within the interval */
  create table _pdev as                            /* placebo deviations from their mean */
    select e.USUBJID, e.ADY, e.ATPTN, e.CHG - p.pbo as dev
    from eg as e inner join _pbo as p on e.ADY = p.ADY and e.ATPTN = p.ATPTN
    where e.&TRTNVAR = 0
    order by USUBJID, ADY, ATPTN;
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
  create table _pdev1 as
    select a.USUBJID, a.ATPTN, a.qc - b.pqc as dev
    from _d1 as a inner join _d1p as b on a.ATPTN = b.ATPTN
    where a.dose = 0
    order by USUBJID, ATPTN;
quit;

/*--- prespecified direct-effect model, no time factor, all doses and days ----*/
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

/*--- x = C / participant Cmax on that day; add the Day -1 series --------------*/
proc sql;
  create table _r2 as
    select r.*, r.conc / max(r.conc) as x, d.dm1
    from _res as r left join d1 as d on r.USUBJID = d.USUBJID and r.ATPTN = d.ATPTN
    group by r.USUBJID, r.ADY
    order by r.USUBJID, r.ADY, r.ARRLT;
quit;

/*--- per-participant closed-path signed areas (Day 1 residual and Day -1) -----*/
data _area(keep=USUBJID trt dose ADY A Adm1);
  set _r2;  by USUBJID ADY;
  retain x1 r1 d1 xp rp dp A Adm1;
  if first.ADY then do; x1=x; r1=resid; d1=dm1; A=0; Adm1=0; end;
  else do;
    A    = A    + 0.5*(xp*resid - x*rp);
    Adm1 = Adm1 + 0.5*(xp*dm1   - x*dp);           /* missing if Day -1 incomplete */
  end;
  xp=x; rp=resid; dp=dm1;
  if last.ADY then do;
    A    = A    + 0.5*(x*r1 - x1*resid);           /* closing segment: m -> 1     */
    Adm1 = Adm1 + 0.5*(x*d1 - x1*dm1);
    output;
  end;
run;

/*--- per-participant tmax and time of peak ddQTcF; mean profile per dose -------*/
proc sort data=_r2 out=_s1; by USUBJID ADY descending conc ATPTN; run;
data _tmax(keep=USUBJID ADY tmax); set _s1; by USUBJID ADY; if first.ADY; tmax=ATPTN; run;
proc sort data=_r2 out=_s2; by USUBJID ADY descending ddqtcf ATPTN; run;
data _tpk(keep=USUBJID ADY tpeak); set _s2; by USUBJID ADY; if first.ADY; tpeak=ATPTN; run;
data _part; merge _area _tmax _tpk; by USUBJID ADY; run;
proc means data=_r2 nway noprint;                  /* mean ddQTcF profile         */
  class ADY dose ATPTN; var ddqtcf; output out=_prof(drop=_type_ _freq_) mean=mdd;
run;
proc means data=_r2 nway noprint;                  /* pooled over active doses    */
  class ADY ATPTN; var ddqtcf; output out=_profall(drop=_type_ _freq_) mean=mdd;
run;
data _profall; set _profall; dose=9999; run;       /* 9999 = all active doses     */
data _prof; set _prof _profall; run;

/*--- mean x of each row's active participants by day and nominal time ----------*/
proc means data=_r2 nway noprint;
  class ADY dose ATPTN; var x; output out=_xb(drop=_type_ _freq_) mean=xm;
run;
proc means data=_r2 nway noprint;
  class ADY ATPTN; var x; output out=_xball(drop=_type_ _freq_) mean=xm;
run;
data _xball; set _xball; dose=9999; run;
data _xb; set _xb _xball; run;

/*--- placebo participants' areas against each row's mean x (h: profile day, h1:
      Day -1, paired with each profile day's mean x) ------------------------------*/
%macro pboarea(in=, out=, var=, on=);
  proc sql;
    create table _ph as
      select x.ADY, x.dose, p.USUBJID, p.ATPTN, x.xm, p.dev
      from &in as p inner join _xb as x on &on
      order by ADY, dose, USUBJID, ATPTN;          /* nominal-time order          */
  quit;
  data &out(keep=ADY dose USUBJID &var);
    set _ph;  by ADY dose USUBJID;
    retain x1 v1 xp vp &var;
    if first.USUBJID then do; x1=xm; v1=dev; &var=0; end;
    else &var = &var + 0.5*(xp*dev - xm*vp);
    xp=xm; vp=dev;
    if last.USUBJID then do; &var = &var + 0.5*(xm*v1 - x1*dev); output; end;
  run;
%mend pboarea;
%pboarea(in=_pdev,  out=_harea,  var=h,  on=%str(p.ADY = x.ADY and p.ATPTN = x.ATPTN));
%pboarea(in=_pdev1, out=_harea1, var=h1, on=%str(p.ATPTN = x.ATPTN));

/*--- placebo-adjusted t-test, CI and summaries by day and dose (PROC IML) -----*/
proc iml;
  start pbot(A, h);                                /* t-test of mean(A); SE adds the placebo part */
    n = nrow(A);  np = nrow(h);
    va = ssq(A - A[:]) / (n - 1) / n;  vh = ssq(h - h[:]) / (np - 1) / np;
    se = sqrt(va + vh);
    df = (va + vh)##2 / (va##2 / (n - 1) + vh##2 / (np - 1));   /* Welch-Satterthwaite */
    t0 = A[:] / se;  q = quantile("T", 0.975, df);
    return (A[:] || (A[:] - q*se) || (A[:] + q*se) || (1 - probt(t0, df)) ||
            (2 * (1 - probt(abs(t0), df))));      /* est lcl ucl p1 p2           */
  finish;
  use _part;    read all var {dose A Adm1 tmax tpeak ADY} into M;  close _part;
  use _prof;    read all var {dose ATPTN mdd ADY} into P;          close _prof;
  use _harea;   read all var {ADY dose h} into H;                  close _harea;
  use _harea1;  read all var {ADY dose h1} into H1;                close _harea1;
  days = unique(M[,6]);  doses = unique(M[,1]) || 9999;   /* each active dose, then all */
  R = j(ncol(days) * ncol(doses), 13, .);  row = 0;
  do d = 1 to ncol(days);  do k = 1 to ncol(doses);
    row = row + 1;
    if doses[k] = 9999 then idx = loc(M[,6] = days[d]);
    else idx = loc(M[,6] = days[d] & M[,1] = doses[k]);
    A = M[idx, 2];  n = nrow(A);
    h = H[loc(H[,1] = days[d] & H[,2] = doses[k]), 3];
    t = pbot(A, h);
    pr = P[loc(P[,4] = days[d] & P[,1] = doses[k]), ];
    tmaxmed = median(M[idx, 4]);
    a1 = M[idx, 3];  ok = loc(a1 ^= .);               /* Day -1 evaluable participants */
    if ncol(ok) > 1 then do;
      a1 = a1[ok];  t1 = pbot(a1, H1[loc(H1[,1] = days[d] & H1[,2] = doses[k]), 3]);
    end;
    else do;  a1 = {.};  t1 = j(1, 5, .);  end;
    R[row, ] = days[d] || doses[k] || n || nrow(h) || t ||
               (median(M[idx, 5]) - tmaxmed) ||             /* tmax gap, individual   */
               (pr[pr[,3][<:>], 2] - tmaxmed) ||            /* tmax gap, mean profile */
               a1[:] || t1[5];
  end;  end;
  create _hyst from R[colname={"ADY" "dose" "n" "npbo" "abar" "lcl" "ucl" "p1" "p2"
                                "gap_ind" "gap_mean" "abar_dm1" "p2_dm1"}];
  append from R;  close _hyst;
quit;

/*--- display values ------------------------------------------------------------*/
proc sql;
  create table _lbl as select distinct dose, trt from _part order by dose;
quit;
proc sort data=_hyst; by dose; run;
data _disp;
  merge _hyst _lbl;  by dose;
  length dayc $10 dosec $40 abarci $40 p1c p2c gapi gapm $12 dm1c $30 fc $10;
  dayc = catx(' ', 'Day', ADY);
  if dose = 9999 then dosec = 'All active doses';  else dosec = trt;
  abarci = cats(put(abar, 8.2), ' (', put(lcl, 8.2), ', ', put(ucl, 8.2), ')');
  p1c  = put(p1, 6.4);   p2c = put(p2, 6.4);
  gapi = put(gap_ind, 5.1);  gapm = put(gap_mean, 5.1);
  if abar_dm1 = . then dm1c = 'NE';
  else dm1c = cats(put(abar_dm1, 8.2), ' (', put(p2_dm1, 6.4), ')');
  fc = ifc("&FORM" = "LINEAR", 'Linear', 'Emax');
run;

proc sort data=_disp; by ADY dose; run;
%tfltitle(num=14.3.6.5, type=Table,
   text=%str(Assessment of Delay between Concentration and ddQTcF: Mean Signed Loop Area on Direct-Effect Model Residuals, by Dose and Profile Day),
   pop=C-QTc Analysis Set,
   foot=%str(Area = signed area of the closed path of each participant (concentration / participant Cmax on that day, residual ddQTcF) in time order over the dosing interval; positive = counterclockwise = effect lags concentration. Residuals from the prespecified direct-effect model (no time factor, participant random intercept) fitted to all active doses and profile days. CI and p: t-test of the mean area whose standard error adds the variance of the time-matched placebo mean shared by the ddQTcF of every active participant (the signed area of each placebo participant about the placebo mean on that day, against the mean scaled concentration profile of the active participants), Welch-Satterthwaite degrees of freedom. tmax gap: median time of peak ddQTcF (individual) or time of peak mean ddQTcF (mean profile) minus median tmax; > 1 h is flagged in the SAP. Day -1: Day -1 time-matched QTcF, centered and placebo-corrected as on the profile day, paired with the concentrations of that day and tested the same way; no drug, so any area reflects timing alone. NE = not evaluable. A significant result prompts an effect-compartment model; it does not replace the C-QTc analysis.));
proc report data=_disp nowd split='|';
  columns ADY dayc dose dosec n npbo abarci p1c p2c gapi gapm dm1c fc;
  define ADY    / order noprint;
  define dayc   / order 'Profile|Day';
  define dose   / order noprint;
  define dosec  / display 'Dose' width=20 flow;
  define n      / display 'n';
  define npbo   / display 'n|Placebo';
  define abarci / display 'Mean Area, ms|(95% CI)';
  define p1c    / display 'p|One-sided';
  define p2c    / display 'p|Two-sided';
  define gapi   / display 'tmax Gap, h|(Individual)';
  define gapm   / display 'tmax Gap, h|(Mean Profile)';
  define dm1c   / display 'Day -1 Mean Area, ms|(p Two-sided)';
  define fc     / display 'Model|for f';
run;
