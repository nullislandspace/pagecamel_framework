package PageCamel::Web::SendMail;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::DateStrings;
use MIME::QuotedPrint;
use MIME::Base64;
use Email::Simple;
use PageCamel::Helpers::DBSerialize;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);

use Email::Simple;


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get");
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};

    my @recievers;
    if(defined($ua->{postparams}->{"reciever"})) {
        if(ref $ua->{postparams}->{"reciever"} eq 'ARRAY') {
            @recievers = @{$ua->{postparams}->{"reciever"}};
        } else {
            push @recievers, $ua->{postparams}->{"reciever"};
        }
    }
    my $subject = $ua->{postparams}->{"subject"} || "";
    my $mailtext = $ua->{postparams}->{"mailtext"} || "";
    my $mustupdate = $ua->{postparams}->{"submitform"} || "0";

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        webpath        =>  $self->{admin}->{webpath},
        subject     =>  $subject,
        mailtext   =>  $mailtext,
    );

    my %recieverchecked;
    if($mustupdate) {
        my $statustext = "Can't spool message!";

        my @realrecievers;

        foreach my $reciever (@recievers) {
            if($reciever ne '') {
                push @realrecievers, $reciever;
                $recieverchecked{$reciever} = 1;
            }
        }

        my $ok = $self->sendMail(\@realrecievers, $subject, $mailtext, "text/plain");

        if($ok) {
            $statustext = "All spooled!";
            $webdata{statuscolor} = "oktext";
        } else {
            $webdata{statuscolor} = "errortext";
        }

        $webdata{statustext} = $statustext;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sth = $dbh->prepare_cached("SELECT username, email_addr
                                      FROM users
                                      WHERE email_addr != ''
                                      ORDER BY username")
                or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);
    my @users;
    while((my $user = $sth->fetchrow_hashref)) {
        if($recieverchecked{$user->{email_addr}}) {
            $user->{checked} = 1;
        } else {
            $user->{checked} = 0;
        }
        push @users, $user;
    }
    $webdata{users} = \@users;


    my $template = $th->get("sendmail", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


sub sendMail {
    my ($self, $recievers, $subject, $message, $contenttype) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $sth = $dbh->prepare_cached("INSERT INTO mail_data
                                   (title, fullmail, sender, recievers, spooled_by, trusted_sender)
                                   VALUES (?,?,?,?,?,true)")
                or croak($dbh->errstr);

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
    );

    my $spooler = $self->{APPNAME} . '/';
    if(defined($webdata{userData}->{user})) {
        $spooler .= $webdata{userData}->{user}
    } else {
        $spooler .= 'guest';
    }

    my $email = Email::Simple->create(
        header  => [
            From    => '',
            To      => join(', ', @{$recievers}),
            Subject => $subject,
            'Content-Type' => $contenttype,
        ],
        body    => $message,
    );
    my $fullmail = $email->as_string();
    $fullmail = dbfreeze($fullmail);

    if($sth->execute($subject, $fullmail, $self->{sender}, $recievers, $spooler)) {
        $dbh->commit;
        return 1;
    }

    $dbh->rollback;
    return 0;
}

sub sendToPrinter{
    my ($self, $sender, $reciever, $subject, $fname, $data) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $boundary = "====" . time() . "====";
    my $contenttype = "multipart/mixed; boundary=\"$boundary\"";
    my $message = "";

    my $fdata = encode_base64($data);
    my $shortname = $fname;
    $shortname =~ s/^.*\///go;
    $shortname =~ s/^.*\\//go;
    my $longtype = "application/pdf";

    $message .= "--$boundary\n" .
                "Content-Type: application/zip; name=\"$shortname\"\n" .
                "Content-Transfer-Encoding: base64\n" .
                "Content-Disposition: attachment; filename=\"$shortname\"\n" .
                "\n" .
                "$fdata\n";


    $message .= "--$boundary--\n";

    my @recievers = ($reciever);


    my $email = Email::Simple->create(
        header  => [
            From    => $sender,
            To      => join(', ', @recievers),
            Subject => $subject,
            'Content-Type' => $contenttype,
            Boundary    => $boundary,
        ],
        body    => $message,
    );
    my $fullmail = $email->as_string();
    $fullmail = dbfreeze($fullmail);

    my $sth = $dbh->prepare_cached("INSERT INTO mail_data
                                   (title, fullmail, sender, recievers, spooled_by, trusted_sender)
                                   VALUES (?,?,?,?,?, true)")
                or croak($dbh->errstr);

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
    );

    my $spooler = $self->{APPNAME} . '/' . $webdata{userData}->{user};

    if($sth->execute($subject, $fullmail, $sender, \@recievers, $spooler)) {
        $dbh->commit;
        return (1, "Mail2Print spooled");
    }

    $dbh->rollback;
    return (0, "Failed to spool Mail2Print");
}

sub sendFiles{
    my ($self, $recievers, $subject, $body, $zipFile, @files) = @_;

    my $boundary = "====" . time() . "====";
    my $contenttype = "multipart/mixed; boundary=\"$boundary\"";
    my $message = "--$boundary\n" .
                "Content-Type: text/plain; charset=\"iso-8859-1\"\n" .
                "Content-Transfer-Encoding: quoted-printable\n" .
                "\n" .
                encode_qp($body) . "\n" .
                "\n";

    my $zip = Archive::Zip->new();
    my $fcount = 0;
    foreach my $file (@files) {
        next unless(-f $file);
        $fcount++;
        my $newfname = $file;
        $newfname =~ s/.*\///g;
        my $filemember = $zip->addFile($file, $newfname);
        $filemember->desiredCompressionMethod( COMPRESSION_DEFLATED );
        $filemember->desiredCompressionLevel( COMPRESSION_LEVEL_BEST_COMPRESSION );
    }
    if($fcount == 0) {
        $message .= "WARNING: NO DATA AVAILABLE FOR YOU REQUEST!\n" .
                    "Please check your filter settings. Did you select\n" .
                    "the correct database?\n\n";
    } else {
        $zip->writeToFileNamed($zipFile);
        foreach my $file ($zipFile) {
            my $fdata = slurpBinFile($file);
            $fdata = encode_base64($fdata);
            my $shortname = $file;
            $shortname =~ s/^.*\///go;
            $shortname =~ s/^.*\\//go;
            if($file =~ /\.([^\.]*)$/o) {
                my $type = lc $1;
                my $longtype = "text/plain";
                if($type eq "csv") {
                    $longtype = "text/csv";
                } elsif($type eq "pdf") {
                    $longtype = "application/pdf";
                }

                $message .= "--$boundary\n" .
                            "Content-Type: application/zip; name=\"$shortname\"\n" .
                            "Content-Transfer-Encoding: base64\n" .
                            "Content-Disposition: attachment; filename=\"$shortname\"\n" .
                            "\n" .
                            "$fdata\n";
            } else {
                croak("Filename $file has no extension!");
            }
        }
    }
    $message .= "--$boundary--\n";
    #$message = dbfreeze($message);

    return $self->sendMail($recievers, $subject, $message, $contenttype);
}

1;
__END__

=head1 NAME

PageCamel::Web::SendMail -

=head1 SYNOPSIS

  use PageCamel::Web::SendMail;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 sendMail



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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
