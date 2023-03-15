-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

-- Table for model PlaceOS::Model::User
CREATE TABLE IF NOT EXISTS "user"(
     created_at TIMESTAMPTZ NOT NULL,
   updated_at TIMESTAMPTZ NOT NULL,
   name TEXT NOT NULL,
   nickname TEXT NOT NULL,
   email TEXT NOT NULL,
   phone TEXT NOT NULL,
   country TEXT NOT NULL,
   image TEXT NOT NULL,
   ui_theme TEXT NOT NULL,
   misc TEXT NOT NULL,
   login_name TEXT,
   staff_id TEXT,
   first_name TEXT,
   last_name TEXT,
   building TEXT,
   department TEXT,
   preferred_language TEXT,
   password_digest TEXT,
   email_digest TEXT,
   card_number TEXT,
   deleted BOOLEAN NOT NULL,
   groups TEXT[] NOT NULL,
   access_token TEXT,
   refresh_token TEXT,
   expires_at BIGINT,
   expires BOOLEAN NOT NULL,
   password TEXT,
   sys_admin BOOLEAN NOT NULL,
   support BOOLEAN NOT NULL,
   authority_id TEXT,
   id TEXT NOT NULL PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS user_authority_id_index ON "user" USING BTREE (authority_id);
CREATE INDEX IF NOT EXISTS user_email_digest_index ON "user" USING BTREE (email_digest);
CREATE INDEX IF NOT EXISTS user_login_name_index ON "user" USING BTREE (login_name);
CREATE INDEX IF NOT EXISTS user_staff_id_index ON "user" USING BTREE (staff_id);
CREATE INDEX IF NOT EXISTS user_sys_admin_index ON "user" USING BTREE (sys_admin);

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

DROP TABLE IF EXISTS "user"