# Report/export QC: complete rows, escaping, all printed components and honest failures.
source('toolkit_launcher/analysis_runner.R')
root <- normalizePath('.')
folder <- tempfile('renderer study '); dir.create(folder)
build <- file.path(folder,'build'); dir.create(file.path(build,'r/programs'),recursive=TRUE)
writeLines('invisible(NULL)',file.path(build,'r/00_setup.R'))
program <- file.path(build,'r/programs/t_example.R')
writeLines(c('ttl <- list(titles=c("Study", "Table", "<unsafe> report"),footnotes="Reviewer must inspect")',
 'print(data.frame(USUBJID=sprintf("%04d",1:1001), Value=1:1001),n=Inf)',
 'print(data.frame(Label=c("=1+1", "<script>oops()</script>", "α – µ"),Estimate=c(1,NA,3)))',
 'print(ggplot2::ggplot(data.frame(x=1:3,y=2:4),ggplot2::aes(x,y))+ggplot2::geom_point())',
 'print(rtables::build_table(rtables::analyze(rtables::basic_table(),"AGE"),data.frame(AGE=c(20,30))))',
 'warning("Known diagnostic")'),program,useBytes=TRUE)
analysis_json(list(values=list(study_id='<img onerror=x>',outputs=list('t_example'))),file.path(build,'setup_profile.json'))
make_plan <- function(name) {out <- file.path(folder,name);dir.create(out);list(schema=1,module_id='r_tlf',build_root=build,run_root=out,source_root=root,build_id='build-test',run_id=name,bundle_sha256='test',engine_sha256='test')}
plan <- make_plan('success')
stopifnot(run_analysis(plan))
output <- file.path(plan$run_root,'outputs/t_example')
x <- readRDS(file.path(output,'component-01.rds'))
stopifnot(nrow(x)==1001L,x$USUBJID[1]=='0001',x$Value[1001]==1001L)
page2 <- paste(readLines(file.path(output,'component-01-page-002.html'),warn=FALSE),collapse='\n')
stopifnot(grepl('<td>1001</td>',page2,fixed=TRUE))
page <- paste(readLines(file.path(output,'index.html'),warn=FALSE),collapse='\n')
stopifnot(grepl('&lt;script&gt;oops()',page,fixed=TRUE),!grepl('<script>oops()',page,fixed=TRUE),grepl('Known diagnostic',page,fixed=TRUE),grepl('theme-toggle',page,fixed=TRUE))
csv <- read.csv(file.path(output,'component-02.csv'),check.names=FALSE)
stopifnot(csv$Label[1]=="'=1+1",readRDS(file.path(output,'component-02.rds'))$Label[1]=='=1+1')
stopifnot(file.info(file.path(output,'component-03.png'))$size>1000,file.info(file.path(output,'component-03.pdf'))$size>1000)
stopifnot(readRDS(file.path(output,'component-04.rds'))$stat=='25')
# Direct components (such as vaccine plots) are first drawn during rendering.
# Export warnings must survive in the per-output report, log and return metadata.
direct <- file.path(folder,'direct-warning');dir.create(direct)
plot <- ggplot2::ggplot(data.frame(x=1:3,y=c(1,NA,3)),ggplot2::aes(x,y))+ggplot2::geom_point()
rendered <- analysis_render(list(components=list(list(name='Missing plot row',value=plot)),warnings=character()),
                            direct,'direct-warning','', 'Synthetic warning check')
stopifnot(any(grepl('Removed',rendered$warnings,fixed=TRUE)),
          any(grepl('Removed',readLines(file.path(direct,'program.log')),fixed=TRUE)),
          any(grepl('Execution warnings',readLines(file.path(direct,'index.html')),fixed=TRUE)),
          'direct-warning/program.log' %in% rendered$files)
manifest <- jsonlite::fromJSON(file.path(plan$run_root,'output_manifest.json'),simplifyVector=FALSE)
stopifnot(length(manifest$outputs)==1L,!manifest$approved,all(file.exists(file.path(plan$run_root,unlist(manifest$outputs[[1]]$files)))))
for(source_text in c('print(data.frame(x=1)); stop("deliberate failure")','print(data.frame(x=Inf))','print(data.frame(x="NaN"))','x <- 2')) {
 writeLines(source_text,program); bad <- make_plan(paste0('failure',length(list.dirs(folder))))
 stopifnot(!run_analysis(bad))
 qc <- jsonlite::fromJSON(file.path(bad$run_root,'qc.json'))
 stopifnot(!qc$passed,!qc$approved,length(qc$errors)>0L)
 stopifnot(!length(list.files(file.path(bad$run_root,'outputs/t_example'),pattern='\\.(csv|rds|png)$')))
}
# Failure at configuration-load time must still yield the five diagnostic files.
unlink(file.path(build,'setup_profile.json'))
bad <- make_plan('missing-profile');stopifnot(!run_analysis(bad))
stopifnot(all(file.exists(file.path(bad$run_root,c('analysis_report.html','qc.json','output_manifest.json','execution_status.csv','software_versions.csv')))))
unlink(folder,recursive=TRUE)
cat('Renderer QC passed: complete 1001-row listing, four components, rtables, PNG/PDF, UTF-8, formula/XSS escaping, failure cleanup and fatal diagnostics.\n')
