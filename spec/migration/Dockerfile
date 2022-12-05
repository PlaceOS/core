FROM placeos/crystal:latest

WORKDIR /app

COPY . /app

ENV PATH /app/bin:$PATH

RUN shards build

ENTRYPOINT [ "/app/run.sh" ]