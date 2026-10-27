METRICS <- new.env(parent = emptyenv())
METRICS$requests       <- list()
METRICS$duration_sum   <- 0
METRICS$duration_count <- 0
METRICS$started        <- Sys.time()

metrics_record <- function(path, status, seconds) {
  key <- paste(path, status, sep = "\u001f")
  previous <- METRICS$requests[[key]]
  METRICS$requests[[key]] <- if (is.null(previous)) 1L else previous + 1L
  METRICS$duration_sum   <- METRICS$duration_sum + seconds
  METRICS$duration_count <- METRICS$duration_count + 1L
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
    "# HELP kserver_model_loaded Whether a model is loaded and being served.",
    "# TYPE kserver_model_loaded gauge",
    sprintf('kserver_model_loaded{model="%s"} 1', model),
    "# HELP kserver_uptime_seconds Seconds since the server started.",
    "# TYPE kserver_uptime_seconds gauge",
    sprintf(
      'kserver_uptime_seconds{model="%s"} %.3f',
      model, as.numeric(difftime(Sys.time(), METRICS$started, units = "secs"))
    ),
    "# HELP kserver_requests_total Total HTTP requests handled.",
    "# TYPE kserver_requests_total counter"
  )

  if (length(METRICS$requests)) {
    for (key in names(METRICS$requests)) {
      parts <- strsplit(key, "\u001f", fixed = TRUE)[[1L]]
      lines <- c(lines, sprintf(
        'kserver_requests_total{model="%s",path="%s",status="%s"} %d',
        model, escape_label(parts[[1L]]), escape_label(parts[[2L]]),
        METRICS$requests[[key]]
      ))
    }
  } else {
    lines <- c(lines, sprintf('kserver_requests_total{model="%s"} 0', model))
  }

  lines <- c(
    lines,
    "# HELP kserver_request_duration_seconds Time spent handling requests.",
    "# TYPE kserver_request_duration_seconds summary",
    sprintf('kserver_request_duration_seconds_sum{model="%s"} %.6f',
            model, METRICS$duration_sum),
    sprintf('kserver_request_duration_seconds_count{model="%s"} %d',
            model, METRICS$duration_count)
  )

  paste0(paste(lines, collapse = "\n"), "\n")
}
