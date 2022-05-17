# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::DatablobLoader;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DataBlobs;

use PageCamel::Helpers::FileSlurp qw(slurpBinFile writeBinFile);
use File::Temp;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(defined($self->{convert}) && defined($self->{convert}->{source}) && defined($self->{convert}->{destination}) && defined($self->{convert}->{command})) {
        $self->{useconvert} = 1;
    } else {
        $self->{useconvert} = 0;
    }

    return $self;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get_blob", 'GET');

    return;
}

sub get_blob {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $id = $ua->{url};
    $id =~ s/^.*\///g;

    my $selstmt = "SELECT desttable." . $self->{dest}->{pkcolumn} . " AS blobidcolumn
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

        my $cmd = '' . $self->{convert}->{command};
        $cmd =~ s/SOURCE/$sourcefname/g;
        $cmd =~ s/DESTINATION/$destinationfname/g;

        print STDERR "Writing datablob to tempfile $sourcefname\n";
        writeBinFile($sourcefname, $blobdata);

        print STDERR "Running command $cmd\n";
        my @state = `$cmd`;

        print STDERR "Command returned: ", join("\n", @state), "\n";

        print STDERR "Slurping tempfile $destinationfname\n";
        $blobdata = slurpBinFile($destinationfname);
    }


    return (status  =>  200,
            type    => $self->{filetype},
            data    => $blobdata,
    );


}


1;
