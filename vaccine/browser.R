# Browser adapter: configuration, canonical mapping and reproducible exports only.
# All statistical derivations remain in the shared, unchanged vaccine/analysis.R.
# This file does not launch a server, run a shell, install packages or send data.

vaccine_browser_limits <- function() list(csv_bytes=16*1024^2, csv_rows=200000L,
  expected_grid=250000L, diary_figures=32L)

vaccine_browser_feeds <- function() list(
  participants=c(USUBJID="text",ARM="text",IMMFL="flag",SAFEFL="flag"),
  titers=c(USUBJID="text",ASSAY="text",ANTIGEN="text",UNIT="text",VISIT="text",AVAL="number",QUALIFIER="qualifier",LLOQ="number",ULOQ="number"),
  doses=c(USUBJID="text",DOSE="text"),
  diary=c(USUBJID="text",DOSE="text",DAY="integer",SYMPTOM="text",GRADE="integer"))

vaccine_browser_defaults <- function() list(study_id="",study_title="",outputs=character(),
  confidence=.95,yes_value="Y",no_value="N",assay="",antigen="",unit="",baseline_visit="",
  followup_visits="",visits_confirmed=FALSE,blq_policy="exclude",alq_policy="exclude",
  qualifier_exact="EXACT",qualifier_blq="BLQ",qualifier_alq="ALQ",qualifier_missing="MISSING",
  response_rule="threshold",response_threshold="",fold_threshold="",baseline_threshold="",
  dose_labels="",symptoms="",day_start=0L,day_end=6L,max_grade=4L,
  react_denominator="complete",diary_confirmed=FALSE,review_confirmed=FALSE,columns=list())

vaccine_browser_asset_root <- function(asset_root=NULL) {
  candidates<-if(is.null(asset_root)) c(".","../..") else asset_root
  found<-candidates[file.exists(file.path(candidates,"vaccine/analysis.R"))]
  if(!length(found)) stop("The shared vaccine analysis files are unavailable. Reload the application.",call.=FALSE)
  normalizePath(found[[1]],mustWork=TRUE)
}

vaccine_browser_engine <- function(asset_root=NULL,renderer=FALSE) {
  root<-vaccine_browser_asset_root(asset_root);scope<-new.env(parent=globalenv())
  sys.source(file.path(root,"vaccine/analysis.R"),envir=scope)
  if(renderer) sys.source(file.path(root,"toolkit_launcher/analysis_runner.R"),envir=scope)
  scope
}

vaccine_browser_read_csv <- function(path) {
  lim<-vaccine_browser_limits()
  if(length(path)!=1L||!file.exists(path)||is.na(file.info(path)$size)||file.info(path)$size>lim$csv_bytes)
    stop("Upload one UTF-8 CSV of at most 16 MiB. Remove unused columns while retaining every required analysis record. Inputs that still exceed this limit need a workflow with higher upload capacity.",call.=FALSE)
  bytes<-readBin(path,"raw",n=lim$csv_bytes+1L)
  if(any(bytes==as.raw(0)))stop("CSV files cannot contain NUL bytes.",call.=FALSE)
  text<-rawToChar(bytes);Encoding(text)<-"UTF-8"
  if(is.na(iconv(text,from="UTF-8",to="UTF-8",sub=NA)))stop("Upload a UTF-8 CSV; this file has invalid text encoding.",call.=FALSE)
  text<-sub("^\ufeff","",text)
  con<-textConnection(text);on.exit(close(con),add=TRUE)
  parse_csv<-function(expr)withCallingHandlers(expr,warning=function(w){
    # A final newline is optional; malformed quoting is not. R's CSV parser
    # otherwise returns repaired rows after an unterminated quoted field.
    if(grepl("^incomplete final line",conditionMessage(w)))invokeRestart("muffleWarning")
    else stop(paste("Cannot read CSV:",conditionMessage(w)),call.=FALSE)
  })
  widths<-parse_csv(utils::count.fields(con,sep=",",quote='"',comment.char="",blank.lines.skip=TRUE))
  if(!length(widths)||is.na(widths[[1]])||any(widths[!is.na(widths)]!=widths[[1]]))
    stop("Every CSV record must have the same number of fields as its header.",call.=FALSE)
  out<-tryCatch(parse_csv(utils::read.csv(text=text,colClasses="character",na.strings=NULL,
    check.names=FALSE,stringsAsFactors=FALSE,fill=FALSE,comment.char="",strip.white=FALSE)),
    error=function(e)stop(paste("Cannot read CSV:",conditionMessage(e)),call.=FALSE))
  if(nrow(out)>lim$csv_rows)stop("Use at most 200,000 records per CSV. Export records needed for the selected analysis while retaining all eligible participants and the full prespecified window. Inputs that still exceed this limit need a workflow with higher upload capacity.",call.=FALSE)
  if(!length(names(out))||any(!nzchar(names(out)))||anyDuplicated(names(out)))
    stop("CSV headers must be nonblank and distinct.",call.=FALSE)
  attr(out,"vaccine_original_csv")<-text
  attr(out,"vaccine_original_bytes")<-bytes
  out
}

