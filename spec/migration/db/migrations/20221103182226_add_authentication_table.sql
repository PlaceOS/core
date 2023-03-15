-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied
-- Table for model PlaceOS::Model::UserAuthLookup
CREATE TABLE IF NOT EXISTS "authentication"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   uid TEXT NOT NULL,
   provider TEXT NOT NULL,
   user_id TEXT,
   authority_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS authentication_user_id_index ON "authentication" USING BTREE (user_id);
CREATE INDEX IF NOT EXISTS authentication_authority_id_index ON "authentication" USING BTREE (authority_id);


-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS "authentication"