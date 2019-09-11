# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Minecraft::Mapcrafter;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---
use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Padding qw(doFPad);

use Readonly;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(!defined($self->{jobs})) {
        $self->{jobs} = 1;
    }

    $self->{nextrun} = 0;

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
    my $self = shift;
    $self->register_worker("update_map");
    return;
}


sub update_map {
    my ($self) = @_;
    
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
