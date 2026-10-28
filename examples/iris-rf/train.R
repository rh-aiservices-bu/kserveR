#!/usr/bin/env Rscript
# Fits the example model and writes model.rds, request.json and expected.json.

suppressPackageStartupMessages(library(randomForest))
set.seed(42)

out_dir <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]))) else getwd()
})

model <- randomForest(Species ~ ., data = iris, ntree = 100)
saveRDS(model, file.path(out_dir, "model.rds"))
cat(sprintf("wrote %s\n", file.path(out_dir, "model.rds")))

rows     <- iris[c(1L, 51L, 101L, 120L), setdiff(names(iris), "Species")]
features <- names(rows)

request <- list(
  id = "iris-sample",
  inputs = unname(lapply(features, function(col) {
    list(
      name     = col,
      shape    = I(nrow(rows)),   # I() so a length-1 shape stays a JSON array
      datatype = "FP64",
      data     = I(rows[[col]])
    )
  }))
)

writeLines(
  jsonlite::toJSON(request, auto_unbox = TRUE, digits = NA, pretty = TRUE),
  file.path(out_dir, "request.json")
)
cat(sprintf("wrote %s\n", file.path(out_dir, "request.json")))

# Ground truth for the smoke test to diff served predictions against.
expected <- as.character(predict(model, rows))
writeLines(
  jsonlite::toJSON(list(predictions = expected), auto_unbox = TRUE, pretty = TRUE),
  file.path(out_dir, "expected.json")
)
cat(sprintf("wrote %s -> %s\n", file.path(out_dir, "expected.json"),
            paste(expected, collapse = ", ")))
