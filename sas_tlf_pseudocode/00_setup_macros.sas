/******************************************************************************
* PROGRAM   : 00_setup_macros.sas
* PURPOSE   : Shared environment + utility macros for the early-phase
*             clin-pharm TLF library. %include this at the top of every TLF
*             program. PSEUDOCODE — illustrative structure, not validated code.
* INPUT     : ADaM datasets (ADSL, ADAE, ADLB, ADVS, ADEG, ADPC, ADPP, ADPD,
*             ADIS, ADEX). CDISC ADaM IG-conformant.
* CONVENTION: All population flags, treatment, period and analysis variables
*             come from ADaM (no re-derivation in TLF code). Reported numbers
*             come from validated ADaM + this code; double-program per SOP.
******************************************************************************/

/*--- environment ---------------------------------------------------------*/
%macro setup(study=, adam=, out=);
  libname adam   "&adam"  access=readonly;   /* ADaM read-only            */
  libname tfl    "&out";                      /* output datasets           */
  options nodate nonumber missing=' ' validvarname=v7 mprint;
  /* study-level formats: treatment order, AE severity, lab ranges, etc.  */
  proc format library=tfl.formats; /* %include study format catalog */ run;
  options fmtsearch=(tfl.formats);
  %global STUDYID;  %let STUDYID=&study;
%mend setup;

/*--- big N: population counts per treatment column (header denominators) --
* trtvar  = column variable (e.g. TRT01A parallel; TRTA/APERIODC crossover) *
* popfl   = population flag (SAFFL, PKFL, ITTFL, ...)                       */
%macro bign(ds=adam.adsl, trtvar=TRT01A, trtn=TRT01AN, popfl=SAFFL, out=_bign);
  proc sql noprint;
    create table &out as
      select &trtvar as trt length=200, &trtn as trtn, count(distinct USUBJID) as N
      from &ds where &popfl='Y'
      group by &trtvar, &trtn
    union all  /* Total column */
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as N
      from &ds where &popfl='Y';
  quit;
  /* build "Treatment\n(N=xx)" column headers into macro vars &c1..&cK */
%mend bign;

/*--- descriptive stats for a continuous analysis var (AVAL/CHG/PCHG) ------
* Produces n, Mean (SD), Median, Min, Max formatted to ADaM decimal hints. */
%macro descstat(ds=, var=AVAL, class=TRT01A APERIODC AVISITN PARAMCD,
                where=%str(1), dp=1, out=_desc);
  proc means data=&ds(where=(&where)) noprint;
    class &class;  var &var;
    output out=&out n=n mean=mean std=std median=med min=min max=max q1=q1 q3=q3;
  run;
  data &out;  set &out;  length cmean csd cmed cminmax $40;
    cmean   = put(mean, 8.%eval(&dp+1));
    csd     = cats('(', put(std, 8.%eval(&dp+2)), ')');
    cmed    = put(med, 8.%eval(&dp+1));
    cminmax = catx(', ', put(min,8.&dp), put(max,8.&dp));
  run;
%mend descstat;

/*--- categorical n (%) with denominator = bign per column ----------------*/
%macro catfreq(ds=, var=, class=TRT01A, denom=_bign, out=_cat);
  proc freq data=&ds noprint;  by &class;  tables &var / out=&out(drop=percent);  run;
  /* merge to &denom on &class -> pct = count/N*100 ; format "n (xx.x%)"   */
%mend catfreq;

/*--- AE counting: participants with >=1 event (NOT event rows) at each level --
* Counts distinct USUBJID per column, per SOC and SOC*PT. Treatment-emergent
* uses TRTEMFL='Y'. Severity/relationship via AESEVN / AREL.               */
%macro aecount(ds=adam.adae, trtvar=TRT01A, popden=_bign,
               where=%str(TRTEMFL='Y'), byvars=AESOC AEDECOD, out=_ae);
  proc sql;
    create table &out as
      select &trtvar as trt, %unquote(&byvars) ,
             count(distinct USUBJID) as nsubj
      from &ds where &where group by &trtvar, %unquote(&byvars);
  quit;
  /* %catpct(&out, denom=&popden) -> n (%) of PARTICIPANTS; sort SOC by overall
     frequency desc, PT within SOC desc; add an "Any AE" overall row.      */