vaccine_browser_example <- function(asset_root=NULL) {
  root<-vaccine_browser_asset_root(asset_root)
  settings<-vaccine_browser_defaults()
  example<-jsonlite::fromJSON(file.path(root,"vaccine/examples/example_settings.json"),simplifyVector=TRUE)
  settings[names(example)]<-example
  settings[c("visits_confirmed","diary_confirmed","review_confirmed")]<-list(FALSE,FALSE,FALSE)
  data<-setNames(lapply(names(vaccine_browser_feeds()),function(slot)
    vaccine_browser_read_csv(file.path(root,"vaccine/examples",paste0(slot,".csv")))),names(vaccine_browser_feeds()))
  list(settings=settings,data=data)
}

vaccine_browser_validate <- function(data,settings,asset_root=NULL) {
  errors<-data.frame(field=character(),message=character(),stringsAsFactors=FALSE)
  fail<-function(field,message) {if(!field%in%errors$field)errors[nrow(errors)+1L,]<<-list(field,message);invisible(NULL)}
  n<-vaccine_browser_defaults()
  if(!is.list(settings)) {fail("settings","Settings must be a named list.");settings<-list()}
  if(!is.list(data)) {fail("inputs","Inputs must be a named list of CSV data frames.");data<-list()}
  keys<-intersect(names(n),names(settings));n[keys]<-settings[keys]
  text<-function(key,required=TRUE,maxlen=200L) {
    x<-n[[key]]
    if(length(x)!=1L||!is.character(x)||is.na(x)) {fail(key,"Enter one text value.");return("")}
    x<-trimws(as.character(x));if((required&&!nzchar(x))||nchar(x)>maxlen||grepl("[[:cntrl:]]",x))fail(key,"Use single-line text within the field length limit.")
    x
  }
  number<-function(key,lo=-Inf,hi=Inf,integer=FALSE) {
    x<-n[[key]]
    if(!is.atomic(x)||is.logical(x)) {fail(key,"Enter one finite numeric value.");return(NA_real_)}
    v<-suppressWarnings(as.numeric(x))
    if(length(v)!=1L||!is.finite(v)||v<lo||v>hi||(integer&&v!=floor(v))) {fail(key,"Enter a finite number within the displayed limits.");return(NA_real_)}
    v
  }
  labels<-function(key) {
    x<-n[[key]]
    if(is.list(x))x<-unlist(x,use.names=FALSE)
    if(!is.character(x)) {fail(key,"Enter one label per line.");return(character())}
    x<-trimws(unlist(strsplit(x,"\r?\n",perl=TRUE),use.names=FALSE));x<-x[nzchar(x)]
    if(!length(x)||length(x)>50L||anyDuplicated(x)||any(nchar(x)>200L)||any(grepl("[[:cntrl:]]",x)))fail(key,"Use 1–50 distinct, single-line labels of at most 200 characters.")
    x
  }
  n$study_id<-text("study_id",maxlen=100L);n$study_title<-text("study_title",FALSE)
  n$confidence<-number("confidence",.5,.999)
  n$yes_value<-text("yes_value");n$no_value<-text("no_value")
  if(identical(n$yes_value,n$no_value))fail("yes_value","Included and excluded population values must differ.")
  ids<-n$outputs;if(is.list(ids))ids<-unlist(ids,use.names=FALSE)
  allowed<-c("immunogenicity","fold_rise","response","titer_plot","reactogenicity","diary_profile")
  if(!is.character(ids)||!length(ids)||anyNA(ids)||anyDuplicated(ids)||any(!ids%in%allowed)) {fail("outputs","Select supported outputs without duplicates.");ids<-character()}
  n$outputs<-ids
  immune<-any(ids%in%allowed[1:4]);react<-any(ids%in%allowed[5:6])
  if(!isTRUE(n$review_confirmed))fail("review_confirmed","Review the settings and confirm the study-specific choices.")
  cfg<-n
  if(immune) {
    for(k in c("assay","antigen","unit","baseline_visit","qualifier_exact","qualifier_blq","qualifier_alq","qualifier_missing"))n[[k]]<-text(k)
    cfg$followup_visits<-labels("followup_visits")
    if(n$baseline_visit%in%cfg$followup_visits)fail("followup_visits","Baseline must be distinct from follow-up visits.")
    if(!isTRUE(n$visits_confirmed))fail("visits_confirmed","Confirm the prespecified visit assignment and populations.")
    for(k in c("blq_policy","alq_policy")) {
      permitted<-if(k=="blq_policy")c("exclude","half_lloq","lloq")else c("exclude","uloq")
      if(length(n[[k]])!=1L||!n[[k]]%in%permitted)fail(k,"Choose a listed assay-limit rule.")
    }
    if(anyDuplicated(unlist(n[paste0("qualifier_",c("exact","blq","alq","missing"))],use.names=FALSE)))fail("qualifier_exact","Each assay qualifier must have a distinct source value.")
    if("response"%in%ids) {
      if(length(n$response_rule)!=1L||!n$response_rule%in%c("threshold","fold_rise","conditional"))fail("response_rule","Choose a listed response rule.")
      else for(k in switch(n$response_rule,threshold="response_threshold",fold_rise="fold_threshold",conditional=c("response_threshold","fold_threshold","baseline_threshold"))) {
        n[[k]]<-number(k,0,1e100)
        if(is.finite(n[[k]])&&n[[k]]<=if(k=="fold_threshold")1 else 0)fail(k,"Use a positive threshold, or a fold-rise multiplier greater than one.")
      }
    }
  }
  if(react) {
    for(k in c("dose_labels","symptoms"))cfg[[k]]<-labels(k)
    n$day_start<-number("day_start",-1,60,TRUE);n$day_end<-number("day_end",-1,60,TRUE);n$max_grade<-number("max_grade",1,5,TRUE)
    if(is.finite(n$day_start)&&is.finite(n$day_end)&&n$day_end<n$day_start)fail("day_end","Last diary day must be at or after the first day.")
    if(length(n$react_denominator)!=1L||!n$react_denominator%in%c("complete","observed"))fail("react_denominator","Choose a listed denominator policy.")
    if(!isTRUE(n$diary_confirmed))fail("diary_confirmed","Confirm administered doses, day numbering, symptoms and grades.")
  }
  cfg[names(n)[!names(n)%in%c("followup_visits","dose_labels","symptoms")]]<-n[!names(n)%in%c("followup_visits","dose_labels","symptoms")]
  feeds<-vaccine_browser_feeds();needed<-c("participants",if(immune)"titers",if(react)c("doses","diary"))
  canonical<-lapply(feeds,function(types)as.data.frame(setNames(lapply(types,function(t)if(t%in%c("number","integer"))numeric()else character()),names(types)),stringsAsFactors=FALSE))
  if(!is.list(n$columns)) {fail("columns","Column mappings must be named lists.");n$columns<-list()}
  lim<-vaccine_browser_limits()
  for(slot in needed) {
    raw<-data[[slot]];types<-feeds[[slot]]
    if(!is.data.frame(raw)) {fail(paste0("inputs.",slot),"Upload the required CSV input.");next}
    if(nrow(raw)>lim$csv_rows) {fail(paste0("inputs.",slot),"Use at most 200,000 records per input. Export records needed for the selected analysis while retaining all eligible participants and the full prespecified window. Inputs that still exceed this limit need a workflow with higher upload capacity.");next}
    if(anyDuplicated(names(raw))||any(!nzchar(names(raw)))) {fail(paste0("inputs.",slot),"Source headers must be nonblank and distinct.");next}
    if(!nrow(raw)&&slot%in%c("participants","doses"))fail(paste0("inputs.",slot),"This roster must contain at least one record.")
    mapping<-n$columns[[slot]];if(is.null(mapping))mapping<-list()
    if(!is.list(mapping)&&!is.character(mapping)) {fail(paste0("columns.",slot),"Use a named source-column mapping.");next}
    selected<-setNames(rep("",length(types)),names(types));out<-list()
    for(key in names(types)) {
      src<-if(key%in%names(mapping))mapping[[key]]else NULL;if(is.null(src))src<-if(key%in%names(raw))key else ""
      required<-!key%in%c("AVAL","LLOQ","ULOQ","GRADE")
      field<-paste("columns",slot,key,sep=".")
      if(length(src)!=1L||is.na(src)||!is.character(src)||nzchar(src)&&!src%in%names(raw)) {fail(field,"Select an existing source column.");src<-""}
      if(!nzchar(src)&&(required||key=="GRADE"))fail(field,"Map this required column.")
      selected[[key]]<-src
      value<-if(nzchar(src))raw[[src]] else rep("",nrow(raw))
      if(!is.atomic(value)) {fail(field,"Map an ordinary CSV column.");value<-rep("",nrow(raw))}
      value<-trimws(as.character(value));value[is.na(value)]<-""
      field<-paste("inputs",slot,key,sep=".")
      if(required&&any(!nzchar(value)))fail(field,"A value is required on every row.")
      if(types[[key]]%in%c("number","integer")) {
        numeric<-suppressWarnings(as.numeric(value));blank<-!nzchar(value)
        valid<-grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$",value)
        if(any(!blank&(!valid|!is.finite(numeric)))||types[[key]]=="integer"&&any(!blank&is.finite(numeric)&numeric!=floor(numeric)))fail(field,"Use finite numeric values (whole numbers for day and grade), or permitted blanks.")
        numeric[blank]<-NA_real_;out[[key]]<-numeric
      } else if(types[[key]]=="flag") {
        if(any(!value%in%c(n$yes_value,n$no_value)))fail(field,"Use the configured included or excluded population value.")
        out[[key]]<-ifelse(value==n$yes_value,"Y","N")
      } else if(types[[key]]=="qualifier") {
        q<-c("EXACT","BLQ","ALQ","MISSING");source<-unlist(n[paste0("qualifier_",tolower(q))],use.names=FALSE)
        if(any(!value%in%source))fail(field,"Use a configured assay qualifier.")
        out[[key]]<-q[match(value,source)]
      } else {
        if(any(nchar(value)>200L)||any(grepl("[[:cntrl:]]",value)))fail(field,"Use single-line text of at most 200 characters.")
        out[[key]]<-value
      }
    }
    groups<-split(names(selected)[nzchar(selected)],selected[nzchar(selected)])
    if(any(vapply(groups,function(keys)length(keys)>1L&&!setequal(keys,c("IMMFL","SAFEFL")),logical(1))))fail(paste0("columns.",slot),"Use distinct source columns, except when both population flags intentionally share one flag.")
    canonical[[slot]]<-as.data.frame(out,stringsAsFactors=FALSE,check.names=FALSE)
  }
  if(!nrow(errors)) {
    p<-canonical$participants
    if(immune&&sum(p$IMMFL=="Y")*(1+length(cfg$followup_visits))>lim$expected_grid)
      fail("followup_visits","Browser participant/visit grid exceeds 250,000. Select fewer follow-up visits while retaining the full eligible population, or use the optional desktop toolkit if its separate CSV limits are met.")
    if(react) {
      d<-canonical$doses;nd<-sum(d$USUBJID%in%p$USUBJID[p$SAFEFL=="Y"]&d$DOSE%in%cfg$dose_labels)
      if(nd*length(cfg$symptoms)*(n$day_end-n$day_start+1)>lim$expected_grid)
        fail("symptoms","Browser diary grid exceeds 250,000. Select fewer doses or symptoms while retaining the prespecified window and population, or use the optional desktop toolkit if its separate CSV limits are met.")
      if("diary_profile"%in%ids&&length(cfg$dose_labels)*ceiling(length(cfg$symptoms)/4)>lim$diary_figures)
        fail("dose_labels","Browser daily profiles support at most 32 figure pages. Select fewer doses or symptoms while retaining the prespecified window and population, or use the optional desktop toolkit if its separate CSV limits are met.")
    }
  }
  prepared<-NULL
  if(!nrow(errors))prepared<-tryCatch(vaccine_browser_engine(asset_root)$vaccine_prepare(canonical,cfg),error=function(e){fail("inputs",conditionMessage(e));NULL})
  warnings<-c("Descriptive analyses only: no efficacy, protection, immunobridging, between-arm test or multiplicity adjustment is supplied.",
    if(immune)"Geometric summaries use natural-log t intervals; paired fold rises use within-participant log differences. Response intervals are exact Clopper–Pearson. A single evaluable participant has no t interval.",
    if(react)"Missing diary rows and blank grades are not grade zero. Review complete, partial and missing diaries alongside the selected denominator.",
    "SAS is an unexecuted native reference export. Completed computation is not scientific review or study approval.")
  list(ok=!nrow(errors),errors=errors,config=cfg,settings=n,data=canonical,prepared=prepared,
    preview=list(counts=if(is.null(prepared))data.frame()else prepared$audit,warnings=warnings),warnings=warnings)
}

