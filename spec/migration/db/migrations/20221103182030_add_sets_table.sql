-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Settings
CREATE TABLE IF NOT EXISTS "sets"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   modified_by_id TEXT,
   settings_id TEXT,
   encryption_level INTEGER NOT NULL,
   settings_string TEXT NOT NULL,
   keys TEXT[] NOT NULL,
   parent_type INTEGER NOT NULL,
   parent_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS sets_settings_id_index ON "sets" USING BTREE (settings_id);
CREATE INDEX IF NOT EXISTS sets_parent_id_index ON "sets" USING BTREE (parent_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "sets"