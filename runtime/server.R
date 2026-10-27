#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(plumber)
  library(jsonlite)
})

runtime_home <- function() {
  from_env <- Sys.getenv("RUNTIME_HOME", "")
  if (nzchar(from_env)) return(from_env)

  args     <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]))))
  }
  getwd()
}

HOME_DIR <- runtime_home()

for (file in c("config.R", "schema.R", "formats.R", "tensors.R", "model.R", "api_v2.R")) {
  source(file.path(HOME_DIR, "R", file), local = FALSE)
}

message(sprintf("[kserveR] %s %s | R %s", RUNTIME_NAME, RUNTIME_VERSION, getRversion()))

state <- load_model_state()

message(sprintf("[kserveR] listening on %s:%d", SERVER_HOST, SERVER_PORT))
plumber::pr_run(
  build_router(state),
  host = SERVER_HOST,
  port = SERVER_PORT,
  docs = FALSE
)
