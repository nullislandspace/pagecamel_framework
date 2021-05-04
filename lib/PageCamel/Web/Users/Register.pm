package PageCamel::Web::Users::Register;
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
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use Digest::MD5 qw(md5_hex);
use Digest::SHA1 qw(sha1_hex);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::Strings qw(stripString webSafeString);

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

    $self->register_webpath($self->{webpath}, "get_register");
    $self->register_public_url($self->{webpath});
    $self->register_defaultwebdata("defaultwebdata");
    return;
}

sub reload {
    my ($self) = @_;

    # Nothing to do

    return;
}

sub get_register {
    my ($self, $ua) = @_;


    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $pwresetid = $ua->{url};

    # Reroute Ajax calls
    if($pwresetid eq $self->{webpath} . '/checkuser') {
        return $self->get_checkuser($ua);
    } elsif($pwresetid eq $self->{webpath} . '/checkemail') {
        return $self->get_checkemail($ua);
    }

    # Check for registerkey. If found, call the "execute" form (stage 2),
    # else "register" (stage 1)
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

sub get_checkuser {
    my ($self, $ua) = @_;

    my $user = $ua->{postparams}->{'username'} || '';

    my $state = $self->validateUsername($user);

    return (status  => 200,
            type    => 'text/plain',
            data    => $state,
            );
}

sub validateUsername {
    my ($self, $user) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if($user ne lc($user) || $user !~ /^[a-z0-9]+$/) {
        return "Only lower case characters and numbers allowed";
    }

    if(length($user) < 4) {
        return "Minimum length: 4 characters";
    }

    if(contains($user, $self->{reservednames}->{item})) {
        return "User already exists";
    }

    my $countsth = $dbh->prepare_cached("SELECT count (username) as userexists FROM (
                                            SELECT username FROM users WHERE username = ?
                                            union
                                            SELECT username FROM users_register WHERE username = ?
                                        ) AS foo")
            or croak($dbh->errstr);
    $countsth->execute($user, $user) or croak($dbh->errstr);
    my ($count) = $countsth->fetchrow_array;
    $countsth->finish;
    $dbh->rollback;

    if($count) {
        return "User already exists";
    }

    return "OK";
}

sub get_checkemail {
    my ($self, $ua) = @_;

    my $email = $ua->{postparams}->{'email'} || '';

    my $state = $self->validateEmail($email);

    return (status  => 200,
            type    => 'text/plain',
            data    => $state,
            );
}

sub validateEmail {
    my ($self, $email) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $safeemail = webSafeString($email);
    if($email ne $safeemail) {
        return "Illegal characters in email address";
    }

    if($email ne lc($email)) {
        return "Only lower case characters allowed";
    }

    if($email !~ /\@/) {
        return "Incomplete";
    }

    if(length($email) < 6) {
        return "Minimum length: 6 characters";
    }

    my $countsth = $dbh->prepare_cached("SELECT count (email_addr) as userexists FROM (
                                            SELECT email_addr FROM users WHERE email_addr = ?
                                            union
                                            SELECT email_addr FROM users_register WHERE email_addr = ?
                                        ) AS foo")
            or croak($dbh->errstr);
    $countsth->execute($email, $email) or croak($dbh->errstr);
    my ($count) = $countsth->fetchrow_array;
    $countsth->finish;
    $dbh->rollback;

    if($count) {
        return "Email address already registered";
    }

    return "OK";
}

sub get_request {
    my ($self, $ua) = @_;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $self->{webpath},
        userpath    =>  $self->{webpath} . '/checkuser',
        emailpath   =>  $self->{webpath} . '/checkemail',
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    # Verify user/password combination
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $mailh = $self->{server}->{modules}->{$self->{sendmail}};

    if($mode eq 'request') {
        my $user = $ua->{postparams}->{'username'} || '';
        my $email = $ua->{postparams}->{'email'} || '';
        my $firstname = $ua->{postparams}->{'first_name'} || '';
        my $lastname = $ua->{postparams}->{'last_name'} || '';

        $webdata{username} = $user;
        $webdata{email} = $email;
        $webdata{firstname} = $firstname;
        $webdata{lastname} = $lastname;
        $firstname = webSafeString($firstname);
        $lastname = webSafeString($lastname);

        $email = lc $email;
        if($user eq '' || $email eq '' || $firstname eq '' || $lastname eq '') {
            $webdata{statustext} = 'You must fill on all fields!';
            $webdata{statuscolor} = 'errortext';
            goto showform;
        }

        my $uservalid = $self->validateUsername($user);
        my $emailvalid = $self->validateEmail($email);
        if($uservalid ne 'OK') {
            $webdata{statustext} = 'Invalid username';
            $webdata{statuscolor} = 'errortext';
            goto showform;
        }
        if($emailvalid ne 'OK') {
            $webdata{statustext} = 'Invalid email address';
            $webdata{statuscolor} = 'errortext';
            goto showform;
        }

        my $delsth= $dbh->prepare_cached("DELETE FROM users_register WHERE valid_until < now()")
                or croak($dbh->errstr);
        $delsth->execute or croak($dbh->errstr);

        my $insth = $dbh->prepare_cached("INSERT INTO users_register
                                         (username, registerkey, first_name, last_name, email_addr) VALUES (?, ?, ?, ?, ?)")
                or croak($dbh->errstr);


        my $registerkey = PageCamel::Helpers::Passwords::gen_textsalt();
        $insth->execute($user, $registerkey, $firstname, $lastname, $email) or croak($dbh->errstr);
        $dbh->commit;

        # SEND MAIL
        my @recievers = ($email);

        my $exthostname = $ua->{headers}->{'Host'};

        # Construct the socket path from WSPath
        my $url = 'http';
        if($self->{usessl}) {
            $url = 'https';
        }
        $url .= '://' . $exthostname;

        $url .= $self->{webpath} . '/' . $registerkey;

        print STDERR "URL: $url\n";

        my $body = <<"END";
Dear PageCamel-User,

Someone (hopefully you) has registered with your email address. To
complete the registration and set your password, please use the
following link:

$url

This link is only valid for one hour. If you do not proceed with the
registration, it will be canceled automatically.

Have a nice day!
END

        my $subject = $webdata{EmailPrefix} . " User registration requested";
        #my ($self, $recievers, $subject, $message, $contenttype) = @_;
        $mailh->sendMail(\@recievers, $subject, $body, 'text/plain');

        $dbh->commit;
        $webdata{statuscolor} = 'oktext';
    }


    showform:
    $dbh->rollback;
    my $template = $self->{server}->{modules}->{templates}->get("users/register_request", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


sub get_execute {
    my ($self, $ua, $registerkey) = @_;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $ua->{url},
        registerkey    => $registerkey,
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # clean old registerkeys
    my $oldsth = $dbh->prepare_cached("DELETE FROM users_register
                                      WHERE valid_until < now()")
            or croak($dbh->errstr);
    if($oldsth->execute) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }

    # Verify registerkey
    my $selsth = $dbh->prepare_cached("SELECT username, first_name, last_name, email_addr FROM users_register
                                      WHERE registerkey = ?")
            or croak($dbh->errstr);
    $selsth->execute($registerkey) or croak($dbh->errstr);
    my ($user, $firstname, $lastname, $email) = $selsth->fetchrow_array;
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
            my $delsth = $dbh->prepare_cached("DELETE FROM users_register
                                              WHERE registerkey = ?")
                    or croak($dbh->errstr);

            my $createsth = $dbh->prepare_cached("INSERT INTO users (username, email_addr, first_name, last_name, company_name, next_password_change)
                                                 VALUES (?, ?, ?, ?, ?, now() + interval '3 months')")
                    or croak($dbh->errstr);

            if($createsth->execute($user, $email, $firstname, $lastname, $self->{company}) &&
                    update_password($dbh, $user, $pwnew1) &&
                    $delsth->execute($registerkey) && $self->addUserRights($user)) {
                $dbh->commit;
                $webdata{statuscolor} = "oktext";
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
    my $template = $self->{server}->{modules}->{templates}->get("users/register_execute", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub addUserRights {
    my ($self, $user) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $insth = $dbh->prepare_cached("INSERT INTO users_permissions (username, permission_name, has_access)
                                     VALUES (?, ?, true)")
            or croak($dbh->errstr);

    foreach my $permname (@{$self->{permissions}->{item}}) {
        if(!$insth->execute($user, $permname)) {
            return 0;
        }
    }

    return 1;
}

sub defaultwebdata {
    my ($self, $webdata) = @_;

    # Just allow the "register" menu item
    $webdata->{canRegisterUsers} = 1;
    return;
}


1;
__END__

=head1 NAME

PageCamel::Web::Users::Register -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Register;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 get_register



=head2 get_checkuser



=head2 validateUsername



=head2 get_checkemail



=head2 validateEmail



=head2 get_request



=head2 get_execute



=head2 addUserRights



=head2 defaultwebdata



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
