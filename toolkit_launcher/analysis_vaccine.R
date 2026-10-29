# Fixed adapter for a verified vaccine package; source/data paths are not user commands.
analysis_vaccine_prepare <- function(build) {
  scope <- new.env(parent=globalenv())
  sys.source(file.path(build,"R/vaccine_analysis.R"),envir=scope)
  cfg <- jsonlite::fromJSON(file.path(build,"study_setup.json"),simplifyVector=FALSE)
  types <- list(
    participants=c("character","character","character","character"),
    titers=c(rep("character",5),"numeric","character","numeric","numeric"),
    doses=c("character","character"),
    # Validate whole-number semantics in the core after reading; R's integer
    # scanner has a narrower range than the form's finite numeric parser.
    diary=c("character","character","numeric","character","numeric")
  )
  data <- lapply(names(types),function(slot) utils::read.csv(
    file.path(build,"inputs",paste0(slot,".csv")),colClasses=types[[slot]],
    check.names=FALSE,na.strings="",fileEncoding="UTF-8",stringsAsFactors=FALSE))
  names(data) <- names(types)
  list(scope=scope,config=cfg,prepared=scope$vaccine_prepare(data,cfg))
}
