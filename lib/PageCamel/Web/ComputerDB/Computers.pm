package PageCamel::Web::ComputerDB::Computers;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw(doFPad);
use PDF::Report;

sub reload {
    my ($self) = shift;

    my (@keynames, @nullfields, @readonlykeynames, %datatypes);

    push @keynames, 'old_computer_name';

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $selsth = $dbh->prepare("SELECT column_name, data_type, is_nullable FROM information_schema.columns
                                WHERE table_name = 'computers'")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    while((my $line = $selsth->fetchrow_hashref)) {
        if($line->{column_name} eq 'pagecamel_designation' ||
                $line->{column_name} eq 'pagecamel_notes') {
            next;
        }
        $datatypes{$line->{column_name}} = $line->{data_type};
        if($line->{is_nullable} eq 'YES') {
            push @nullfields, $line->{column_name};
        }
        if($line->{column_name} eq 'vnc_width' || $line->{column_name} eq 'vnc_height') {
            push @readonlykeynames, $line->{column_name};
        } else {
            push @keynames, $line->{column_name};
        }
    }
    $selsth->finish;
    $self->{keynames} = \@keynames;
    $self->{nullfields} = \@nullfields;
    $self->{readonlykeynames} = \@readonlykeynames;
    $self->{datatypes} = \%datatypes;

    return;
}

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}



sub register {
    my $self = shift;
    $self->register_webpath($self->{computeredit}->{webpath}, "get_edit");
    $self->register_webpath($self->{computerselect}->{webpath}, "get_select");
    $self->register_webpath($self->{computervnc}->{webpath}, "get_vncedit");
    return;
}

