package PageCamel::Helpers::Translator;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::DBSerialize;
use JSON::XS;
use Digest::SHA1  qw(sha1_hex);
use MIME::Base64;
use Storable qw[freeze thaw];

# Translations and caching

use base qw(Exporter);
our @EXPORT = qw(tr_init tr_reload tr_checklang tr_rememberkey tr_translate tr_export tr_import tr_checkreload); ## no critic (Modules::ProhibitAutomaticExportation)


my $globalmemh; # We ALWAYS want to use a PostgreSQL backed memh!
my $globaldbh;
my $is_init;
my $isDebugging;

my $localcache;
my $cachechecksum = '--------'; # Init whith invalid hash

BEGIN {
    $is_init = 0;
    $isDebugging = 0;
}


sub tr_init {
    my ($dbh, $memh, $debugflag) = @_;

    $globalmemh = $memh;
    $globaldbh = $dbh;
    $isDebugging = $debugflag;
    $is_init = 1;

    return;
}

sub tr_checkreload {
    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    my $remotechecksum = $memh->get("LanguageCache");
    $remotechecksum = dbderef($remotechecksum);
    if($cachechecksum ne $remotechecksum) {
        tr_reload();
    }

    return;
}

sub tr_reload {
    #my ($dbh, $memh) = @_;

    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    my $lsth = $dbh->prepare_cached("SELECT lang FROM translate_languages")
        or croak($dbh->errstr);
    my $ksth = $dbh->prepare_cached("SELECT originaltext FROM translate_keys")
        or croak($dbh->errstr);
    my $tsth = $dbh->prepare_cached("SELECT originaltext, translation FROM translate_translations WHERE lang = ?")
        or croak($dbh->errstr);

    my %translate;

    my @langs;
    $lsth->execute or croak($dbh->errstr);
    while(defined(my $lang = $lsth->fetchrow_array)) {
        push @langs, $lang;
    }
    $lsth->finish;
    $translate{langs} = \@langs;

    my @keys;
    $ksth->execute or croak($dbh->errstr);
    while(defined(my $key = $ksth->fetchrow_array)) {
        push @keys, $key;
    }
    $ksth->finish;
    $translate{keys} = \@keys;

    foreach my $lang (@langs) {
        my %trans;
        $tsth->execute($lang) or croak($dbh->errstr);
        while((my $line = $tsth->fetchrow_hashref)) {
            $trans{$line->{originaltext}} = $line->{translation};
        }
        $tsth->finish;
        $translate{lang}->{$lang} = \%trans;
    }

    $localcache = \%translate;
    #$cachechecksum = sha1_hex(encode_json(\%translate));
    $cachechecksum = makeCacheChecksum($localcache);

    $memh->set("LanguageCache", \$cachechecksum);
    return;
}

sub makeCacheChecksum {
    my ($cache) = @_;
    
    my $cachestring = '';
    $cachestring .= join('', sort @{$cache->{keys}});
    
    foreach my $lang (sort keys %{$cache->{lang}}) {
        $cachestring .= $lang;
        foreach my $key (sort keys %{$cache->{lang}->{$lang}}) {
            $cachestring .= $key . $cache->{lang}->{$lang}->{$key};
        }
    }
    
    if(is_utf8($cachestring)) {
        $cachestring = encode_utf8($cachestring);
    }
    
    return sha1_hex($cachestring);
    
}

sub tr_checklang {
    my ($lang) = @_;

    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    if(contains($lang, $localcache->{langs})) {
        return 1;
    } else {
        return 0;
    }

}

sub tr_rememberkey {
    my ($key) = @_;

    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    if(contains($key, $localcache->{keys})) {
        return;
    }

    my $sth = $dbh->prepare("SELECT insert_translatekey(?)")
            or croak($dbh->errstr);
    if(!$sth->execute($key)) {
        $dbh->rollback;
    } else {
        $dbh->commit;
        tr_reload();
    }
    return;

}

sub tr_translate {
    my ($lang, $key) = @_;

    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    if(!defined($memh)) {
        return $key;
    }

    if(contains($key, $localcache->{keys})) {
        if(defined($localcache->{lang}->{$lang}) &&
               defined($localcache->{lang}->{$lang}->{$key})) {
            return $localcache->{lang}->{$lang}->{$key};
        } else {
            return $key;
        }
    } else {
        if(1 || $isDebugging) {
            my $sth = $dbh->prepare("SELECT insert_translatekey(?)")
                    or croak($dbh->errstr);
            if(!$sth->execute($key)) {
                $dbh->rollback;
            } else {
                $dbh->commit;
                tr_reload();
            }
        } else {
            return $key;
        }
    }
    return $key;
}

sub tr_export {
    #my ($dbh, $memh) = @_;

    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    tr_reload();

    my %exportdata = (
        ExportVersion   => 3,
        Translations    => encode_base64(freeze($localcache), ''),
    );


    my $exp = dbfreeze(\%exportdata);

    return $exp;
}

sub tr_import {
    my ($impraw) = @_;

    croak("Not initialized!") unless($is_init);
    my ($dbh, $memh) = ($globaldbh, $globalmemh);

    tr_reload();


    my $imp = dbthaw($impraw);
    $imp = dbderef($imp);
    my $impversion = 1;
    if(defined($imp->{ExportVersion})) {
        $impversion = $imp->{ExportVersion};
        delete $imp->{ExportVersion};
    }

    if($impversion >= 3) {
        $imp = thaw(decode_base64($imp->{Translations}));
    }

    my $delsth = $dbh->prepare("DELETE FROM translate_languages")
            or croak($dbh->errstr);

    my $limpsth = $dbh->prepare("INSERT INTO translate_languages
                                             (lang, description)
                                             VALUES (?,'')")
            or croak($dbh->errstr);

    my $kimpsth = $dbh->prepare("SELECT insert_translatekey(?)")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare("SELECT merge_translation(?, ?, ?)")
            or croak($dbh->errstr);

    $delsth->execute() or croak($dbh->errstr);

    # Insert missing languages
    foreach my $lang (@{$imp->{langs}}) {
        $limpsth->execute($lang) or croak($dbh->errstr);
    }

    # Insert all keys
    foreach my $key (@{$imp->{keys}}) {
        $kimpsth->execute($key) or croak($dbh->errstr);
    }

    # Now, merge all new translations
    foreach my $lang (@{$imp->{langs}}) {
        # $translate{lang}->{$lang}
        foreach my $orig (keys %{$imp->{lang}->{$lang}}) {
            my $trans = $imp->{lang}->{$lang}->{$orig};
            if($impversion == 2) {
                $trans = decode_base64($trans);
            }
            chomp $trans;
            $upsth->execute($orig, $lang, $trans)
                or croak($dbh->errstr);
        }
    }
    $dbh->commit;

    tr_reload();

    return;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::Translator - helper for multilanguage support

=head1 SYNOPSIS

  use PageCamel::Helpers::Translator;

=head1 DESCRIPTION

This helper module handles the translation* tables as well as caching translation in memcached

=head2 tr_init

Initialize the module and check for memcached availability.

=head2 tr_checkreload

Check if we need to reload data from the database.

=head2 tr_reload

Reload data from the database.

=head2 tr_checklang

Check if a language is available.

=head2 tr_rememberkey

Add a new key to the list of keys needing translations (if applicable)

=head2 tr_translate

Translate a key.

=head2 tr_export

Export the whole multilanguage tables into a single export file.

=head2 tr_import

Import a previously exported multilanguage export.

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
