METRICS <- new.env(parent = emptyenv())
METRICS$infer_success     <- 0L
METRICS$infer_failure     <- 0L
METRICS$infer_duration_ms <- 0
METRICS$infer_count       <- 0L
METRICS$http              <- list()
METRICS$started           <- Sys.time()

INFER_PATH_TEMPLATE <- "/v2/models/{model_name}/infer"

normalise_path <- function(path) {
  if (grepl("/infer$", path)) INFER_PATH_TEMPLATE else path
}

metrics_record <- function(path, status, seconds) {
  label <- normalise_path(path)
  entry <- METRICS$http[[label]]
  METRICS$http[[label]] <- if (is.null(entry)) {
    list(sum = seconds, count = 1L)
  } else {
    list(sum = entry$sum + seconds, count = entry$count + 1L)
  }

  if (grepl("/infer$", path)) {
    code <- suppressWarnings(as.integer(status))
    if (!is.na(code) && code >= 200L && code < 300L) {
      METRICS$infer_success <- METRICS$infer_success + 1L
    } else {
      METRICS$infer_failure <- METRICS$infer_failure + 1L
    }
    METRICS$infer_duration_ms <- METRICS$infer_duration_ms + seconds * 1000
    METRICS$infer_count       <- METRICS$infer_count + 1L
  }
  invisible(NULL)
}

escape_label <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub('"', '\\\\"', x)
  gsub("\n", "\\\\n", x)
}

metrics_render <- function(model_name = MODEL_NAME) {
  model <- escape_label(model_name)

  lines <- c(
    "# HELP model_infer_request_success_total Successful inference requests.",
    "# TYPE model_infer_request_success_total counter",
    sprintf('model_infer_request_success_total{model="%s"} %d', model, METRICS$infer_success),
    "# HELP model_infer_request_failure_total Failed inference requests.",
    "# TYPE model_infer_request_failure_total counter",
    sprintf('model_infer_request_failure_total{model="%s"} %d', model, METRICS$infer_failure),
    "# HELP model_infer_request_duration Inference request duration in milliseconds.",
    "# TYPE model_infer_request_duration summary",
    sprintf('model_infer_request_duration_sum{model="%s"} %.3f', model, METRICS$infer_duration_ms),
    sprintf('model_infer_request_duration_count{model="%s"} %d', model, METRICS$infer_count),
    "# HELP rest_server_request_duration_seconds HTTP request duration in seconds.",
    "# TYPE rest_server_request_duration_seconds summary"
  )

  for (path in names(METRICS$http)) {
    entry <- METRICS$http[[path]]
    label <- escape_label(path)
    lines <- c(
      lines,
      sprintf('rest_server_request_duration_seconds_sum{model="%s",path="%s"} %.6f',
              model, label, entry$sum),
      sprintf('rest_server_request_duration_seconds_count{model="%s",path="%s"} %d',
              model, label, entry$count)
    )
  }

  lines <- c(
    lines,
    "# HELP kserver_model_loaded Whether a model is loaded and being served.",
    "# TYPE kserver_model_loaded gauge",
    sprintf('kserver_model_loaded{model="%s"} 1', model),
    "# HELP kserver_uptime_seconds Seconds since the server started.",
    "# TYPE kserver_uptime_seconds gauge",
    sprintf('kserver_uptime_seconds{model="%s"} %.3f',
            model, as.numeric(difftime(Sys.time(), METRICS$started, units = "secs")))
  )

  paste0(paste(lines, collapse = "\n"), "\n")
}
