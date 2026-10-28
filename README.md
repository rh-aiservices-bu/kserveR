# kserveR

A custom [KServe](https://kserve.github.io/website/) `ServingRuntime` for models
fitted in R, speaking the V2 Open Inference Protocol. Deploy an R model with the
same `InferenceService` YAML you would use for sklearn or XGBoost.

---

## 1. Build the image

```bash
podman build \
  --platform linux/amd64 \
  -t quay.io/yourorg/kserve-r-runtime:0.1.0 \
  -f Containerfile .

podman push quay.io/yourorg/kserve-r-runtime:0.1.0
```

The baked package list is the `PACKAGES` vector at the top of
`runtime/install-packages.R`.

---

## 2. Install the runtime

If you built the image yourself, replace the image url to your own one inside of `manifests/servingruntime-template.yaml`, then apply it once
for the whole cluster:

```bash
oc apply -n redhat-ods-applications -f manifests/servingruntime-template.yaml
```

The runtime is now available to every project and selectable in the OpenShift AI
dashboard. Per default its pulling from quay.io/sara_banderby/kserver:latest. 

---

## 3. Deploy a model

Two ways to get the model to the pod.

### Modelcar (OCI image)

The model travels as a container image. `examples/iris-rf/Containerfile`:

```containerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

COPY model.rds /models/model.rds

USER 1001
```

```bash
Rscript examples/iris-rf/train.R

podman build -t quay.io/yourorg/iris-rf-modelcar:0.1.0 \
  -f examples/iris-rf/Containerfile examples/iris-rf
podman push quay.io/yourorg/iris-rf-modelcar:0.1.0
```

The model has to exist under /models/ in the modelcar for the runtime to be able to access it.

```yaml
storageUri: oci://quay.io/yourorg/iris-rf-modelcar:0.1.0
```
You can also pull the test model container from quay.io/sara_banderby/kserver:test.

### Object storage

Point at a **prefix**, not a single file:

```
s3://your-bucket/models/iris-rf/
  model.rds
```

```yaml
storageUri: s3://your-bucket/models/iris-rf/
```

### The InferenceService

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-rf
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    labels:
      app.openshift.io/runtime: r
      app.openshift.io/runtime-version: "4.4.2"
    minReplicas: 1
    maxReplicas: 1
    model:
      modelFormat:
        name: R
      runtime: kserve-r-runtime
      storageUri: oci://quay.io/yourorg/iris-rf-modelcar:0.1.0 #change this to your own or use the example template
      env:
        - name: MODEL_NAME
          value: iris-rf
      resources:
        requests:
          cpu: "500m"
          memory: 1Gi
        limits:
          cpu: "2"
          memory: 4Gi
```

```bash
oc apply -f manifests/inferenceservice.yaml
oc get isvc iris-rf -w
```

---

## 4. Call it

```bash
curl -X POST http://iris-rf-predictor/v2/models/iris-rf/infer \
  -H 'Content-Type: application/json' \
  -d '{"inputs": [
        {"name":"Sepal.Length","shape":[2],"datatype":"FP64","data":[5.1,6.3]},
        {"name":"Sepal.Width","shape":[2],"datatype":"FP64","data":[3.5,3.3]},
        {"name":"Petal.Length","shape":[2],"datatype":"FP64","data":[1.4,6.0]},
        {"name":"Petal.Width","shape":[2],"datatype":"FP64","data":[0.2,2.5]}]}'
```

```json
{"model_name":"iris-rf","model_version":"1","outputs":[
  {"name":"predictions","datatype":"BYTES","shape":[2],
   "data":["setosa","virginica"]}]}
```

One tensor per column, named for the column. For matrix-oriented models such as
glmnet, send a single 2-D tensor named `input` with shape `[rows, cols]` instead
— column order then follows the model's schema.

Also available: `GET /v2/models/<name>` for metadata, `/v2/health/{live,ready}`.

---

## Optional files alongside the model

| File | Purpose |
|---|---|
| `renv.lock` | Packages not baked into the image. Restored at startup. |
| `predict.R` | Define `kserve_predict(model, newdata)` to replace the default `predict()` call — preprocessing, custom signatures, multi-output responses. |
| `schema.json` | Override the inferred input schema. Needed for matrix requests when the model exposes no predictor names. |

---

## Supported models

Any `.rds` whose object has a `predict()` method: `lm`, `glm`, randomForest,
ranger, glmnet, rpart, nnet, e1071, MASS, caret `train`, tidymodels
`workflow`/`model_fit`.

Also `.qs2`, `.qs` and `.rda`/`.RData`. Name the file `model.<ext>`.

Factor columns are rebuilt against the levels seen during training, so a request
sending levels in a different order still predicts correctly. Unseen levels are
rejected with a 400 rather than becoming silent `NA`s.

---

## Environment variables

Set these in the `ServingRuntime`, or per-model in the `InferenceService`.

| Variable | Default | |
|---|---|---|
| `MODEL_NAME` | `model` | name advertised in metadata |
| `MODEL_FILE` | — | explicit filename, overriding discovery |
| `MODEL_FORMAT` | — | force a loader instead of inferring it from the extension |
| `MODEL_OBJECT` | — | which object to take from a multi-object `.RData` |
| `MODEL_PACKAGES` | — | namespaces to load for `predict` dispatch |
| `PREDICT_TYPE` | — | passed to `predict(..., type=)`, e.g. `prob` |
| `MODEL_DIR` | `/mnt/models` | where the storage-initializer lands the model |
| `SERVER_PORT` | `8080` | |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no applicable method for 'predict'` | the package defining `predict.<class>` is missing — set `MODEL_PACKAGES=yourpkg` or ship an `renv.lock` |
| `no model found in /mnt/models` | `storageUri` points at the file; point it at the prefix |
| `found N candidate model files` | name one `model.rds` or set `MODEL_FILE` |
| `contains N objects` | multi-object `.RData` — set `MODEL_OBJECT` |
| Pod runs but `InferenceService` never Ready | the container must be named `kserve-container` |
| 400 `value(s) not seen during training` | a factor level absent when the model was fitted |
| Slow first start | `renv.lock` restore; `startupProbe` allows 10 minutes |

---

## Developing the runtime

```bash
Rscript examples/iris-rf/train.R                  # fit the example model
MODEL_DIR=examples/iris-rf MODEL_NAME=iris-rf \
  Rscript runtime/server.R                        

Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'
./tests/smoke.sh                                  # end-to-end
```

```bash
podman run --rm -p 8080:8080 --user 1000650000 \
  -v "$PWD/examples/iris-rf:/mnt/models:z,ro" \
  -e MODEL_NAME=iris-rf quay.io/yourorg/kserve-r-runtime:0.1.0
```

---

## Limitations

- **Single-threaded.** Plumber sits on `httpuv`; scale with replicas.
- **Not shown in the RHOAI Endpoint performance UI tab.** `/metrics` works and is
  scraped, but odh-model-controller only writes dashboard queries for runtimes it
  recognises.
- **Single model per pod.** `multiModel: false`.
- **No GPU support.**
