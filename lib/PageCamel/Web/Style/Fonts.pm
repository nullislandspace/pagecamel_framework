package PageCamel::Web::Style::Fonts;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use Digest::SHA1  qw(sha1_hex);

my %fontfamilies = (
    Georgia => 'Georgia, serif',
    TimesNewRoman => '\'Times New Roman\', Times, serif',
    Arial => 'Arial, Helvetica, sans-serif',
    ArialBlack => '\'Arial Black\', Gadget, sans-serif',
    ComicSans => '\'Comic Sans MS\', cursive, sans-serif',
    Impact => 'Impact, Charcoal, sans-serif',
    Trebuchet => '\'Trebuchet MS\', Helvetica, sans-serif',
    Verdana => 'Verdana, Geneva, sans-serif',
    Courier => '\'Courier New\', Courier, monospace',
    Console => '\'Lucida Console\', Monaco, monospace',
    Clipboard => 'herrvonmuellerhoff',
    Portcullion => 'portcullion',
    SourceCode => 'sourcecodepro',
    OpenDyslexic => 'opendyslexic',
    Anquietas => 'anquietas',
);
my @fontnames = sort keys %fontfamilies;

my @fontlist;
foreach my $key (sort keys %fontfamilies) {
    push @fontlist, {
                        name => $key,
                        style => $fontfamilies{$key}
                    };
}

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(!defined($self->{csspath})) {
        croak("Undefined 'csspath' setting");
    }

    return $self;
}

sub reload {
    my ($self) = shift;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createEnum(modulename => $self->{modname},
                        settingname => "default_font",
                        settingvalue => $self->{default_font},
                        description => 'Default Font',
                        enum_values => \@fontnames,
                        processinghints => [
                        'type=dropdown',
        ])
        or croak("Failed to create setting default_font!");

    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get");
    $self->register_webpath($self->{csspath}, "get_css");
    $self->register_prerender("prerender");
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        AvailThemes     =>  $self->{Themes},
        FontFamilies    => \@fontlist,
        showads => $self->{showads},
    );

    # We don't actually set the Theme into webdata here, this is done during the prerender stage.
    # Also, we don't handle the "select a default theme if non set" case, TemplateCache falls back to
    # its own default theme anyway
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "setvalue") {

        my $fontfamily = $ua->{postparams}->{'fontfamily'} || "";
        if($fontfamily ne "") {
            $seth->set($webdata{userData}->{user}, "UserFont", \$fontfamily);
        }
    }


    my $template = $self->{server}->{modules}->{templates}->get("style/fonts", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub prerender {
    my ($self, $webdata) = @_;

    my $userFont = $self->{default_font};

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    {
        my ($ok, $data) = $sysh->get($self->{modname}, "default_font");
        if($ok) {
            $userFont = $data->{settingvalue};
        }
    }

    # Logged in user?
    if(defined($webdata->{userData}) &&
              defined($webdata->{userData}->{user}) &&
              $webdata->{userData}->{user} ne "") {
        my $seth = $self->{server}->{modules}->{$self->{usersettings}};
        {
            my ($uok, $tmpFont) = $seth->get($webdata->{userData}->{user}, "UserFont");
            if($uok && defined($tmpFont)) {
                my $dref = dbderef($tmpFont);

                # Check if Font is still available
                foreach my $temp (@fontnames) {
                    if($dref eq $temp) {
                        $userFont = $dref;
                        last;
                    }
                }
            }
        }

        if($webdata->{userData}->{user} eq 'guest' &&
            $webdata->{IsAprilFoolsDay}) {
            $userFont = 'Anquietas';
        }
    }


    $webdata->{UIThemeFont} = $userFont;
    $webdata->{UIThemeFontFace} = $fontfamilies{$userFont};
    
    $webdata->{UIThemeFontCSSFile} = $self->{csspath} . '/' . $userFont . '.css';

    return;
}

sub get_css {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $userFont;
    if($webpath =~ /\/([a-zA-Z0-9]+?)\.css/) {
        $userFont = $1;
    } else {
        return (status => 404);
    }
    
    if(!defined($fontfamilies{$userFont})) {
        return (status => 404);
    }
    
    my $data = "* {\n" .
               "    font-family: " . $fontfamilies{$userFont} . ";\n" .
               "}\n";
    
    my $etag = sha1_hex($data);

    return (status  =>  200,
            type    => "text/css",
            expires         => '+14d',
            cache_control   =>  'max-age=1209600',
            ETag    => $etag,
            data    => $data);    
    
}


1;
__END__

=head1 NAME

PageCamel::Web::Fonts -

=head1 SYNOPSIS

  use PageCamel::Web::Fonts;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 prerender



=head2 get_defaultwebdata



=head2 redirect_themed_images



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
