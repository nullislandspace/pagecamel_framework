package PageCamel::Helpers::Passwords;
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

# PAGECAMEL  (C) 2008-2019 Rene Schickbauer
# Developed under Artistic license

use Digest;
use Data::Entropy::Algorithms qw(rand_bits);
use MIME::Base64;
use PageCamel::Helpers::DateStrings;
use Time::HiRes qw[sleep];

use base qw(Exporter);
our @EXPORT= qw(update_password verify_password gen_textsalt); ## no critic (Modules::ProhibitAutomaticExportation)

sub gen_textsalt {
    my $saltbase = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

    my $salt = '';
    my $count = int(rand(20))+20;
    for(1..$count) {
        my $pos = int(rand(length($saltbase)));
        $salt .= substr($saltbase, $pos, 1);
    }

    return $salt;
}


sub update_password {
    my ($dbh, $username, $password) = @_;

    # While pre- and postsalt does not much for complexity, it helps preventing rainbow tables attacks.
    # I know, the bcrypt salt already does that, in case of a general bcrypt breach, this should
    # make it a bit more difficult.
    my $presalt = gen_textsalt();
    my $postsalt = gen_textsalt();
    my $bsalt = rand_bits(16*8); # 16 octets (16 bytes at 8 bits)
    #print length($bsalt) . "\n";
    #print $bsalt . "\n";
    my $bsalt_b64 = encode_base64($bsalt, '');
    #my $cost = getCurrentYear() - 2000 + 3;
    my $cost = 5; # FIXME: Make SystemSetting

    my $bcrypt = Digest->new('Bcrypt');
    $bcrypt->cost($cost);
    $bcrypt->salt($bsalt);

    $bcrypt->add($presalt);
    $bcrypt->add($password);
    $bcrypt->add($postsalt);

    my $pwsalted = $bcrypt->b64digest;

    my $upsth = $dbh->prepare("UPDATE users
                              SET password_prefix = ?,
                              password_postfix = ?,
                              password_bcrypt_hash = ?,
                              password_bcrypt_salt = ?,
                              password_bcrypt_cost = ?,
                              next_password_change = now() + interval '12 weeks'
                              WHERE username = ?")
        or croak($dbh->errstr);
    if(!$upsth->execute($presalt, $postsalt, $pwsalted, $bsalt_b64, $cost, $username)) {
        return 0;
    }

    return 1;
}

sub verify_password {
    my ($dbh, $username, $password) = @_;

    # Pre-initialize for random pw calculations in case no user is found (there should be no
    # measurable time difference for unknown users. This will make it harder to guess is a username
    # exists)
    my $presalt = gen_textsalt();
    my $postsalt = gen_textsalt();
    my $bsalt = rand_bits(16*8); # 16 octets (16 bytes at 8 bits)
    #my $cost = getCurrentYear() - 2000 + 3;
    my $cost = 16; # FIXME: Make SystemSetting
    my $pwhash = '';
    my $isLocked = 0;


    my $selsth = $dbh->prepare("SELECT account_locked,
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
                              ")
        or croak($dbh->errstr);
    if(!$selsth->execute($username)) {
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

    # sleep for a random amount of time, up to a second fo further limit
    # bruteforcing and "unknown user" detection
    my $sleeptime = int(rand(900) + 100) / 1000;
    sleep($sleeptime);

    if($isLocked || !$found || $pwsalted ne $pwhash) {
        return 0;
    }

    return 1;
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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
