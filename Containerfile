FROM rocker/r-ver:4.4.2

LABEL version="0.1.0"
LABEL maintainer="Sara Banderby <abanderb@redhat.com>"

RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev \
      libssl-dev \
      libxml2-dev \
      zlib1g-dev \
      libicu-dev \
      libgomp1 \
 && rm -rf /var/lib/apt/lists/*

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