vaccine_browser_sas_data <- function(name,data) {
  # Names come only from fixed adapter schemas. Values are UTF-8 hex literals.
  stopifnot(grepl("^[a-z_]+$",name),all(grepl("^[A-Za-z_][A-Za-z0-9_]*$",names(data))))
  text<-vapply(data,is.character,logical(1));lines<-paste0("data work.",name,";")
  for(k in names(data))lines<-c(lines,paste0("length ",k,if(text[[k]])paste0(" $",max(c(1L,nchar(enc2utf8(data[[k]]),type="bytes")),na.rm=TRUE))else " 8",";"))
  if(nrow(data)) {
    statements<-matrix("",nrow=nrow(data),ncol=ncol(data)+1L)
    for(j in seq_along(data)) {
      k<-names(data)[[j]];v<-data[[k]]
      literal<-if(text[[k]]) {
        values<-unique(v)
        encoded<-vapply(values,function(s)if(is.na(s)||!nzchar(s))"''" else paste0("'",paste(sprintf("%02x",as.integer(charToRaw(enc2utf8(s)))),collapse=""),"'x"),character(1))
        encoded[match(v,values)]
      } else {
        if(any(!is.na(v)&!is.finite(v)))stop("Cannot export non-finite SAS input.",call.=FALSE)
        value<-sprintf("%.17g",v);value[is.na(v)]<-".";value
      }
      statements[,j]<-paste0(k,"=",literal,";")
    }
    statements[,ncol(data)+1L]<-"output;"
    lines<-c(lines,as.vector(t(statements)))
  } else lines<-c(lines,"stop;")
  paste(c(lines,"run;"),collapse="\n")
}

