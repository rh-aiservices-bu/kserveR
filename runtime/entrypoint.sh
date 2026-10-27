#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/mnt/models}"
RUNTIME_HOME="${RUNTIME_HOME:-/opt/kserve-r}"

mkdir -p "${R_LIBS_USER:-/tmp/R-libs}" "${RENV_PATHS_CACHE:-/tmp/renv-cache}"

echo "[kserveR] model dir : ${MODEL_DIR}"
echo "[kserveR] uid/gid   : $(id -u):$(id -g)"

if [ -f "${MODEL_DIR}/renv.lock" ]; then
  echo "[kserveR] renv.lock found, restoring into ${R_LIBS_USER:-/tmp/R-libs}"
  Rscript -e '
    lock <- file.path(Sys.getenv("MODEL_DIR", "/mnt/models"), "renv.lock")
    lib  <- Sys.getenv("R_LIBS_USER", "/tmp/R-libs")
    renv::restore(lockfile = lock, library = lib, prompt = FALSE)
  '
  echo "[kserveR] renv restore complete"
fi

exec Rscript "${RUNTIME_HOME}/server.R"
