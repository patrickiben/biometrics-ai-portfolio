################################################################################
# PROGRAM   : 00_setup_helpers.R
# PURPOSE   : Shared analysis and reporting helpers for the early-phase TLF library.
# INPUT     : Analysis-ready ADaM data. Population, treatment, period, analysis
#             flags, baseline and clinical grading must be supplied by the study.
# USE       : Execute through the guided launcher with an approved analysis plan.
#             Synthetic fixture QC is not study-specific clinical validation.
################################################################################

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(purrr); library(tibble)
  library(rtables); library(ggplot2)
  library(emmeans); library(lme4); library(broom); library(broom.mixed)
})

## --- environment ------------------------------------------------------------
## meddra / whodrug = coding-dictionary versions named in the SAP; tfl_titles()
## writes them into footnotes wherever a footnote says {meddra} or {whodrug}. Use the
## MedDRA version current at study start (FDA sdTCG 6.1.4) and the WHODrug Global B3
## release actually used for coding; the defaults are examples (October 2026).
setup <- function(study = "CP-101", adam = "/data/adam", out = "/data/tfl",
                  meddra = "MedDRA v29.1", whodrug = "WHODrug Global B3, Sep 2026") {
  options(stringsAsFactors = FALSE, tfl.study = study,
          tfl.meddra = meddra, tfl.whodrug = whodrug)
  ## read ADaM (haven::read_xpt / read_sas) or assume already loaded as tibbles
  ## adsl <- haven::read_xpt(file.path(adam, "adsl.xpt")) ...
  list(study = study, adam = adam, out = out, meddra = meddra, whodrug = whodrug)
}

# The guided setup writes these settings; direct scripts use explicit defaults.
tfl_settings <- function(name, default = NULL) {
  settings <- getOption("tfl.settings", list())
  if (is.null(settings[[name]])) default else settings[[name]]
}

# Unknown analysis flags remain unknown; absence of a positive is not a negative.
flag_any <- function(x) {
  x <- toupper(trimws(as.character(x)))
  if (any(x == "Y", na.rm = TRUE)) TRUE
  else if (length(x) && all(!is.na(x) & x == "N")) FALSE
  else NA
}
flag_label <- function(x, yes = "Yes", no = "No", unknown = "Unknown") {
  dplyr::case_when(toupper(trimws(x)) == "Y" ~ yes,
                  toupper(trimws(x)) == "N" ~ no, TRUE ~ unknown)
}
safe_stat <- function(x, fun, ...) {
  x <- x[is.finite(x)]
  if (!length(x)) NA_real_ else fun(x, ...)
}
assert_unique_analysis <- function(df, by, label = "analysis") {
  keys <- unique(c("USUBJID", by))
  if ("USUBJID" %in% names(df) && any(is.na(df$USUBJID) | !nzchar(trimws(as.character(df$USUBJID)))))
    stop(label, ": missing participant identifier.", call. = FALSE)
  if (all(keys %in% names(df)) && anyDuplicated(df[keys]))
    stop(label, ": multiple analysis records for a participant within a reporting cell. ",
         "Select one analysis record or include the appropriate day/period/time key.", call. = FALSE)
  invisible(df)
}

## --- design helper: resolve column + by-structure for a design --------------
## design = PARALLEL | CROSSOVER | SINGLESEQ | SAD | MAD
##   trtvar/trtnvar : period/actual treatment (BDS: ADAE/ADPP/...)
##   seqvar/seqvarn : PARTICIPANT-LEVEL sequence label on ADSL (crossover &
##                    single-/fixed-sequence) -> use for participant-level tables
##                    (disposition/demographics/baseline/medhx)
##   byperiod       : period columns; per-period denominators must come from a
##                    period-bearing source (ADEX/ADIS/ADPD), NOT ADSL.
design_vars <- function(design = c("PARALLEL","CROSSOVER","SINGLESEQ","SAD","MAD")) {
  design <- toupper(match.arg(design))
  switch(design,
    CROSSOVER = list(trtvar="TRTA",   trtnvar="TRTAN",   seqvar="TRTSEQP", seqvarn="TRTSEQPN",
                     byperiod=c("APERIOD","APERIODC")),
    SINGLESEQ = list(trtvar="TRTA",   trtnvar="TRTAN",   seqvar="TRTSEQP", seqvarn="TRTSEQPN",
                     byperiod=c("APERIOD","APERIODC")),
    ## PARALLEL / SAD / MAD : one treatment per participant
    list(trtvar="TRT01A", trtnvar="TRT01AN", seqvar=NA_character_, seqvarn=NA_character_,
         byperiod=character(0)))
}