# This is a quite complex tool. Until i have found a better way, disable the ExcessComplexity warning
# of Perl::Critic
sub get_edit { ## no critic (ProhibitExcessComplexity)
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $host_addr = $ua->{remote_addr};
    my $mode = $ua->{postparams}->{'mode'} || 'new';
    my $foo = $ua->{postparams}->{'old_computer_name'} || '';
        
    if($foo eq 'NEW') {
        $mode = 'new';
    }

    my @networktypes;
    my $nsth = $dbh->prepare_cached("SELECT enumvalue FROM enum_computers_network
                                    ORDER BY enumvalue")
            or croak($dbh->errstr);
    $nsth->execute or croak($dbh->errstr);
    while(defined(my $networktype = $nsth->fetchrow_array)) {
        push @networktypes, $networktype;
    }
    $nsth->finish;

    my @prodlines;
    my $psth = $dbh->prepare_cached("SELECT * FROM global_prodlines
                                    ORDER BY line_id")
            or croak($dbh->errstr);
    $psth->execute or croak($dbh->errstr);
    while((my $prodline = $psth->fetchrow_hashref)) {
        push @prodlines, $prodline;
    }
    $psth->finish;

    my @companies;
    my $csth = $dbh->prepare_cached("SELECT * FROM company
                                    ORDER BY company_name")
            or croak($dbh->errstr);
    $csth->execute or croak($dbh->errstr);
    while((my $company = $csth->fetchrow_hashref)) {
        push @companies, $company->{company_name};
    }
    $psth->finish;

    my @databases;
    my $dbsth = $dbh->prepare_cached("SELECT * FROM computers_databases
                                    ORDER BY database_name, description")
            or croak($dbh->errstr);
    $dbsth->execute or croak($dbh->errstr);
    while((my $database = $dbsth->fetchrow_hashref)) {
        push @databases, $database;
    }
    $dbsth->finish;

    my @locations;
    my $locsth = $dbh->prepare_cached("SELECT * FROM enum_computerlocations
                                    ORDER BY enumvalue, description")
            or croak($dbh->errstr);
    $locsth->execute or croak($dbh->errstr);
    while((my $location = $locsth->fetchrow_hashref)) {
        push @locations, $location;
    }
    $locsth->finish;
    

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{computeredit}->{pagetitle},
        webpath            =>  $self->{computeredit}->{webpath},
        ComputerSelect    =>    $self->{computerselect}->{webpath},
        networktypes    => \@networktypes,
        AvailProdLines  => \@prodlines,
        databases       => \@databases,
        locations       => \@locations,
        HasDeveloperRights => 0,
        showads => $self->{showads},
    );
    
    my $developermode = 0;
    my @extracolumns;
    if(contains('has_developer', $webdata{userData}->{rights})) {
        $developermode = 1;
        $webdata{HasDeveloperRights} = 1;
        @extracolumns = ('pagecamel_designation', 'pagecamel_notes');
    }

    my %computer;
    if($mode ne "new") {
        # Get parameters from webform
        foreach my $keyname (@{$self->{keynames}}, @extracolumns) {
            if(!defined($computer{$keyname})) {
                $computer{$keyname} = $ua->{postparams}->{$keyname} || '';
                my $datatype = 'text';
                if(defined($self->{datatypes}->{$keyname})) {
                    $datatype = $self->{datatypes}->{$keyname};
                }
                if($keyname =~ /^net_.*_type/) {
                    $datatype = 'domain';
                }
                if($datatype eq 'boolean') {
                    if($computer{$keyname} eq "on") {
                        $computer{$keyname} = 1;
                    } else {
                        $computer{$keyname} = 0;
                    }
                } elsif($datatype eq 'domain') {
                    if($computer{$keyname} eq "") {
                        $computer{$keyname} = "NONE";
                    }
                } elsif($datatype eq 'integer') {
                    if(defined($computer{$keyname})) {
                        if($computer{$keyname} eq "") {
                            $computer{$keyname} = 0;
                        }
                        $computer{$keyname} = $computer{$keyname} + 0;
                    } else {
                        $computer{$keyname} = 0;
                    }
                } elsif($datatype eq 'numeric') {
                    if(defined($computer{$keyname})) {
                        if($computer{$keyname} eq "") {
                            $computer{$keyname} = 0.0;
                        }
                        $computer{$keyname} = $computer{$keyname} + 0.0;
                    } else {
                        $computer{$keyname} = 0.0;
                    }
                }
            }
        }
    }

    # Handle standard POST requests
    if($mode eq "delete") {
        my $sth = $dbh->prepare("DELETE FROM computers
                                       WHERE computer_name = ?")
                or croak($dbh->errstr);
        if($sth->execute($computer{old_computer_name})) {
            $sth->finish;
            $dbh->commit;
            $webdata{statustext} = "Computer deleted";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "Computer " . $computer{old_computer_name} . " deleted", $webdata{userData}->{user});
            return $self->get_select($ua, 1);
        } else {
            $webdata{statustext} = "Deletion failed: " . $dbh->errstr;
            $webdata{statuscolor} = "errortext";
            $dbh->rollback;
        }
        $mode = 'new';
    } elsif($mode eq "create") {
        my @fields;
        my @values;
        my @auditdata;
        foreach my $keyname (@{$self->{keynames}}, @extracolumns) {
            next if($keyname eq "old_computer_name");

            # Handle NULL values for database_name
            if(contains($keyname, $self->{nullfields})) {
                if(!defined($computer{$keyname}) || $computer{$keyname} eq '') {
                    # Ignore empty field - database sets it to NULL by default
                    next;
                }
            }

            push @fields, $keyname;
            if(!defined($computer{$keyname})) {
                $computer{$keyname} = "";
            }
            if($keyname eq "lastedit_time") {
                push @values, "now()";
            } elsif($keyname eq "lastedit_user") {
                push @values, $dbh->quote($webdata{userData}->{user});
            } elsif($keyname =~ /^(is_|has_)/) {
                if($computer{$keyname} == 1) {
                    push @values, "'true'";
                } else {
                    push @values, "'false'";
                }

            } else {
                push @values, $dbh->quote($computer{$keyname});
            }
        }
        for(my $i = 0; $i < scalar(@fields); $i++) {
            push @auditdata, $fields[$i] . ": " . $values[$i];
        }

        my $stmt = "INSERT INTO computers (" . join(',', @fields) . ") " .
                    " VALUES (" . join(',', @values) . ")";

        my $sth = $dbh->prepare($stmt)
                or croak($dbh->errstr);
        my $ok = 1;
        if(!$sth->execute()) {
            $ok = 0;
        } else {
            $sth->finish;
        }

        my @vcompany;
        my @vcompanies;
        if(ref $ua->{postparams}->{'vnccompany'} eq 'ARRAY') {
            @vcompanies = @{$ua->{postparams}->{'vnccompany'}};
        } else {
            push @vcompanies, $ua->{postparams}->{'vnccompany'};
        }
        foreach my $company (@companies) {
            my $enabled = 0;
            if(contains($company, \@vcompanies)) {
                $enabled = 1;
            }

            my %tmp = (
                name        => $company,
                is_active    => $enabled,
            );
            push @vcompany, \%tmp;
        }

        if($ok) {
            my $vsth = $dbh->prepare_cached("INSERT INTO computers_vnccompany
                                            (computer_name, company_name, is_enabled)
                                            VALUES (?,?,?)")
                    or croak($dbh->errstr);
            foreach my $vcomp (@vcompany) {
                push @auditdata, 'VNC ' . $vcomp->{name} . ': ' . $vcomp->{is_active};
                if(!$vsth->execute($computer{computer_name}, $vcomp->{name}, $vcomp->{is_active})) {
                    $ok = 0;
                    last;
                }
            }
        }

        if($ok) {
            $dbh->commit;
            $webdata{statustext} = "Computer created";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "Computer " . $computer{computer_name} . " created", $webdata{userData}->{user}, @auditdata);


            # Force reload from database so server side processing gets integrated into
            # the displayed data
            $computer{old_computer_name} = $computer{computer_name};
            $mode = "select";

        } else {
            $webdata{statustext} = "Creation failed: " . $dbh->errstr;
            $webdata{statuscolor} = "errortext";
            $webdata{vnccompanies} = \@vcompany;
            $mode = "create";
            $dbh->rollback;
        }
    } elsif($mode eq "edit") {
        my @fields;
        my @auditdata;
        foreach my $keyname (@{$self->{keynames}}, @extracolumns) {
            next if($keyname eq "old_computer_name");
            my $field = "$keyname = ";
            if(!defined($computer{$keyname})) {
                $computer{$keyname} = "";
            }
            if($keyname eq "lastedit_time") {
                $field .= "now()";
            } elsif($keyname eq "lastedit_user") {
                $field .= $dbh->quote($webdata{userData}->{user});
            } elsif($keyname =~ /^(is_|has_)/) {
                if($computer{$keyname} == 1) {
                    $field .= "'true'";
                } else {
                    $field .= "'false'";
                }
            } elsif(contains($keyname, $self->{nullfields}) && $computer{$keyname} eq '') {
                # NULL fields
                $field .= "NULL";
            } else {
                $field .= $dbh->quote($computer{$keyname});
            }
            push @fields, $field;
        }
        push @auditdata, @fields;

        my $stmt = "UPDATE computers SET " . join(',', @fields) .
                    " WHERE computer_name = " . $dbh->quote($computer{old_computer_name});

        my $sth = $dbh->prepare($stmt)
                or croak($dbh->errstr);
        my $ok = 1;
        if(!$sth->execute()) {
            $ok = 0;
        } else {
            $sth->finish;
        }

        if($ok) {
            my $vdelsth = $dbh->prepare_cached("DELETE FROM computers_vnccompany
                                               WHERE computer_name = ?")
                    or croak($dbh->errstr);
            if(!$vdelsth->execute($computer{computer_name})) {
                $ok = 0;
            } else {
                $vdelsth->finish;
            }
        }

        my @vcompany;
        my @vcompanies;
        if(ref $ua->{postparams}->{'vnccompany'} eq 'ARRAY') {
            @vcompanies = @{$ua->{postparams}->{'vnccompany'}};
        } else {
            push @vcompanies, $ua->{postparams}->{'vnccompany'};
        }
               
        foreach my $company (@companies) {
            my $enabled = 0;
            if(contains($company, \@vcompanies)) {
                $enabled = 1;
            }

            my %tmp = (
                name        => $company,
                is_active    => $enabled,
            );
            push @vcompany, \%tmp;
        }

        if($ok) {
            my $vsth = $dbh->prepare_cached("INSERT INTO computers_vnccompany
                                            (computer_name, company_name, is_enabled)
                                            VALUES (?,?,?)")
                    or croak($dbh->errstr);

            foreach my $vcomp (@vcompany) {
                push @auditdata, 'VNC ' . $vcomp->{name} . ': ' . $vcomp->{is_active};
                if(!$vsth->execute($computer{computer_name}, $vcomp->{name}, $vcomp->{is_active})) {
                    $ok = 0;
                    last;
                }
            }
        }

        if($ok) {
            $dbh->commit;
            $webdata{statustext} = "Computer updated";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "Computer " . $computer{computer_name} . " updated", $webdata{userData}->{user}, @auditdata);

            # Force reload from database so server side processing gets integrated into
            # the displayed data
            $computer{old_computer_name} = $computer{computer_name};
            $mode = "select";

        } else {
            $webdata{statustext} = "Update failed: " . $dbh->errstr;
            $webdata{statuscolor} = "errortext";
            $mode = "edit";
            $webdata{vnccompanies} = \@vcompany;
            $dbh->rollback;
        }
    }

    if($mode eq "select") {
        my $stmt = "SELECT * FROM computers " .
                    "WHERE computer_name = ?";
        my $sth = $dbh->prepare($stmt)
                or croak($dbh->errstr);
        if(!$sth->execute($computer{old_computer_name})) {
            $dbh->rollback;
            $webdata{statustext} = "Can't load computer";
            $webdata{statuscolor} = "errortext";
            $mode = "new";
        } else {
            my $line = $sth->fetchrow_hashref;
            $sth->finish;
            $dbh->rollback;
            if(defined($line)) {
                foreach my $keyname (@{$self->{keynames}}, @{$self->{readonlykeynames}}, 'pagecamel_designation', 'pagecamel_notes') {
                    next if($keyname eq "old_computer_name");
                    if(!defined($line->{$keyname})) {
                        $computer{$keyname} = "";
                    } else {
                        $computer{$keyname} = $line->{$keyname};
                    }
                }

                my $vsth = $dbh->prepare_cached("SELECT company_name, is_enabled
                                                FROM computers_vnccompany
                                                WHERE computer_name = ?")
                        or croak($dbh->errstr);
                my %vcomp;
                $vsth->execute($computer{old_computer_name});
                while((my $vline = $vsth->fetchrow_hashref)) {
                    $vcomp{$vline->{company_name}} = $vline->{is_enabled};
                }
                $vsth->finish;
                my @vnccompanies;
                foreach my $vnccompany (@companies) {
                    my %tmp = (
                        name        =>    $vnccompany,
                        is_active    =>    0,
                    );
                    if(defined($vcomp{$vnccompany})) {
                        $tmp{is_active}    = $vcomp{$vnccompany};
                    }
                    push @vnccompanies, \%tmp;
                }
                $webdata{vnccompanies} = \@vnccompanies;

                $mode = "edit";
            } else {
                $webdata{statustext} = "Can't load computer";
                $webdata{statuscolor} = "errortext";
                $mode = "new";
            }
        }
    }

    if($mode eq "new") {
        my %defaultcomputer = (
            is_64bit            => 0,
            has_vnc                => 0,
            net_public1_type   => 'NONE',
            net_public2_type   => 'NONE',
            net_private1_type   => 'NONE',
            net_private2_type   => 'NONE',
        );
        foreach my $keyname (@{$self->{keynames}}) {
            if(!defined($defaultcomputer{$keyname})) {
                $defaultcomputer{$keyname} = "";
            }
        }

        $webdata{computer} = \%defaultcomputer;

        my @vnccompanies;
        foreach my $vnccompany (@companies) {
            my %tmp = (
                name        =>    $vnccompany,
                is_active    =>    0,
            );
            push @vnccompanies, \%tmp;
        }
        $webdata{vnccompanies} = \@vnccompanies;

        $mode = "create";
    } else {
        # Beautify a bit
        $webdata{computer} = \%computer;
    }
    $webdata{EditMode} = $mode;

    my $ossth = $dbh->prepare_cached("SELECT * FROM computers_os
                                     ORDER BY operating_system")
            or croak($dbh->errstr);
    $ossth->execute() or croak($dbh->errstr);
    my @oss;
    while((my $line = $ossth->fetchrow_hashref)) {
        push @oss, $line;
    }
    $webdata{operating_systems} = \@oss;

    my $custh = $dbh->prepare_cached("SELECT * FROM global_costunits
                                 ORDER BY costunit")
        or croak($dbh->errstr);
    $custh->execute() or croak($dbh->errstr);
    my @costunits;
    while((my $line = $custh->fetchrow_hashref)) {
        push @costunits, $line;
    }
    $webdata{costunits} = \@costunits;
    
    my $typesth = $dbh->prepare_cached("SELECT * FROM computers_type
                                 ORDER BY device_type")
        or croak($dbh->errstr);
    $typesth->execute() or croak($dbh->errstr);
    my @devicetypes;
    while((my $line = $typesth->fetchrow_hashref)) {
        push @devicetypes, $line;
    }
    $webdata{devicetypes} = \@devicetypes;

    if(!defined($webdata{HeadExtraScripts})) {
        my @tmp;
        $webdata{HeadExtraScripts} = \@tmp;
    }
    if(!defined($webdata{HeadExtraCSS})) {
        my @tmp;
        $webdata{HeadExtraCSS} = \@tmp;
    }
    push @{$webdata{HeadExtraScripts}}, $self->{jspath};
    push @{$webdata{HeadExtraCSS}}, $self->{csspath};
    
    # -- CVCEditor stuff --
    push @{$webdata{HeadExtraScripts}}, (
                                         '/static/cvceditor/cvceditor.js',
                                         '/static/cvceditor/adapters/jquery.js',
                                        );
    $ua->{UseUnsafeCVCEditor} = 1;
    # -- CVCEditor stuff --

    if(defined($self->{admindirectvncpath}) &&
            $self->{admindirectvncpath} ne '' &&
            contains('has_admin', $webdata{userData}->{rights}) &&
            $webdata{EditMode} eq 'edit') {
        $webdata{admindirectvncpath} = $self->{admindirectvncpath} . '/admdirect/' . $webdata{computer}->{computer_name};
    }

    my $template = $self->{server}->{modules}->{templates}->get("computerdb/computers_edit", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


# "get_select" actually only displays the available card list, POST
# is done to the main mask to have a smoother workflow without redirects
sub get_select {
    my ($self, $ua, $afterdelete) = @_;

    if(!defined($afterdelete)) {
        $afterdelete = 0;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    my $urlname = $ua->{url};
    my $remove = $self->{computerselect}->{webpath};
    $urlname =~ s/^$remove//;
    $urlname =~ s/^\///;
    $urlname =~ s/\/$//;

    if($afterdelete) {
        $mode = 'view';
        $urlname = '';
    }

    if($urlname ne '') {
        $ua->{postparams}->{'old_computer_name'} = $urlname;
        $ua->{postparams}->{'mode'} = 'select';
        return $self->get_edit($ua);
    }

    if($mode eq "view") {
        my $sth = $dbh->prepare_cached("SELECT * FROM computers
                                       ORDER BY computer_name")
                    or croak($dbh->errstr);
        my @computers;

        if($sth->execute) {
            while((my $line = $sth->fetchrow_hashref)) {
                push @computers, $line;
            }
        }
        $sth->finish;
        $dbh->rollback;


        my %webdata =
        (
            $self->{server}->get_defaultwebdata(),
            PageTitle   =>  $self->{computerselect}->{pagetitle},
            webpath        =>  $self->{computerselect}->{webpath},
            computers        =>  \@computers,
            HasDeveloperRights  => 0,
        );

    
        if(contains('has_developer', $webdata{userData}->{rights})) {
            $webdata{HasDeveloperRights} = 1;
        }

        my $template = $self->{server}->{modules}->{templates}->get("computerdb/computers_select", 1, %webdata);
        return (status  =>  404) unless $template;
        return (status  =>  200,
                type    => "text/html",
                data    => $template);
    } else {
        return $self->get_edit($ua);
    }
}

# VNCEdit is a quickedit tool to quickly changes VNC access rights on a number
# of computers
sub get_vncedit {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $mode = $ua->{postparams}->{'mode'} || 'view';


    my $csth = $dbh->prepare_cached("SELECT * FROM computers
                                    ORDER BY line_id, computer_name")
            or croak($dbh->errstr);
    my $rsth = $dbh->prepare_cached("SELECT * FROM company
                                    ORDER BY company_name")
            or croak($dbh->errstr);
    my $vsth = $dbh->prepare_cached("SELECT * FROM computers_vnccompany
                                    WHERE computer_name = ?
                                    AND company_name = ?")
            or croak($dbh->errstr);

    # Search available computers and companies
    my @AvailComputers;
    if(!$csth->execute) {
        $dbh->rollback;
    } else {
        while((my $line = $csth->fetchrow_hashref)) {
            push @AvailComputers, $line;
        }
        $csth->finish;
    }

    my @AvailCompanies;
    if(!$rsth->execute) {
        $dbh->rollback;
    } else {
        while((my $line = $rsth->fetchrow_hashref)) {
            push @AvailCompanies, $line;
        }
        $rsth->finish;
    }

    my $selectedcompany = $ua->{postparams}->{'selectedcompany'} ||  $AvailCompanies[0]->{company_name};

    # Update rights if needed
    if($mode eq "save") {
        my $upsth = $dbh->prepare_cached("SELECT merge_vnccompany(?,?,?)")
                or croak($dbh->errstr);
        foreach my $computer (@AvailComputers) {
            my $enabled = $ua->{postparams}->{'vnc_' . $computer->{computer_name} . '_' . $selectedcompany} || '0';
            if($upsth->execute($computer->{computer_name},
                               $selectedcompany,
                               $enabled)) {
                $upsth->finish;
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
        }
    }


    # Read back merged rights from database
    foreach my $computer (@AvailComputers) {
        my @rights;

            my $enabled = 0;
            if($vsth->execute($computer->{computer_name}, $selectedcompany)) {
                my $line = $vsth->fetchrow_hashref;
                if(defined($line)) {
                    if($line->{is_enabled} == 1) {
                        $enabled = 1;
                    }
                }
                $vsth->finish;
            } else {
                $dbh->rollback;
            }
            my %vright = (
                company    => $selectedcompany,
                val        => $enabled,
            );
            push @rights, \%vright;

        $computer->{rights} = \@rights;
    }

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{computervnc}->{pagetitle},
        webpath            =>  $self->{computervnc}->{webpath},
        AvailComputers  => \@AvailComputers,
        AvailCompanies  => \@AvailCompanies,
        SelectedCompany => $selectedcompany,
    );

    my $template = $self->{server}->{modules}->{templates}->get("computerdb/computers_vncedit", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}

1;
__END__

=head1 NAME

PageCamel::Web::ComputerDB::Computers -

=head1 SYNOPSIS

  use PageCamel::Web::ComputerDB::Computers;



=head1 DESCRIPTION



=head2 reload



=head2 new



=head2 register



=head2 on_login



=head2 get_edit



=head2 get_select



=head2 get_vncedit



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
