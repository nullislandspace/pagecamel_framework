package PageCamel::Web::Tools::ScriptDownload;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    return $self;
}

sub reload($self) {
    # Nothing to do

    return;
}

sub register($self) {

    $self->register_webpath($self->{webpath}, "get_file");
    return;
}

sub get_file($self, $ua) {

    my $webpath = '' . $ua->{url};
    $webpath =~ s/^$self->{webpath}//;
    $webpath =~ s/^\///;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selsth = $dbh->prepare_cached("SELECT " . $self->{data} . " AS dlscriptdata FROM " . $self->{table} .
                                      " WHERE " . $self->{scriptname} . " = ?")
            or croak($dbh->errstr);

    if(!$selsth->execute($webpath)) {
        $dbh->rollback;
        print STDERR $dbh->errstr, "\n";
        return (status => 500);
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->commit;

    if(!defined($line) || !defined($line->{dlscriptdata})) {
        return (status => 404);
    }

    return (status  =>  200,
            type    => "text/plain",
            data    => $line->{dlscriptdata});
}

1;
