PACKAGES <- c(
  "plumber", "jsonlite", "renv",
  "randomForest", "ranger", "glmnet", "rpart", "nnet", "e1071", "MASS",
  "caret", "parsnip", "workflows", "recipes", "hardhat",
  "qs2", "xgboost", "vetiver", "pins"
)

options(Ncpus = max(1L, parallel::detectCores()))

cat("------------------------------------------------------------\n")
cat(sprintf("R        : %s on %s\n", getRversion(), R.version$platform))
cat(sprintf("library  : %s\n", .libPaths()[[1L]]))
cat(sprintf("repo     : %s\n", getOption("repos")[["CRAN"]]))
cat(sprintf("packages : %d\n", length(PACKAGES)))
cat("------------------------------------------------------------\n")
flush.console()

install.packages(PACKAGES)

load_error <- function(pkg) {
  tryCatch({ loadNamespace(pkg); NA_character_ },
           error = function(e) conditionMessage(e))
}

errors <- vapply(PACKAGES, load_error, character(1))
failed <- PACKAGES[!is.na(errors)]

if (length(failed)) {
  for (pkg in failed) cat(sprintf("FAILED %s: %s\n", pkg, errors[[pkg]]))
  quit(status = 1L)
}

cat("all packages load cleanly\n")
