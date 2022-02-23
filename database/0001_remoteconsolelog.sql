CREATE TABLE remoteconsolelog (
    logid bigserial NOT NULL,
    logtime timestamp without time zone NOT NULL DEFAULT now(),
    client_ip inet NOT NULL,
    username text NOT NULL,
    logdata json NOT NULL,
    logdata_formatted text NOT NULL,
    CONSTRAINT remoteconsolelog_pk PRIMARY KEY(logid)
)
WITH (
  OIDS=FALSE
);


