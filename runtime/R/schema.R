training_xlevels <- function(model) {
  if (!is.null(model$xlevels) && length(model$xlevels)) {
    return(keep_character_levels(model$xlevels))
  }
  if (!is.null(model$forest$xlevels)) {
    return(keep_character_levels(model$forest$xlevels))
  }
  list()
}

keep_character_levels <- function(xlevels) {
  is_real <- vapply(
    xlevels,
    function(lv) is.character(lv) && length(lv) > 0L,
    logical(1)
  )
  xlevels[is_real]
}

training_predictors <- function(model) {
  terms_obj <- tryCatch(stats::terms(model), error = function(e) NULL)
  if (!is.null(terms_obj)) {
    classes <- attr(terms_obj, "dataClasses")
    if (!is.null(classes)) {
      response <- attr(terms_obj, "response")
      if (!is.null(response) && response > 0L) classes <- classes[-response]
      if (length(classes)) return(classes)
    }
  }

  names_only <- NULL
  if (!is.null(model$forest$xlevels)) {
    names_only <- names(model$forest$xlevels)
  } else if (!is.null(model$feature_names)) {
    names_only <- model$feature_names
  } else if (!is.null(colnames(model$x))) {
    names_only <- colnames(model$x)
  }

  if (is.null(names_only)) return(character(0))

  xlevels <- training_xlevels(model)
  stats::setNames(
    ifelse(names_only %in% names(xlevels), "factor", "numeric"),
    names_only
  )
}

training_classes <- function(model) {
  if (!is.null(model$classes)) return(as.character(model$classes))
  if (!is.null(model$levels))  return(as.character(model$levels))
  if (!is.null(model$y) && is.factor(model$y)) return(levels(model$y))
  NULL
}

read_schema_file <- function(dir = MODEL_DIR) {
  path <- model_dir_path("schema.json", dir)
  if (is.null(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

build_schema <- function(model, dir = MODEL_DIR) {
  schema <- list(
    predictors = training_predictors(model),
    xlevels    = training_xlevels(model),
    classes    = training_classes(model)
  )

  declared <- read_schema_file(dir)
  if (is.null(declared)) return(schema)

  for (input in declared$inputs %||% list()) {
    if (is.null(input$name)) next
    if (!is.null(input$levels)) {
      schema$xlevels[[input$name]] <- as.character(unlist(input$levels))
    }
    if (!is.null(input$datatype)) {
      schema$predictors[input$name] <-
        if (identical(input$datatype, "BYTES")) "factor" else "numeric"
    }
  }
  if (!is.null(declared$classes)) {
    schema$classes <- as.character(unlist(declared$classes))
  }
  schema$declared_outputs <- declared$outputs
  schema
}
