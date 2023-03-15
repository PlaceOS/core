-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Zone
CREATE TABLE IF NOT EXISTS "zone"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   tags TEXT[] NOT NULL,
   location TEXT,
   display_name TEXT,
   code TEXT,
   type TEXT,
   count INTEGER NOT NULL,
   capacity INTEGER NOT NULL,
   map_id TEXT,
   timezone TEXT,
   triggers TEXT[] NOT NULL,
   images TEXT[] NOT NULL,
   parent_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS zone_parent_id_index ON "zone" USING BTREE (parent_id);
CREATE INDEX IF NOT EXISTS zone_name_index ON "zone" USING BTREE (name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "zone"