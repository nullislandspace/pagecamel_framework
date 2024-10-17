ALTER TABLE users DROP COLUMN password_can_expire;
ALTER TABLE users DROP COLUMN next_password_change;
ALTER TABLE users ADD COLUMN force_password_change boolean NOT NULL DEFAULT false;