vaccine_browser_sas <- function(data,cfg,asset_root=NULL) {
  root<-vaccine_browser_asset_root(asset_root)
  blocks<-c("/* Configured native SAS reference: NOT executed or reconciled. Use a UTF-8 SAS session. */","options validvarname=v7;")
  for(slot in names(vaccine_browser_feeds()))blocks<-c(blocks,vaccine_browser_sas_data(slot,data[[slot]]))
  numeric<-c("confidence","response_threshold","fold_threshold","baseline_threshold","day_start","day_end","max_grade")
  keys<-names(vaccine_browser_defaults());keys<-setdiff(keys,c("outputs","columns","followup_visits","dose_labels","symptoms","visits_confirmed","diary_confirmed","review_confirmed"))
  conf<-lapply(keys,function(k)if(k%in%numeric){v<-suppressWarnings(as.numeric(cfg[[k]]));if(length(v)!=1L||!is.finite(v))NA_real_ else v}else as.character(cfg[[k]]))
  names(conf)<-keys;blocks<-c(blocks,vaccine_browser_sas_data("vax_config",as.data.frame(conf,stringsAsFactors=FALSE)))
  for(k in c("followup_visits","dose_labels","symptoms","outputs")) {
    name<-switch(k,followup_visits="vax_visits",dose_labels="vax_doses",symptoms="vax_symptoms",outputs="vax_outputs")
    column<-switch(k,followup_visits="VISIT",dose_labels="DOSE",symptoms="SYMPTOM",outputs="ID")
    vals<-if(is.character(cfg[[k]])&&length(cfg[[k]])==1L&&!nzchar(cfg[[k]]))character()else unlist(cfg[[k]],use.names=FALSE)
    if(k=="followup_visits"&&any(cfg$outputs%in%c("immunogenicity","fold_rise","response","titer_plot")))vals<-c(cfg$baseline_visit,vals)
    frame<-data.frame(value=as.character(vals),ORDER=seq_along(vals)-1L,stringsAsFactors=FALSE);names(frame)[1]<-column
    blocks<-c(blocks,vaccine_browser_sas_data(name,frame))
  }
  paste(c(blocks,readLines(file.path(root,"vaccine/reference.sas"),warn=FALSE,encoding="UTF-8")),collapse="\n")
}

