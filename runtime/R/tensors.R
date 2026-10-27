bad_request <- function(fmt, ...) {
  msg <- if (length(list(...))) sprintf(fmt, ...) else fmt
  structure(
    class = c("kserve_bad_request", "error", "condition"),
    list(message = msg, call = NULL)
  )
}

coerce_v2 <- function(values, datatype, name) {
  switch(
    toupper(as.character(datatype)),
    BOOL   = as.logical(values),
    INT8 = , INT16 = , INT32 = , UINT8 = , UINT16 = , UINT32 = as.integer(values),
    INT64 = , UINT64 = , FP16 = , FP32 = , FP64 = as.numeric(values),
    BYTES  = as.character(values),
    stop(bad_request("input '%s' has unknown datatype '%s'", name, datatype))
  )
}

v2_datatype <- function(x) {
  if (is.logical(x))                        "BOOL"
  else if (is.factor(x) || is.character(x)) "BYTES"
  else if (is.integer(x))                   "INT32"
  else if (is.numeric(x))                   "FP64"
  else stop(sprintf("cannot express an R '%s' as a V2 tensor", class(x)[[1L]]))
}

require_fields <- function(tensor) {
  if (is.null(tensor$name) || !nzchar(as.character(tensor$name))) {
    stop(bad_request("every input tensor needs a 'name'"))
  }
  for (field in c("datatype", "shape", "data")) {
    if (is.null(tensor[[field]])) {
      stop(bad_request("input '%s' is missing '%s'", tensor$name, field))
    }
  }
}

tensor_shape <- function(tensor) {
  shape <- suppressWarnings(as.integer(unlist(tensor$shape, use.names = FALSE)))
  if (!length(shape) || anyNA(shape) || any(shape < 0L)) {
    stop(bad_request("input '%s' has an invalid shape", tensor$name))
  }
  shape
}

tensor_values <- function(tensor) {
  data <- tensor$data
  if (is.list(data)) data <- unlist(data, use.names = FALSE)
  coerce_v2(data, tensor$datatype, tensor$name)
}

check_length <- function(tensor, shape, values) {
  expected <- prod(shape)
  if (length(values) != expected) {
    stop(bad_request(
      "input '%s' declares shape [%s] (%d values) but carries %d",
      tensor$name, paste(shape, collapse = ","), expected, length(values)
    ))
  }
}

inputs_to_dataframe <- function(inputs, schema) {
  if (!length(inputs)) stop(bad_request("request has no 'inputs'"))

  if (length(inputs) == 1L) {
    require_fields(inputs[[1L]])
    shape <- tensor_shape(inputs[[1L]])
    if (length(shape) == 2L && shape[2L] > 1L) {
      return(matrix_to_dataframe(inputs[[1L]], schema))
    }
  }
  columns_to_dataframe(inputs)
}

columns_to_dataframe <- function(inputs) {
  cols  <- list()
  nrows <- NULL

  for (tensor in inputs) {
    require_fields(tensor)
    shape  <- tensor_shape(tensor)
    values <- tensor_values(tensor)
    check_length(tensor, shape, values)

    n <- shape[1L]
    if (is.null(nrows)) {
      nrows <- n
    } else if (n != nrows) {
      stop(bad_request(
        "input '%s' has %d rows but an earlier input has %d - all inputs must agree",
        tensor$name, n, nrows
      ))
    }
    if (tensor$name %in% names(cols)) {
      stop(bad_request("input '%s' appears more than once", tensor$name))
    }
    cols[[tensor$name]] <- values
  }

  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
}

matrix_to_dataframe <- function(tensor, schema) {
  shape  <- tensor_shape(tensor)
  values <- tensor_values(tensor)
  check_length(tensor, shape, values)

  cols <- names(schema$predictors)
  if (!length(cols)) {
    stop(bad_request(
      paste0("input '%s' is a %dx%d matrix, but this model exposes no predictor ",
             "names to label the columns with - send one tensor per column, or ",
             "ship a schema.json"),
      tensor$name, shape[1L], shape[2L]
    ))
  }
  if (length(cols) != shape[2L]) {
    stop(bad_request(
      "input '%s' has %d columns but the model expects %d (%s)",
      tensor$name, shape[2L], length(cols), paste(cols, collapse = ", ")
    ))
  }

  frame <- as.data.frame(
    matrix(values, nrow = shape[1L], ncol = shape[2L], byrow = TRUE),
    stringsAsFactors = FALSE
  )
  names(frame) <- cols
  frame
}

apply_training_levels <- function(frame, xlevels) {
  for (name in intersect(names(frame), names(xlevels))) {
    levels_seen <- xlevels[[name]]
    values      <- as.character(frame[[name]])
    unseen      <- setdiff(unique(values[!is.na(values)]), levels_seen)

    if (length(unseen)) {
      stop(bad_request(
        "column '%s' has value(s) not seen during training: %s (known levels: %s)",
        name,
        paste(sprintf("'%s'", unseen), collapse = ", "),
        paste(levels_seen, collapse = ", ")
      ))
    }
    frame[[name]] <- factor(values, levels = levels_seen)
  }
  frame
}

check_required_columns <- function(frame, schema) {
  required <- names(schema$predictors)
  if (!length(required)) return(invisible(TRUE))

  missing <- setdiff(required, names(frame))
  if (length(missing)) {
    stop(bad_request(
      "missing required input(s): %s (expected %s)",
      paste(missing, collapse = ", "), paste(required, collapse = ", ")
    ))
  }
  invisible(TRUE)
}

make_output <- function(name, value, parameters = NULL) {
  if (is.factor(value)) value <- as.character(value)

  if (is.matrix(value)) {
    shape <- dim(value)
    flat  <- as.vector(t(value))
  } else {
    shape <- length(value)
    flat  <- unname(value)
  }

  output <- list(
    name     = name,
    datatype = v2_datatype(flat),
    shape    = I(as.integer(shape)),
    data     = I(flat)
  )
  if (!is.null(parameters)) output$parameters <- parameters
  output
}

predictions_to_outputs <- function(predictions) {
  if (is.data.frame(predictions)) {
    return(unname(Map(make_output, names(predictions), as.list(predictions))))
  }

  if (is.list(predictions)) {
    names_present <- names(predictions)
    if (is.null(names_present) || any(!nzchar(names_present))) {
      stop("a predict.R hook returning a list must name every element")
    }
    return(unname(Map(make_output, names_present, predictions)))
  }

  if (is.matrix(predictions)) {
    parameters <- if (!is.null(colnames(predictions))) {
      list(class_names = I(colnames(predictions)))
    } else {
      NULL
    }
    return(list(make_output("predictions", predictions, parameters)))
  }

  list(make_output("predictions", predictions))
}
