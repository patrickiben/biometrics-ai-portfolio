/******************************************************************************
* FIGURE    : f_cqtc_hysteresis  (Multiple Ascending Dose)
* TITLE     : Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time
*             Order (Hysteresis Loop) by Dose and Profile Day
* POPULATION: C-QTc Analysis Set (PKFL='Y' and SAFFL='Y'), active doses
* INPUT     : ADEG (PARAMCD='QTCF'; CHG, ADY, ATPTN), ADPC (PARAMCD='CONC';
*             AVAL, ADY, ATPTN), time-matched on profile day and nominal time
* NOTE      : PSEUDOCODE. Descriptive companion to t_cqtc_hysteresis (the
*             signed loop-area check run before the C-QTc analysis). ddQTcF =
*             individual dQTcF (CHG) minus the time-matched placebo mean dQTcF on
*             the same profile day and nominal time (placebo pooled); use the
*             C-QTc analysis dataset's ddQTcF instead if the ADaM specification
*             carries one. Rows = profile days (Day 1 and the steady-state day
*             named in the SAP, &PROFDAYS), columns = doses. Mean concentration
*             (x) vs mean ddQTcF (y) at each nominal time over the dosing
*             interval, joined IN TIME ORDER with arrows (VECTOR from the
*             previous time point), +/-1 SE bars, and a dotted segment closing
*             the path back to predose (the trough at steady state). A
*             counterclockwise loop suggests the effect lags concentration;
*             Table 14.3.6.5 gives the test. Descriptive only.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=MAD);               /* -> TRTVAR=TRT01A, TRTNVAR=TRT01AN  */

%let PROFDAYS = 1 14;                  /* full-profile days per the SAP       */

/*--- profile-day dQTcF records (active and placebo) -------------------------*/
data eg;
  set adam.adeg(where=(SAFFL='Y' and ANL01FL='Y' and PARAMCD='QTCF'
                       and ADY in (&PROFDAYS) and CHG ne .));
  keep USUBJID &TRTVAR &TRTNVAR ADY ATPTN CHG;
run;

/*--- time-matched placebo mean dQTcF by day and nominal time ------------------*/
proc means data=eg(where=(&TRTNVAR=0)) nway noprint;
  class ADY ATPTN;  var CHG;
  output out=_pbo(drop=_type_ _freq_) mean=pbo_chg;
run;

/*--- ddQTcF with time-matched concentrations, active doses only --------------*/
proc sql;
  create table cq as
    select e.USUBJID, e.&TRTVAR as trt length=200, e.&TRTNVAR as dose, e.ADY, e.ATPTN,
           e.CHG - p.pbo_chg as ddqtcf, c.AVAL as conc
    from eg as e
         inner join _pbo as p on e.ADY = p.ADY and e.ATPTN = p.ATPTN
         inner join adam.adpc(where=(PKFL='Y' and PARAMCD='CONC' and AVAL ne .)) as c
           on e.USUBJID = c.USUBJID and e.ADY = c.ADY and e.ATPTN = c.ATPTN
    where e.&TRTNVAR > 0;
quit;

/*--- mean concentration and mean (SE) ddQTcF per dose x day x nominal time ----*/
proc means data=cq nway noprint;
  class dose trt ADY ATPTN;
  var conc ddqtcf;
  output out=_loop(drop=_type_ _freq_) mean(conc)=mconc mean(ddqtcf)=mdd
         stderr(ddqtcf)=sedd n(ddqtcf)=n;
run;
proc sort data=_loop; by dose ADY ATPTN; run;

/*--- arrow origins (previous time point) and the closing segment -------------*/
data _plot;
  set _loop;  by dose ADY;
  retain x_first y_first;
  length day $10;
  day = catx(' ', 'Day', ADY);
  xo = lag(mconc);  yo = lag(mdd);                 /* LAG runs on every record   */
  if first.ADY then do; xo = .; yo = .; x_first = mconc; y_first = mdd; end;
  lo = mdd - sedd;  hi = mdd + sedd;
  output;
  if last.ADY then do;                             /* last time -> predose       */
    xc = mconc; yc = mdd; xe = x_first; ye = y_first;
    mconc = .; mdd = .; lo = .; hi = .; xo = .; yo = .;
    output;
  end;
run;
proc sort data=_plot; by ADY dose; run;            /* panel order: day, then dose */

%tfltitle(num=14.3.6.4, type=Figure,
   text=%str(Mean (+/-SE) ddQTcF versus Mean Plasma Concentration in Time Order (Hysteresis Loop) by Dose and Profile Day),
   pop=C-QTc Analysis Set,
   foot=%str(ddQTcF = change from baseline in QTcF minus the time-matched placebo mean on the same day (placebo pooled). Points = means at each nominal time over the dosing interval, joined in time order (arrows); bars = +/-1 SE across active participants (excludes the variance of the placebo mean itself); dotted segment closes the path back to predose (the trough at steady state). A counterclockwise loop suggests the effect lags concentration; Table 14.3.6.5 gives the test. Descriptive only.));
proc sgpanel data=_plot;
  panelby day trt / layout=lattice novarname uniscale=row sort=data;  /* rows = days, columns = doses */
  refline 0 / axis=y lineattrs=(color=gray);
  highlow x=mconc low=lo high=hi / lineattrs=(color=gray);
  vector  x=mconc y=mdd / xorigin=xo yorigin=yo arrowheadshape=filled
                          lineattrs=(pattern=solid thickness=2);
  vector  x=xe y=ye / xorigin=xc yorigin=yc noarrowheads lineattrs=(pattern=dot);
  scatter x=mconc y=mdd / markerattrs=(symbol=circlefilled size=6);
  colaxis label='Mean Plasma Concentration (CONC)';
  rowaxis label='Mean ddQTcF (ms) +/- SE';
run;