## --- big N: population counts per column (+ Total) ---------------------------
## trtvar = column variable; popfl = population flag (SAFFL/PKFL/ITTFL/...)
bign <- function(df, trtvar, popfl = "SAFFL") {
  d <- df %>% filter(.data[[popfl]] == "Y")
  if (anyNA(d$USUBJID) || anyNA(d[[trtvar]]) || any(trimws(as.character(d[[trtvar]])) == ""))
    stop("Population records need participant identifiers and treatment labels.", call. = FALSE)
  per <- d %>% group_by(trt = as.character(.data[[trtvar]])) %>%
    summarise(N = n_distinct(USUBJID), .groups = "drop")
  bind_rows(per, tibble(trt = "Total", N = n_distinct(d$USUBJID)))
}

## --- descriptive stats for a continuous analysis var (AVAL/CHG/PCHG) --------
descstat <- function(df, var = "AVAL", by, dp = 1L) {
  assert_unique_analysis(df, by, "Continuous summary")
  df %>% group_by(across(all_of(by))) %>%
    summarise(n = sum(is.finite(.data[[var]])),
      mean = safe_stat(.data[[var]], mean), sd = safe_stat(.data[[var]], sd),
      median = safe_stat(.data[[var]], median), min = safe_stat(.data[[var]], min),
      max = safe_stat(.data[[var]], max), .groups = "drop") %>%
    mutate(c_mean = dplyr::if_else(is.na(mean), "NE", sprintf(paste0("%.", dp+1L, "f"), mean)),
      c_sd = dplyr::if_else(is.na(sd), "NE", sprintf(paste0("(%.", dp+2L, "f)"), sd)),
      c_median = dplyr::if_else(is.na(median), "NE", sprintf(paste0("%.", dp+1L, "f"), median)),
      c_minmax = dplyr::if_else(is.na(min), "NE", sprintf(paste0("%.", dp, "f, %.", dp, "f"), min, max)))
}

## --- categorical n (%) with denominator from bign() -------------------------
catfreq <- function(df, var, by, denom) {
  trtvar <- tail(by, 1)
  d <- df %>% mutate(cat = ifelse(is.na(.data[[var]]) | trimws(as.character(.data[[var]])) == "", "Unknown", as.character(.data[[var]])))
  # Include Total using distinct participants, never by summing arm counts.
  if ("Total" %in% denom$trt) {
    total <- d; total[[trtvar]] <- "Total"; d <- bind_rows(d, total)
  }
  cnt <- d %>% group_by(across(all_of(by)), cat) %>% summarise(n = n_distinct(USUBJID), .groups = "drop")
  keys <- unique(c(head(by, -1), "cat"))
  rows <- distinct(cnt, across(all_of(keys)))
  grid <- tidyr::crossing(rows, tibble(!!trtvar := denom$trt))
  grid %>% left_join(cnt, by = c(by,"cat")) %>% mutate(n = replace_na(n, 0L)) %>%
    left_join(denom, by = setNames("trt", trtvar)) %>%
    mutate(pct = ifelse(N > 0, 100*n/N, NA_real_), disp = n_pct(n, N))
}

# Complete observed row categories against every planned treatment column.
# Call before a long-to-wide count table is assembled.
complete_counts <- function(df, denom, rows, count = "nsubj") {
  if (!nrow(df)) return(df)
  grid <- tidyr::crossing(distinct(df, across(all_of(rows))), trt = denom$trt)
  grid %>% left_join(df, by = c(rows, "trt")) %>%
    mutate(!!count := replace_na(.data[[count]], 0L))
}

## --- AE counting: participants with >=1 event (NOT event rows) ------------------
## Counts distinct USUBJID per column, per requested by-levels. Treatment-
## emergent via TRTEMFL. Pass `where` as a dplyr filter expression.
aecount <- function(df, trtvar, where = quote(TRTEMFL == "Y"), byvars) {
  df %>% filter(!!where) %>%
    group_by(trt = .data[[trtvar]], across(all_of(byvars))) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  ## downstream: join to bign() for n (%); order SOC by overall freq desc, PT
  ## within SOC desc; prepend an "Any TEAE" overall row (distinct participants).
}

