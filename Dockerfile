FROM crystallang/crystal:0.35.1-alpine as base

# Set the commit through a build arg
ARG PLACE_COMMIT="DEV"
ARG TARGET="core"

WORKDIR /app

# Install the latest version of LibSSH2, ping
RUN apk add --no-cache libssh2 libssh2-dev iputils

# Add trusted CAs for communicating with external services
RUN apk update && apk add --no-cache ca-certificates tzdata && update-ca-certificates

# Create a non-privileged user
# defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735RUN
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

COPY shard.yml /app
COPY shard.lock /app
RUN PLACE_COMMIT=$PLACE_COMMIT \
    shards install --production

# Add source last for efficient caching
COPY src /app/src

# Core
###############################################################################

FROM base AS build-core

# Build Core
RUN UNAME_AT_COMPILE_TIME=true \
    PLACE_COMMIT=$PLACE_COMMIT \
    crystal build --error-trace --debug -o bin/core src/core-app.cr
    # crystal build --error-trace --release --debug -o bin/core src/core-app.cr

# Edge
###############################################################################

FROM base AS edge-base

# Build Edge
RUN UNAME_AT_COMPILE_TIME=true \
    PLACE_COMMIT=$PLACE_COMMIT \
    crystal build --error-trace /app/src/edge-app.cr -o /app/edge
    # crystal build --release --error-trace /app/src/edge-app.cr -o /app/edge

# Extract dependencies
RUN ldd /app/edge | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

FROM scratch as build-edge

WORKDIR /
ENV PATH=$PATH:/
COPY --from=edge-base /app/deps /
COPY --from=edge-base /app/edge /edge

# These are required for communicating with external services
COPY --from=edge-base /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=edge-base /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# This is required for Timezone support
COPY --from=edge-base /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Copy the user information over
COPY --from=edge-base /etc/passwd /etc/passwd
COPY --from=edge-base /etc/group /etc/group

# Common environment configuration
###############################################################################

FROM build-${TARGET} AS common

# Create a non-privileged user
# defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# These provide certificate chain validation where communicating with external services over TLS
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Use an unprivileged user.
USER appuser:appuser

# Entrypoints and custom environment
###############################################################################

FROM common as edge

CMD ["/edge"]

FROM common as core

# Set up driver directory
RUN mkdir -p /app/bin/drivers

# Create binary directories
RUN mkdir -p /app/repositories /app/bin/drivers

RUN chown appuser -R /app

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/api/core/v1
CMD ["/app/bin/core", "-b", "0.0.0.0", "-p", "3000"]

# Final build artefact
###############################################################################

FROM ${TARGET} as final
