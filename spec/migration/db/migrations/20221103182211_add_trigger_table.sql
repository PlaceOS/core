-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Trigger
CREATE TABLE IF NOT EXISTS "trigger"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   actions JSONB NOT NULL,
   conditions JSONB NOT NULL,
   debounce_period INTEGER NOT NULL,
   important BOOLEAN NOT NULL,
   enable_webhook BOOLEAN NOT NULL,
   supported_methods TEXT[] NOT NULL,
   control_system_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS trigger_control_system_id_index ON "trigger" USING BTREE (control_system_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS "trigger"