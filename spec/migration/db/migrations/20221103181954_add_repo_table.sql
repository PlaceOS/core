-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Repository
CREATE TABLE IF NOT EXISTS "repo"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   description TEXT NOT NULL,
   folder_name TEXT NOT NULL,
   uri TEXT NOT NULL,
   commit_hash TEXT NOT NULL,
   branch TEXT NOT NULL,
   deployed_commit_hash TEXT,
   release BOOLEAN NOT NULL,
   username TEXT,
   password TEXT,
   repo_type INTEGER NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS repo_folder_name_index ON "repo" USING BTREE (folder_name);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "repo"