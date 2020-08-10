FROM crystallang/crystal:0.35.1-alpine

WORKDIR /app

# Install the latest version of LibSSH2
RUN apk add --no-cache libssh2 libssh2-dev

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
RUN shards install --production

# Add source last for efficient caching
COPY src /app/src

# Build App
RUN mkdir -p /app/bin/drivers
RUN crystal build --error-trace --release --debug -o bin/core src/app.cr

# These provide certificate chain validation where communicating with external services over TLS
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Use an unprivileged user.
RUN chown appuser:appuser -R /app
USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/api/core/v1
CMD ["/app/bin/core", "-b", "0.0.0.0", "-p", "3000"]
