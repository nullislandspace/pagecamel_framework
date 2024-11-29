ALTER TABLE pagecamel.users ADD COLUMN is_internal boolean NOT NULL DEFAULT false;

UPDATE pagecamel.users SET is_internal = true WHERE username IN('cashbook', 'admin', 'developer', 'giczi', 'kaiser', 'baron', 'hirt', 'guest');

ALTER TABLE pagecamel.permissiongroups ADD COLUMN is_internal boolean NOT NULL DEFAULT false;
UPDATE pagecamel.permissiongroups SET is_internal = true WHERE groupname IN ('Developer', 'Guest');

ALTER TABLE pagecamel.users_organisation ADD COLUMN is_internal boolean NOT NULL DEFAULT false;
UPDATE pagecamel.users_organisation SET is_internal = true WHERE organisation_name IN ('Developer', 'Calyx_Automation', 'Guest');

ALTER TABLE pagecamel.users ADD COLUMN applogin_usercode text NOT NULL DEFAULT ''
