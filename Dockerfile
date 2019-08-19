FROM alpine:3.10 as builder

ARG SHARDS_VERSION="0.8.1"

RUN apk add --no-cache curl yaml-dev git build-base libressl-dev zlib-dev libxml2-dev upx

# Add crystal from edge
RUN apk add --no-cache crystal=0.30.1-r0 --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community

# Compile shards
RUN curl -L https://github.com/crystal-lang/shards/archive/v${SHARDS_VERSION}.tar.gz | tar -xz
RUN CRFLAGS=--release make -C ./shards-${SHARDS_VERSION}

# Install shards for caching
COPY shard.yml shard.yml
RUN ./shards-${SHARDS_VERSION}/bin/shards install --production

# Add src
COPY . ./

# Build application
RUN crystal build src/engine-core.cr --release --no-debug --static

# Compress static executable
RUN upx --best engine-core

# Build a minimal docker image
FROM alpine:3.10
COPY --from=builder engine-core engine-core

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget --spider localhost:3000/
CMD ["/engine-core", "-b", "0.0.0.0", "-p", "3000"]
