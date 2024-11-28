ALTER TABLE pagecamel.users ADD COLUMN is_internal boolean NOT NULL DEFAULT false;

UPDATE pagecamel.users SET is_internal = true WHERE username IN('cashbook', 'admin', 'developer', 'giczi', 'kaiser', 'baron', 'hirt');

ALTER TABLE pagecamel.permissiongroups ADD COLUMN is_internal boolean NOT NULL DEFAULT false;
UPDATE pagecamel.permissiongroups SET is_internal = true WHERE groupname IN ('Developer');

ALTER TABLE pagecamel.users_organisation ADD COLUMN is_internal boolean NOT NULL DEFAULT false;
UPDATE pagecamel.users_organisation SET is_internal = true WHERE organisation_name IN ('Developer', 'Calyx_Automation');