## --- PK descriptive stats: arithmetic + GEOMETRIC ---------------------------
## Geo Mean = exp(mean(log)); Geo CV% = 100*sqrt(exp(var(log)) - 1). Computed
## across participants ON THE LOG SCALE -- never exp(arithmetic mean of raw).
## Tmax is reported as Median (Min, Max) only (handle separately).
pkstats <- function(df, var = "AVAL", by) {
  assert_unique_analysis(df, by, "PK summary")
  # Retain all groups, including all-BLQ groups, and report exclusions explicitly.
  df %>% group_by(across(all_of(by))) %>%
    group_modify(~ {
      raw <- .x[[var]]
      blq <- if ("AVALC" %in% names(.x)) toupper(trimws(as.character(.x$AVALC))) == "BLQ" else rep(FALSE, length(raw))
      blq[is.na(blq)] <- FALSE
      x <- raw[is.finite(raw) & raw > 0 & !blq]
      tibble(n_input = length(raw), n = length(x), n_missing = sum(!is.finite(raw)),
        n_nonpositive = sum(is.finite(raw) & raw <= 0), n_blq_excluded = sum(blq), n_excluded = length(raw)-length(x),
        mean = safe_stat(x, mean), sd = safe_stat(x, sd),
        cv = if (length(x)>1) 100*sd(x)/mean(x) else NA_real_,
        geomean = if(length(x)) exp(mean(log(x))) else NA_real_,
        geocv = if(length(x)>1) 100*sqrt(expm1(stats::var(log(x)))) else NA_real_,
        median = safe_stat(x, median), min = safe_stat(x, min), max = safe_stat(x, max))
    }) %>% ungroup()
}

## --- titles / footnotes banner (feed to rtables / ggplot) -------------------
tfl_titles <- function(num, type = "Table", text, pop = "Safety Population",
                       foot = NULL, study = getOption("tfl.study", "CP-101")) {
  foot <- gsub("{meddra}",  getOption("tfl.meddra",  "MedDRA v29.1"), foot, fixed = TRUE)
  foot <- gsub("{whodrug}", getOption("tfl.whodrug", "WHODrug Global B3, Sep 2026"), foot, fixed = TRUE)
  list(
    titles    = c(sprintf("%s  %s", study, format(Sys.Date())),
                  sprintf("%s %s", type, num), text, sprintf("(%s)", pop)),
    footnotes = c(foot, paste0("Source: supplied analysis-ready ADaM. Program: ",getOption("tfl.program","analysis"),". NE = not estimable; Unknown = missing or unrecognized status.")))
}

## --- small format helpers ---------------------------------------------------
n_pct <- function(n, N) ifelse(is.na(N) | N <= 0, paste0(n, " (NE)"), sprintf("%d (%.1f%%)", as.integer(n), 100*n/N))
fmt   <- function(x, dp = 1L) formatC(x, format = "f", digits = dp)

