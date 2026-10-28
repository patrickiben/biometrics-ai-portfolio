# Trusted, non-interactive analysis runner. Inputs are a verified generated package.
# Source this file to obtain run_analysis(plan), or invoke Rscript with one plan.json.
# A completed computation never constitutes study approval.
suppressPackageStartupMessages(library(jsonlite))

analysis_escape <- function(x) {
  x <- as.character(x); x[is.na(x)] <- "Not estimable / missing"
  x <- gsub("&", "&amp;", x, fixed=TRUE)
  x <- gsub("<", "&lt;", x, fixed=TRUE); x <- gsub(">", "&gt;", x, fixed=TRUE)
  x <- gsub('"', "&quot;", x, fixed=TRUE); gsub("'", "&#39;", x, fixed=TRUE)
}
analysis_json <- function(x, path) jsonlite::write_json(x, path, pretty=TRUE, auto_unbox=TRUE, null="null", na="null", digits=NA)
analysis_csv <- function(x, path, spreadsheet=TRUE) {
  if (spreadsheet) for (key in names(x)) if (is.character(x[[key]])) {
    risky <- !is.na(x[[key]]) & grepl("^[[:space:]]*[=+@-]", x[[key]])
    x[[key]][risky] <- paste0("'", x[[key]][risky])
  }
  utils::write.csv(x, path, row.names=FALSE, na="", fileEncoding="UTF-8")
}
analysis_table <- function(x) {
  if (!ncol(x)) return("<p>No columns were produced.</p>")
  cell <- function(v) if (is.list(v)) vapply(v, function(z) paste(z,collapse="; "),character(1)) else as.character(v)
  cols <- lapply(x, cell)
  header <- paste0("<th scope='col'>",analysis_escape(names(x)),"</th>",collapse="")
  body <- if(nrow(x)) vapply(seq_len(nrow(x)),function(i) paste0("<tr>",paste0("<td>",vapply(cols,function(v) analysis_escape(v[i]),character(1)),"</td>",collapse=""),"</tr>"),character(1)) else "<tr><td colspan='100'>No qualifying records; see the population and missing-data notes.</td></tr>"
  paste0("<div class='table-wrap' tabindex='0'><table><thead><tr>",header,"</tr></thead><tbody>",paste(body,collapse="\n"),"</tbody></table></div>")
}
analysis_page <- function(title, body, css, study="") paste0(
  "<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>",analysis_escape(title),"</title><style>",css,
  "body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 var(--sans)}main{max-width:1200px;margin:auto;padding:24px}h1,h2,h3{line-height:1.25;color:var(--ink)}section{padding:20px;margin:20px 0;background:var(--surface);border:1px solid var(--line);border-radius:10px}.table-wrap{overflow:auto;max-width:100%}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:8px;border:1px solid var(--line);text-align:left;vertical-align:top}th{background:var(--surface-2)}a{color:var(--accent)}pre{white-space:pre-wrap;overflow-wrap:anywhere}button{padding:9px;margin-right:8px;background:var(--surface);color:var(--text);border:1px solid var(--control);border-radius:6px}img{max-width:100%;height:auto;background:white}.failed{border-left:5px solid var(--danger)}.note{padding:12px;background:var(--surface-2)}@media print{button{display:none}body{background:white;color:black}.table-wrap{overflow:visible}th,td{color:black;font-size:9px;overflow-wrap:anywhere}section{break-inside:auto}a{color:black}@page{size:landscape;margin:12mm}}</style><main><button class='theme-toggle'>Light / dark</button><button class='print-report'>Print / save PDF</button><p>TRIAL BIOSTATISTICS TOOLKIT · PRIVATE ANALYSIS</p><h1>",analysis_escape(title),"</h1><p>",analysis_escape(study),"</p>",body,
  "</main><script>(()=>{const d=document.documentElement;let t;try{t=localStorage.getItem('bp-theme')}catch(e){}d.dataset.theme=t==='dark'||t==='light'?t:(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');document.querySelector('.theme-toggle').onclick=()=>{const n=d.dataset.theme==='dark'?'light':'dark';d.dataset.theme=n;try{localStorage.setItem('bp-theme',n)}catch(e){}};document.querySelector('.print-report').onclick=()=>print()})();</script></html>")

