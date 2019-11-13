# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Minecraft::PlayerCoords;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
#---AUTOPRAGMAEND---
use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::FileSlurp qw[slurpBinFile];

use JSON::XS;
use Minecraft::NBTReader;
use GD;
use MIME::Base64;
use WWW::Mechanize::GZip;
use PageCamel::Helpers::FileSlurp qw[writeBinFile];
use Digest::SHA1 qw[sha1_hex];
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{oldmode} = '';

    return $self;
}

sub reload {
    my ($self) = shift;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'mode',
                    settingvalue => 'auto',
                    description => 'Mode',
                    processinghints => [
                        'type=tristate',
                        'on=Record',
                        'auto=Live',
                        'off=Playback'
                                        ])
        or croak("Failed to create setting mode!");

    my $clacks = $self->newClacksFromConfig($clconf);
    $clacks->listen($self->{clacks}->{signal});
    $clacks->ping;
    $clacks->doNetwork();
    $self->{clacksclient} = $clacks;

    $self->{nextping} = time + 10;

    return;
}

sub register {
    my $self = shift;

    $self->register_worker("work_cycle");

    return;
}

sub work_cycle {
    my ($self) = @_;

    my $workCount = 0;
    my ($ok, $sval, $mode);
    my $now = time;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    ($ok, $sval) = $sysh->get($self->{modname}, 'mode');
    if(!$ok) {
        $reph->debuglog("Can't read systemsetting mode");
        return $workCount;
    }
    $mode = $sval->{settingvalue};
    if($mode ne $self->{oldmode}) {
        $self->{nextstep} = -1;
        $self->{oldmode} = $mode;
    }

    $self->{clacksclient}->doNetwork();
    if($now > $self->{nextping}) {
        $self->{clacksclient}->ping();
        $self->{nextping} = $now + 10;
    }

    my %tristatemap = (
        on => 'record',
        auto => 'live',
        off => 'playback',
    );
    $mode = $tristatemap{$mode};

    if($mode eq 'playback') {
        $workCount += $self->playbackCoords();
    } else {
        my $cmd = $self->{clacksclient}->getNext();

        if(defined($cmd) && $cmd->{type} eq 'set' && $cmd->{name} eq $self->{clacks}->{signal}) {
            my $data = $cmd->{data};
            $workCount += $self->updateCoords($data);

            if($mode eq 'record') {
                $workCount += $self->recordCoords();
            }
        }
    }

    $workCount += $self->updateSkins();

    return $workCount;
}

