-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::OAuthAuthentication
CREATE TABLE IF NOT EXISTS "oauth_strat"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   client_id TEXT NOT NULL,
   client_secret TEXT NOT NULL,
   info_mappings JSONB NOT NULL,
   authorize_params JSONB NOT NULL,
   ensure_matching JSONB NOT NULL,
   site TEXT NOT NULL,
   authorize_url TEXT NOT NULL,
   token_method TEXT NOT NULL,
   auth_scheme TEXT NOT NULL,
   token_url TEXT NOT NULL,
   scope TEXT NOT NULL,
   raw_info_url TEXT,
   authority_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS oauth_strat_authority_id_index ON "oauth_strat" USING BTREE (authority_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "oauth_strat"