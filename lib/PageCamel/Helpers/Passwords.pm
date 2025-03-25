package PageCamel::Helpers::Passwords;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license

use Digest;
use Data::Entropy::Algorithms qw(rand_bits);
use MIME::Base64;
use PageCamel::Helpers::DateStrings;
use Time::HiRes qw[sleep];

sub new($proto, $config) {
    my $class = ref($proto) || $proto;

    my $self = bless $config, $class;

    my $ok = 1;
    # Required settings
    foreach my $key (qw[sysh dbh reph]) {
        if(!defined($self->{$key})) {
            print STDERR "Passwords.pm missing setting $key\n";
            $ok=0;
        }
    }
    if(!$ok) {
        croak("Failed to initialize Helpers::Passwords.pm");
    }

    return $self;
}


sub gen_textsalt($self) {

    my $saltbase = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

    my $salt = '';
    my $count = int(rand(20))+20;
    for(1..$count) {
        my $pos = int(rand(length($saltbase)));
        $salt .= substr($saltbase, $pos, 1);
    }

    return $salt;
}


sub update_password($self, $username, $password) {


    # While pre- and postsalt does not much for complexity, it helps preventing rainbow tables attacks.
    # I know, the bcrypt salt already does that, in case of a general bcrypt breach, this should
    # make it a bit more difficult.
    my $presalt = $self->gen_textsalt();
    my $postsalt = $self->gen_textsalt();
    my $bsalt = rand_bits(16*8); # 16 octets (16 bytes at 8 bits)
    my $bsalt_b64 = encode_base64($bsalt, '');

    my $settings = $self->getSettings();
    my $cost = $settings->{password_bcryptcost};

    my $bcrypt = Digest->new('Bcrypt');
    $bcrypt->cost($cost);
    $bcrypt->salt($bsalt);

    $bcrypt->add($presalt);
    $bcrypt->add($password);
    $bcrypt->add($postsalt);

    my $pwsalted = $bcrypt->b64digest;

    my $upsth = $self->{dbh}->prepare("UPDATE users
                              SET password_prefix = ?,
                              password_postfix = ?,
                              password_bcrypt_hash = ?,
                              password_bcrypt_salt = ?,
                              password_bcrypt_cost = ?,
                              force_password_change = false
                              WHERE username = ?")
        or croak($self->{dbh}->errstr);
    if(!$upsth->execute($presalt, $postsalt, $pwsalted, $bsalt_b64, $cost, $username)) {
        $self->{reph}->debuglog($self->{dbh}->errstr);
        return 0;
    }

    return 1;
}

sub verify_password($self, $username, $password) {

    # Pre-initialize for random pw calculations in case no user is found (there should be no
    # measurable time difference for unknown users. This will make it harder to guess is a username
    # exists)
    my $presalt = $self->gen_textsalt();
    my $postsalt = $self->gen_textsalt();
    my $bsalt = rand_bits(16*8); # 16 octets (16 bytes at 8 bits)

    my $settings = $self->getSettings();
    my $cost = $settings->{password_bcryptcost};
    my $pwhash = '';
    my $isLocked = 0;


    my $selsth = $self->{dbh}->prepare("SELECT account_locked,
                              password_prefix,
                              password_postfix,
                              password_bcrypt_hash,
                              password_bcrypt_salt,
                              password_bcrypt_cost
                              FROM users
                              WHERE username = ?
                              AND password_prefix != ''
                              AND password_postfix != ''
                              AND password_bcrypt_hash != ''
                              AND password_bcrypt_salt != ''
                              LIMIT 1")
        or croak($self->{dbh}->errstr);
    if(!$selsth->execute($username)) {
        $self->{reph}->debuglog($self->{dbh}->errstr);
        return 0;
    }

    my $found = 0;
    while((my $line = $selsth->fetchrow_arrayref)) {
        my $bsalt_b64;
        ($isLocked, $presalt, $postsalt, $pwhash, $bsalt_b64, $cost) = @{$line};
        $bsalt = decode_base64($bsalt_b64);
        $found = 1;
        last;
    }
    $selsth->finish;


    my $bcrypt = Digest->new('Bcrypt');
    $bcrypt->cost($cost);
    $bcrypt->salt($bsalt);

    $bcrypt->add($presalt);
    $bcrypt->add($password);
    $bcrypt->add($postsalt);

    my $pwsalted = $bcrypt->b64digest;

    # sleep for a random amount of time, up to a third of second fo further limit
    # bruteforcing and "unknown user" detection
    my $sleeptime = int(rand(200) + 100) / 1000;
    sleep($sleeptime);

    if($isLocked || !$found || $pwsalted ne $pwhash) {
        return 0;
    }

    return 1;
}

sub verify_appkey($self, $username, $appkey) {

    my $isLocked = 0;

    my $selsth = $self->{dbh}->prepare("SELECT account_locked
                              FROM users
                              WHERE username = ?
                              AND appkey = ?
                              LIMIT 1")
        or croak($self->{dbh}->errstr);
    if(!$selsth->execute($username, $appkey)) {
        $self->{reph}->debuglog($self->{dbh}->errstr);
        return 0;
    }

    my $found = 0;
    while((my $line = $selsth->fetchrow_arrayref)) {
        ($isLocked) = @{$line};
        $found = 1;
        last;
    }
    $selsth->finish;

    # sleep for a random amount of time, up to a third of second fo further limit
    # bruteforcing and "unknown user" detection
    my $sleeptime = int(rand(200) + 100) / 1000;
    sleep($sleeptime);

    if($isLocked || !$found) {
        return 0;
    }

    return 1;
}

sub getSettings($self) {

    my $sysh = $self->{sysh};
    my $dbh = $self->{dbh};
    my $reph = $self->{reph};

    # Defaults
    my %settings = (
        allow_keep_logged_in => 0,
        standard_valid_time => '10 minutes',
        keeploggedin_valid_time => '90 days',
    );

    foreach my $key (qw[password_bcryptcost]) {
        my ($ok, $sysval) = $sysh->get('security', $key);
        if($ok) {
            $settings{$key} = $sysval->{settingvalue};
        }
    }

    return \%settings;
}


1;
__END__

=head1 NAME

PageCamel::Helpers::Passwords - handle passwords in a PageCamel database

=head1 SYNOPSIS

  use PageCamel::Helpers::Passwords;

=head1 DESCRIPTION

This central module does all the actual password handling for PageCamel projects. This way, changing the hashing algorithm or adapting its strengh (vs time) can be done in one central place in the code.

=head2 gen_textsalt

Randomly generate a salt used for hashing passwords.

=head2 update_password

Update a password in the database (also generates a new salt).

=head2 verify_password

Verify correctness of a password.

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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
