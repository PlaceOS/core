FROM crystallang/crystal:0.33.0-alpine
ADD . /src
WORKDIR /src

# Install the latest version of LibSSH2
RUN apk update
RUN apk add libssh2 libssh2-dev

# Build App
RUN mkdir -p /src/bin/drivers
RUN shards build --error-trace --production

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/api/core/v1
CMD ["/src/bin/engine-core", "-b", "0.0.0.0", "-p", "3000"]
