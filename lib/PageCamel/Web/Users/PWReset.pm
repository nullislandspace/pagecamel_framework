package PageCamel::Web::Users::PWReset;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use Digest::MD5 qw(md5_hex);
use Digest::SHA1 qw(sha1_hex);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::Strings qw(stripString);

use Readonly;


Readonly my $TESTRANGE => 1_000_000;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(!defined($self->{extrainfo})) {
        $self->{extrainfo} = '';
    }

    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{webpath}, "get_pwreset");
    $self->register_public_url($self->{webpath});
    return;
}

sub reload {
    my ($self) = @_;

    # Nothing to do

    return;
}

sub get_pwreset {
    my ($self, $ua) = @_;


    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $pwresetid = $ua->{url};
    my $remove = $self->{webpath};
    $pwresetid =~ s/^$remove//;
    $pwresetid =~ s/^\///;
    $pwresetid =~ s/\/$//;
    $pwresetid = stripString($pwresetid);
    if($pwresetid ne '' || $mode eq 'execute') {
        return $self->get_execute($ua, $pwresetid);
    }

    return $self->get_request($ua);
}


sub get_request {
    my ($self, $ua) = @_;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $self->{webpath},
        ExtraInfo   =>  $self->{extrainfo},
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    # Verify user/password combination
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $mailh = $self->{server}->{modules}->{$self->{sendmail}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    if($mode eq 'request') {
        my $user = $ua->{postparams}->{'username'} || '';
        my $email = $ua->{postparams}->{'email'} || '';
        $user = lc $user;
        $email = lc $email;
        if($user eq '' || $email eq '') {
            $webdata{statustext} = 'You must fill on all fields!';
            $webdata{statuscolor} = 'errortext';
            goto showform;
        }

        my $selsth = $dbh->prepare_cached("SELECT count(*) FROM users
                                          WHERE username = ?
                                          AND lower(email_addr) = ?")
                or croak($dbh->errstr);

        my $delsth= $dbh->prepare_cached("DELETE FROM users_passwordreset WHERE username = ?")
                or croak($dbh->errstr);

        my $insth = $dbh->prepare_cached("INSERT INTO users_passwordreset
                                         (username, resetkey) VALUES (?, ?)")
                or croak($dbh->errstr);

        $selsth->execute($user, $email) or croak($dbh->errstr);
        my ($count) = $selsth->fetchrow_array;
        $selsth->finish;

        if(!$count) {
            $webdata{statustext} = 'Unknown user or email address does not match!';
            $webdata{statuscolor} = 'errortext';
            goto showform;
        }

        my $resetkey = PageCamel::Helpers::Passwords::gen_textsalt();
        $delsth->execute($user) or croak($dbh->errstr);
        $insth->execute($user, $resetkey) or croak($dbh->errstr);
        $dbh->commit;

        # SEND MAIL
        my @recievers = ($email);

        my $exthostname = $ua->{headers}->{'Host'};
        if(defined($self->{forcehost}) && $self->{forcehost} ne '') {
            $exthostname = $self->{forcehost};
        }

        # Construct the socket path from WSPath
        my $url = 'http';
        if($self->{usessl}) {
            $url = 'https';
        }
        $url .= '://' . $exthostname;

        $url .= $self->{webpath} . '/' . $resetkey;

        my $body = <<"END";
Dear PageCamel-User,

Someone (hopefully you) has requested a password reset for your
account.

Please use the following link to reset your password:

$url

This link is only valid for one hour.

If you do nothing, your password will not change.


Have a nice day!
END

        my $subject = $webdata{EmailPrefix} . " Password reset requested";
        #my ($self, $recievers, $subject, $message, $contenttype) = @_;
        $mailh->sendMail(\@recievers, $subject, $body, 'text/plain');

        $dbh->commit;
        $webdata{statuscolor} = 'oktext';
        $reph->auditlog($self->{modname}, "Password reset requested for $user", $webdata{userData}->{user});
    }


    showform:
    $dbh->rollback;
    my $template = $self->{server}->{modules}->{templates}->get("users/pwreset_request", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


sub get_execute {
    my ($self, $ua, $resetkey) = @_;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $ua->{url},
        resetkey    => $resetkey,
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    # clean old resetkeys
    my $oldsth = $dbh->prepare_cached("DELETE FROM users_passwordreset
                                      WHERE valid_until < now()")
            or croak($dbh->errstr);
    if($oldsth->execute) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }

    # Verify resetkey
    my $selsth = $dbh->prepare_cached("SELECT username FROM users_passwordreset
                                      WHERE resetkey = ?")
            or croak($dbh->errstr);
    $selsth->execute($resetkey) or croak($dbh->errstr);
    my ($user) = $selsth->fetchrow_array;
    $selsth->finish;

    if(!defined($user) || $user eq '') {
        $dbh->rollback;
        return(status => 404);
    }

    $webdata{username} = $user;

    if($mode eq 'execute') {
        my $pwnew1 = $ua->{postparams}->{'pwnew1'} || '';
        my $pwnew2 = $ua->{postparams}->{'pwnew2'} || '';
        if($pwnew1 ne $pwnew2) {
            $webdata{statustext} = "New Passwords do not match!";
            $webdata{statuscolor} = "errortext";
        } else {
            my $delsth = $dbh->prepare_cached("DELETE FROM users_passwordreset
                                              WHERE resetkey = ?")
                    or croak($dbh->errstr);

            if(update_password($dbh, $user, $pwnew1) && $delsth->execute($resetkey)) {
                $dbh->commit;
                $webdata{statuscolor} = "oktext";
                $reph->auditlog($self->{modname}, "Password reset complete for $user", $webdata{userData}->{user});
            } else {
                $dbh->rollback;
                $webdata{statustext} = "Internal error, please try again!";
                $webdata{statuscolor} = "errortext";
            }
        }
        $webdata{statuscolor} = 'oktext';
    }


    showform:
    $dbh->rollback;
    my $template = $self->{server}->{modules}->{templates}->get("users/pwreset_execute", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

1;
__END__

=head1 NAME

PageCamel::Web::Users::PWReset -

=head1 SYNOPSIS

  use PageCamel::Web::Users::PWReset;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 get_pwreset



=head2 get_request



=head2 get_execute



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
