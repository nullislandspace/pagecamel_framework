CREATE TABLE pagecamel.users_organisation (
    organisation_name text NOT NULL,
    description text NOT NULL DEFAULT '',
    CONSTRAINT users_organisation_pk PRIMARY KEY (organisation_name)
)
WITH (
  OIDS=FALSE
);

INSERT INTO pagecamel.users_organisation(organisation_name, description)
    SELECT company_name, description FROM pagecamel.company;

ALTER TABLE pagecamel.users ADD COLUMN organisation text;
UPDATE pagecamel.users SET organisation = company_name;
ALTER TABLE pagecamel.users ALTER COLUMN organisation SET NOT NULL;
ALTER TABLE pagecamel.users DROP COLUMN company_name;


CREATE TABLE pagecamel.computers_vncorganisation (
    computer_name text NOT NULL,
    organisation_name text NOT NULL,
    is_enabled boolean NOT NULL DEFAULT false,
    CONSTRAINT computers_vncorganisation_pk PRIMARY KEY (organisation_name),
    CONSTRAINT computers_vncorganisation_fk1 FOREIGN KEY (computer_name) REFERENCES computers(computer_name) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT computers_vncorganisation_fk2 FOREIGN KEY (organisation_name) REFERENCES users_organisation(organisation_name) ON UPDATE CASCADE ON DELETE CASCADE
)
WITH (
  OIDS=FALSE
);

INSERT INTO pagecamel.computers_vncorganisation(computer_name, organisation_name, is_enabled)
    SELECT computer_name, company_name, is_enabled FROM pagecamel.computers_vnccompany;

ALTER TABLE pagecamel.computers DROP COLUMN servicepack;
ALTER TABLE pagecamel.computers DROP COLUMN is_64bit;
ALTER TABLE pagecamel.computers DROP COLUMN line_id;
ALTER TABLE pagecamel.computers DROP COLUMN costunit;
DROP TABLE pagecamel.global_prodlines;
DROP TABLE pagecamel.global_costunits;
ALTER TABLE pagecamel.computers DROP COLUMN database_name;
DROP TABLE pagecamel.computers_databases;

DROP TABLE pagecamel.computers_vnccompany;
DROP TABLE pagecamel.company;

CREATE TABLE pagecamel.permissiongroups (
    groupname text NOT NULL,
    description text NOT NULL DEFAULT '',
    CONSTRAINT permissiongroups_pk PRIMARY KEY (groupname)
)
WITH (
  OIDS=FALSE
);


CREATE TABLE pagecamel.permissiongroupentries (
    groupname text NOT NULL,
    permission_name text NOT NULL,
    includes_subpermissions boolean NOT NULL DEFAULT true,
    CONSTRAINT permissiongroupentries_pk PRIMARY KEY (groupname, permission_name),
    CONSTRAINT permissiongroupentries_fk1 FOREIGN KEY (groupname) REFERENCES pagecamel.permissiongroups(groupname) ON UPDATE CASCADE ON DELETE CASCADE
)
WITH (
  OIDS=FALSE
);

CREATE TABLE pagecamel.users_permissiongroups (
    username text NOT NULL,
    groupname text NOT NULL,
    CONSTRAINT users_permissiongroups_pk PRIMARY KEY (username, groupname),
    CONSTRAINT users_permissiongroups_fk1 FOREIGN KEY (username) REFERENCES pagecamel.users(username) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT users_permissiongroups_fk2 FOREIGN KEY (groupname) REFERENCES pagecamel.permissiongroups(groupname) ON UPDATE CASCADE ON DELETE CASCADE
)
WITH (
  OIDS=FALSE
);

CREATE OR REPLACE FUNCTION pagecamel._migrate_permissions() RETURNS void AS $$
    use strict;

    elog(INFO, 'Converting user permissions to permission groups');

    #my $logsth = spi_prepare("SELECT pos.logfinancial(\$1, \$2, \$3, \$4, \$5, \$6)", 'TEXT', 'TEXT', 'TEXT', 'TEXT', 'TEXT', 'TEXT');

    my %userpermissions;

    # Select existing permissions
    {
        my $selsth = spi_prepare("SELECT * FROM pagecamel.users_permissions WHERE has_access = true");
        my $retval = spi_exec_prepared($selsth);
        if($retval->{status} ne 'SPI_OK_SELECT') {
            elog(ERROR, "Failed to select all rows in users.permissions");
        }
        if(!$retval->{processed}) {
            # No lines found
            return;
        }

        foreach my $line (@{$retval->{rows}}) {
            push @{$userpermissions{$line->{username}}}, $line->{permission_name};
        }
        spi_freeplan $selsth;
    }

    # Invert the lookup
    my %groups;
    foreach my $username (keys %userpermissions) {
        my $grouphash = join(',', sort @{$userpermissions{$username}});
        push @{$groups{$grouphash}}, $username;
    }

    # Create the permission groups
    {
        my $cnt = 1;
        my $namesth = spi_prepare("INSERT INTO pagecamel.permissiongroups(groupname, description) VALUES(\$1, \$2)", 'TEXT', 'TEXT');
        my $entrysth = spi_prepare("INSERT INTO pagecamel.permissiongroupentries(groupname, permission_name) VALUES (\$1, \$2)", 'TEXT', 'TEXT');
        my $usersth = spi_prepare("INSERT INTO pagecamel.users_permissiongroups(username, groupname) VALUES (\$1, \$2)", 'TEXT', 'TEXT');

        foreach my $grouphash (keys %groups) {
            my $groupname = 'GROUP' . $cnt;
            
            {
                my $description = join(', ', @{$groups{$grouphash}});
                my $retval = spi_exec_prepared($namesth, $groupname, $description);
                if($retval->{status} ne 'SPI_OK_INSERT') {
                    elog(ERROR, "Failed to insert into pagecamel.permissiongroups");
                }
            }

            my @permissions = split/\,/, $grouphash;
            foreach my $permission (@permissions) {
                my $retval = spi_exec_prepared($entrysth, $groupname, $permission);
                if($retval->{status} ne 'SPI_OK_INSERT') {
                    elog(ERROR, "Failed to insert into pagecamel.permissionentries");
                }
            }

            foreach my $username (@{$groups{$grouphash}}) {
                my $retval = spi_exec_prepared($usersth, $username, $groupname);
                if($retval->{status} ne 'SPI_OK_INSERT') {
                    elog(ERROR, "Failed to insert into pagecamel.users_permissiongroups");
                }
            }

            $cnt++;
        }
    }

    return; # EXECUTE, all updates sucessfull

$$ LANGUAGE plperlu;

SELECT pagecamel._migrate_permissions();
DROP FUNCTION pagecamel._migrate_permissions();

DROP TABLE pagecamel.users_permissions;
