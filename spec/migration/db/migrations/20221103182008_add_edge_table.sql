-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Edge
CREATE TABLE IF NOT EXISTS "edge"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   api_key_id TEXT NOT NULL,
   user_id TEXT NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS edge_api_key_id_index ON "edge" USING BTREE (api_key_id);
CREATE INDEX IF NOT EXISTS edge_name_index ON "edge" USING BTREE (name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "edge"