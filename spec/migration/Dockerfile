FROM placeos/crystal:latest

WORKDIR /app

COPY . /app

RUN git clone https://github.com/PlaceOS/models
RUN mv ./models/migration/db ./db

ENV PATH /app/bin:$PATH

RUN shards build

ENTRYPOINT [ "/app/run.sh" ]