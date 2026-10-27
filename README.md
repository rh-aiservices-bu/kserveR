# kserveR

A custom [KServe](https://kserve.github.io/website/) `ServingRuntime` for models
fitted in R, speaking the V2 Open Inference Protocol. Deploy an R model with the
same `InferenceService` YAML you would use for sklearn or XGBoost.


---

## Building the image

The image is UBI9 with R from EPEL9 (currently `R-core 4.6.1`). It is a two-stage
build: compilers and `-devel` headers live in the builder stage and do not ship.

**Build on an x86_64 RHEL host.** The target cluster is amd64, and building amd64
under QEMU on an arm64 Mac is slow enough to matter — painfully so if packages
compile from source.

```bash
git clone <this repo> && cd kserveR

podman build \
  --platform linux/amd64 \
  --build-arg PKG_PROFILE=full \
  -t quay.io/yourorg/kserve-r-runtime:0.1.0 \
  -f Containerfile .

podman push quay.io/yourorg/kserve-r-runtime:0.1.0
```

Build args:

| Arg | Default | Notes |
|---|---|---|
| `PKG_PROFILE` | `full` | `lean` drops caret/tidymodels and the extra formats |
| `PPM_REPO` | Posit Package Manager rhel9 | Point at an internal mirror in an air-gapped build |
| `UBI_IMAGE` | `ubi9/ubi:latest` | Pin to a digest for reproducible builds |

### Package binaries — check this on your first build

R packages come from Posit Package Manager's RHEL 9 repo. When PPM has a binary
built for the running R version, installing is just a download; when it does not,
PPM silently serves source instead and the build takes roughly an hour rather than
a couple of minutes.

**This is unresolved for EPEL9's R 4.6.1.** PPM keys binaries on R minor version and
4.6 is recent. The build log answers it definitively:

```
PPM binaries  : YES - installs are downloads
PPM binaries  : NO  - compiling from source, expect a slow build
```

If it says `NO`, either use `PKG_PROFILE=lean` or accept the slow build and cache
the image. Record the answer here once you know it.

### Running it locally

Fit the example model first, then run the image against it:

```bash
Rscript examples/iris-rf/train.R

podman run --rm -p 8080:8080 \
  -v "$PWD/examples/iris-rf:/mnt/models:z,ro" \
  -e MODEL_NAME=iris-rf \
  quay.io/yourorg/kserve-r-runtime:0.1.0

./tests/smoke.sh                             # in another shell
```

Add `--user 1000650000` to that `podman run` to reproduce how OpenShift will
actually start it: a random high UID in group 0 with no home directory. That is
where `HOME`-writing and permission bugs surface, so it is worth doing before
every release.

To run the server straight from the checkout without building anything:

```bash
MODEL_DIR=examples/iris-rf MODEL_NAME=iris-rf Rscript runtime/server.R
```

---

## The model directory

The storage-initializer copies `storageUri` into `/mnt/models`. Only the model file
is required.

```
/mnt/models/
  model.rds        the fitted model
  renv.lock        optional - packages restored at startup
  predict.R        optional - custom prediction hook
  schema.json      optional - overrides the inferred input schema
```

### Formats

Discovered automatically by extension, preferring `model.<ext>`: `.rds`, `.qs2`,
`.qs`, `.rda`/`.RData`, and xgboost's native `.ubj`/`.model`/`.xgb`. Point
`MODEL_FILE` at anything named differently.

`.RData` can hold several objects; if it does, set `MODEL_OBJECT` to name the one
to serve rather than letting the runtime guess. Vetiver/pins bundles are a
directory rather than a file, so they need `MODEL_FORMAT=vetiver`.

### Model types

Anything with a `predict()` method: `lm`, `glm`, randomForest, ranger, glmnet,
rpart, nnet, e1071, MASS, xgboost, caret `train`, and tidymodels
`workflow`/`model_fit`.

One subtlety worth knowing. `readRDS()` restores an object's class attribute but
loads nothing, and S3 dispatch resolves `predict.<class>` by searching *loaded*
namespaces — so a freshly-read model has no `predict` method visible and fails with
`no applicable method for 'predict'`. The runtime resolves this at startup by
loading the namespace that defines the method, mapping class to package where the
names differ (caret fits are class `train`, parsnip's are `model_fit`). If your
model's class maps to neither its own name nor a known package, set
`MODEL_PACKAGES=yourpkg`. A missing package is a startup crash, not a per-request
500.

---

## The V2 API

| Route | |
|---|---|
| `GET /v2/health/live` | liveness |
| `GET /v2/health/ready` | readiness — 200 once the model is loaded |
| `GET /v2` | server metadata |
| `GET /v2/models/<name>` | model metadata, inputs derived from the training schema |
| `GET /v2/models/<name>/ready` | |
| `POST /v2/models/<name>/infer` | inference |

The model name in the path is not validated. A `ServingRuntime` has no reliable way
to template the `InferenceService` name into its container, so strict matching
produces 404s that look like routing faults. Whatever you ask for is echoed back;
`MODEL_NAME` controls what metadata advertises.

### Request shapes

**Columnar** — one tensor per column, named for the column. The normal case:

```json
{"inputs": [
  {"name": "Sepal.Length", "shape": [2], "datatype": "FP64", "data": [5.1, 6.3]},
  {"name": "Species",      "shape": [2], "datatype": "BYTES", "data": ["setosa", "virginica"]}
]}
```

**Matrix** — a single 2-D tensor, for matrix-oriented models like xgboost and
glmnet. Column names come from the model's schema, so order matters:

```json
{"inputs": [{"name": "input", "shape": [2, 4], "datatype": "FP64",
             "data": [5.1, 3.5, 1.4, 0.2, 6.3, 3.3, 6.0, 2.5]}]}
```

A lone `[N,1]` tensor is treated as columnar, not as a one-feature matrix.

### Factor columns

A factor in R is an integer vector plus a `levels` attribute, and most `predict`
methods use the integer. `factor(c("b","a"))` numbers `b` as 1, while a training
factor with levels `c("a","b")` numbers it 2 — hand a model the former and it
predicts against the wrong category rather than erroring.

So the runtime recovers the training levels (from `model$xlevels`,
`model$forest$xlevels`, or `schema.json`) and rebuilds every known factor column
against them. Values never seen during training are rejected with a 400 naming the
column and the offending value, rather than becoming silent `NA`s.

---

## Extension points

### `predict.R`

Define `kserve_predict(model, newdata)` and it replaces the default `predict()`
call. This is where preprocessing, unusual predict signatures, and multi-output
responses belong.

```r
kserve_predict <- function(model, newdata) {
  list(
    predictions   = as.character(predict(model, newdata)),
    probabilities = predict(model, newdata, type = "prob")
  )
}
```

Return an atomic vector for one output, a matrix for `[N,K]`, a data frame for one
output per column, or a named list for full control.

### `schema.json`

Overrides what was inferred. Needed when a model exposes no predictor names but you
want to send matrix-shaped requests.

```json
{"inputs": [{"name": "grade", "datatype": "BYTES", "levels": ["low", "mid", "high"]}]}
```

### `renv.lock`

Restored into `R_LIBS_USER` at startup, before the model loads. The escape hatch for
packages the image does not bake in — at the cost of a slow cold start and egress
from the pod, which is why the common packages are baked in instead.

---

## Deploying on OpenShift AI

```bash
oc apply -f manifests/servingruntime.yaml
oc apply -f manifests/inferenceservice.yaml
```

Replace `quay.io/REPLACE_ME` and the `storageUri` first.

To make the runtime selectable in the dashboard's serving-runtime dropdown rather
than YAML-only, apply the Template into the applications namespace:

```bash
oc apply -n redhat-ods-applications -f manifests/servingruntime-template.yaml
```

The container must be named `kserve-container` — renaming it gives you a pod that
starts and an `InferenceService` that never goes Ready.

The `startupProbe` allows 10 minutes before the liveness probe takes over, because
an `renv.lock` restore can take minutes.

---

## Environment variables

| Variable | Default | |
|---|---|---|
| `MODEL_DIR` | `/mnt/models` | where the storage-initializer lands the model |
| `MODEL_FILE` | — | explicit path, overriding discovery |
| `MODEL_NAME` | `model` | name advertised in metadata |
| `MODEL_VERSION` | `1` | |
| `MODEL_FORMAT` | — | force a loader, e.g. `vetiver` |
| `MODEL_OBJECT` | — | which object to take from a multi-object `.RData` |
| `MODEL_PACKAGES` | — | namespaces to load for `predict` dispatch |
| `PREDICT_TYPE` | — | passed to `predict(..., type=)`, e.g. `prob` |
| `SERVER_PORT` | `8080` | |

---

## Testing

```bash
# 52 unit tests, no container needed
Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'

# end-to-end against a running server
./tests/smoke.sh [base-url] [model-name] [example-dir]
```

The smoke test's last check diffs served predictions against what R produced
locally at training time. A 200 with a well-formed body only proves the HTTP layer
works; the diff is what proves tensor translation and factor handling are correct.

---

## Limitations

- **Single-threaded.** Plumber sits on `httpuv`, which handles one request at a
  time. Scale with replicas, not in-process workers.
- **No `/metrics` endpoint yet.** The OpenShift AI monitoring stack would scrape it
  if it existed; the ServingRuntime deliberately does not advertise Prometheus
  annotations for an endpoint that is not there.
- **Single model per pod.** `multiModel: false`; ModelMesh is out of scope.
- **No GPU support.**