vaccine_browser_json <- function(x,path) {
  arrays<-c("outputs","followup_visits","dose_labels","symptoms")
  protect<-function(v) {for(k in intersect(names(v),arrays))if(is.character(v[[k]]))v[[k]]<-I(v[[k]]);v}
  if(is.list(x)) {x<-protect(x);if(is.list(x$values))x$values<-protect(x$values)}
  jsonlite::write_json(x,path,pretty=TRUE,auto_unbox=TRUE,na="null",null="null",digits=NA)
}

vaccine_browser_run <- function(data,settings,directory,asset_root=NULL) {
  root<-vaccine_browser_asset_root(asset_root)
  checked<-vaccine_browser_validate(data,settings,root)
  if(!checked$ok)stop(paste(checked$errors$message,collapse="\n"),call.=FALSE)
  if(dir.exists(directory)&&length(list.files(directory,all.files=TRUE,no..=TRUE)))stop("Use a new, empty folder for each browser run.",call.=FALSE)
  dir.create(directory,recursive=TRUE,showWarnings=FALSE);directory<-normalizePath(directory,mustWork=TRUE)
  complete<-FALSE;on.exit(if(!complete)unlink(directory,recursive=TRUE),add=TRUE)
  engine<-vaccine_browser_engine(root,renderer=TRUE);cfg<-checked$config
  css<-paste(readLines(file.path(root,"assets/theme/tokens.css"),warn=FALSE,encoding="UTF-8"),collapse="\n")
  results<-list();manifest_outputs<-list();warnings<-checked$warnings;checks<-list();started<-format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  for(id in cfg$outputs) {
    relative<-paste0("outputs/",id);dest<-file.path(directory,relative);dir.create(dest,recursive=TRUE)
    result<-engine$vaccine_output(id,checked$prepared,cfg)
    writeLines("Computed in the current browser session using the unchanged shared vaccine R core.",file.path(dest,"program.log"))
    rendered<-engine$analysis_render(result,dest,relative,css,cfg$study_id)
    results[[id]]<-result;warnings<-unique(c(warnings,rendered$warnings));checks<-c(checks,rendered$checks)
    manifest_outputs[[id]]<-list(id=id,status="completed",title=rendered$title,files=rendered$files)
  }
  for(sub in c("inputs","uploads","vaccine","toolkit_launcher","assets/theme"))dir.create(file.path(directory,sub),recursive=TRUE,showWarnings=FALSE)
  for(slot in names(vaccine_browser_feeds())) {
    engine$analysis_csv(checked$data[[slot]],file.path(directory,"inputs",paste0(slot,".csv")),spreadsheet=FALSE)
    if(is.data.frame(data[[slot]])) {
      original<-attr(data[[slot]],"vaccine_original_bytes")
      matches<-FALSE
      if(!is.null(original))matches<-tryCatch({
        parsed<-utils::read.csv(text=sub("^\ufeff","",rawToChar(original)),colClasses="character",na.strings=NULL,check.names=FALSE,stringsAsFactors=FALSE,fill=FALSE,comment.char="")
        identical(names(parsed),names(data[[slot]]))&&identical(lapply(parsed,as.character),lapply(data[[slot]],as.character))
      },error=function(e)FALSE)
      if(matches)writeBin(original,file.path(directory,"uploads",paste0(slot,".csv")))
      else engine$analysis_csv(data[[slot]],file.path(directory,"uploads",paste0(slot,".csv")),spreadsheet=FALSE)
    }
  }
  source_files<-c("vaccine/analysis.R","vaccine/browser.R","vaccine/reference.sas","toolkit_launcher/analysis_runner.R","assets/theme/tokens.css")
  for(path in source_files)if(!file.copy(file.path(root,path),file.path(directory,path)))stop(paste("Cannot preserve source",path),call.=FALSE)
  vaccine_browser_json(cfg,file.path(directory,"study_setup.json"))
  vaccine_browser_json(list(schema=1L,module_id="vaccine",values=checked$settings),file.path(directory,"setup_profile.json"))
  writeLines(enc2utf8(vaccine_browser_sas(checked$data,cfg,root)),file.path(directory,"vaccine_analysis.sas"),useBytes=TRUE)
  rerun<-c('# Open this folder as the R working directory, then source this file. No shell is used.',
    'source("vaccine/browser.R")',
    'profile <- jsonlite::fromJSON("setup_profile.json", simplifyVector=FALSE)$values',
    'slots <- names(vaccine_browser_feeds())',
    'paths <- file.path("uploads",paste0(slots,".csv")); use <- file.exists(paths)',
    'data <- setNames(lapply(paths[use],vaccine_browser_read_csv),slots[use])',
    'result <- vaccine_browser_run(data,profile,tempfile("vaccine-reproduced-"),asset_root=".")',
    'message("Reproduced results: ",result$directory)')
  writeLines(rerun,file.path(directory,"reproduce.R"))
  writeLines(c("Open analysis_report.html for the complete report. Every component has a complete CSV/RDS or PNG/PDF export.",
    "The inputs and uploads folders contain unsanitized scientific input values for exact reproduction; import them as data rather than spreadsheet formulas. Result CSVs protect formula-like text with an apostrophe; RDS retains original text.",
    "study_setup.json records normalized settings; setup_profile.json preserves form values and mappings. reproduce.R uses the preserved source files with R, ggplot2 and jsonlite; no shell or Python is required.",
    "vaccine_analysis.sas is configured native reference code that has not been executed or reconciled. Use a UTF-8 SAS session.",
    "The source/file MD5 inventory detects accidental file changes and is not a signature or scientific approval.",warnings),file.path(directory,"START_HERE.txt"))
  versions<-data.frame(package=c("R","ggplot2","jsonlite"),version=c(as.character(getRversion()),as.character(utils::packageVersion("ggplot2")),as.character(utils::packageVersion("jsonlite"))))
  engine$analysis_csv(versions,file.path(directory,"software_versions.csv"))
  engine$analysis_csv(checked$prepared$audit,file.path(directory,"input_audit.csv"))
  status<-data.frame(output=cfg$outputs,status="completed",stringsAsFactors=FALSE)
  engine$analysis_csv(status,file.path(directory,"execution_status.csv"))
  manifest<-list(schema=1L,module_id="vaccine",execution="browser_R_shared_core",status="succeeded",approved=FALSE,
    study_id=cfg$study_id,started_at=started,finished_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),outputs=unname(manifest_outputs))
  vaccine_browser_json(manifest,file.path(directory,"output_manifest.json"))
  vaccine_browser_json(list(passed=TRUE,approved=FALSE,checks=checks,warnings=warnings,
    scope="All requested outputs completed. Structural export checks do not provide independent scientific validation or study approval."),file.path(directory,"qc.json"))
  body<-paste0("<p class='note'>All selected outputs completed in your browser. These descriptive results require study-specific scientific review.</p>",
    engine$analysis_table(status),"<ul>",paste(vapply(manifest_outputs,function(o)paste0("<li><a href='outputs/",o$id,"/index.html'>",engine$analysis_escape(o$title),"</a></li>"),character(1)),collapse=""),"</ul>",
    "<h2>Assumptions and scope</h2><ul>",paste0("<li>",engine$analysis_escape(warnings),"</li>",collapse=""),"</ul><h2>Input populations and missingness</h2>",engine$analysis_table(checked$prepared$audit),
    "<h2>Recorded settings and mappings</h2><pre>",engine$analysis_escape(jsonlite::toJSON(cfg,pretty=TRUE,auto_unbox=TRUE,null="null")),"</pre><h2>Software</h2>",engine$analysis_table(versions),
    "<p><a href='vaccine_analysis.sas'>Configured SAS reference (unexecuted)</a> · <a href='setup_profile.json'>Form profile</a> · <a href='study_setup.json'>Normalized settings</a> · <a href='output_manifest.json'>Output manifest</a> · <a href='qc.json'>QC scope</a> · <a href='START_HERE.txt'>Reproduction and file guide</a></p>")
  writeLines(engine$analysis_page("Vaccine analysis results",body,css,cfg$study_id),file.path(directory,"analysis_report.html"),useBytes=TRUE)
  files<-sort(list.files(directory,recursive=TRUE));hashes<-unname(tools::md5sum(file.path(directory,files)))
  engine$analysis_csv(data.frame(file=files,md5=hashes),file.path(directory,"file_inventory.csv"))
  files<-sort(c(files,"file_inventory.csv"));complete<-TRUE
  list(directory=directory,files=files,config=cfg,data=checked$data,prepared=checked$prepared,
    outputs=results,manifest=manifest,warnings=warnings)
}
