-- Rollback: users_add_column_bid

ALTER TABLE users DROP COLUMN IF EXISTS bid;