# Distinct-participant safety hierarchy with explicit zero-event columns and Total.
ae_hierarchy <- function(df, trtvar, denom, label = 'Participants with any TEAE', severity = FALSE) {
  df <- df %>% mutate(trt = as.character(.data[[trtvar]]),
    AESOC = coalesce(na_if(trimws(as.character(AESOC)), ''), 'Unknown SOC'),
    AEDECOD = coalesce(na_if(trimws(as.character(AEDECOD)), ''), 'Unknown preferred term'))
  total <- df; total$trt <- rep('Total', nrow(total)); d <- bind_rows(df, total)
  build <- function(keys, level) {
    g <- d %>% group_by(across(all_of(c('trt','USUBJID',keys))))
    if (severity) {
      counts <- g %>% summarise(sev = safe_stat(AESEVN, max), .groups='drop') %>%
        mutate(severity = case_when(sev == 1 ~ 'Mild', sev == 2 ~ 'Moderate', sev == 3 ~ 'Severe', TRUE ~ 'Unknown')) %>%
        group_by(across(all_of(c('trt',keys,'severity')))) %>% summarise(nsubj=n_distinct(USUBJID),.groups='drop')
    } else counts <- g %>% summarise(.groups='drop') %>% group_by(across(all_of(c('trt',keys)))) %>% summarise(nsubj=n_distinct(USUBJID),.groups='drop')
    if (!length(keys)) {
      rows <- tibble(term=label, level=level, AESOC=NA_character_,AEDECOD=NA_character_)
    } else {
      rows <- distinct(d, across(all_of(keys)))
      if (!'AEDECOD'%in%names(rows)) rows$AEDECOD<-rep(NA_character_, nrow(rows))
      rows <- rows %>% mutate(term=if(level==1L) AESOC else paste0('   ',AEDECOD),level=level)
    }
    grid <- tidyr::crossing(rows,trt=denom$trt)
    if (severity) grid<-tidyr::crossing(grid,severity=c('Mild','Moderate','Severe','Unknown'))
    grid %>% left_join(counts,by=c('trt',keys,if(severity)'severity')) %>% mutate(nsubj=replace_na(nsubj,0L))
  }
  out <- bind_rows(build(character(),0L),build('AESOC',1L),build(c('AESOC','AEDECOD'),2L))
  soc_order<-df%>%group_by(AESOC)%>%summarise(socn=n_distinct(USUBJID),.groups='drop')
  pt_order<-df%>%group_by(AESOC,AEDECOD)%>%summarise(ptn=n_distinct(USUBJID),.groups='drop')
  out<-out%>%left_join(soc_order,by='AESOC')%>%left_join(pt_order,by=c('AESOC','AEDECOD'))%>%
    left_join(denom,by='trt')%>%mutate(value=n_pct(nsubj,N))%>%arrange(level!=0,desc(socn),AESOC,level,desc(ptn),AEDECOD)
  if(severity) out%>%select(term,level,trt,severity,value)%>%pivot_wider(names_from=c(trt,severity),values_from=value,names_sep=' / ')
  else out%>%select(term,level,trt,value)%>%pivot_wider(names_from=trt,values_from=value)
}

ada_summary <- function(adis, trtvar, period = FALSE) {
  d <- adis %>% filter(ADAFL == 'Y') %>% mutate(trt=as.character(.data[[trtvar]]))
  keys<-c('USUBJID','trt',if(period)c('APERIOD','APERIODC'))
  # Only supplied, study-derived flags classify emergence/induction/boosting.
  flagcols<-c(base_pos='BASEADA',te_pos='TEADAFL',induced='ADAINDFL',boosted='ADABSTFL',persistent='ADAPERFL',transient='ADATRNFL',nab_pos='NABFL')
  labels<-c(base_pos='Baseline ADA-positive',te_pos='Treatment-emergent ADA-positive',induced='Treatment-induced',boosted='Treatment-boosted',persistent='Persistent',transient='Transient',nab_pos='Neutralizing antibody (NAb)-positive')
  for(col in unname(flagcols))if(!col%in%names(d))d[[col]]<-NA_character_
  d$BASEADA<-case_when(toupper(d$BASEADA)=='POSITIVE'~'Y',toupper(d$BASEADA)=='NEGATIVE'~'N',TRUE~NA_character_)
  subj<-d%>%group_by(across(all_of(keys)))%>%summarise(across(all_of(unname(flagcols)),flag_any),.groups='drop')
  if(!period){total<-d;total$trt<-'Total';subj<-bind_rows(subj,total%>%group_by(USUBJID,trt)%>%summarise(across(all_of(unname(flagcols)),flag_any),.groups='drop'))}
  groupkeys<-setdiff(keys,'USUBJID')
  denom<-subj%>%group_by(across(all_of(groupkeys)))%>%summarise(N=n_distinct(USUBJID),.groups='drop')
  rows<-lapply(seq_along(flagcols),function(i){col<-flagcols[[i]];lab<-labels[[i]]
    bind_rows(subj%>%group_by(across(all_of(groupkeys)))%>%summarise(nsubj=n_distinct(USUBJID[which(.data[[col]]%in%TRUE)]),.groups='drop')%>%mutate(category=lab,ord=i*2L),
      subj%>%group_by(across(all_of(groupkeys)))%>%summarise(nsubj=n_distinct(USUBJID[is.na(.data[[col]])]),.groups='drop')%>%mutate(category=paste(lab,'— unknown status'),ord=i*2L+1L))})
  bind_rows(denom%>%mutate(nsubj=N,category='ADA-evaluable participants',ord=0L)%>%select(-N),bind_rows(rows))%>%
    left_join(denom,by=groupkeys)%>%mutate(value=n_pct(nsubj,N))%>%select(any_of(c('APERIOD','APERIODC')),category,ord,trt,value)%>%
    pivot_wider(names_from=trt,values_from=value)%>%arrange(across(any_of('APERIOD')),ord)
}

