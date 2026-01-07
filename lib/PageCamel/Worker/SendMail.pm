package PageCamel::Worker::SendMail;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

use PageCamel::Helpers::DateStrings;
use Mail::Sendmail;
use MIME::QuotedPrint;
use MIME::Base64;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use PageCamel::Helpers::DBSerialize;
use Email::Simple;


sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {
    return;
}



sub sendMail($self, $recievers, $subject, $message, $contenttype, $extip = '0.0.0.0') {
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if(!defined($extip)) {
        $extip = '0.0.0.0';
    }

    my $sth = $dbh->prepare_cached("INSERT INTO mail_data
                                   (title, fullmail, sender, recievers, spooled_by, trusted_sender, external_sender)
                                   VALUES (?,?,?,?,?,true,?)")
                or croak($dbh->errstr);

    my $spooler = $self->{APPNAME};

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

    if($sth->execute($subject, $fullmail, $self->{sender}, $recievers, $spooler, $extip)) {
        $dbh->commit;
        return 1;
    }

    $dbh->rollback;
    return 0;
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

sub sendToPrinter{
    my ($self, $sender, $recievers, $subject, $fname, $data) = @_;

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

    my $email = Email::Simple->create(
        header  => [
            From    => $sender,
            To      => join(', ', @{$recievers}),
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

    my $spooler = $main::APPNAME;

    if($sth->execute($subject, $message, $sender, $recievers, $spooler)) {
        $dbh->commit;
        return (1, "Mail2Print spooled");
    }

    $dbh->rollback;
    return (0, "Failed to spool Mail2Print");
}

1;
__END__

=head1 NAME

PageCamel::Worker::SendMail -

=head1 SYNOPSIS

  use PageCamel::Worker::SendMail;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
