MODEL_VERSION <- Sys.getenv("MODEL_VERSION", "1")

load_model_state <- function(dir = MODEL_DIR) {
  if (!dir.exists(dir)) {
    stop(sprintf("model directory '%s' does not exist", dir))
  }

  path <- resolve_model_file(dir)
  message(sprintf("[kserveR] loading model from %s", path))

  model <- load_model_object(path)
  message(sprintf("[kserveR] loaded a '%s' object", paste(class(model), collapse = "/")))

  schema     <- build_schema(model, dir)
  predict_fn <- load_predict_hook(dir)

  if (is.null(predict_fn) && !ensure_predict_method(model)) {
    stop(sprintf(
      paste0(
        "no predict() method is available for a '%s' object. The package that ",
        "defines it is probably not in this image - set MODEL_PACKAGES=<pkg>, ",
        "ship an renv.lock alongside the model, or provide a predict.R hook."
      ),
      paste(class(model), collapse = "/")
    ))
  }

  if (length(schema$predictors)) {
    message(sprintf(
      "[kserveR] predictors: %s",
      paste(sprintf("%s<%s>", names(schema$predictors), schema$predictors), collapse = ", ")
    ))
  } else {
    message("[kserveR] could not infer predictor names from this model; ",
            "matrix-shaped requests will need a schema.json")
  }
  if (length(schema$xlevels)) {
    message(sprintf("[kserveR] factor columns: %s",
                    paste(names(schema$xlevels), collapse = ", ")))
  }

  list(
    model      = model,
    path       = path,
    name       = MODEL_NAME,
    version    = MODEL_VERSION,
    schema     = schema,
    predict_fn = predict_fn
  )
}

load_predict_hook <- function(dir = MODEL_DIR) {
  path <- model_dir_path("predict.R", dir)
  if (is.null(path)) return(NULL)

  message(sprintf("[kserveR] sourcing prediction hook %s", path))
  env <- new.env(parent = globalenv())
  sys.source(path, envir = env)

  if (!exists("kserve_predict", envir = env, inherits = FALSE)) {
    stop(sprintf("%s must define a function kserve_predict(model, newdata)", path))
  }
  hook <- get("kserve_predict", envir = env)
  if (!is.function(hook)) {
    stop(sprintf("%s defines kserve_predict but it is not a function", path))
  }
  hook
}

run_prediction <- function(state, newdata) {
  if (!is.null(state$predict_fn)) {
    return(state$predict_fn(state$model, newdata))
  }
  args <- list(state$model, newdata)
  if (!is.null(PREDICT_TYPE)) args$type <- PREDICT_TYPE
  do.call(stats::predict, args)
}

run_inference <- function(state, body) {
  inputs <- body$inputs
  if (is.null(inputs) || !length(inputs)) {
    stop(bad_request("request body has no 'inputs'"))
  }

  frame <- inputs_to_dataframe(inputs, state$schema)
  check_required_columns(frame, state$schema)
  frame <- apply_training_levels(frame, state$schema$xlevels)

  newdata     <- prepare_newdata(state$model, frame)
  predictions <- run_prediction(state, newdata)

  predictions_to_outputs(predictions)
}
