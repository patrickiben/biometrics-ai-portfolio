BW_TEMPLATES <- list("test_scripts.csv" = list(data = seed$tests, required = TRUE),
  "defect_log.csv" = list(data = seed$defects, required = FALSE),
  "traceability_matrix.csv" = list(data = seed$trace, required = TRUE))
bw_uat_validate <- function(frames, settings = NULL) {
  data <- stats::setNames(frames, c("tests", "defects", "trace"))
  uat_validate(data$tests, data$defects, data$trace)
  bw_need(all(data$tests$RequirementID %in% data$trace$RequirementID), "A test references a requirement absent from the traceability file.")
  bw_need(all(data$defects$FoundInTest %in% data$tests$TestID), "A defect references a test absent from the test-script file.")
  linked <- data$tests$LinkedDefect; linked <- linked[!is.na(linked) & nzchar(linked)]
  bw_need(all(linked %in% data$defects$DefectID), "A linked defect is absent from the defect log.")
  bw_need(all(unlist(uat_covering_tests(data$trace)) %in% data$tests$TestID), "Traceability references a test absent from the test-script file.")
  uat_gate(data$tests, data$defects, data$trace); data
}
