-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied
-- Table for model PlaceOS::Model::TriggerInstance
CREATE TABLE IF NOT EXISTS "trig"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   enabled BOOLEAN NOT NULL,
   triggered BOOLEAN NOT NULL,
   important BOOLEAN NOT NULL,
   exec_enabled BOOLEAN NOT NULL,
   webhook_secret TEXT NOT NULL,
   trigger_count INTEGER NOT NULL,
   control_system_id TEXT,
   trigger_id TEXT,
   zone_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS trig_control_system_id_index ON "trig" USING BTREE (control_system_id);
CREATE INDEX IF NOT EXISTS trig_trigger_id_index ON "trig" USING BTREE (trigger_id);
CREATE INDEX IF NOT EXISTS trig_zone_id_index ON "trig" USING BTREE (zone_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS "trig"