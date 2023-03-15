-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::SamlAuthentication
CREATE TABLE IF NOT EXISTS "adfs_strat"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   issuer TEXT NOT NULL,
   idp_sso_target_url_runtime_params JSONB NOT NULL,
   name_identifier_format TEXT NOT NULL,
   uid_attribute TEXT,
   assertion_consumer_service_url TEXT NOT NULL,
   idp_sso_target_url TEXT NOT NULL,
   idp_cert TEXT,
   idp_cert_fingerprint TEXT,
   attribute_service_name TEXT,
   attribute_statements JSONB NOT NULL,
   request_attributes JSONB NOT NULL,
   idp_slo_target_url TEXT,
   slo_default_relay_state TEXT,
   authority_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS adfs_strat_authority_id_index ON "adfs_strat" USING BTREE (authority_id);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "adfs_strat"