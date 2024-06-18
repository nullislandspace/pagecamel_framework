# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::DatablobLoader;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DataBlobs;

use PageCamel::Helpers::FileSlurp qw(slurpBinFile writeBinFile);
use PageCamel::Helpers::Strings qw(windowsStringsQuote);
use File::Temp;
use PDF::Report;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(defined($self->{convert}) && defined($self->{convert}->{source}) && defined($self->{convert}->{destination}) && defined($self->{convert}->{command})) {
        $self->{useconvert} = 1;
    } else {
        $self->{useconvert} = 0;
    }

    if(!defined($self->{disable_compression})) {
        $self->{disable_compression} = 0;
    }

    return $self;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get_blob", 'GET');

    return;
}

sub get_blob($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $id = $ua->{url};
    $id =~ s/^.*\///g;

    my $downloadfilename = $id;

    my $extracolumns = '';

    if(defined($self->{source}->{filename})) {
        $extracolumns = ",sourcetable." . $self->{source}->{filename} . " AS downloadfilename";
    }

    my $selstmt = "SELECT desttable." . $self->{dest}->{pkcolumn} . " AS blobidcolumn
                    $extracolumns
                   FROM " . $self->{source}->{table} . " sourcetable
                   INNER JOIN " . $self->{dest}->{table} . " desttable
                   ON sourcetable." . $self->{source}->{blobcolumn} . " = desttable." . $self->{dest}->{pkcolumn} . "
                   WHERE sourcetable." . $self->{source}->{pkcolumn} . " = ?
                   LIMIT 1";

    my $selsth = $dbh->prepare_cached($selstmt)
            or croak($dbh->errstr);

    if(!$selsth->execute($id)) {
        $dbh->rollback;
        return(status => 500);
    }

    my $datablobid;
    while((my $line = $selsth->fetchrow_hashref)) {
        $datablobid = $line->{blobidcolumn};
        if(defined($line->{downloadfilename})) {
            $downloadfilename = windowsStringsQuote(lc $line->{downloadfilename});
            $downloadfilename =~ s/\ /_/g;
        }
    }
    $selsth->finish;

    if(!defined($datablobid)) {
        $dbh->rollback;
        return(status => 404);
    }

    my $blobdata;
    my $blob = PageCamel::Helpers::DataBlobs->new($dbh, $datablobid);
    $blob->blobRead(\$blobdata);
    $blob->blobClose();
    $dbh->commit;

    if($self->{useconvert}) {
        print STDERR "Converting datablob from ", $self->{convert}->{source}, " to ", $self->{convert}->{destination}, "\n";
        my $dir = File::Temp->newdir();
        my $dirname = $dir->dirname;

        my $sourcefname = $dirname . '/source.' . $self->{convert}->{source};
        my $destinationfname = $dirname . '/dest.' . $self->{convert}->{destination};

        print STDERR "Writing datablob to tempfile $sourcefname\n";
        writeBinFile($sourcefname, $blobdata);

        if($self->{convert}->{command} eq 'INTERNALPDF') {
            print STDERR "Using internal PDF converter\n";

            my $scalefactor = 80/210; # Resize so that document is still aproximately the same size as original (80mm = invoice paper width, 210 = A4 width)
            my $image = GD::Image->newFromPngData($blobdata);
            my ($w, $h) = $image->getBounds();

            $h = int($h * $scalefactor) + 1;

            my $pdf = PDF::Report->new(PageSize          => "A4",
                                        PageOrientation => "Portrait",
                                        );
            $pdf->newpage(1);
            my ($pagewidth, $pageheight) = $pdf->getPageDimensions();
            print STDERR "Page width: $pagewidth\n";
            my $z = $pageheight - 50;
            $pdf->addImgScaled($sourcefname, 80, $z - $h, $scalefactor);

            $blobdata = $pdf->Finish();
        } else {
            print STDERR "Using external command\n";
            my $cmd = '' . $self->{convert}->{command};
            $cmd =~ s/SOURCE/$sourcefname/g;
            $cmd =~ s/DESTINATION/$destinationfname/g;


            print STDERR "Running command $cmd\n";
            my @state = `$cmd`;

            print STDERR "Command returned: ", join("\n", @state), "\n";

            print STDERR "Slurping tempfile $destinationfname\n";
            $blobdata = slurpBinFile($destinationfname);
        }

    }

    if($self->{filetype} eq 'image/png') {
        $downloadfilename .= '.png';
    } elsif($self->{filetype} eq 'application/pdf') {
        $downloadfilename .= '.pdf';
    }


    return (status  =>  200,
            type    => $self->{filetype},
            data    => $blobdata,
            "Content-Disposition" =>  'attachment; filename="' . $downloadfilename . '"',
            disable_compression => $self->{disable_compression},
    );


}


1;
