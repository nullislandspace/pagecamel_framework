package PageCamel::Web::Tools::RemoteConsoleLog;
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

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use JSON::XS;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/remoteconsolelog';

    return $self;
}

sub wsmaskget($self, $ua, $settings, $webdata) {

    foreach my $key (qw[HeadExtraScripts HeadExtraCSS]) {
        if(!defined($webdata->{$key})) {
            my @temp;
            $webdata->{$key} = \@temp;
        }
    }

    push @{$webdata->{HeadExtraScripts}}, (  
                                            '/static/codemirror/codemirror.js',
                                            '/static/codemirror/addon/edit/matchbrackets.js',
                                            '/static/codemirror/addon/comment/continuecomment.js', 
                                            '/static/codemirror/addon/comment/comment.js',
                                            '/static/codemirror/addon/dialog/dialog.js',
                                            '/static/codemirror/addon/search/searchcursor.js',
                                            '/static/codemirror/addon/search/search.js',
                                            '/static/codemirror/addon/search/match-highlighter.js',
                                            '/static/codemirror/addon/search/matchesonscrollbar.js',
                                            '/static/codemirror/addon/edit/closebrackets.js',
                                            '/static/codemirror/mode/javascript/javascript.js',
                                          );
    push @{$webdata->{HeadExtraCSS}}, (
                                            '/static/codemirror/codemirror.css',
                                            '/static/codemirror/addon/dialog/dialog.css',
                                            '/static/codemirror/addon/search/matchesonscrollbar.css',
                                            '/static/codemirror/theme/3024-night.css',
                                      );

    return 200;
}

sub wscrossregister($self) {

    $self->register_webpath($self->{beacon}->{webpath}, 'beaconhandler', 'POST');
    $self->register_public_url($self->{beacon}->{webpath});
    $self->register_defaultwebdata("get_defaultwebdata");

    return;
}

sub wshandlerstart($self, $ua, $settings) {

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    $self->{clacks}->listen('PageCamel::RemoteConsoleLog');
    $self->{clacks}->doNetwork();

    return;
}

sub wscleanup($self) {

    delete $self->{nextping};
    delete $self->{clacks};

    return;
}

sub wscyclic($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        if($cmsg->{type} eq 'set' && $cmsg->{name} eq 'PageCamel::RemoteConsoleLog') {
            my $selsth = $dbh->prepare_cached("SELECT * FROM remoteconsolelog WHERE logid = ?")
                    or croak($dbh->errstr);
            if(!$selsth->execute($cmsg->{data})) {
                $reph->debuglog("DB Error: ", $dbh->errstr);
                $dbh->rollback;
                next;
            }
            my $line = $selsth->fetchrow_hashref;
            $selsth->finish;
            $dbh->commit;

            if(!defined($line) || !defined($line->{logdata_formatted})) {
                next;
            }

            my %msg = (
                type => 'LOGDATA',
                logdata => $line->{logdata_formatted},
            );

            if(!$self->wsprint(\%msg)) {
                return 0;
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}


sub get_defaultwebdata($self, $webdata) {

    $webdata->{EnableRemoteConsoleLog} = 1;
    return;
}


sub beaconhandler($self, $ua) {
    
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $reph->debuglog("Got RemoteConsoleLog");
    my $ip = $ua->{remote_addr} || '0.0.0.0';
    my $username = '';


    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
    );

    if(defined($webdata{userData}->{user})) {
        $username = $webdata{userData}->{user};
    }

    my $beacondata;
    my $decoded = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $beacondata = decode_json($ua->{postdata});
        $decoded = 1;
    };
    
    if(!$decoded || !defined($beacondata)) {
        return (status => 400); # Bad request
    }

    my $insth = $dbh->prepare_cached("INSERT INTO remoteconsolelog (client_ip, username, logdata, logdata_formatted)
                                      VALUES (?, ?, ?, ?)
                                      RETURNING logid")
            or croak($dbh->errstr);

    if($insth->execute($ip, $username, $ua->{postdata}, Dumper($beacondata))) {
        my $line = $insth->fetchrow_hashref;
        $insth->finish;
        $dbh->commit;

        my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
        my $clacks = $self->newClacksFromConfig($clconf);
        $clacks->set("PageCamel::RemoteConsoleLog", $line->{logid});
        $clacks->disconnect();

        return(status => 204,
               "__do_not_log_to_accesslog" => 1, # Don't spam the accesslog
               ); # No content
    }

    $dbh->rollback;
    return(status => 500);
}

1;
__END__
