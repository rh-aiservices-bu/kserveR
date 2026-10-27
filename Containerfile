ARG UBI_IMAGE=registry.access.redhat.com/ubi9/ubi:latest
ARG R_LIB=/opt/kserve-r/library
ARG RUNTIME_HOME=/opt/kserve-r

# ------------------------------------------------------------------ builder ---
FROM ${UBI_IMAGE} AS builder

ARG R_LIB
ARG PKG_PROFILE=full
ARG CRAN_REPO=https://cloud.r-project.org

# R-core-devel needs flexiblas-devel and libtirpc-devel, which live in CodeReady
# Builder. The glob matches CRB whether it comes from UBI's own repo definition
# (ubi-9-codeready-builder-rpms) or a subscribed host's
# (codeready-builder-for-rhel-9-x86_64-rpms), and is silently ignored if neither
# is present -- unlike an exact --enablerepo name, which errors.
RUN dnf install -y --nodocs --setopt=install_weak_deps=False \
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
 && dnf install -y --nodocs --setopt=install_weak_deps=False \
      --enablerepo="*codeready*" --enablerepo="*crb*" \
      R-core R-core-devel \
      flexiblas-devel libtirpc-devel \
      gcc gcc-c++ gcc-gfortran make \
      openblas-devel \
      openssl-devel libcurl-devel libxml2-devel \
      zlib-devel bzip2-devel xz-devel pcre2-devel libicu-devel \
 && dnf clean all && rm -rf /var/cache/dnf

COPY runtime/install-packages.R /tmp/install-packages.R
RUN mkdir -p "${R_LIB}" \
 && Rscript /tmp/install-packages.R "${PKG_PROFILE}" "${R_LIB}" "${CRAN_REPO}"

# ------------------------------------------------------------------ runtime ---
FROM ${UBI_IMAGE} AS runtime

ARG R_LIB
ARG RUNTIME_HOME

LABEL org.opencontainers.image.title="kserveR" \
      org.opencontainers.image.description="KServe ServingRuntime for R models (V2 Open Inference Protocol)" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.authors="Sara Banderby <abanderb@redhat.com>" \
      org.opencontainers.image.licenses="Apache-2.0"

LABEL version="0.1.0"
LABEL maintainer="Sara Banderby <abanderb@redhat.com>"

RUN dnf install -y --nodocs --setopt=install_weak_deps=False \
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
 && dnf install -y --nodocs --setopt=install_weak_deps=False \
      R-core \
      openblas-serial libgomp \
      openssl-libs libcurl libxml2 \
      zlib bzip2-libs xz-libs pcre2 libicu \
 && dnf clean all && rm -rf /var/cache/dnf

COPY --from=builder ${R_LIB} ${R_LIB}
COPY runtime/ ${RUNTIME_HOME}/

ENV R_LIBS_SITE=${R_LIB} \
    RUNTIME_HOME=${RUNTIME_HOME} \
    MODEL_DIR=/mnt/models \
    SERVER_HOST=0.0.0.0 \
    SERVER_PORT=8080

ENV HOME=/tmp \
    RENV_PATHS_CACHE=/tmp/renv-cache \
    R_LIBS_USER=/tmp/R-libs

RUN chmod +x ${RUNTIME_HOME}/entrypoint.sh \
 && chgrp -R 0 ${RUNTIME_HOME} \
 && chmod -R g=u ${RUNTIME_HOME}

EXPOSE 8080
USER 1001

ENTRYPOINT ["/opt/kserve-r/entrypoint.sh"]
