CREATE TABLE pagecamel.backup_schedule (
    backup_name text NOT NULL,
    is_enabled boolean NOT NULL DEFAULT true,
    backup_directory text NOT NULL,
    backup_time time without time zone NOT NULL DEFAULT '00:00:00'::time without time zone,
    max_age_days bigint NOT NULL DEFAULT 14,
    external_backup_directory text NOT NULL DEFAULT '',
    external_max_age_days bigint NOT NULL DEFAULT 30,
    CONSTRAINT backup_schedule_pk PRIMARY KEY (backup_name)
)
WITH (
  OIDS=FALSE
);

INSERT INTO pagecamel.backup_schedule(backup_name, backup_time, backup_directory, max_age_days, external_backup_directory, external_max_age_days) VALUES
    ('BACKUP 1', '06:00', 'PC_DATABASE_BACKUPDIR', 14, 'PC_DATABASE_USBBACKUPDIR', 90);

INSERT INTO pagecamel.backup_schedule(backup_name, backup_time, backup_directory, max_age_days, external_backup_directory, external_max_age_days) VALUES
    ('BACKUP 2', '14:00', 'PC_DATABASE_BACKUPDIR', 14, 'PC_DATABASE_USBBACKUPDIR', 90);

INSERT INTO pagecamel.backup_schedule(backup_name, backup_time, backup_directory, max_age_days, external_backup_directory, external_max_age_days) VALUES
    ('BACKUP 3', '22:00', 'PC_DATABASE_BACKUPDIR', 14, 'PC_DATABASE_USBBACKUPDIR', 90);

DELETE FROM pagecamel.dirsync;