sub updateCoords {
    my ($self, $data) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $json = decode_json(decode_base64($data));

    my $delworldsth = $dbh->prepare_cached("DELETE FROM minecraft_worlds
                                           WHERE module = ?")
            or croak($dbh->errstr);
    my $delplayersth = $dbh->prepare_cached("DELETE FROM minecraft_playercoords
                                            WHERE module = ?")
            or croak($dbh->errstr);
    if(!$delworldsth->execute($self->{dbmodule}) || !$delplayersth->execute($self->{dbmodule})) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    $workCount++;

    my $inworldsth = $dbh->prepare_cached("INSERT INTO minecraft_worlds
                                          (module, world_dimension, border_center_x, border_center_z, border_size)
                                           VALUES (?, ?, ?, ?, ?)")
            or croak($dbh->errstr);
    my $inplayersth = $dbh->prepare_cached("INSERT INTO minecraft_playercoords
                                           (module, playername, pos_x, pos_y, pos_z, world_dimension, health, gamemode, is_spectator, team)
                                           VALUES (?,?,?,?,?,?,?,?,?,?)")
            or croak($dbh->errstr);

    foreach my $world (sort keys %{$json->{worlds}}) {
        #print "World $world...\n";
        my $w = $json->{worlds}->{$world};


        if(!$inworldsth->execute(
            $self->{dbmodule},
            $world,
            int($w->{border}->{center}->{x}),
            int($w->{border}->{center}->{z}),
            int($w->{border}->{size} / 2), # border size = "length of one side", but we need "distance from center"
        )) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
            return 0;
        }
        $workCount++;

        foreach my $playerid (sort keys %{$w->{players}}) {
            my $p = $w->{players}->{$playerid};
            if(!defined($p->{team}) || $p->{team} eq '') {
                $p->{team} = 'unteamed';
            }

            my %modemap = (
                survival => 0,
                creative => 1,
                adventure => 2,
                spectator => 3,
            );

            if(defined($modemap{lc $p->{gamemode}})) {
                $p->{mode} = $modemap{lc $p->{gamemode}};
            } else {
                $p->{mode} = -1;
            }

            #(module, playername, pos_x, pos_y, pos_z, world_dimension, health, gamemode, is_spectator, team)
            if(!$inplayersth->execute(
                $self->{dbmodule},
                $p->{name},
                int($p->{location}->{x}),
                int($p->{location}->{y}),
                int($p->{location}->{z}),
                $world,
                int($p->{health}),
                $p->{mode},
                $p->{spectator},
                $p->{team},
            )) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                return 0;
            }
            $workCount++;
        }
        $workCount++;
    }

    $dbh->commit;

    return $workCount;
}

sub updateSkins {
    my ($self) = @_;

    my $workCount = 0;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Checking player skins...");

    my $skindelsth = $dbh->prepare_cached("DELETE FROM minecraft_playerskins ms
                                        WHERE NOT EXISTS (
                                          SELECT 1 FROM minecraft_playercoords mc
                                          WHERE mc.playername = ms.playername
                                        )
                                        AND NOT EXISTS (
                                          SELECT 1 FROM minecraft_playback_coords mp
                                          WHERE mp.playername = ms.playername
                                        )")
            or croak($dbh->errstr);
    my $skininsth = $dbh->prepare_cached("INSERT INTO minecraft_playerskins
                                        (playername, alive_base64, alive_etag, dead_base64, dead_etag)
                                        VALUES (?,?,?,?,?)")
            or croak($dbh->errstr);
    my $skinupsth = $dbh->prepare_cached("UPDATE minecraft_playerskins
                                        SET alive_base64 = ?, alive_etag = ?, dead_base64 = ?, dead_etag = ?, last_update = now()
                                        WHERE playername = ?")
            or croak($dbh->errstr);
    my $selnewsth = $dbh->prepare_cached("SELECT DISTINCT playername FROM minecraft_playercoords mc
                                         WHERE NOT EXISTS (
                                            SELECT 1 FROM minecraft_playerskins ms
                                            WHERE mc.playername = ms.playername
                                         )
                                         UNION
                                         SELECT DISTINCT playername FROM minecraft_playback_coords mp
                                         WHERE NOT EXISTS (
                                            SELECT 1 FROM minecraft_playerskins ms
                                            WHERE mp.playername = ms.playername
                                         )
                                         ")
            or croak($dbh->errstr);
    my $selstalesth = $dbh->prepare_cached("SELECT DISTINCT playername FROM minecraft_playerskins
                                           WHERE last_update < (now() - interval '24 hours')")
            or croak($dbh->errstr);

    if(!$skindelsth->execute) {
        $dbh->rollback;
        $reph->debuglog("Failed to delete not-existent player's skin");
        return $workCount;
    }
    $workCount++;

    if(!$selnewsth->execute) {
        $dbh->rollback;
        $reph->debuglog("Can't check for new players");
        return $workCount;
    }
    my @newplayers;
    while((my $line = $selnewsth->fetchrow_hashref)) {
        push @newplayers, $line->{playername};
    }
    $selnewsth->finish;

    if(!$selstalesth->execute) {
        $dbh->rollback;
        $reph->debuglog("Can't check for new players");
        return $workCount;
    }
    my @staleplayers;
    while((my $line = $selstalesth->fetchrow_hashref)) {
        push @staleplayers, $line->{playername};
    }
    $selstalesth->finish;

    foreach my $player (@newplayers) {
        $reph->debuglog("Adding playerskin for $player");
        my ($aliveskin, $deadskin) = $self->getIcons($player);
        next unless(defined($aliveskin) && defined($deadskin));
        if(!$skininsth->execute($player, $aliveskin, sha1_hex($aliveskin), $deadskin, sha1_hex($deadskin))) {
            $reph->debuglog("Can't insert new playerskin");
            $dbh->rollback;
            return $workCount;
        }
        $workCount++;
    }

    foreach my $player (@staleplayers) {
        $reph->debuglog("Updating playerskin for $player");
        my ($aliveskin, $deadskin) = $self->getIcons($player);
        next unless(defined($aliveskin) && defined($deadskin));
        if(!$skinupsth->execute($aliveskin, sha1_hex($aliveskin), $deadskin, sha1_hex($deadskin), $player)) {
            $reph->debuglog("Can't update playerskin");
            $dbh->rollback;
            return $workCount;
        }
        $workCount++;
    }

    $dbh->commit;

    $reph->debuglog("Done refreshing playerskins");


    # Nothing to do

    return $workCount;
}

sub recordCoords {
    my ($self) = @_;

    my $workCount = 0;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Recording current player data in archive...");

    my $evsth = $dbh->prepare_cached("INSERT INTO minecraft_playback (module) VALUES (?)
                                      RETURNING eventid")
            or croak($dbh->errstr);
    my $csth = $dbh->prepare_cached("INSERT INTO minecraft_playback_coords
                                    (eventid, playername, pos_x, pos_y, pos_z, world_dimension, health, gamemode, is_spectator, team)
                                      (SELECT ?, playername, pos_x, pos_y, pos_z, world_dimension, health, gamemode, is_spectator, team
                                       FROM minecraft_playercoords
                                       WHERE module = ?)")
            or croak($dbh->errstr);

    my $wsth = $dbh->prepare_cached("INSERT INTO minecraft_playback_worlds
                                    (eventid, world_dimension, border_center_x, border_center_z, border_size)
                                      (SELECT ?, world_dimension, border_center_x, border_center_z, border_size
                                       FROM minecraft_worlds
                                       WHERE module = ?)")
            or croak($dbh->errstr);

    if(!$evsth->execute($self->{dbmodule})) {
        $reph->debuglog("Failed to create new playback event!");
        $dbh->rollback;
        return $workCount;
    }
    $workCount++;

    my $line = $evsth->fetchrow_hashref;
    my $eventid = $line->{eventid};
    $evsth->finish;

    if(!$csth->execute($eventid, $self->{dbmodule})) {
        $reph->debuglog("Failed to backup current player data!");
        $dbh->rollback;
        return $workCount;
    }
    $workCount++;

    if(!$wsth->execute($eventid, $self->{dbmodule})) {
        $reph->debuglog("Failed to backup current world data!");
        $dbh->rollback;
        return $workCount;
    }
    $workCount++;

    $dbh->commit;
    return $workCount;
}

sub playbackCoords {
    my ($self) = @_;

    my $workCount = 0;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $now = time;

    if($self->{nextstep} == -1) {
        $reph->debuglog("Re-initializing playback");

        my @events;
        my $esth = $dbh->prepare_cached("SELECT eventid, extract(epoch from logtime)::bigint as uxtime, logtime
                                        FROM minecraft_playback
                                        ORDER BY eventid")
                or croak($dbh->errstr);

        if(!$esth->execute) {
            $reph->debuglog("Failed to load data");
            $dbh->rollback;
            return $workCount;
        }

        my $offset = 0;
        my $numelem = 0;

        while((my $line = $esth->fetchrow_hashref)) {
            if($offset == 0) {
                $offset = $line->{uxtime} - $now - 10; # First element will be 10 seconds in the future
            }
            $line->{uxtime} -= $offset; # Move all timestamps into the immediate future
            print "Diff: $now / ", $line->{uxtime}, " = ", $line->{uxtime} - $now, "\n";
            push @events, $line;
            $numelem++;
        }
        $esth->finish;
        $dbh->rollback;

        $self->{nextstep} = 0;
        $self->{numelem} = $numelem;
        $self->{events} = \@events;
        $workCount++;
    }

    # Now, check if we need to update to a new recorded event
    if($self->{events}->[$self->{nextstep}]->{uxtime} <= $now) {
        $reph->debuglog("Playback event " . $self->{events}->[$self->{nextstep}]->{eventid});

        my $pdelsth = $dbh->prepare_cached("DELETE FROM minecraft_playercoords
                                           WHERE module = ?")
                or croak($dbh->errstr);
        my $pinsth = $dbh->prepare_cached("INSERT INTO minecraft_playercoords
                                            (module, playername, pos_x, pos_y, pos_z, world_dimension, health, gamemode, is_spectator, team)
                                            (
                                                SELECT ?, playername, pos_x, pos_y, pos_z, world_dimension, health, gamemode, is_spectator, team
                                                FROM minecraft_playback_coords
                                                WHERE eventid = ?
                                            );")
                or croak($dbh->errstr);

        my $wdelsth = $dbh->prepare_cached("DELETE FROM minecraft_worlds
                                           WHERE module = ?")
                or croak($dbh->errstr);
        my $winsth = $dbh->prepare_cached("INSERT INTO minecraft_worlds
                                            (module, world_dimension, border_center_x, border_center_z, border_size)
                                            (
                                                SELECT ?, world_dimension, border_center_x, border_center_z, border_size
                                                FROM minecraft_playback_worlds
                                                WHERE eventid = ?
                                            );")
                or croak($dbh->errstr);

        if(!$pdelsth->execute($self->{dbmodule}) ||
           !$pinsth->execute($self->{dbmodule}, $self->{events}->[$self->{nextstep}]->{eventid}) ||
           !$wdelsth->execute($self->{dbmodule}) ||
           !$winsth->execute($self->{dbmodule}, $self->{events}->[$self->{nextstep}]->{eventid})
           ) {
            $reph->debuglog("Failed to update from playback data");
            $dbh->rollback;
            return $workCount;
        }
        $dbh->commit;

        $self->{nextstep}++;
        if($self->{nextstep} >= $self->{numelem}) {
            $self->{nextstep} = -1;
        }
    }
    return;
}


sub getNameFromUUID {
    my ($self, $uuid) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $mech = WWW::Mechanize::GZip->new();
    my $url = "https://api.mojang.com/user/profiles/" . $uuid . "/names";
    my $username = '';

    my $success = 0;
    my $result;
    my $content;

    if(!(eval {
        $result = $mech->get($url);
        $content = $result->content;
        $success = 1;
        1;
    })) {
        $success = 0;
    }
    if(!$success || !defined($result) || !$result->is_success) {
        $reph->debuglog("FAILED TO GET DATA FOR $uuid");
        return $username;
    }



    if(defined($content)) {
        $username = parseUserdata($content);
    } else {
        $reph->debuglog("Can't parse username for $uuid!\n");
        $username = '';
    }

    return $username;
}

sub getIcons {
    my ($self, $playername) = @_;

    my $skindata = $self->loadRawSkin($playername);
    my $alive = $self->renderIcon($playername, $skindata, 0);
    my $dead = $self->renderIcon($playername, $skindata, 1);

    return $alive, $dead;
}

sub loadRawSkin {
    my ($self, $playername) = @_;

    my $skindata;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $url = "http://skins.minecraft.net/MinecraftSkins/" . $playername . ".png";
    my $mech = WWW::Mechanize::GZip->new();
    my $success = 0;
    my $result;
    if(!(eval {
        $result = $mech->get($url);
        $success = 1;
        1;
    })) {
        $success = 0;
    }
    if($success && defined($result) && $result->is_success) {
        my $content = $result->content;
        if(defined($content)) {
            $skindata = $content;
        }
    }

    if(!defined($skindata)) {
        $reph->debuglog("Can't download skin for player $playername!");
        $reph->debuglog("Defaulting to steve!");
        $skindata = decode_base64($self->{steveskin_base64});
    }

    return $skindata;
}

sub renderIcon {
    my ($self, $playername, $skindata, $isdead) = @_;

    my $src = GD::Image->newFromPngData($skindata, 1);
    my $wings = GD::Image->newFromPngData(getAngelWings(), 1);
    my $dst = GD::Image->newTrueColor(64, 64);

    $src->alphaBlending(1);
    $src->saveAlpha(1);

    $wings->alphaBlending(1);
    $wings->saveAlpha(1);

    $dst->alphaBlending(0);
    $dst->saveAlpha(1);


    my $alpha = $dst->colorAllocateAlpha(255, 0, 255, 127);
    $dst->fill(0, 0, $alpha);


    if(!$isdead) {
        #$dst->copy($src, 4, 0, 8, 8, 8, 8);      #Head
        $dst->copyResampled($src, 16+8, 0, 8, 8, 16, 16, 8, 8);      #Head

        #$dst->copy($src, 4, 8, 20, 20, 8, 12);   #Body
        $dst->copyResampled($src, 16+8, 16, 20, 20, 16, 24, 8, 12);   #Body

        #$dst->copy($src, 0, 8, 44, 20, 4, 12);   #Arm-L
        $dst->copyResampled($src, 16+0, 16, 44, 20, 8, 24, 4, 12);   #Arm-L

        #$dst->copyResampled($src, 12, 8, 47, 20, 4, 12, -4, 12); #Arm-R
        $dst->copyResampled($src, 16+24, 16, 47, 20, 8, 24, -4, 12); #Arm-R

        #$dst->copy($src, 4, 20, 4, 20, 4, 12);   #Leg-L
        $dst->copyResampled($src, 16+8, 40, 4, 20, 8, 24, 4, 12);   #Leg-L

        #$dst->copyResampled($src, 8, 20, 7, 20, 4, 12, -4, 12);  #Leg-R
        $dst->copyResampled($src, 16+16, 40, 7, 20, 8, 24, -4, 12);  #Leg-R

        $dst->alphaBlending(1);
        $dst->copyResampled($src, 16+8, 0, 40, 8, 16, 16, 8, 8); # Hat
    } else {
        $dst->copy($wings, 0, 0, 0, 0, 64, 64);
        $dst->copyResampled($src, 16+8, 12+0, 8, 8, 16, 16, 8, 8);      #Head
        $dst->copyResampled($src, 16+8, 12+16, 20, 20, 16, 24, 8, 12);   #Body

        $dst->alphaBlending(1);
        $dst->copyResampled($src, 16+8, 12+0, 40, 8, 16, 16, 8, 8); # Hat
    }

    #my $transparentcolor = $src->getPixel(40, 0);
    #print STDERR "Alpha $transparentcolor\n";

    #$src->transparent($transparentcolor);



    my $playericon = $dst->png(0);

    if(1) {
        if($isdead) {
            writeBinFile('/home/cavac/src/temp/mc/' . $playername . '_dead.png', $playericon);
        } else {
            writeBinFile('/home/cavac/src/temp/mc/' . $playername . '_alive.png', $playericon);
        }
    }

    return encode_base64($playericon);

}

sub getAngelWings {
    return decode_base64("
        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
        /AX941QSdFEyUwAAAABJRU5ErkJggg==
        ");
}

sub parseUserdata {
    my ($raw) = @_;

    $raw =~ s/\[//g;
    $raw =~ s/\]//g;
    $raw =~ s/\"//g;

    my $uname = '';
    my $lastedit = 0;

    my @parts = split/\}\,\{/, $raw;
    foreach my $part (@parts) {
        $part =~ s/\{//g;
        $part =~ s/\}//g;
        my %data = split/[\,\:]/, $part;
        #print Dumper (\%data);
        if(!defined($data{changedToAt})) {
            # First(?) entry
            $uname = $data{name};
        } elsif($data{changedToAt} > $lastedit) {
            $lastedit = $data{changedToAt};
            $uname = $data{name};
        }
    }
    return $uname;
}

1;
