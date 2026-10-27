load_model_object <- function(path, format = MODEL_FORMAT) {
  fmt <- format %||% tolower(tools::file_ext(path))

  switch(
    fmt,
    rds     = readRDS(path),
    rda     = ,
    rdata   = load_rdata(path),
    qs2     = with_package("qs2",     function() qs2::qs_read(path)),
    qs      = with_package("qs",      function() qs::qread(path)),
    ubj     = ,
    model   = ,
    xgb     = ,
    json    = with_package("xgboost", function() xgboost::xgb.load(path)),
    vetiver = load_vetiver(path),
    stop(sprintf(
      "unsupported model format '%s' for %s (supported: %s, vetiver)",
      fmt, basename(path), paste(MODEL_EXTENSIONS, collapse = ", ")
    ))
  )
}

load_rdata <- function(path) {
  env    <- new.env(parent = emptyenv())
  loaded <- load(path, envir = env)

  wanted <- Sys.getenv("MODEL_OBJECT", "")
  if (nzchar(wanted)) {
    if (!wanted %in% loaded) {
      stop(sprintf(
        "MODEL_OBJECT='%s' is not in %s (contains: %s)",
        wanted, basename(path), paste(loaded, collapse = ", ")
      ))
    }
    return(get(wanted, envir = env))
  }

  if (length(loaded) == 1L) return(get(loaded, envir = env))

  stop(sprintf(
    "%s contains %d objects (%s) - set MODEL_OBJECT to pick one",
    basename(path), length(loaded), paste(loaded, collapse = ", ")
  ))
}

load_vetiver <- function(path) {
  dir <- if (dir.exists(path)) path else dirname(path)
  with_package("vetiver", function() {
    with_package("pins", function() {
      board <- pins::board_folder(dir)
      name  <- Sys.getenv("MODEL_OBJECT", "")
      pins  <- pins::pin_list(board)
      if (!nzchar(name)) {
        if (length(pins) != 1L) {
          stop(sprintf(
            "vetiver board at %s holds %d pins (%s) - set MODEL_OBJECT to pick one",
            dir, length(pins), paste(pins, collapse = ", ")
          ))
        }
        name <- pins[[1L]]
      }
      vetiver::vetiver_pin_read(board, name)
    })
  })
}

with_package <- function(pkg, fn) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf(
      paste0(
        "this model needs the '%s' package, which is not in this image. ",
        "Either rebuild with --build-arg PKG_PROFILE=full, or ship an renv.lock ",
        "alongside the model so it is restored at startup."
      ),
      pkg
    ))
  }
  fn()
}

CLASS_PACKAGE_HINTS <- c(
  train         = "caret",
  workflow      = "workflows",
  model_fit     = "parsnip",
  recipe        = "recipes",
  vetiver_model = "vetiver",
  xgb.Booster   = "xgboost",
  svm           = "e1071",
  naiveBayes    = "e1071",
  lda           = "MASS",
  qda           = "MASS",
  multinom      = "nnet",
  lognet        = "glmnet",
  elnet         = "glmnet",
  multnet       = "glmnet",
  fishnet       = "glmnet",
  coxnet        = "glmnet",
  cv.glmnet     = "glmnet"
)

has_predict_method <- function(classes) {
  any(vapply(
    classes,
    function(cls) !is.null(utils::getS3method("predict", cls, optional = TRUE)),
    logical(1)
  ))
}

ensure_predict_method <- function(model) {
  classes <- class(model)
  if (has_predict_method(classes)) return(TRUE)

  explicit <- strsplit(Sys.getenv("MODEL_PACKAGES", ""), "[,[:space:]]+")[[1L]]
  candidates <- unique(c(
    explicit,
    unname(CLASS_PACKAGE_HINTS[classes]),
    classes,
    sub("\\..*$", "", classes)
  ))
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]

  for (pkg in candidates) {
    loaded <- suppressWarnings(suppressPackageStartupMessages(
      requireNamespace(pkg, quietly = TRUE)
    ))
    if (loaded) message(sprintf("[kserveR] loaded namespace '%s' for predict dispatch", pkg))
  }

  has_predict_method(classes)
}

prepare_newdata <- function(model, df) {
  if (inherits(model, c("xgb.Booster", "glmnet", "cv.glmnet"))) {
    return(as.matrix(df))
  }
  df
}
