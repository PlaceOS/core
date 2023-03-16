-- +micrate Up
-- SQL in section 'Up' is executed when this migration is applied

ALTER TABLE "sys" ADD COLUMN public BOOLEAN NOT NULL DEFAULT false;

-- +micrate Down
-- SQL section 'Down' is executed when this migration is rolled back

ALTER TABLE "sys" DROP COLUMN public;
