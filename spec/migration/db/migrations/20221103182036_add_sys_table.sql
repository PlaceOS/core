-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::ControlSystem
CREATE TABLE IF NOT EXISTS "sys"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   features TEXT[] NOT NULL,
   email TEXT,
   bookable BOOLEAN NOT NULL,
   display_name TEXT,
   code TEXT,
   type TEXT,
   capacity INTEGER NOT NULL,
   map_id TEXT,
   images TEXT[] NOT NULL,
   timezone TEXT,
   support_url TEXT NOT NULL,
   version INTEGER NOT NULL,
   installed_ui_devices INTEGER NOT NULL,
   zones TEXT[] NOT NULL,
   modules TEXT[] NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS sys_email_index ON "sys" USING BTREE (email);
CREATE INDEX IF NOT EXISTS sys_name_index ON "sys" USING BTREE (name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "sys"