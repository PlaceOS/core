-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::Statistics
CREATE TABLE IF NOT EXISTS "stats"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   modules_disconnected INTEGER NOT NULL,
   triggers_active INTEGER NOT NULL,
   websocket_connections INTEGER NOT NULL,
   fixed_connections INTEGER NOT NULL,
   core_nodes_online INTEGER NOT NULL,
   ttl BIGINT NOT NULL,
   id TEXT NOT NULL PRIMARY KEY
);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
DROP TABLE IF EXISTS "stats"