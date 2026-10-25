/******************************************************************************
* FIGURE    : f_cqtc_hysteresis  (Single Ascending Dose)
* TITLE     : Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time
*             Order (Hysteresis Loop) by Dose
* POPULATION: C-QTc Analysis Set (PKFL='Y' and SAFFL='Y'), active doses
* INPUT     : ADEG (PARAMCD='QTCF'; CHG, ATPTN), ADPC (PARAMCD='CONC'; AVAL,
*             ATPTN), time-matched on nominal post-dose time
* NOTE      : PSEUDOCODE. Descriptive companion to t_cqtc_hysteresis (the
*             signed loop-area check run before the C-QTc analysis). ddQTcF =
*             individual dQTcF (CHG) minus the time-matched placebo mean dQTcF
*             (placebo pooled across cohorts); use the C-QTc analysis dataset's
*             ddQTcF instead if the ADaM specification carries one. One panel
*             per dose; mean concentration (x) vs mean ddQTcF (y) at each
*             nominal time, joined IN TIME ORDER with arrows (VECTOR from the
*             previous time point), +/-1 SE bars on ddQTcF, and a dotted segment
*             closing the path back to predose. A counterclockwise loop suggests
*             the effect lags concentration; Table 14.3.5.5 gives the test.
*             Descriptive only; no model is drawn.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=SAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

/*--- Day 1 dQTcF records (active and placebo) -------------------------------*/
data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and PARAMCD='QTCF' and CHG ne .));
  keep USUBJID &TRTVAR &TRTNVAR ATPTN CHG;
run;

/*--- time-matched placebo mean dQTcF (placebo pooled) ------------------------*/
proc means data=eg(where=(&TRTNVAR=0)) nway noprint;
  class ATPTN;  var CHG;
  output out=_pbo(drop=_type_ _freq_) mean=pbo_chg;
run;

/*--- ddQTcF with time-matched concentrations, active doses only --------------*/
proc sql;
  create table cq as
    select e.USUBJID, e.&TRTVAR as trt length=200, e.&TRTNVAR as dose, e.ATPTN,
           e.CHG - p.pbo_chg as ddqtcf, c.AVAL as conc
    from eg as e
         inner join _pbo as p on e.ATPTN = p.ATPTN
         inner join adam.adpc(where=(PKFL='Y' and PARAMCD='CONC' and AVAL ne .)) as c
           on e.USUBJID = c.USUBJID and e.ATPTN = c.ATPTN
    where e.&TRTNVAR > 0;
quit;

/*--- mean concentration and mean (SE) ddQTcF per dose x nominal time ---------*/
proc means data=cq nway noprint;
  class dose trt ATPTN;
  var conc ddqtcf;
  output out=_loop(drop=_type_ _freq_) mean(conc)=mconc mean(ddqtcf)=mdd
         stderr(ddqtcf)=sedd n(ddqtcf)=n;
run;
proc sort data=_loop; by dose ATPTN; run;

/*--- arrow origins (previous time point) and the closing segment -------------*/
data _plot;
  set _loop;  by dose;
  retain x_first y_first;
  xo = lag(mconc);  yo = lag(mdd);                 /* LAG runs on every record   */
  if first.dose then do; xo = .; yo = .; x_first = mconc; y_first = mdd; end;
  lo = mdd - sedd;  hi = mdd + sedd;
  output;
  if last.dose then do;                            /* last time -> predose       */
    xc = mconc; yc = mdd; xe = x_first; ye = y_first;
    mconc = .; mdd = .; lo = .; hi = .; xo = .; yo = .;
    output;
  end;
run;

%tfltitle(num=14.3.5.4, type=Figure,
   text=%str(Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time Order (Hysteresis Loop) by Dose),
   pop=C-QTc Analysis Set,
   foot=%str(ddQTcF = change from baseline in QTcF minus the time-matched placebo mean (placebo pooled). Points = means at each nominal post-dose time, joined in time order (arrows); bars = +/-1 SE; dotted segment closes the path from the last time back to predose. A counterclockwise loop suggests the effect lags concentration; Table 14.3.5.5 gives the test. Descriptive only.));
proc sgpanel data=_plot;
  panelby trt / novarname uniscale=row sort=data;  /* one panel per dose, ascending */
  refline 0 / axis=y lineattrs=(color=gray);
  highlow x=mconc low=lo high=hi / lineattrs=(color=gray);
  vector  x=mconc y=mdd / xorigin=xo yorigin=yo arrowheadshape=filled
                          lineattrs=(pattern=solid thickness=2);
  vector  x=xe y=ye / xorigin=xc yorigin=yc noarrowheads lineattrs=(pattern=dot);
  scatter x=mconc y=mdd / markerattrs=(symbol=circlefilled size=6);
  colaxis label='Mean Plasma Concentration (CONC)';
  rowaxis label='Mean ddQTcF (ms) +/- SE';
run;
