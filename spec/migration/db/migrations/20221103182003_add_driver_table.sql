-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Driver
CREATE TABLE IF NOT EXISTS "driver"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   json_schema JSONB NOT NULL,
   default_uri TEXT,
   default_port INTEGER,
   role INTEGER NOT NULL,
   file_name TEXT NOT NULL,
   commit TEXT NOT NULL,
   compilation_output TEXT,
   module_name TEXT NOT NULL,
   ignore_connected BOOLEAN NOT NULL,
   repository_id TEXT NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS driver_repository_id_index ON "driver" USING BTREE (repository_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "driver"