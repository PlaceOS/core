-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Metadata
CREATE TABLE IF NOT EXISTS "metadata"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   modified_by_id TEXT,
   metadata_id TEXT,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   details JSONB NOT NULL,
   editors TEXT[] NOT NULL,
   parent_id TEXT,
   schema_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS metadata_metadata_id_index ON "metadata" USING BTREE (metadata_id);
CREATE INDEX IF NOT EXISTS metadata_parent_id_index ON "metadata" USING BTREE (parent_id);
CREATE INDEX IF NOT EXISTS metadata_name_index ON "metadata" USING BTREE (name);
CREATE INDEX IF NOT EXISTS metadata_schema_id_index ON "metadata" USING BTREE (schema_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "metadata"