%mend aecount;

/*--- PK descriptive stats: arithmetic + GEOMETRIC summaries --------------
* Per ADPP/ADPC convention: n, Mean, SD, CV%, Geo Mean, Geo CV%, Median,
* Min, Max. Tmax reported as Median (Min, Max) only.                        */
%macro pkstats(ds=, var=AVAL, class=TRTA PARAMCD, where=%str(1), out=_pk);
  /* arithmetic stats on the raw scale */
  proc means data=&ds(where=(&where and &var>0)) noprint;
    class &class;  var &var;
    output out=_pk_arith n=n mean=amean std=asd median=med min=min max=max
                         cv=cv  /* arithmetic CV% */ ;
  run;
  /* geometric stats: PROC MEANS on log(&var), then back-transform. Geo Mean =
     exp(mean of logs); Geo CV% = 100*sqrt(exp(var of logs)-1). Aggregated
     across participants INSIDE proc means - NEVER exp(arithmetic mean of raw).   */
  data _pk_log;  set &ds(where=(&where and &var>0));  logv=log(&var);  run;
  proc means data=_pk_log noprint;
    class &class;  var logv;
    output out=_pk_logm mean=meanlog std=sdlog;
  run;
  data &out;
    merge _pk_arith _pk_logm;  by &class;
    geomean = exp(meanlog);                  /* geometric mean             */
    geocv   = 100*sqrt(exp(sdlog**2)-1);     /* geometric CV%              */
  run;
%mend pkstats;

/*--- titles / footnotes from a standard banner --------------------------*/
%macro tfltitle(num=, type=Table, text=, pop=Safety Population, foot=);
  title1 j=l "&STUDYID" j=r "Page ^{thispage} of ^{lastpage}";
  title3 j=c "&type &num";
  title4 j=c "&text";
  title5 j=c "(&pop)";
  footnote1 j=l "&foot";
  footnote2 j=l "Source: ADaM &sysdate9 &systime  Program: &SYSPROCESSNAME";
%mend tfltitle;

/*--- design helper: resolve the column + by-structure for a design -------
* design = PARALLEL | CROSSOVER | SINGLESEQ | SAD | MAD                     *
* Sets the column + by-structure so the SAME TLF body works per design:     *
*   &TRTVAR/&TRTNVAR  - period/actual treatment (BDS: ADAE/ADPP/...)        *
*   &SEQVAR/&SEQVARN  - PARTICIPANT-LEVEL sequence label on ADSL (crossover &    *
*                       single-/fixed-sequence); use for participant-level       *
*                       tables (disposition/demographics/baseline/medhx)     *
*   &BYPERIOD         - period columns; per-period denominators must come    *
*                       from a period-bearing source (ADEX/ADIS/ADPD), NOT   *
*                       from ADSL (ADSL is one-record-per-participant).          */
%macro designvars(design=PARALLEL);
  %global TRTVAR TRTNVAR SEQVAR SEQVARN BYPERIOD;
  %if %upcase(&design)=CROSSOVER %then %do;
     %let TRTVAR=TRTA; %let TRTNVAR=TRTAN; %let SEQVAR=TRTSEQP; %let SEQVARN=TRTSEQPN; %let BYPERIOD=APERIOD APERIODC; %end;
  %else %if %upcase(&design)=SINGLESEQ %then %do;
     /* one fixed sequence: participant-level tables use &SEQVAR/&SEQVARN (ADSL); *
      * period tables use &BYPERIOD with per-period denominators from ADEX.   */
     %let TRTVAR=TRTA; %let TRTNVAR=TRTAN; %let SEQVAR=TRTSEQP; %let SEQVARN=TRTSEQPN; %let BYPERIOD=APERIOD APERIODC; %end;
  %else %do; /* PARALLEL / SAD / MAD : one treatment per participant */
     %let TRTVAR=TRT01A; %let TRTNVAR=TRT01AN; %let SEQVAR=; %let SEQVARN=; %let BYPERIOD=; %end;
%mend designvars;
