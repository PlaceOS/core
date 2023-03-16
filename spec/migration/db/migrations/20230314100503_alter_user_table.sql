-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

alter table "user" alter COLUMN nickname drop NOT NULL;
alter table "user" alter COLUMN phone drop NOT NULL;
alter table "user" alter COLUMN country drop NOT NULL;
alter table "user" alter COLUMN image drop NOT NULL;
alter table "user" alter COLUMN ui_theme drop NOT NULL;
alter table "user" alter COLUMN misc drop NOT NULL;

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back
alter table "user" alter COLUMN nickname set NOT NULL;
alter table "user" alter COLUMN phone set NOT NULL;
alter table "user" alter COLUMN country set NOT NULL;
alter table "user" alter COLUMN image set NOT NULL;
alter table "user" alter COLUMN ui_theme set NOT NULL;
alter table "user" alter COLUMN misc set NOT NULL;