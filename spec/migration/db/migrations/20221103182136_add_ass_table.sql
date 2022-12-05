-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::AssetInstance
CREATE TABLE IF NOT EXISTS "ass"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   tracking INTEGER NOT NULL,
   approval BOOLEAN NOT NULL,
   asset_id TEXT,
   requester_id TEXT,
   zone_id TEXT,
   usage_start TIMESTAMPTZ NOT NULL,
   usage_end TIMESTAMPTZ NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS ass_asset_id_index ON "ass" USING BTREE (asset_id);
CREATE INDEX IF NOT EXISTS ass_zone_id_index ON "ass" USING BTREE (zone_id);
CREATE INDEX IF NOT EXISTS ass_requester_id_index ON "ass" USING BTREE (requester_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "ass"