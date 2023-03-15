-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::ApiKey
CREATE TABLE IF NOT EXISTS "api_key"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   scopes JSONB NOT NULL,
   permissions INTEGER,
   secret TEXT NOT NULL,
   user_id TEXT,
   authority_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS api_key_user_id_index ON "api_key" USING BTREE (user_id);
CREATE INDEX IF NOT EXISTS api_key_authority_id_index ON "api_key" USING BTREE (authority_id);
CREATE INDEX IF NOT EXISTS api_key_name_index ON "api_key" USING BTREE (name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "api_key"