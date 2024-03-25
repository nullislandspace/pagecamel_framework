CREATE TABLE pagecamel.enum_pgbackuplog_types (
    enumvalue text NOT NULL,
    description text NOT NULL DEFAULT '',
    CONSTRAINT pos_enum_pgbackuplog_types_pk PRIMARY KEY (enumvalue)
)
WITH (
  OIDS=FALSE
);

INSERT INTO pagecamel.enum_pgbackuplog_types (enumvalue, description) VALUES ('BACKUP', 'pgbackup tool');
INSERT INTO pagecamel.enum_pgbackuplog_types (enumvalue, description) VALUES ('DIRSYNC', 'DirSync to external storage');
INSERT INTO pagecamel.enum_pgbackuplog_types (enumvalue, description) VALUES ('DIRCLEANER', 'DirCleaner');

CREATE TABLE pagecamel.pgbackup_log (
    logid bigserial,
    logtime timestamp without time zone NOT NULL DEFAULT now(),
    backuptype text NOT NULL,
    is_ok boolean NOT NULL,
    CONSTRAINT pagecamel_pgbackup_log_pk PRIMARY KEY (logid),
    CONSTRAINT pagecamel_pgbackup_log_fk1 FOREIGN KEY(backuptype) REFERENCES pagecamel.enum_pgbackuplog_types(enumvalue) ON UPDATE CASCADE ON DELETE CASCADE
)
WITH (
  OIDS=FALSE
);

INSERT INTO pagecamel.pgbackup_log(logid, logtime, backuptype, is_ok) VALUES (-3, '2000-01-01 00:00:00', 'DIRCLEANER', false);
INSERT INTO pagecamel.pgbackup_log(logid, logtime, backuptype, is_ok) VALUES (-2, '2000-01-01 00:00:00', 'BACKUP', false);
INSERT INTO pagecamel.pgbackup_log(logid, logtime, backuptype, is_ok) VALUES (-1, '2000-01-01 00:00:00', 'DIRSYNC', false);
