package PageCamel::Web::Translate;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---



use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Web::TT::Translate;
use PageCamel::Helpers::Translator;
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);


use Readonly;
Readonly my $TESTRANGE => 1_000_000;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my @themes;
    foreach my $key (sort keys %{$self->{view}}) {
        my %theme = %{$self->{view}->{$key}};
        $theme{name} = $key;

        push @themes, \%theme;
    }
    $self->{Themes} = \@themes;
    $self->{firstReload} = 1;

    return $self;
}

sub reload {
    my ($self) = shift;

    # Update the handles for the template plugin
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    if($self->{firstReload}) {
        $self->{firstReload} = 0;
        tr_init($dbh, $memh, $self->{isDebugging});
    }
    tr_reload();

    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{settings}->{webpath}, "get_settings");
    $self->register_webpath($self->{languages}->{webpath}, "get_languages");
    $self->register_webpath($self->{translations}->{webpath}, "get_translations");
    $self->register_webpath($self->{export}->{webpath}, "get_export");
    $self->register_webpath($self->{exportfile}->{webpath}, "get_file");
    $self->register_prerender("prerender");
    $self->register_postfilter("postfilter");

    $self->register_preconnect("check_translationupdates");
    return;
}

sub get_settings {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my @AvailLangs;

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{settings}->{pagetitle},
        webpath         =>  $self->{settings}->{webpath},
        showads => $self->{showads},
    );

    my $whereclause = "";
    if($webdata{userData}->{user} ne "admin") {
        $whereclause = "WHERE lang not like '%yoda%'";
    }

    my $sth = $dbh->prepare_cached("SELECT * FROM translate_languages
                                   $whereclause
                                   ORDER BY lang")
            or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);
    while((my $lang = $sth->fetchrow_hashref)) {
        push @AvailLangs, $lang;
    }
    $sth->finish;
    $webdata{AvailLanguages} = \@AvailLangs;


    # We don't actually set the Theme into webdata here, this is done during the prerender stage.
    # Also, we don't handle the "select a default theme if non set" case, TemplateCache falls back to
    # its own default theme anyway
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "setvalue") {
        my $lang = $ua->{postparams}->{'language'} || "eng";
        if($lang ne "") {
            $seth->set($webdata{userData}->{user}, "UserLanguage", \$lang);
        }
    }

    my $template = $self->{server}->{modules}->{templates}->get("translate_select", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_languages {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{languages}->{pagetitle},
        webpath         =>  $self->{languages}->{webpath},
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    if($mode eq "change") {
        my $upsth = $dbh->prepare_cached("UPDATE translate_languages
                                         SET lang = ?, description = ?
                                         WHERE lang = ?")
                or croak($dbh->errstr);
        my $oldlang = $ua->{postparams}->{'language'} || '';
        my $newlang = $ua->{postparams}->{'newlanguage'} || '';
        my $description = $ua->{postparams}->{'description'} || '';
        if($oldlang ne '' && $newlang ne '') {
            if($upsth->execute($newlang, $description, $oldlang)) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
        }
    } elsif($mode eq "delete") {
        my $delsth = $dbh->prepare_cached("DELETE FROM translate_languages
                                         WHERE lang = ?")
                or croak($dbh->errstr);
        my $oldlang = $ua->{postparams}->{'language'} || '';
        if($oldlang ne '') {
            if($delsth->execute($oldlang)) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
        }
    } elsif($mode eq "create") {
        my $insth = $dbh->prepare_cached("INSERT INTO translate_languages
                                         (lang, description)
                                         VALUES (?,?)")
                or croak($dbh->errstr);
        my $newlang = $ua->{postparams}->{'newlanguage'} || '';
        my $description = $ua->{postparams}->{'description'} || '';
        if($newlang ne '') {
            if($insth->execute($newlang, $description)) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
        }
    }

    my @AvailLangs;
    my $sth = $dbh->prepare_cached("SELECT * FROM translate_languages
                                   ORDER BY lang")
            or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);
    while((my $lang = $sth->fetchrow_hashref)) {
        push @AvailLangs, $lang;
    }
    $sth->finish;
    $webdata{AvailLanguages} = \@AvailLangs;

    my $template = $self->{server}->{modules}->{templates}->get("translate_languages", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_translations {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my @AvailLangs;
    my $sth = $dbh->prepare_cached("SELECT * FROM translate_languages
                                   ORDER BY lang")
            or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);
    while((my $lang = $sth->fetchrow_hashref)) {
        push @AvailLangs, $lang;
    }
    $sth->finish;

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{translations}->{pagetitle},
        webpath         =>  $self->{translations}->{webpath},
        AvailLanguages  =>  \@AvailLangs,
        showads => $self->{showads},
    );

    my ($ok, $langname) = $seth->get($webdata{userData}->{user}, "EditLanguage");

    my $lang = "eng"; # Use english as default
    if(defined($langname)) {
        $langname = dbderef($langname);
    }
    if($ok && defined($langname) && $langname ne "") {
        $lang = $langname;
    }

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "setlanguage") {
        $lang = $ua->{postparams}->{'language'} || "eng";
        $seth->set($webdata{userData}->{user}, "EditLanguage", \$lang);
    } elsif($mode eq "change") {
        my @keys = @{$ua->{postparams}->{'originaltext'}};
        my @delkeys = @{$ua->{postparams}->{'delkeys'}};
        my $upsth = $dbh->prepare_cached("SELECT merge_translation(?, ?, ?)")
                or croak($dbh->errstr);
        my $delsth = $dbh->prepare_cached("DELETE FROM translate_keys WHERE originaltext = ?")
                or croak($dbh->errstr);
        foreach my $key (@keys) {
            my $translation = $ua->{postparams}->{"translate_$key"} || '';

            $translation =~ s/\r//g;
            $translation =~ s/\n{3,}/\n\n/g;
            if($upsth->execute($key, $lang, $translation)) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
        }

        foreach my $key (@delkeys) {
            next if(!defined($key) || $key eq '');
            if($delsth->execute($key)) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
        }
        tr_reload();
    }

    $webdata{EditLanguage} = $lang;

    my @trLines;
    my $selsth = $dbh->prepare_cached("SELECT k.originaltext, t.translation
                                   FROM translate_keys k
                                   LEFT OUTER JOIN translate_translations t
                                    ON (k.originaltext = t.originaltext)
                                    AND t.lang = ?
                                    ORDER BY originaltext")
            or croak($dbh->errstr);
    $selsth->execute($lang) or croak($dbh->errstr);
    while((my $line = $selsth->fetchrow_hashref)) {
        if(!defined($line->{translation})) {
            $line->{translation} = '';
        }
        push @trLines, $line;
    }
    $selsth->finish;
    $webdata{trLines} = \@trLines;

    my $template = $self->{server}->{modules}->{templates}->get("translate_translate", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_export {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my @AvailLangs;
    my $sth = $dbh->prepare_cached("SELECT * FROM translate_languages
                                   ORDER BY lang")
            or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);
    while((my $lang = $sth->fetchrow_hashref)) {
        push @AvailLangs, $lang;
    }
    $sth->finish;

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{export}->{pagetitle},
        webpath         =>  $self->{export}->{webpath},
        AvailLanguages  =>  \@AvailLangs,
        showads => $self->{showads},
    );


    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "import") {
        if(defined($ua->{postparams}->{filename})) {
            my $fname = $ua->{postparams}->{filename};
            if(defined($ua->{files}->{$fname})) {
                tr_import($ua->{files}->{$fname}->{data});
            }
        }
    }

    $webdata{ExportFile} = $self->{exportfile}->{webpath}. "/EXPORT" . int(rand($TESTRANGE) + 1) . "." . int(rand($TESTRANGE) + 1) . ".txt";

    my $template = $self->{server}->{modules}->{templates}->get("translate_export", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


sub get_file {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $exp = tr_export();

    return (status  =>  404) unless $exp;
    return (status  =>  200,
            type    => "text/plain",
            "Content-Disposition" => "attachment; filename=\"translations_export.txt\";",
            data    => $exp);
}


sub prerender {
    my ($self, $webdata) = @_;

    # Unless the user is logged in, we don't have set a user selected Language, use English
    if(!defined($webdata->{userData}) ||
              !defined($webdata->{userData}->{user}) ||
              $webdata->{userData}->{user} eq "") {
              $webdata->{UserLanguage} = "eng";
              PageCamel::Web::TT::Translate->setLang("eng");
    }

    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my ($ok, $langname) = $seth->get($webdata->{userData}->{user}, "UserLanguage");

    my $lang = "eng"; # Use english as default
    if(defined($langname)) {
        $langname = dbderef($langname);
    }
    if($ok && defined($langname) && $langname ne "") {
        # Now, we have to check if this theme is still available

        # FIXME: Check if language still available!
        if(tr_checklang($langname)) {
            $lang = $langname;
        }

    }

    $webdata->{UserLanguage} = $lang;
    PageCamel::Web::TT::Translate->setLang($lang);

    # Remember for postfilter
    $self->{lastuserlanguage} = $lang;

    return;
}

sub postfilter {
    my ($self, $ua, $header, $result) = @_;

    return if(!defined($self->{lastuserlanguage}));

    ### FIXME: This should come from the translation database
    if($self->{lastuserlanguage} eq "eng") {
        $result->{"Content-Language"} = "en";
    } elsif($self->{lastuserlanguage} eq "ger") {
        $result->{"Content-Language"} = "de";
    }

    return;
}

# Translation
sub check_translationupdates {
    my ($self) = @_;

    tr_checkreload();

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Translate -

=head1 SYNOPSIS

  use PageCamel::Web::Translate;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get_settings



=head2 get_languages



=head2 get_translations



=head2 get_export



=head2 get_file



=head2 prerender



=head2 postfilter



=head2 check_translationupdates



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
