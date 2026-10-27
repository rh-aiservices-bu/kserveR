METRICS <- new.env(parent = emptyenv())
METRICS$requests  <- list()
METRICS$durations <- list()
METRICS$started   <- Sys.time()

metrics_record <- function(path, status, seconds) {
  key <- paste(path, status, sep = "\u001f")
  previous <- METRICS$requests[[key]]
  METRICS$requests[[key]] <- if (is.null(previous)) 1L else previous + 1L

  duration <- METRICS$durations[[path]]
  METRICS$durations[[path]] <- if (is.null(duration)) {
    list(sum = seconds, count = 1L)
  } else {
    list(sum = duration$sum + seconds, count = duration$count + 1L)
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

  for (key in names(METRICS$requests)) {
    parts <- strsplit(key, "\u001f", fixed = TRUE)[[1L]]
    lines <- c(lines, sprintf(
      'kserver_requests_total{model="%s",path="%s",status="%s"} %d',
      model, escape_label(parts[[1L]]), escape_label(parts[[2L]]),
      METRICS$requests[[key]]
    ))
  }

  lines <- c(
    lines,
    "# HELP kserver_request_duration_seconds Time spent handling requests.",
    "# TYPE kserver_request_duration_seconds summary"
  )
  for (path in names(METRICS$durations)) {
    duration <- METRICS$durations[[path]]
    label <- escape_label(path)
    lines <- c(
      lines,
      sprintf('kserver_request_duration_seconds_sum{model="%s",path="%s"} %.6f',
              model, label, duration$sum),
      sprintf('kserver_request_duration_seconds_count{model="%s",path="%s"} %d',
              model, label, duration$count)
    )
  }

  paste0(paste(lines, collapse = "\n"), "\n")
}
