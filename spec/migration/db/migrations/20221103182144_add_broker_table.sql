-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Broker
CREATE TABLE IF NOT EXISTS "broker"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   auth_type INTEGER NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   host TEXT NOT NULL,
   port INTEGER NOT NULL,
   tls BOOLEAN NOT NULL,
   username TEXT,
   password TEXT,
   certificate TEXT,
   secret TEXT NOT NULL,
   filters TEXT[] NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS broker_name_index ON "broker" USING BTREE (name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "broker"