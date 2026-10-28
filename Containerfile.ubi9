FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL version="0.1.0"
LABEL maintainer="Sara Banderby <abanderb@redhat.com>"

ARG R_VERSION=4.4.2
ARG CRAN_REPO=https://packagemanager.posit.co/cran/__linux__/rhel9/latest

ENV R_VERSION=${R_VERSION}

ENV TZ=UTC

RUN dnf -y upgrade --nodocs --disableplugin=subscription-manager \
 && dnf install -y --nodocs --disableplugin=subscription-manager \
      tzdata \
      https://cdn.rstudio.com/r/rhel-9/pkgs/R-${R_VERSION}-1-1.x86_64.rpm \
 && ln -sf /usr/share/zoneinfo/UTC /etc/localtime \
 && dnf clean all && rm -rf /var/cache/dnf \
 && ln -s /opt/R/${R_VERSION}/bin/R /usr/local/bin/R \
 && ln -s /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript

RUN mkdir -p /opt/kserve-r/library \
 && printf '%s\n' \
      'options(repos = c(CRAN = "'"${CRAN_REPO}"'"), download.file.method = "libcurl")' \
      'options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version$platform, R.version$arch, R.version$os)))' \
      '.libPaths(c("/opt/kserve-r/library", .libPaths()))' \
      >> /opt/R/${R_VERSION}/lib/R/etc/Rprofile.site

COPY runtime/install-packages.R /tmp/install-packages.R
RUN Rscript /tmp/install-packages.R

COPY runtime/ /opt/kserve-r/

ENV RUNTIME_HOME=/opt/kserve-r \
    MODEL_DIR=/mnt/models \
    SERVER_HOST=0.0.0.0 \
    SERVER_PORT=8080

ENV HOME=/tmp \
    RENV_PATHS_CACHE=/tmp/renv-cache \
    R_LIBS_USER=/tmp/R-libs

RUN chmod +x /opt/kserve-r/entrypoint.sh \
 && chgrp -R 0 /opt/kserve-r \
 && chmod -R g=u /opt/kserve-r

EXPOSE 8080
USER 1001

ENTRYPOINT ["/opt/kserve-r/entrypoint.sh"]
