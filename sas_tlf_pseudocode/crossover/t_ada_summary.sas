/******************************************************************************
* TABLE     : t_ada_summary  (Crossover - 2x2 or Williams)
* TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Treatment
* POPULATION: Immunogenicity / ADA-Evaluable Population (ISEVALFL='Y')
* INPUT     : ADIS (PARCAT1='ADA'; PARAMCD = ADA / NAB result and status
*             flags; AVALC; ADADET/baseline+post-baseline derived statuses;
*             NABFL; TRTA/TRTAN, APERIODC, TRTSEQP from ADaM)
* NOTE      : PSEUDOCODE. Counts are PARTICIPANTS (distinct USUBJID), NOT result
*             rows; % denominator = N per treatment column from %bign
*             (ADA-evaluable). Within-participant crossover: a participant can develop
*             ADA under each treatment received -> summarize by ANALYSIS
*             treatment TRTA. Standard immunogenicity categories (from ADIS
*             status flags, no re-derivation):
*               - Baseline ADA positive
*               - Treatment-emergent ADA positive  (treatment-induced +
*                 treatment-boosted)
*               - Treatment-unaffected ADA positive
*               - Persistent / transient (of treatment-emergent)
*               - Neutralizing antibody (NAb) positive (of ADA positive)
*             A by-period breakout adds APERIODC if requested by the SAP.
******************************************************************************/
%include "../00_setup_macros.sas";
%setup(study=CP-101, adam=/data/adam, out=/data/tfl);
%designvars(design=CROSSOVER);     /* TRTVAR=TRTA TRTNVAR=TRTAN BYPERIOD=APERIOD APERIODC SEQVAR=TRTSEQP */

/*--- header denominators: N per treatment column + Total (ADA-evaluable) --*/
%bign(ds=adam.adsl, trtvar=&TRTVAR, trtn=&TRTNVAR, popfl=ISEVALFL, out=_bign);

/* one ADA-status record per participant x treatment (status flags from ADIS;
   no re-derivation of immunogenicity categories in TLF code)              */
data ada;
  set adam.adis(where=(ISEVALFL='Y' and PARCAT1='ADA'));
  /* participant-level status flags carried on ADIS, e.g.:
     ADABLFL = baseline ADA positive
     TEADAFL = treatment-emergent ADA positive
     ADAINDFL= treatment-induced ; ADABSTFL = treatment-boosted
     ADAPERFL= persistent ; ADATRNFL = transient
     NABFL   = neutralizing antibody positive
     treatment / period / sequence come straight from ADaM                 */
run;

/*--- count PARTICIPANTS (distinct USUBJID) per category x treatment ----------*
* Each row = one immunogenicity category; numerator = distinct participants     *
* meeting the ADIS status flag; denominator = &bign N per treatment.        *
* %catfreq merged to _bign gives "n (xx.x%)" of PARTICIPANTS, not rows.        */
%macro adacat(flag=, label=, denomfl=, ord=);
  proc sql;
    create table _c_&ord as
      select &TRTVAR as trt length=200, &TRTNVAR as trtn,
             count(distinct USUBJID) as nsubj
      from ada
      where &flag='Y' %if %length(&denomfl) %then and &denomfl='Y';
      group by &TRTVAR, &TRTNVAR
    union all   /* Total column */
      select 'Total' as trt, 9999 as trtn, count(distinct USUBJID) as nsubj
      from ada
      where &flag='Y' %if %length(&denomfl) %then and &denomfl='Y';;
  quit;
  data _cat_&ord; set _c_&ord;
    length category $48 denom $24; category="&label"; ord=&ord;
    /* denom label drives which N is the % denominator for this row:
       overall categories -> ADA-evaluable N (_bign);
       sub-categories (Persistent/Transient/NAb) -> the parent positive N  */
    denom = "&denomfl";
  run;
%mend adacat;

%adacat(flag=ADABLFL,  label=Baseline ADA positive,                                  denomfl=,        ord=1);
%adacat(flag=TEADAFL,  label=Treatment-emergent ADA positive,                        denomfl=,        ord=2);
%adacat(flag=ADAINDFL, label=%str(  Treatment-induced ADA positive),                 denomfl=,        ord=3);
%adacat(flag=ADABSTFL, label=%str(  Treatment-boosted ADA positive),                 denomfl=,        ord=4);
%adacat(flag=ADAPERFL, label=%str(  Persistent (of treatment-emergent)),             denomfl=TEADAFL, ord=5);
%adacat(flag=ADATRNFL, label=%str(  Transient (of treatment-emergent)),              denomfl=TEADAFL, ord=6);
%adacat(flag=NABFL,    label=%str(  Neutralizing antibody positive (of ADA positive)), denomfl=ADAPOSFL, ord=7);

data _all; set _cat_:; run;

/*--- attach the correct % denominator per row, build n (%) of PARTICIPANTS ---*
* Overall rows divide by ADA-evaluable N (_bign); sub-rows divide by the    *
* relevant parent-positive N (computed analogously). Result "n (xx.x%)".   */
proc sort data=_all; by ord category trtn; run;
proc transpose data=_all out=_wide; by ord category; id trtn; var nsubj; run;

%tfltitle(num=14.5.1.1, type=Table,
   text=%str(Summary of Anti-Drug Antibody (ADA) Incidence by Treatment),
   pop=Immunogenicity Analysis Population,
   foot=%str(Counts = participants (distinct USUBJID), not samples. Treatment-emergent = treatment-induced + treatment-boosted. Persistent/Transient denominators = treatment-emergent positive; NAb denominator = ADA positive. By analysis treatment received (crossover). Immunogenicity status flags from ADIS (no re-derivation).));
proc report data=_wide nowd split='|';
  columns ord category ("Treatment" /* trt cols + Total, each "Trt (N=xx)" */);
  define ord      / order noprint;
  define category / order 'ADA Category' width=44 flow;
  /* define <each treatment var> / display center "&header (N=&n)";
     each cell pre-formatted as "n (xx.x%)" of PARTICIPANTS                     */
run;
