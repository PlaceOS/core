FROM crystallang/crystal:0.34.0-alpine

WORKDIR /app

# Install the latest version of LibSSH2
RUN apk add --no-cache libssh2 libssh2-dev

COPY shard.yml /app
COPY shard.lock /app
RUN shards install --production

# Add source last for efficient caching
COPY src /app/src

# Build App
RUN mkdir -p /app/bin/drivers
RUN crystal build --error-trace --release --debug -o bin/core src/app.cr

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/api/core/v1
CMD ["/app/bin/core", "-b", "0.0.0.0", "-p", "3000"]
