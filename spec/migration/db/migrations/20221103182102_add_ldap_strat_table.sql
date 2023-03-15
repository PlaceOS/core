-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::LdapAuthentication
CREATE TABLE IF NOT EXISTS "ldap_strat"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   port INTEGER NOT NULL,
   auth_method TEXT NOT NULL,
   uid TEXT NOT NULL,
   host TEXT NOT NULL,
   base TEXT NOT NULL,
   bind_dn TEXT,
   password TEXT,
   filter TEXT,
   authority_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS ldap_strat_authority_id_index ON "ldap_strat" USING BTREE (authority_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "ldap_strat"