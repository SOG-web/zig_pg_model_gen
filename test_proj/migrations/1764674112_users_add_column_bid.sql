-- Migration: users_add_column_bid
-- Table: users
-- Type: add_column

ALTER TABLE users ADD COLUMN bid TEXT;
