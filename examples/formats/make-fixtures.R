#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(randomForest)
  library(jsonlite)
})
set.seed(42)

root <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]))) else getwd()
})

features <- setdiff(names(iris), "Species")
rows     <- iris[c(1L, 51L, 101L, 120L), features]

write_request <- function(dir) {
  request <- list(
    id = "fixture",
    inputs = unname(lapply(features, function(col) {
      list(name = col, shape = I(nrow(rows)), datatype = "FP64", data = I(rows[[col]]))
    }))
  )
  writeLines(toJSON(request, auto_unbox = TRUE, digits = NA, pretty = TRUE),
             file.path(dir, "request.json"))
}

write_expected <- function(dir, predictions) {
  writeLines(toJSON(list(predictions = predictions), auto_unbox = TRUE, pretty = TRUE),
             file.path(dir, "expected.json"))
}

new_dir <- function(name) {
  dir <- file.path(root, name)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  dir
}

rf <- randomForest(Species ~ ., data = iris, ntree = 100)
rf_expected <- as.character(predict(rf, rows))

dir <- new_dir("rds")
saveRDS(rf, file.path(dir, "model.rds"))
write_request(dir); write_expected(dir, rf_expected)
cat("rds        model.rds\n")

dir <- new_dir("rda")
fit <- rf
save(fit, file = file.path(dir, "model.rda"))
write_request(dir); write_expected(dir, rf_expected)
cat("rda        model.rda (single object 'fit')\n")

dir <- new_dir("rda-multi")
fit <- rf
metadata <- list(trained = Sys.Date())
save(fit, metadata, file = file.path(dir, "model.rda"))
write_request(dir); write_expected(dir, rf_expected)
cat("rda-multi  model.rda (two objects, needs MODEL_OBJECT=fit)\n")

if (requireNamespace("qs2", quietly = TRUE)) {
  dir <- new_dir("qs2")
  qs2::qs_save(rf, file.path(dir, "model.qs2"))
  write_request(dir); write_expected(dir, rf_expected)
  cat("qs2        model.qs2\n")
} else {
  cat("qs2        SKIPPED (qs2 not installed)\n")
}

if (requireNamespace("xgboost", quietly = TRUE)) {
  dir <- new_dir("xgb")
  labels <- as.integer(iris$Species) - 1L
  booster <- xgboost::xgboost(
    data = as.matrix(iris[, features]), label = labels,
    nrounds = 20, objective = "multi:softmax", num_class = 3L,
    verbose = 0
  )
  xgboost::xgb.save(booster, file.path(dir, "model.ubj"))

  writeLines(
    toJSON(list(inputs = lapply(features, function(col) {
      list(name = col, datatype = "FP64")
    })), auto_unbox = TRUE, pretty = TRUE),
    file.path(dir, "schema.json")
  )

  predicted <- predict(booster, as.matrix(rows))
  write_request(dir)
  write_expected(dir, as.character(predicted))

  matrix_request <- list(
    id = "fixture-matrix",
    inputs = list(list(
      name = "input",
      shape = c(nrow(rows), length(features)),
      datatype = "FP64",
      data = as.vector(t(as.matrix(rows)))
    ))
  )
  writeLines(toJSON(matrix_request, auto_unbox = TRUE, digits = NA, pretty = TRUE),
             file.path(dir, "matrix-request.json"))
  cat("xgb        model.ubj + schema.json + matrix-request.json\n")
} else {
  cat("xgb        SKIPPED (xgboost not installed)\n")
}
