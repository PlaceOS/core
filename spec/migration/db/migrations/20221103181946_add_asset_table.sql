-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Asset
CREATE TABLE IF NOT EXISTS "asset"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   category TEXT NOT NULL,
   description TEXT NOT NULL,
   purchase_date TIMESTAMPTZ NOT NULL,
   good_until_date TIMESTAMPTZ,
   identifier TEXT,
   brand TEXT NOT NULL,
   purchase_price INTEGER NOT NULL,
   images TEXT[] NOT NULL,
   invoice TEXT,
   quantity INTEGER NOT NULL,
   in_use INTEGER NOT NULL,
   other_data JSONB NOT NULL,
   parent_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS asset_parent_id_index ON "asset" USING BTREE (parent_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "asset"