analysis_capture <- function(scope, program, directory) {
  captured <- list(); warnings <- character(); text <- character()
  scope$print <- function(x, ...) {
    name <- paste(deparse(substitute(x)),collapse=" ")
    if (is.data.frame(x) || inherits(x,"ggplot") || inherits(x,"TableTree") || inherits(x,"VTableTree") || is.matrix(x)) {
      captured[[length(captured)+1L]] <<- list(name=name,value=x)
    }
    # Some original listings use tibble's n=Inf. Imported base data.frames
    # partially match that argument to na.print; the exported object is already
    # complete, so log plain data.frames without tibble-only display arguments.
    if (is.data.frame(x) && !inherits(x,"tbl_df")) base::print(x) else base::print(x,...)
    invisible(x)
  }
  # Explicit print() captures all final components, rather than guessing object names.
  device <- file.path(directory,"printed_figures.pdf")
  if(capabilities("cairo")) grDevices::cairo_pdf(device,width=11,height=8.5) else grDevices::pdf(device,width=11,height=8.5)
  device_number <- grDevices::dev.cur()
  on.exit(try(grDevices::dev.off(device_number),silent=TRUE),add=TRUE)
  failure <- NULL
  text <- capture.output(withCallingHandlers(tryCatch(sys.source(program,envir=scope,keep.source=FALSE),error=function(e) {failure <<- conditionMessage(e);NULL}),warning=function(w) {warnings <<- unique(c(warnings,conditionMessage(w)));invokeRestart("muffleWarning")}))
  writeLines(enc2utf8(c(text,if(length(warnings)) c("Execution warnings:",warnings))),file.path(directory,"program.log"),useBytes=TRUE)
  if (!is.null(failure)) stop(failure,call.=FALSE)
  if (!length(captured)) stop("The selected program produced no complete table, listing or figure.",call.=FALSE)
  list(components=captured,warnings=warnings,title=if(exists("ttl",envir=scope,inherits=FALSE)) scope$ttl else NULL)
}

