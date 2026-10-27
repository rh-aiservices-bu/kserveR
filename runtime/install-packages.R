PACKAGES <- c(
  "plumber", "jsonlite", "renv",
  "randomForest", "ranger", "glmnet", "rpart", "nnet", "e1071", "MASS",
  "caret", "parsnip", "workflows", "recipes", "hardhat",
  "qs2", "xgboost", "vetiver", "pins"
)

options(Ncpus = max(1L, parallel::detectCores()), warn = 2L)

cat("------------------------------------------------------------\n")
cat(sprintf("R        : %s on %s\n", getRversion(), R.version$platform))
cat(sprintf("library  : %s\n", .libPaths()[[1L]]))
cat(sprintf("repo     : %s\n", getOption("repos")[["CRAN"]]))
cat(sprintf("packages : %d\n", length(PACKAGES)))
cat("------------------------------------------------------------\n")
flush.console()

install.packages(PACKAGES)

ok <- vapply(PACKAGES, requireNamespace, logical(1), quietly = TRUE)
if (any(!ok)) {
  cat(sprintf("FAILED: %s\n", paste(PACKAGES[!ok], collapse = ", ")))
  quit(status = 1L)
}

cat("all packages load cleanly\n")
