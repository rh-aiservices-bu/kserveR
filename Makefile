REGISTRY    ?= quay.io/REPLACE_ME
IMAGE       ?= $(REGISTRY)/kserve-r-runtime
TAG         ?= 0.1.0
PKG_PROFILE ?= full
PLATFORM    ?= linux/amd64
CONTAINER   ?= podman
EXAMPLE     ?= examples/iris-rf
PORT        ?= 8080

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ----------------------------------------------------------------- build ----

.PHONY: build
build: ## Build the runtime image for $(PLATFORM)
	$(CONTAINER) build \
	  --platform $(PLATFORM) \
	  --build-arg PKG_PROFILE=$(PKG_PROFILE) \
	  -t $(IMAGE):$(TAG) \
	  -f Containerfile .

.PHONY: build-lean
build-lean: ## Build without caret/tidymodels/extra formats (much faster)
	$(MAKE) build PKG_PROFILE=lean TAG=$(TAG)-lean

.PHONY: push
push: ## Push the image
	$(CONTAINER) push $(IMAGE):$(TAG)

# ------------------------------------------------------------------ run ----

.PHONY: example
example: ## Fit the example model (needs R + randomForest locally)
	Rscript $(EXAMPLE)/train.R

.PHONY: run
run: ## Run the image locally against $(EXAMPLE)
	$(CONTAINER) run --rm -p $(PORT):8080 \
	  -v $(PWD)/$(EXAMPLE):/mnt/models:z,ro \
	  -e MODEL_NAME=$(notdir $(EXAMPLE)) \
	  $(IMAGE):$(TAG)

.PHONY: run-asuser
run-asuser: ## Same, as a random high UID, the way OpenShift will run it
	$(CONTAINER) run --rm -p $(PORT):8080 --user 1000650000 \
	  -v $(PWD)/$(EXAMPLE):/mnt/models:z,ro \
	  -e MODEL_NAME=$(notdir $(EXAMPLE)) \
	  $(IMAGE):$(TAG)

.PHONY: serve-local
serve-local: ## Run the server straight from the checkout, no container
	MODEL_DIR=$(EXAMPLE) MODEL_NAME=$(notdir $(EXAMPLE)) SERVER_PORT=$(PORT) \
	  Rscript runtime/server.R

# ----------------------------------------------------------------- test ----

.PHONY: test
test: ## Unit tests (no container needed)
	Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'

.PHONY: smoke
smoke: ## End-to-end check against a running server
	./tests/smoke.sh http://localhost:$(PORT) $(notdir $(EXAMPLE)) $(EXAMPLE)

# --------------------------------------------------------------- deploy ----

.PHONY: deploy
deploy: ## Apply the ServingRuntime + InferenceService
	oc apply -f manifests/servingruntime.yaml
	oc apply -f manifests/inferenceservice.yaml

.PHONY: deploy-dashboard
deploy-dashboard: ## Register the runtime in the OpenShift AI dashboard
	oc apply -n redhat-ods-applications -f manifests/servingruntime-template.yaml
