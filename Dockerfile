# One of `core` | `edge`
ARG TARGET=core
ARG CRYSTAL_VERSION=1.2.0

FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine as build

ARG TARGET
ARG PLACE_COMMIT="DEV"
ARG PLACE_VERSION="DEV"

WORKDIR /app

# Install the latest version of 
# - libSSH2
# - ping
RUN apk add --update --no-cache \
    'apk-tools>=2.10.8-r0' \
    'libcurl>=7.79.1-r0' \
    ca-certificates \
    iputils \
    libssh2-static \
    yaml-static

# Add trusted CAs for communicating with external services
RUN update-ca-certificates

# Create a non-privileged user
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

# Install dependencies
COPY shard.yml /app
COPY shard.override.yml /app
COPY shard.lock /app
RUN shards install --production --ignore-crystal-version

# Add source last for efficient caching
COPY src /app/src

# Build the required target
RUN UNAME_AT_COMPILE_TIME=true \
    PLACE_VERSION=${PLACE_VERSION} \
    PLACE_COMMIT=${PLACE_COMMIT} \
    shards build ${TARGET} --production --release --error-trace

RUN mkdir -p /app/bin/drivers
RUN chown appuser -R /app

# Extract target's dependencies (produces a smaller image than static compilation)
RUN ldd /app/bin/${TARGET} | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname dependencies%); cp % dependencies%;'

RUN ldd /bin/ping | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname ping-dependencies%); cp % ping-dependencies%;'

RUN ldd /bin/ping6 | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname ping-dependencies%); cp % ping-dependencies%;'

###############################################################################

FROM scratch as minimal

WORKDIR /

# These are required for communicating with external services
COPY --from=build /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Copy the user information over
COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

# These provide certificate chain validation where communicating with external services over TLS
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Service dependencies
COPY --from=build /app/dependencies /
# Service binary
COPY --from=build /app/bin /bin/${TARGET}

USER appuser:appuser

COPY --from=build /app/bin /bin/drivers

###############################################################################

FROM minimal as edge

CMD ["/bin/edge"]

###############################################################################

FROM minimal as core
ENV PATH=$PATH:/bin

# Include `ping`
COPY --from=build /app/ping-dependencies /
COPY --from=build /bin/ping /ping
COPY --from=build /bin/ping6 /ping6

EXPOSE 3000
VOLUME ["/app/repositories/", "/app/bin/drivers/"]
HEALTHCHECK CMD /bin/core --curl http://localhost:3000/api/core/v1
CMD ["/bin/core", "-b", "0.0.0.0", "-p", "3000"]

###############################################################################

# hadolint ignore=DL3006
FROM ${TARGET}
