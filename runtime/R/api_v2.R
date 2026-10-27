json_serializer <- function() {
  plumber::serializer_json(auto_unbox = TRUE, digits = NA, na = "null", null = "null")
}

parse_request_body <- function(req) {
  raw  <- req$bodyRaw
  text <- if (!is.null(raw) && length(raw)) rawToChar(raw) else req$postBody

  if (is.null(text) || !nzchar(text)) stop(bad_request("empty request body"))

  tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) {
      stop(bad_request("request body is not valid JSON: %s", conditionMessage(e)))
    }
  )
}

v2_datatype_for_class <- function(cls) {
  switch(cls, numeric = "FP64", integer = "INT32", logical = "BOOL", "BYTES")
}

server_metadata <- function() {
  list(
    name       = RUNTIME_NAME,
    version    = RUNTIME_VERSION,
    extensions = I(character(0))
  )
}

model_metadata <- function(state, name) {
  predictors <- state$schema$predictors

  inputs <- unname(Map(
    function(col, cls) {
      list(name = col, datatype = v2_datatype_for_class(cls), shape = I(c(-1L)))
    },
    names(predictors), as.character(predictors)
  ))

  outputs <- list(list(
    name     = "predictions",
    datatype = if (length(state$schema$classes)) "BYTES" else "FP64",
    shape    = I(c(-1L))
  ))

  list(
    name     = name,
    versions = I(as.character(state$version)),
    platform = "kserveR",
    inputs   = inputs,
    outputs  = outputs
  )
}

error_handler <- function(req, res, err) {
  is_bad_request <- inherits(err, "kserve_bad_request")
  res$status <- if (is_bad_request) 400L else 500L

  message_text <- conditionMessage(err)
  if (!is_bad_request) {
    message(sprintf("[kserveR] 500 on %s: %s", req$PATH_INFO, message_text))
  }
  list(error = message_text)
}

# Model name is not validated: a ServingRuntime cannot reliably template the
# InferenceService name into its container, so strict matching yields spurious
# 404s. We echo back whatever was asked for; MODEL_NAME drives metadata.
build_router <- function(state) {
  pr <- plumber::pr()
  pr <- plumber::pr_set_serializer(pr, json_serializer())
  pr <- plumber::pr_set_error(pr, error_handler)

  ok <- function() list()

  pr <- plumber::pr_get(pr, "/v2/health/live",  function() ok())
  pr <- plumber::pr_get(pr, "/v2/health/ready", function() ok())
  pr <- plumber::pr_get(pr, "/v2", function() server_metadata())

  pr <- plumber::pr_get(
    pr, "/v2/models/<model_name>/ready",
    function(model_name) ok()
  )
  pr <- plumber::pr_get(
    pr, "/v2/models/<model_name>",
    function(model_name) model_metadata(state, model_name)
  )

  infer <- function(model_name, req) {
    body    <- parse_request_body(req)
    outputs <- run_inference(state, body)

    response <- list(
      model_name    = model_name,
      model_version = as.character(state$version),
      outputs       = outputs
    )
    if (!is.null(body$id)) response$id <- body$id
    response
  }

  pr <- plumber::pr_post(pr, "/v2/models/<model_name>/infer", infer, parsers = "octet")

  pr <- plumber::pr_post(
    pr, "/v2/models/<model_name>/versions/<model_version>/infer",
    function(model_name, model_version, req) infer(model_name, req),
    parsers = "octet"
  )

  pr
}