marked_lab_summary <- function(adlb, trtvar, denom, method = 'grade') {
  d <- adlb %>% filter(SAFFL=='Y', ONTRTFL=='Y') %>% mutate(trt=as.character(.data[[trtvar]]))
  if(method=='grade') {
    threshold<-tfl_settings('lab_grade_min',3)
    d<-d%>%mutate(unknown=is.na(ATOXGRN)|is.na(BTOXGRN),
      marked=if_else(unknown,NA,ATOXGRN>=threshold & ATOXGRN>BTOXGRN),
      high=marked & toupper(ANRIND)=='HIGH',low=marked & toupper(ANRIND)=='LOW')
  } else {
    hi<-tfl_setting_map('lab_high_limits',c(ALT=3,AST=3,BILI=2,ALP=3,CREAT=1.5,BUN=2,GLUC=1.5,K=1.1,'NA'=1.05,HGB=1.2,WBC=2,PLAT=1.5))
    lo<-tfl_setting_map('lab_low_limits',c(ALT=.5,AST=.5,BILI=.5,ALP=.5,CREAT=.5,BUN=.5,GLUC=.5,K=.5,'NA'=.5,HGB=.5,WBC=.5,PLAT=.5))
    multiplier<-function(x,p) {x<-unlist(x);if(length(x)==1)rep(as.numeric(x),length(p))else as.numeric(x[p])}
    d<-d%>%mutate(mult_hi=multiplier(hi,PARAMCD),mult_lo=multiplier(lo,PARAMCD),
      unknown=!is.finite(AVAL)|!is.finite(A1HI)|!is.finite(A1LO)|is.na(mult_hi)|is.na(mult_lo),
      high=if_else(unknown,NA,AVAL>A1HI*mult_hi),low=if_else(unknown,NA,AVAL<A1LO*mult_lo),marked=high|low)
  }
  if('Total'%in%denom$trt) {total<-d;total$trt<-rep('Total',nrow(total));d<-bind_rows(d,total)}
  rows<-d%>%group_by(trt,PARAMCD,PARAM,USUBJID)%>%summarise(
    `Any markedly abnormal`=any(marked%in%TRUE),`Markedly high`=any(high%in%TRUE),`Markedly low`=any(low%in%TRUE),
    `Unknown evaluability`=any(unknown),.groups='drop')%>%
    pivot_longer(c(`Any markedly abnormal`,`Markedly high`,`Markedly low`,`Unknown evaluability`),names_to='criterion',values_to='flag')%>%
    group_by(trt,PARAMCD,PARAM,criterion)%>%summarise(nsubj=n_distinct(USUBJID[flag]),.groups='drop')
  complete_counts(rows,denom,c('PARAMCD','PARAM','criterion'))%>%left_join(denom,by='trt')%>%
    mutate(value=n_pct(nsubj,N))%>%select(PARAMCD,PARAM,criterion,trt,value)%>%pivot_wider(names_from=trt,values_from=value)%>%
    mutate(marking_rule=if(method=='grade')paste0('Post grade >= ',threshold,' and > baseline grade')else
      paste0('High > ',multiplier(hi,PARAMCD),' x ULN; Low < ',multiplier(lo,PARAMCD),' x LLN'))
}

