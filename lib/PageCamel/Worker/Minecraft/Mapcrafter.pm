# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Minecraft::Mapcrafter;
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
use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Padding qw(doFPad);

use Readonly;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(!defined($self->{jobs})) {
        $self->{jobs} = 1;
    }

    $self->{nextrun} = 0;

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register($self) {
    $self->register_worker("update_map");
    return;
}


sub update_map($self) {
    
    my $workCount = 0;
    
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $now = time;
    
    if($now < $self->{nextrun}) {
        return $workCount;
    }
    $self->{nextrun} = $now + $self->{cycletime};
    
    $reph->debuglog("Rendering mapcrafter for " . $self->{dynfilename});
    if(defined($self->{renderexracommand})) {
        $reph->debuglog("Running " . $self->{renderexracommand});
        $memh->disable_lifetick;
        my @deblines = `$self->{renderexracommand}`;
        $memh->refresh_lifetick;
        foreach my $debline (@deblines) {
            chomp $debline;
            $reph->debuglog('> ' . $debline);
        }
        $workCount++;
    }

    {
        $reph->debuglog($self->{dynfilename} . " Update overview map");
        my $cmd = "/usr/local/bin/mapcrafter -c " . $self->{mapcraftconf} . " -b -j " . $self->{jobs};
        $reph->debuglog(" Running $cmd");
        {
            $memh->disable_lifetick;
            my @deblines = `$cmd`;
            $memh->refresh_lifetick;
            foreach my $debline (@deblines) {
                chomp $debline;
                $reph->debuglog('> ' . $debline);
            }
        }
        $workCount++;
    }
    if(defined($self->{parsemarkersfrommap}) && $self->{parsemarkersfrommap}) {
        $reph->debuglog($self->{dynfilename} . " Update markers");
        my $cmd = "/usr/local/bin/mapcrafter_markers -c " . $self->{mapcraftconf};
        $reph->debuglog(" Running $cmd");
        {
            $memh->disable_lifetick;
            my @deblines = `$cmd`;
            $memh->refresh_lifetick;
            foreach my $debline (@deblines) {
                chomp $debline;
                $reph->debuglog('> ' . $debline);
            }
        }
        $workCount++;
    }


    { # Schedule re-scanning of overview map files
        my $csth = $dbh->prepare_cached("INSERT INTO commandqueue (command, arguments) VALUES ('DYNAMICEXTERNALFILES_UPDATE_DATABASE', '{\"" . $self->{dynfilename} . 
                "\", \"" . $self->{dynfiledir} . "\", \"0\", \"1\"}')")
            or croak($dbh->errstr);

        $reph->debuglog("Schedule rescanning of " . $self->{dynfilename} . " world map");
        if($csth->execute()) {
            $dbh->commit;
            $workCount++;
        } else {
            $dbh->rollback;
            $reph->debuglog($self->{dynfilename} . " Scheduling FAILED!");
        }

        $dbh->commit;
    }

    return $workCount;
}

1;
__END__
