-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::JsonSchema
CREATE TABLE IF NOT EXISTS "json_schema"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   schema JSONB NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);


-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS "json_schema"