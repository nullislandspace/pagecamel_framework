package PageCamel::Web::Users::PWChange;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use Digest::MD5 qw(md5_hex);
use Digest::SHA1 qw(sha1_hex);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Passwords;

use Readonly;


Readonly my $TESTRANGE => 1_000_000;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{webpath}, "get_pwchange");
    return;
}

sub reload {
    my ($self) = @_;

    # Nothing to do

    return;
}

sub get_pwchange {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $auth = $self->{server}->{modules}->{$self->{authentification}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        pwold    =>  $ua->{postparams}->{'pwold'} || '',
        pwnew1    =>  $ua->{postparams}->{'pwnew1'} || '',
        pwnew2    =>  $ua->{postparams}->{'pwnew1'} || '',
        PostLink    =>  $self->{webpath},
        ResetLink    =>  $self->{resetpath},
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "changepw") {
        if($webdata{pwold} ne "" && $webdata{pwnew1} ne "" && $webdata{pwnew2} ne "") {
            if($webdata{pwnew1} ne $webdata{pwnew2}) {
                $webdata{statustext} = "New Passwords do not match!";
                $webdata{statuscolor} = "errortext";
                $webdata{FocusOnField} = "pwnew1";
            } else {
                my $oldpwok = verify_password($dbh, $webdata{userData}->{user}, $webdata{pwold});

                if(!$oldpwok) {
                    $webdata{statustext} = "Old password incorrect!";
                    $webdata{statuscolor} = "errortext";
                    $webdata{FocusOnField} = "pwold";
                    $dbh->rollback;
                } else {
                    if(update_password($dbh, $webdata{userData}->{user}, $webdata{pwnew1})) {
                        $webdata{statustext} = "Password changed!";
                        $webdata{statuscolor} = "oktext";
                        $webdata{userData}->{require_password_change} = 0;
                        $dbh->commit;
                        $auth->password_changed($ua);
                        $reph->auditlog($self->{modname}, "Password changed by user", $webdata{userData}->{user});
                    } else {
                        $webdata{statustext} = "Password change failed!";
                        $webdata{statuscolor} = "errortext";
                        $webdata{FocusOnField} = "pwold";
                        $dbh->rollback;
                    }
                }

            }
        } else {
            $webdata{statustext} = "Incomplete form!";
            $webdata{statuscolor} = "errortext";
        }
    }

    my $template = $self->{server}->{modules}->{templates}->get("users/pwchange", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}

1;
__END__

=head1 NAME

PageCamel::Web::Users::PWChange -

=head1 SYNOPSIS

  use PageCamel::Web::Users::PWChange;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 get_pwchange



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