# Preserve nominal within-visit readings as distinct plotted analysis cells.
visit_time_labels <- function(d) {
  if(all(c('AVISIT','AVISITN','ATPT','ATPTN')%in%names(d))) {
    schedule<-d%>%distinct(AVISIT,AVISITN,ATPT,ATPTN)%>%arrange(AVISITN,ATPTN)%>%
      mutate(.visit_label=paste(AVISIT,ATPT,sep=' / '),.visit_order=row_number())
    d<-d%>%left_join(schedule,by=c('AVISIT','AVISITN','ATPT','ATPTN'))%>%
      mutate(AVISIT=.visit_label,AVISITN=.visit_order)%>%select(-.visit_label,-.visit_order)
  }
  d
}
tfl_setting_codes <- function(name, default) {
  value<-tfl_settings(name,default)
  unique(trimws(unlist(strsplit(paste(unlist(value),collapse=','),',',fixed=TRUE)))) |> (function(x)x[nzchar(x)])()
}
tfl_setting_map <- function(name, default) {
  value<-tfl_settings(name,default)
  if(is.character(value)&&is.null(names(value))) {
    lines<-trimws(unlist(strsplit(paste(value,collapse='\n'),'[\n,;]')));lines<-lines[nzchar(lines)]
    pairs<-strsplit(lines,'=',fixed=TRUE)
    if(any(lengths(pairs)!=2L))stop(name,': use PARAMCD=value entries.',call.=FALSE)
    value<-setNames(vapply(pairs,function(x)as.numeric(trimws(x[2])),numeric(1)),vapply(pairs,function(x)trimws(x[1]),character(1)))
  }
  value<-unlist(value)
  if(any(!is.finite(value)|value<0)||anyDuplicated(names(value)))stop(name,': limits must be unique, finite, nonnegative values.',call.=FALSE)
  value
}
baseline_summary <- function(adsl, trtvar) {
  cont<-tfl_setting_codes('baseline_continuous','SBPBL,DBPBL,PULSEBL')
  cats<-tfl_setting_codes('baseline_categorical','SMOKSTAT,ALCOHOL')
  missing<-setdiff(c(cont,cats),names(adsl));if(length(missing))stop('Missing selected baseline fields: ',paste(missing,collapse=', '))
  d<-adsl%>%filter(SAFFL=='Y');denom<-bign(d,trtvar,'SAFFL')
  with_total<-d;with_total[[trtvar]]<-rep('Total',nrow(d));with_total<-bind_rows(d,with_total)
  numeric_rows<-lapply(seq_along(cont),function(i){var<-cont[i];if(!is.numeric(d[[var]]))stop(var,': continuous baseline field must be numeric.')
    descstat(with_total,var=var,by=trtvar)%>%transmute(trt=.data[[trtvar]],characteristic=var,ord=i,
      n=as.character(n),`Mean (SD)`=paste(c_mean,c_sd),Median=c_median,`Min, Max`=c_minmax)%>%
      pivot_longer(c(n,`Mean (SD)`,Median,`Min, Max`),names_to='stat',values_to='value')})
  category_rows<-lapply(seq_along(cats),function(i){var<-cats[i]
    catfreq(d,var,by=trtvar,denom=denom)%>%transmute(trt=.data[[trtvar]],characteristic=var,ord=length(cont)+i,stat=cat,value=disp)})
  if(!length(c(cont,cats)))stop('Select at least one baseline field.')
  bind_rows(bind_rows(numeric_rows),bind_rows(category_rows))%>%pivot_wider(names_from=trt,values_from=value)%>%arrange(ord)
}

complete_count_rows <- function(df, denom) {
  complete_counts(df,denom,setdiff(names(df),c('trt','nsubj','N')))
}

with_total_column <- function(df, column) {
  df[[column]]<-as.character(df[[column]])
  total<-df;total[[column]]<-rep('Total',nrow(total))
  bind_rows(df,total)
}

check_analysis_units <- function(df) {
  if(all(c('PARAMCD','AVALU')%in%names(df)) && nrow(df)) {
    reported<-if('AVAL'%in%names(df))is.finite(df$AVAL)else rep(TRUE,nrow(df))
    d<-df[reported,,drop=FALSE]
    if(any(is.na(d$AVALU)|!nzchar(trimws(as.character(d$AVALU)))))
      stop('Reported quantitative values need nonmissing analysis units (AVALU).',call.=FALSE)
    if(any(d%>%group_by(PARAMCD)%>%summarise(n=n_distinct(AVALU),.groups='drop')%>%pull(n)>1L))
      stop('Mixed analysis units within PARAMCD; standardize units before reporting.',call.=FALSE)
  }
  df
}