analysis_render <- function(result, directory, relative, css, study) {
  blocks <- character(); checks <- list()
  if(!any(vapply(result$components,function(c) inherits(c$value,"ggplot"),logical(1)))) unlink(file.path(directory,"printed_figures.pdf"))
  auxiliary <- c("program.log","printed_figures.pdf","verified_preview.json")
  files <- file.path(relative,auxiliary[file.exists(file.path(directory,auxiliary))])
  for (i in seq_along(result$components)) {
    component <- result$components[[i]]; x <- component$value; key <- sprintf("component-%02d",i)
    # Expressions passed to print() belong in the program log, not report titles.
    label <- paste(if(inherits(x,"ggplot")) "Figure" else "Table",i)
    if(is.data.frame(x) && "n_excluded" %in% names(x)) label <- paste0(label," · Analysis exclusions")
    if(component$name %in% c("Recomputed facts","Unapproved paragraph")) label <- component$name
    if (inherits(x,"ggplot")) {
      png <- paste0(key,".png"); pdf <- paste0(key,".pdf")
      ggplot2::ggsave(file.path(directory,png),x,width=10,height=6.5,dpi=150,bg="white",limitsize=TRUE)
      if(capabilities("cairo")) ggplot2::ggsave(file.path(directory,pdf),x,width=10,height=6.5,device=grDevices::cairo_pdf,bg="white") else ggplot2::ggsave(file.path(directory,pdf),x,width=10,height=6.5,bg="white")
      files <- c(files,file.path(relative,c(png,pdf)))
      blocks <- c(blocks,paste0("<h3>",analysis_escape(label),"</h3><p><a href='",pdf,"'>PDF figure</a></p><img alt='",analysis_escape(label),"' src='",png,"'>"))
    } else {
      if (inherits(x,"TableTree") || inherits(x,"VTableTree")) x <- rtables::as_result_df(x,make_ard=TRUE)
      x <- as.data.frame(x,stringsAsFactors=FALSE)
      if (!ncol(x)) stop("A reported component has no columns.",call.=FALSE)
      numeric_cols <- vapply(x,is.numeric,logical(1))
      if (any(vapply(x[numeric_cols],function(v) any(is.infinite(v)|is.nan(v)),logical(1)))) stop("A reported numeric component contains Inf or NaN.",call.=FALSE)
      strings <- unlist(lapply(x[!numeric_cols],as.character),use.names=FALSE)
      if (any(grepl("(^|[[:space:](,])[-+]?(Inf|NaN)([[:space:]),%]|$)",strings),na.rm=TRUE)) stop("A formatted result contains Inf or NaN; check its data and estimability.",call.=FALSE)
      csv <- paste0(key,".csv"); rds <- paste0(key,".rds")
      analysis_csv(x,file.path(directory,csv)); saveRDS(x,file.path(directory,rds),version=3)
      files <- c(files,file.path(relative,c(csv,rds)))
      pages <- max(1L,ceiling(nrow(x)/1000L)); page_names <- sprintf("%s-page-%03d.html",key,seq_len(pages))
      for(j in seq_len(pages)) {
        part <- if(nrow(x)) x[seq.int((j-1L)*1000L+1L,min(j*1000L,nrow(x))),,drop=FALSE] else x
        nav <- paste0("<p><a href='index.html'>Output overview</a> · <a href='",csv,"'>Complete CSV (",nrow(x)," rows)</a> · Page ",j," / ",pages,"</p>")
        if(j>1L) nav <- paste0(nav,"<a href='",page_names[j-1L],"'>Previous</a> ")
        if(j<pages) nav <- paste0(nav,"<a href='",page_names[j+1L],"'>Next</a>")
        writeLines(analysis_page(label,paste0(nav,analysis_table(part)),css,study),file.path(directory,page_names[j]),useBytes=TRUE)
      }
      files <- c(files,file.path(relative,page_names))
      blocks <- c(blocks,paste0("<h3>",analysis_escape(label),"</h3><p>",nrow(x)," rows · <a href='",csv,"'>Complete CSV</a> · <a href='",page_names[1],"'>Complete paginated table</a></p>",if(nrow(x)>100) "<p>Overview shows the first 100 rows. The linked table pages and CSV contain every row.</p>" else "",analysis_table(utils::head(x,100))))
      checks[[length(checks)+1L]] <- list(id=paste(relative,key,sep="/"),passed=TRUE,details=paste(nrow(x),"complete rows exported; no infinite/non-number results."))
    }
  }
  title <- if(is.list(result$title)&&length(result$title$titles)>=3L) result$title$titles[[3]] else basename(relative)
  foot <- if(is.list(result$title)) result$title$footnotes else character()
  note <- paste0("<p class='note'>Computed output. Scientific review and study approval remain separate. CSV exports protect formula-like text with an apostrophe; RDS objects retain original values.</p>",if(length(foot)) paste0("<ul>",paste0("<li>",analysis_escape(foot),"</li>",collapse=""),"</ul>") else "")
  if(length(result$warnings)) note <- paste0(note,"<h2>Execution warnings</h2><ul>",paste0("<li>",analysis_escape(result$warnings),"</li>",collapse=""),"</ul>")
  writeLines(analysis_page(title,paste0(note,paste(blocks,collapse="\n")),css,study),file.path(directory,"index.html"),useBytes=TRUE)
  list(files=c(files,file.path(relative,"index.html")),checks=checks,title=title)
}

