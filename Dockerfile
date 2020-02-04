FROM crystallang/crystal:0.32.1

WORKDIR /app

# Add
# - ping (not in base xenial image the crystal image is based off)
# - curl
RUN apt-get update && \
    apt-get install --no-install-recommends -y iputils-ping curl && \
    rm -rf /var/lib/apt/lists/*

# Install the latest version of LibSSH2
RUN curl -sLO https://launchpad.net/ubuntu/+source/libgpg-error/1.32-1/+build/15118612/+files/libgpg-error0_1.32-1_amd64.deb && dpkg -i libgpg-error0_1.32-1_amd64.deb
RUN curl -sLO https://launchpad.net/ubuntu/+source/libgcrypt20/1.8.3-1ubuntu1/+build/15106861/+files/libgcrypt20_1.8.3-1ubuntu1_amd64.deb && dpkg -i libgcrypt20_1.8.3-1ubuntu1_amd64.deb
RUN curl -sLO https://launchpad.net/ubuntu/+source/libssh2/1.8.0-2/+build/15151524/+files/libssh2-1_1.8.0-2_amd64.deb && dpkg -i libssh2-1_1.8.0-2_amd64.deb
RUN curl -sLO https://launchpad.net/ubuntu/+source/libgpg-error/1.32-1/+build/15118612/+files/libgpg-error-dev_1.32-1_amd64.deb && dpkg -i libgpg-error-dev_1.32-1_amd64.deb
RUN curl -sLO https://launchpad.net/ubuntu/+source/libgcrypt20/1.8.3-1ubuntu1/+build/15106861/+files/libgcrypt20-dev_1.8.3-1ubuntu1_amd64.deb && dpkg -i libgcrypt20-dev_1.8.3-1ubuntu1_amd64.deb
RUN curl -sLO https://launchpad.net/ubuntu/+source/libssh2/1.8.0-2/+build/15151524/+files/libssh2-1-dev_1.8.0-2_amd64.deb && dpkg -i libssh2-1-dev_1.8.0-2_amd64.deb
RUN rm -rf ./*.deb

# Install shards for caching
COPY shard.yml shard.yml
COPY shard.lock shard.lock

RUN shards install --production

# Add src
COPY ./src /app/src

RUN mkdir -p /app/bin/drivers

# Build application
RUN crystal build --error-trace --release /app/src/app.cr -o engine-core

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD curl -I localhost:3000/api/core/v1
CMD ["/app/engine-core", "-b", "0.0.0.0", "-p", "3000"]
