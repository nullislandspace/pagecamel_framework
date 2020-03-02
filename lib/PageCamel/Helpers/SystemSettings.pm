package PageCamel::Helpers::SystemSettings;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize qw[dbfreeze dbthaw dbderef];

sub createNumber {
    my ($self, %setting) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Check for required fields
    foreach my $key (qw[modulename settingname settingvalue description value_min value_max processinghints]) {
        if(!defined($setting{$key})) {
            croak("Missing key $key when creating system setting");
        }
    }


    my ($ok, $data) = $self->get($setting{modulename}, $setting{settingname});
    if($ok) {
        return ($self->updateProcessinghints($setting{modulename}, $setting{settingname}, $setting{processinghints}) &&
                    $self->updateMinMax($setting{modulename}, $setting{settingname}, $setting{value_min}, $setting{value_max}));
    }

    my $sth = $dbh->prepare_cached("INSERT INTO system_settings (modulename, settingname, settingvalue, value_min, value_max, processinghints, description, fieldtype)
                                   VALUES (?,?,?,?,?,?,?,'number')")
            or croak($dbh->errstr);
    if(!$sth->execute($setting{modulename}, $setting{settingname}, $setting{settingvalue},
                  $setting{value_min}, $setting{value_max}, $setting{processinghints}, $setting{description})) {
              $dbh->rollback;
              return 0;
    }

    $dbh->commit;
    return 1;
}

sub createText {
    my ($self, %setting) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Check for required fields
    foreach my $key (qw[modulename settingname settingvalue description processinghints]) {
        if(!defined($setting{$key})) {
            croak("Missing key $key when creating system setting");
        }
    }


    my ($ok, $data) = $self->get($setting{modulename}, $setting{settingname}, 1);
    if($ok) {
        return $self->updateProcessinghints($setting{modulename}, $setting{settingname}, $setting{processinghints});
    }

    my $sth = $dbh->prepare_cached("INSERT INTO system_settings (modulename, settingname, settingvalue, processinghints, description, fieldtype)
                                   VALUES (?,?,?,?,?,'text')")
            or croak($dbh->errstr);
    if(!$sth->execute($setting{modulename}, $setting{settingname}, $setting{settingvalue},
                  $setting{processinghints}, $setting{description})) {
        $dbh->rollback();
        return 0;
    }
    $dbh->commit;
    return 1;
}

sub createBool {
    my ($self, %setting) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Check for required fields
    foreach my $key (qw[modulename settingname settingvalue description processinghints]) {
        if(!defined($setting{$key})) {
            croak("Missing key $key when creating system setting");
        }
    }


    my ($ok, $data) = $self->get($setting{modulename}, $setting{settingname}, 1);
    if($ok) {
        return $self->updateProcessinghints($setting{modulename}, $setting{settingname}, $setting{processinghints});
    }

    my $sth = $dbh->prepare_cached("INSERT INTO system_settings (modulename, settingname, settingvalue, processinghints, description, fieldtype)
                                   VALUES (?,?,?,?,?,'bool')")
            or croak($dbh->errstr);
    if(!$sth->execute($setting{modulename}, $setting{settingname}, $setting{settingvalue},
                  $setting{processinghints}, $setting{description})) {
        $dbh->rollback();
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub createEnum {
    my ($self, %setting) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Check for required fields
    foreach my $key (qw[modulename settingname settingvalue description processinghints enum_values]) {
        if(!defined($setting{$key})) {
            croak("Missing key $key when creating system setting");
        }
    }


    my ($ok, $data) = $self->get($setting{modulename}, $setting{settingname}, 1);
    if($ok) {
        return ($self->updateProcessinghints($setting{modulename}, $setting{settingname}, $setting{processinghints}) &&
                    $self->updateEnumValues($setting{modulename}, $setting{settingname}, $setting{enum_values}));
    }

    my $sth = $dbh->prepare_cached("INSERT INTO system_settings (modulename, settingname, settingvalue, enum_values, processinghints, description, fieldtype)
                                   VALUES (?,?,?,?,?,?,'enum')")
            or croak($dbh->errstr);
    $sth->execute($setting{modulename}, $setting{settingname}, $setting{settingvalue},
                  $setting{enum_values}, $setting{processinghints}, $setting{description})
            or croak($dbh->errstr);

    $dbh->commit;
    return 1;
}

sub get {
    my ($self, $modulename, $settingname, $forcedb) = @_;

    if(!defined($modulename) || !defined($settingname)) {
        return 0;
    }

    if(!defined($forcedb)) {
        $forcedb = 0;
    }

    my $settingref;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "SystemSettings::" . $modulename . "::" . $settingname;

    if(!$forcedb) {
        $settingref = $memh->get($memhname);
        if(defined($settingref)) {
            return (1, $settingref);
        }
    }

    my $sth = $dbh->prepare_cached("SELECT * FROM system_settings " .
                            "WHERE modulename = ? AND settingname = ?")
                    or croak($dbh->errstr);

    if(!$sth->execute($modulename, $settingname)) {
        $dbh->rollback;
        return 0;
    }

    if((my $row = $sth->fetchrow_hashref)) {
        $settingref = $row;
        $memh->set($memhname, $settingref);
    }
    $sth->finish;
    $dbh->rollback;

    if(defined($settingref)) {
        return (1, $settingref);
    } else {
        return 0;
    }
}

sub set { ## no critic (NamingConventions::ProhibitAmbiguousNames)
    my ($self, $modulename, $settingname, $value) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "SystemSettings::" . $modulename . "::" . $settingname;

    my $upsth = $dbh->prepare_cached("SELECT merge_system_settings(?, ?, ?)")
            or return;
    if(!$upsth->execute($modulename, $settingname, $value)) {
        $dbh->rollback();
        return 0;
    }

    $upsth->finish;
    $dbh->commit;

    # Now, reload complete data set and also push it into memcached
    my $sth = $dbh->prepare_cached("SELECT * FROM system_settings " .
                            "WHERE modulename = ? AND settingname = ?")
                    or croak($dbh->errstr);

    $sth->execute($modulename, $settingname)
            or croak($dbh->errstr);

    if((my $row = $sth->fetchrow_hashref)) {
        $memh->set($memhname, $row);
        $sth->finish;
        $dbh->rollback;
        return 1;
    }

    $sth->finish;
    $dbh->rollback;
    return 0;
}

sub delete {## no critic(BuiltinHomonyms)
    my ($self, $modulename, $settingname) = @_;

    my $settingref;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "SystemSettings::" . $modulename . "::" . $settingname;

    $memh->delete($memhname);

    my $sth = $dbh->prepare_cached("DELETE FROM system_settings " .
                            "WHERE modulename = ? AND settingname = ?")
            or return;
    if(!$sth->execute($modulename, $settingname)) {
        $dbh->rollback;
        return;
    }

    $sth->finish;
    $dbh->commit;

    return 1;
}

sub list {
    my ($self, $modulename) = @_;

    my @settingnames;
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $sth = $dbh->prepare_cached("SELECT settingname FROM system_settings
                                   WHERE modulename = ?
                                    ORDER BY modulename, settingname")
                or return 0;
    if(!$sth->execute($modulename)) {
        $dbh->rollback;
        return 0;
    }
    while((my @row = $sth->fetchrow_array)) {
        push @settingnames, $row[0];
    }
    $sth->finish;
    $dbh->rollback;

    return (1, @settingnames);
}

sub updateProcessinghints {
    my ($self, $modulename, $settingname, $hints) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "SystemSettings::" . $modulename . "::" . $settingname;

    my $upsth = $dbh->prepare_cached("UPDATE system_settings
                                     SET processinghints = ?
                                     WHERE modulename = ? AND settingname = ?")
            or croak($dbh->errstr);
    if(!$upsth->execute($hints, $modulename, $settingname)) {
        $dbh->rollback;
        return 0;
    }

    $upsth->finish;
    $dbh->commit;

    # Now, reload complete data set and also push it into memcached
    my $sth = $dbh->prepare_cached("SELECT * FROM system_settings " .
                            "WHERE modulename = ? AND settingname = ?")
                    or croak($dbh->errstr);

    if(!$sth->execute($modulename, $settingname)) {
        $dbh->rollback;
        return 0;
    }

    if((my $row = $sth->fetchrow_hashref)) {
        $memh->set($memhname, $row);
        $sth->finish;
        $dbh->rollback;
        return 1;
    }

    $sth->finish;
    $dbh->rollback;
    return 0;
}

sub updateEnumValues {
    my ($self, $modulename, $settingname, $values) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "SystemSettings::" . $modulename . "::" . $settingname;

    my $upsth = $dbh->prepare_cached("UPDATE system_settings
                                     SET enum_values = ?
                                     WHERE modulename = ? AND settingname = ?")
            or croak($dbh->errstr);
    $upsth->execute($values, $modulename, $settingname)
            or croak($dbh->errstr);

    $upsth->finish;
    $dbh->commit;

    # Now, reload complete data set and also push it into memcached
    my $sth = $dbh->prepare_cached("SELECT * FROM system_settings " .
                            "WHERE modulename = ? AND settingname = ?")
                    or croak($dbh->errstr);

    if(!$sth->execute($modulename, $settingname)) {
        $dbh->rollback;
        return 0;
    }

    if((my $row = $sth->fetchrow_hashref)) {
        $memh->set($memhname, $row);
        $sth->finish;
        $dbh->rollback;
        return 1;
    }

    $sth->finish;
    $dbh->rollback;
    return 0;
}

sub updateMinMax {
    my ($self, $modulename, $settingname, $min, $max) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "SystemSettings::" . $modulename . "::" . $settingname;

    my $upsth = $dbh->prepare_cached("UPDATE system_settings
                                     SET value_min = ?,
                                     value_max = ?
                                     WHERE modulename = ? AND settingname = ?")
            or croak($dbh->errstr);
    if(!$upsth->execute($min, $max, $modulename, $settingname)) {
        $dbh->rollback;
        return 0;
    }

    $upsth->finish;
    $dbh->commit;

    # Update value if out of min/max boundary
    if(1) {
        my $up1sth = $dbh->prepare_cached("UPDATE system_settings
                                          SET settingvalue = value_min::text
                                          WHERE modulename = ? AND settingname = ?
                                          AND settingvalue::numeric < value_min")
                or croak($dbh->errstr);
        my $up2sth = $dbh->prepare_cached("UPDATE system_settings
                                          SET settingvalue = value_max::text
                                          WHERE modulename = ? AND settingname = ?
                                          AND settingvalue::numeric > value_max")
                or croak($dbh->errstr);
        $up1sth->execute($modulename, $settingname) or croak($dbh->errstr);
        $up2sth->execute($modulename, $settingname) or croak($dbh->errstr);
        $dbh->commit;
    }

    # Now, reload complete data set and also push it into memcached
    my $sth = $dbh->prepare_cached("SELECT * FROM system_settings " .
                            "WHERE modulename = ? AND settingname = ?")
                    or croak($dbh->errstr);

    if(!$sth->execute($modulename, $settingname)) {
        $dbh->rollback;
        return 0;
    }

    if((my $row = $sth->fetchrow_hashref)) {
        $memh->set($memhname, $row);
        $sth->finish;
        $dbh->rollback;
        return 1;
    }

    $sth->finish;
    $dbh->rollback;
    return 0;
}


1;
__END__

=head1 NAME

PageCamel::Helpers::SystemSettings - helper for dealing with PageCamel System settings

=head1 SYNOPSIS

  use PageCamel::Helpers::SystemSettings;

=head1 DESCRIPTION

This helper unifies the handling of System settings. It is usually not used directly but through the appropriate "Worker" resp. "Web" modules.

=head2 createNumber

Create a "number" system setting.

=head2 createText

Create a "text" system setting

=head2 createBool

Create a "bool" system setting

=head2 createEnum

Create a "enum" system setting

=head2 get

Get value of a system setting.

=head2 set

Update a system setting.

=head2 delete

Delete a system setting.

=head2 list

List all Systemsettings.

=head2 updateProcessinghints

Update the processing hints for a system setting.

=head2 updateEnumValues

Update allowed enum values for system setting.

=head2 updateMinMax

Update min/max values for "number" system setting.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