run_analysis <- function(plan) {
  if (is.character(plan)) plan <- jsonlite::fromJSON(plan,simplifyVector=FALSE)
  stopifnot(identical(as.integer(plan$schema),1L))
  build <- normalizePath(plan$build_root,mustWork=TRUE)
  out <- normalizePath(plan$run_root,mustWork=TRUE)
  if(identical(build,out)) stop("Execution results need a separate run folder.")
  cfg <- list(study_id="Study project")
  css <- ":root{--bg:#f6f8fb;--text:#182333;--surface:#fff;--surface-2:#edf1f5;--ink:#142030;--line:#cbd5e1;--control:#64748b;--accent:#006b69;--sans:system-ui,sans-serif}html[data-theme=dark]{--bg:#10151d;--text:#e5eaf1;--surface:#19212c;--surface-2:#25303c;--ink:#f2f5f9;--line:#526275;--control:#99aabd;--accent:#80dfd4}"
  started <- format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  saved_options <- options(); on.exit(options(saved_options),add=TRUE)
  options(tfl.run_root=out,warn=1)
  statuses <- list(); outputs <- list(); checks <- list(); errors <- character(); warnings <- character()
  record <- function(id, fn) {
    directory <- file.path(out,"outputs",id); dir.create(directory,recursive=TRUE,showWarnings=FALSE)
    relative <- paste0("outputs/",id); start <- proc.time()[[3]]
    options(tfl.program=id)
    error <- NULL; rendered <- NULL
    tryCatch({
      result <- fn(directory)
      rendered <- analysis_render(result,directory,relative,css,cfg$study_id)
      checks <<- c(checks,rendered$checks)
      warnings <<- unique(c(warnings,result$warnings))
    },error=function(e) error <<- conditionMessage(e))
    if(!is.null(error)) {
      errors <<- c(errors,paste(id,error,sep=": "))
      # Never expose partial numerical outputs as a successful report after a failure.
      existing <- list.files(directory,full.names=TRUE,recursive=TRUE)
      unlink(existing[basename(existing)!="program.log"])
      writeLines(paste0("FAILED: ",error),file.path(directory,"error.txt"),useBytes=TRUE)
      writeLines(analysis_page(paste("Failed output:",id),paste0("<section class='failed'><p>",analysis_escape(error),"</p></section><p>No successful result is supplied for this output.</p>"),css,cfg$study_id),file.path(directory,"index.html"),useBytes=TRUE)
    }
    success <- is.null(error)
    statuses[[length(statuses)+1L]] <<- data.frame(output=id,status=if(success) "completed" else "failed",error=if(success) "" else error,elapsed_seconds=round(proc.time()[[3]]-start,3),stringsAsFactors=FALSE)
    outputs[[length(outputs)+1L]] <<- list(id=id,status=if(success) "completed" else "failed",files=if(success) rendered$files else paste0(relative,"/",list.files(directory)),title=if(success) rendered$title else id)
  }
  fatal <- tryCatch({
    cfg <- jsonlite::fromJSON(file.path(build,"setup_profile.json"),simplifyVector=FALSE)$values
    if(!is.list(cfg)||!is.character(cfg$study_id)||length(cfg$study_id)!=1L) stop("Study configuration is missing or invalid.")
    css <- paste(readLines(file.path(plan$source_root,"assets/theme/tokens.css"),warn=FALSE,encoding="UTF-8"),collapse="\n")
    options(tfl.settings=cfg,tfl.study=cfg$study_id)
    if(plan$module_id %in% c("r_tlf","sas_tlf")) {
      bundle_root <- file.path(build,"r")
      shared <- new.env(parent=globalenv()); shared$bundle_root <- bundle_root
      sys.source(file.path(bundle_root,"00_setup.R"),envir=shared)
      selected <- unlist(cfg$outputs,use.names=FALSE)
      if(!length(selected)||any(!grepl("^[tlf]_[a-z0-9_]+$",selected))) stop("Select a valid analysis output.")
      for(id in selected) local({
        output_id <- id
        record(output_id,function(directory) {
          scope <- new.env(parent=shared)
          analysis_capture(scope,file.path(bundle_root,"programs",paste0(output_id,".R")),directory)
        })
      })
    } else if(plan$module_id=="sas_monitor") {
      source(file.path(plan$source_root,"toolkit_launcher/analysis_monitor.R"),local=TRUE)
      selected <- unlist(cfg$checks,use.names=FALSE)
      for(id in selected) local({
        output_id <- id
        record(output_id,function(directory) list(components=list(list(name=output_id,value=analysis_monitor(output_id,build,cfg))),warnings="Operational screening only. Review data-cut completeness and every flag; no notification or clinical decision is automated.",title=list(titles=c("", "",paste("Monitoring:",output_id)),footnotes=paste("Analysis date:",cfg$analysis_date))))
      })
    } else if(plan$module_id=="interpretation") {
      record("interpretation",function(directory) {
        scope <- new.env(parent=globalenv())
        sys.source(file.path(build,"R/extract_facts.R"),envir=scope)
        sys.source(file.path(build,"R/validate_interpretation.R"),envir=scope)
        settings <- jsonlite::fromJSON(file.path(build,"study_setup.json"))
        types <- if(settings$summary_type=="ae") c("character","integer","numeric") else c("character","character","integer","numeric","numeric","numeric")
        result <- utils::read.csv(file.path(build,"inputs/result.csv"),colClasses=types,check.names=FALSE,na.strings=NULL,fileEncoding="UTF-8")
        facts <- if(settings$summary_type=="ae") scope$extract_facts("t_ae_overview",result,arm=settings$arm,N=settings$population_n) else scope$extract_facts("t_pk_param_summary",result,param=settings$parameter,trt=settings$treatment)
        expected <- jsonlite::fromJSON(file.path(build,"facts.json"))
        if(!isTRUE(all.equal(facts,expected,tolerance=1e-10,check.attributes=FALSE))) stop("R recomputation disagrees with the supplied-facts preview.")
        draft <- paste(readLines(file.path(build,"draft.txt"),warn=FALSE,encoding="UTF-8"),collapse="\n")
        validation <- scope$validate_interpretation(draft,facts)
        if(!isTRUE(validation$numbers$ok)) stop("Draft contains numbers absent from the supplied facts.")
        analysis_json(list(facts=facts,draft=draft,validation=validation,approved=FALSE),file.path(directory,"verified_preview.json"))
        list(components=list(list(name="Recomputed facts",value=data.frame(Fact=names(facts),Value=vapply(facts,as.character,character(1)))),list(name="Unapproved paragraph",value=data.frame(Paragraph=draft))),warnings="Number checks do not establish attribution or scientific validity; review remains required.",title=list(titles=c("","","Independently recomputed aggregate interpretation"),footnotes="No model was called; no clinical conclusion is approved."))
      })
    } else stop("This module has no supported deterministic analysis action.")
    NULL
  },error=function(e) conditionMessage(e))
  if(!is.null(fatal)) errors <- c(errors,fatal)
  if(!length(statuses)) statuses <- list(data.frame(output="setup",status="failed",error=if(is.null(fatal)) "No selected output ran." else fatal,elapsed_seconds=0,stringsAsFactors=FALSE))
  status <- do.call(rbind,statuses)
  passed <- !length(errors)&&nrow(status)>0L&&all(status$status=="completed")
  checks <- c(list(list(id="all_selected_outputs_completed",passed=passed,details=paste(sum(status$status=="completed"),"of",nrow(status),"outputs completed."))),checks)
  analysis_csv(status,file.path(out,"execution_status.csv"))
  namespaces <- sort(loadedNamespaces()); versions <- data.frame(package=c("R",namespaces),version=c(as.character(getRversion()),vapply(namespaces,function(x) as.character(utils::packageVersion(x)),character(1))))
  analysis_csv(versions,file.path(out,"software_versions.csv"))
  qc <- list(schema=1L,passed=passed,status=if(passed) "passed" else "failed",all_selected_outputs_completed=passed,checks=checks,errors=errors,warnings=warnings,approved=FALSE,scope="Execution, structural and explicit method checks; not independent clinical validation or approval.")
  manifest <- list(schema=1L,status=if(passed) "succeeded" else "failed",module_id=plan$module_id,build_id=plan$build_id,run_id=plan$run_id,started_at=started,finished_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),study_id=cfg$study_id,outputs=outputs,approved=FALSE,bundle_sha256=plan$bundle_sha256,engine_sha256=plan$engine_sha256)
  analysis_json(qc,file.path(out,"qc.json")); analysis_json(manifest,file.path(out,"output_manifest.json"))
  body <- paste0("<p class='note'>",if(passed) "All selected outputs completed." else "This analysis did not complete successfully. Failed outputs have no successful result attached."," Scientific review and study approval remain separate.</p><h2>Execution status</h2>",analysis_table(status),"<ul>",paste(vapply(outputs,function(x) paste0("<li><a href='outputs/",x$id,"/index.html'>",analysis_escape(x$title),"</a> — ",analysis_escape(x$status),"</li>"),character(1)),collapse=""),"</ul>",if(length(errors)) paste0("<h2>Errors</h2><pre>",analysis_escape(paste(errors,collapse="\n")),"</pre>") else "","<h2>QC scope</h2><p>",analysis_escape(qc$scope),"</p><h2>Recorded settings</h2><pre>",analysis_escape(jsonlite::toJSON(cfg,pretty=TRUE,auto_unbox=TRUE,null="null")),"</pre><h2>Software versions</h2>",analysis_table(versions),"<p><a href='output_manifest.json'>Run manifest</a> · <a href='qc.json'>QC details</a> · <a href='execution_status.csv'>Status CSV</a></p>")
  writeLines(analysis_page("Study analysis results",body,css,cfg$study_id),file.path(out,"analysis_report.html"),useBytes=TRUE)
  cat(if(passed) "ANALYSIS PASSED" else "ANALYSIS FAILED",":",sum(status$status=="completed"),"/",nrow(status),"outputs completed.\n")
  invisible(passed)
}

if(sys.nframe()==0L) {
  args <- commandArgs(trailingOnly=TRUE)
  if(length(args)!=1L) stop("This runner requires one verified analysis plan.")
  ok <- run_analysis(args[[1]])
  quit(status=if(isTRUE(ok)) 0L else 1L)
}
