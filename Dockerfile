FROM crystallang/crystal:0.31.1

WORKDIR /app

# Add
# - curl (necessary for scrypt install)
# - ping (not in base xenial image the crystal image is based off)
RUN apt-get update && \
    apt-get install --no-install-recommends -y curl=7.47.0-1ubuntu2.13 iputils-ping=3:20121221-5ubuntu2 && \
    rm -rf /var/lib/apt/lists/*

# Install shards for caching
COPY shard.yml shard.yml
RUN shards install --production

# Manually remake libscrypt, PostInstall fails inexplicably
RUN make -C lib/scrypt/ clean
RUN make -C lib/scrypt/

# Add src
COPY ./src /app/src

# Build application
RUN crystal build /app/src/app.cr -o engine-core --release --no-debug

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget --spider localhost:3000/
CMD ["/app/engine-core", "-b", "0.0.0.0", "-p", "3000"]
