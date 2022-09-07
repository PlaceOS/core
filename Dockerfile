# One of `core` | `edge`
ARG TARGET=core
ARG CRYSTAL_VERSION=1.5.0
FROM alpine:3.16 as build
WORKDIR /app

# Set the commit via a build arg
ARG PLACE_COMMIT="DEV"
# Set the platform version via a build arg
ARG PLACE_VERSION="DEV"

# Create a non-privileged user, defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

# Add trusted CAs for communicating with external services
RUN apk add --no-cache \
        ca-certificates \
        curl \
    && \
    update-ca-certificates

# Add crystal lang
# can look up packages here: https://pkgs.alpinelinux.org/packages?name=crystal
RUN apk add \
  --update \
  --no-cache \
  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
    crystal \
    shards \
    yaml-dev \
    yaml-static \
    libxml2-dev \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    tzdata

# Install the latest version of LibSSH2, ping
RUN apk add --update --no-cache \
    'apk-tools>=2.10.8-r0' \
    'expat>=2.2.10-r1' \
    iputils \
    'libcurl>=7.79.1-r0' \
    libssh2-static \
    git

# Install shards for caching
COPY shard.yml shard.yml
COPY shard.override.yml shard.override.yml
COPY shard.lock shard.lock

RUN shards install --production --ignore-crystal-version --skip-postinstall --skip-executables

# Add src
COPY ./src /app/src

# Build the required target
ENV UNAME_AT_COMPILE_TIME=true
RUN PLACE_VERSION=$PLACE_VERSION \
    PLACE_COMMIT=$PLACE_COMMIT \
    shards build "${TARGET}" \
      --error-trace \
      --production \
      --release \
      --static

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Create binary directories
RUN mkdir -p repositories bin/drivers
RUN chown appuser -R /app

###############################################################################

FROM scratch as minimal
WORKDIR /
ENV PATH=$PATH:/

# Copy the user information over
COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

# These are required for communicating with external services
COPY --from=build /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Service binary
COPY --from=build /app/bin /bin

USER appuser:appuser

###############################################################################

FROM minimal as edge
CMD ["/bin/edge"]

###############################################################################

# FIXME: core currently has a number of dependandancies on the runtime for
# retreiving repositories and compiling drivers. When the migrates into an
# external service, this can base from `minimal` instead for cleaner images.
FROM build as core

COPY --from=build /app/bin /bin

WORKDIR /app

USER appuser:appuser

EXPOSE 3000
VOLUME ["/app/repositories/", "/app/bin/drivers/"]
HEALTHCHECK CMD /bin/core --curl http://localhost:3000/api/core/v1
CMD ["/bin/core", "-b", "0.0.0.0", "-p", "3000"]

###############################################################################

# hadolint ignore=DL3006
FROM ${TARGET}
