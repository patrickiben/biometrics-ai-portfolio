# Build-time only: expose the canonical deterministic QC examples as browser CSVs.
args <- commandArgs(trailingOnly=TRUE)
source('toolkit_launcher/tests/analysis_fixtures.R')
examples <- setNames(lapply(c('parallel','crossover','single_sequence','sad','mad'), function(design) {
  lapply(analysis_fixture(design),function(d) paste(capture.output(write.csv(d,row.names=FALSE,na='')),collapse='\n'))
}),c('parallel','crossover','single_sequence','sad','mad'))
jsonlite::write_json(examples,args[[1]],auto_unbox=TRUE)
