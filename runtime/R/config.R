MODEL_DIR       <- Sys.getenv("MODEL_DIR", "/mnt/models")
MODEL_NAME      <- Sys.getenv("MODEL_NAME", "model")
SERVER_HOST     <- Sys.getenv("SERVER_HOST", "0.0.0.0")
SERVER_PORT     <- as.integer(Sys.getenv("SERVER_PORT", "8080"))
RUNTIME_NAME    <- "kserveR"
RUNTIME_VERSION <- "0.1.0"

PREDICT_TYPE <- local({ v <- Sys.getenv("PREDICT_TYPE", ""); if (nzchar(v)) v else NULL })
MODEL_FORMAT <- local({ v <- Sys.getenv("MODEL_FORMAT", ""); if (nzchar(v)) tolower(v) else NULL })

`%||%` <- function(x, y) if (is.null(x)) y else x

MODEL_EXTENSIONS <- c("rds", "qs2", "qs", "rda", "rdata", "ubj", "model", "xgb")

resolve_model_file <- function(dir = MODEL_DIR) {
  explicit <- Sys.getenv("MODEL_FILE", "")
  if (nzchar(explicit)) {
    path <- if (file.exists(explicit)) explicit else file.path(dir, explicit)
    if (!file.exists(path)) {
      stop(sprintf("MODEL_FILE is set to '%s' but no such file exists", explicit))
    }
    return(path)
  }

  for (ext in MODEL_EXTENSIONS) {
    conventional <- file.path(dir, paste0("model.", ext))
    if (file.exists(conventional)) return(conventional)
  }

  pattern <- sprintf("\\.(%s)$", paste(MODEL_EXTENSIONS, collapse = "|"))
  found <- list.files(dir, pattern = pattern, ignore.case = TRUE, full.names = TRUE)
  if (length(found) == 1L) return(found)

  if (length(found) == 0L) {
    present <- list.files(dir)
    stop(sprintf(
      "no model found in %s: expected model.{%s} or a single model file (directory contains: %s)",
      dir, paste(MODEL_EXTENSIONS, collapse = ","),
      if (length(present)) paste(present, collapse = ", ") else "<empty>"
    ))
  }
  stop(sprintf(
    "found %d candidate model files in %s (%s) - name one model.rds or set MODEL_FILE",
    length(found), dir, paste(basename(found), collapse = ", ")
  ))
}

model_dir_path <- function(filename, dir = MODEL_DIR) {
  path <- file.path(dir, filename)
  if (file.exists(path)) path else NULL
}
