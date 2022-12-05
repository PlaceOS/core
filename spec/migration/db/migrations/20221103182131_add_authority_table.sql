-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Authority
CREATE TABLE IF NOT EXISTS "authority"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   domain TEXT NOT NULL,
   login_url TEXT NOT NULL,
   logout_url TEXT NOT NULL,
   internals JSONB NOT NULL,
   config JSONB NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS authority_domain_index ON "authority" USING BTREE (domain);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "authority"