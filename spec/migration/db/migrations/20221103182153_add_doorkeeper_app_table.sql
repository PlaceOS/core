-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::DoorkeeperApplication
CREATE TABLE IF NOT EXISTS "doorkeeper_app"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   secret TEXT NOT NULL,
   scopes TEXT NOT NULL,
   owner_id TEXT NOT NULL,
   redirect_uri TEXT NOT NULL,
   skip_authorization BOOLEAN NOT NULL,
   confidential BOOLEAN NOT NULL,
   revoked_at TIMESTAMPTZ,
   uid TEXT NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS doorkeeper_app_uid_index ON "doorkeeper_app" USING BTREE (uid);
CREATE INDEX IF NOT EXISTS doorkeeper_app_redirect_uri_index ON "doorkeeper_app" USING BTREE (redirect_uri);
CREATE INDEX IF NOT EXISTS doorkeeper_app_name_index ON "doorkeeper_app" USING BTREE (name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS "doorkeeper_app"