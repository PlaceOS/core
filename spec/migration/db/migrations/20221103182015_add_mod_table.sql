-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Module
CREATE TABLE IF NOT EXISTS "mod"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   ip TEXT NOT NULL,
   port INTEGER NOT NULL,
   tls BOOLEAN NOT NULL,
   udp BOOLEAN NOT NULL,
   makebreak BOOLEAN NOT NULL,
   uri TEXT NOT NULL,
   name TEXT NOT NULL,
   custom_name TEXT,
   role INTEGER NOT NULL,
   connected BOOLEAN NOT NULL,
   running BOOLEAN NOT NULL,
   notes TEXT NOT NULL,
   ignore_connected BOOLEAN NOT NULL,
   ignore_startstop BOOLEAN NOT NULL,
   control_system_id TEXT,
   driver_id TEXT NOT NULL,
   edge_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS mod_control_system_id_index ON "mod" USING BTREE (control_system_id);
CREATE INDEX IF NOT EXISTS mod_driver_id_index ON "mod" USING BTREE (driver_id);
CREATE INDEX IF NOT EXISTS mod_edge_id_index ON "mod" USING BTREE (edge_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "mod"