args    <- commandArgs(trailingOnly = TRUE)
profile <- if (length(args) >= 1L) args[[1L]] else "full"
lib     <- if (length(args) >= 2L) args[[2L]] else .libPaths()[[1L]]
repo    <- if (length(args) >= 3L) args[[3L]] else
  "https://packagemanager.posit.co/cran/__linux__/rhel9/latest"

SERVER       <- c("plumber", "jsonlite", "renv")
MODELS_LEAN  <- c("randomForest", "ranger", "glmnet", "rpart", "nnet", "e1071", "MASS")
MODELS_FULL  <- c("caret", "parsnip", "workflows", "recipes", "hardhat")
FORMATS_FULL <- c("qs2", "xgboost", "vetiver", "pins")

packages <- switch(
  profile,
  lean = c(SERVER, MODELS_LEAN),
  full = c(SERVER, MODELS_LEAN, MODELS_FULL, FORMATS_FULL),
  stop(sprintf("unknown PKG_PROFILE '%s' (expected 'lean' or 'full')", profile))
)

options(
  repos = c(CRAN = repo),
  HTTPUserAgent = sprintf(
    "R/%s R (%s)",
    getRversion(),
    paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
  ),
  Ncpus = max(1L, parallel::detectCores()),
  warn = 2L
)

db <- available.packages()
has_binaries <- "Path" %in% colnames(db)

cat("------------------------------------------------------------\n")
cat(sprintf("profile       : %s (%d packages)\n", profile, length(packages)))
cat(sprintf("R             : %s on %s\n", getRversion(), R.version$platform))
cat(sprintf("repo          : %s\n", repo))
cat(sprintf("PPM binaries  : %s\n", if (has_binaries) "YES - installs are downloads"
                                    else "NO  - compiling from source, expect a slow build"))
cat("------------------------------------------------------------\n")
flush.console()

started <- Sys.time()
install.packages(packages, lib = lib)
elapsed <- round(as.numeric(difftime(Sys.time(), started, units = "mins")), 1)


.libPaths(c(lib, .libPaths()))
ok <- vapply(packages, requireNamespace, logical(1), quietly = TRUE)

cat("------------------------------------------------------------\n")
cat(sprintf("installed %d/%d packages in %s minutes\n", sum(ok), length(ok), elapsed))
if (any(!ok)) {
  cat(sprintf("FAILED: %s\n", paste(packages[!ok], collapse = ", ")))
  quit(status = 1L)
}
cat("all packages load cleanly\n")
cat("------------------------------------------------------------\n")
