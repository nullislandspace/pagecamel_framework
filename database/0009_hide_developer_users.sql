ALTER TABLE pagecamel.users ADD COLUMN is_internal boolean NOT NULL DEFAULT false;

UPDATE pagecamel.users SET is_internal = true WHERE username IN('cashbook', 'admin', 'developer', 'giczi', 'kaiser', 'baron', 'hirt');

ALTER TABLE pagecamel.permissiongroups ADD COLUMN is_internal boolean NOT NULL DEFAULT false;
UPDATE pagecamel.permissiongroups SET is_internal = true WHERE groupname IN ('Developer');

