# One of `core` | `edge`
ARG TARGET=core
ARG CRYSTAL_VERSION=1.3.2

FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine as build

ARG TARGET
ARG PLACE_COMMIT="DEV"
ARG PLACE_VERSION="DEV"

WORKDIR /app

RUN apk add \
  --update \
  --no-cache \
  --repository=http://dl-cdn.alpinelinux.org/alpine/v3.15/main \
    'git' \
    'expat'

RUN apk add --update --no-cache \
    'apk-tools>=2.10.8-r0' \
    ca-certificates \
    'expat>=2.2.10-r1' \
    iputils \
    'libcurl>=7.79.1-r0' \
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
    shards build ${TARGET} \
      --error-trace \
      --production \
      --release \
      --static

RUN mkdir -p /app/bin/drivers
RUN chown appuser -R /app

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Extract target's dependencies (produces a smaller image than static compilation)
# hadolint ignore=SC2016
RUN for binary in "/app/bin/${TARGET}" "/bin/ping" "/bin/ping6"; do \
        name="$(basename ${binary})"; \
        ldd "$binary" | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        sed -e "s/^/\/\$name/" | \
        xargs -I % sh -c 'mkdir -p $(dirname dependencies%); cp % dependencies%;'; \
    done

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
COPY --from=build /app/dependencies/${TARGET} /
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
COPY --from=build /app/dependencies/ping* /
COPY --from=build /bin/ping* /

EXPOSE 3000
VOLUME ["/app/repositories/", "/app/bin/drivers/"]
HEALTHCHECK CMD /bin/core --curl http://localhost:3000/api/core/v1
CMD ["/bin/core", "-b", "0.0.0.0", "-p", "3000"]

###############################################################################

# hadolint ignore=DL3006
FROM ${TARGET}
