# Dependency builder image only: application code and model caches belong to pk-mono.
FROM rocker/r2u:22.04@sha256:b51f03901dd738476588240f0c37f359062c755b509213d4273b994e4923faea

LABEL org.opencontainers.image.source="https://github.com/PK-Friend/pk-docker" \
      org.opencontainers.image.description="R and numerical dependencies for building PK-Friend TDM"

ARG R_VERSION=4.6.1
ARG NLMIXR2_VERSION=7.0.1
ARG NLMIXR2EST_VERSION=7.1.0
ARG RXODE2LL_VERSION=2.0.16
ARG RXODE2_VERSION=5.1.7.1
ARG MRGSOLVE_VERSION=2.0.1
ARG NONCOMPART_VERSION=0.8.4

ENV DEBIAN_FRONTEND=noninteractive \
    TDM_R_VERSION=${R_VERSION} \
    NLMIXR2_VERSION=${NLMIXR2_VERSION} \
    NLMIXR2EST_VERSION=${NLMIXR2EST_VERSION} \
    RXODE2LL_VERSION=${RXODE2LL_VERSION} \
    RXODE2_VERSION=${RXODE2_VERSION} \
    MRGSOLVE_VERSION=${MRGSOLVE_VERSION} \
    NONCOMPART_VERSION=${NONCOMPART_VERSION}

COPY scripts/install-apt-packages-with-retries.sh /usr/local/bin/install-apt-packages-with-retries

# Keep the toolchain: pk-mono compiles its own models using this image.
# RCurl's source install requires curl-config from libcurl4-openssl-dev.
RUN bash /usr/local/bin/install-apt-packages-with-retries --upgrade \
      locales r-base-core r-base r-base-dev r-recommended \
      build-essential gfortran \
      libcurl4-openssl-dev libssl-dev libxml2-dev \
      r-cran-jsonlite r-cran-tidyverse r-cran-plumber \
      r-cran-logger r-cran-tictoc r-cran-remotes \
      r-cran-rcpp r-cran-rcpparmadillo r-cran-rcppeigen \
      r-cran-rcppparallel r-cran-bh && \
    Rscript --vanilla -e 'stopifnot(as.character(getRversion()) == Sys.getenv("TDM_R_VERSION"))' && \
    apt-mark hold r-base-core r-base r-recommended && \
    for pkg in r-cran-symengine r-cran-stanheaders r-cran-dparser \
               r-cran-lotri r-cran-qs2 r-cran-mirai r-cran-precisesums \
               r-cran-rcpptrust r-cran-n1qn1 r-cran-lbfgsb3c; do \
      if apt-cache show "$pkg" >/dev/null 2>&1; then \
        apt-get install -y --no-install-recommends "$pkg" || exit 1; \
      fi; \
    done && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    rm -f /usr/local/bin/install-apt-packages-with-retries

RUN sed -i 's/# ko_KR.UTF-8 UTF-8/ko_KR.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen ko_KR.UTF-8 && \
    update-locale LANG=ko_KR.UTF-8
ENV LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8

# Only the numerical engines are pinned. Supporting CRAN/APT dependencies may
# change when publishing a new image; record the complete installed inventory.
COPY scripts/install-numerical-packages.sh scripts/numerical-packages.R /tmp/tdm-base-install/
RUN bash /tmp/tdm-base-install/install-numerical-packages.sh && \
    dpkg-query -W -f='${Package}\t${Version}\n' > /usr/local/share/tdm-build-base/DPKG_PACKAGES.tsv && \
    rm -rf /tmp/tdm-base-install
