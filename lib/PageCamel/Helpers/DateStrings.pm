package PageCamel::Helpers::DateStrings;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::Padding qw(doFPad);

use Date::Manip;
use HTTP::Date;
use Readonly;
use Lingua::EN::Numbers::Ordinate;

use base qw(Exporter);
our @EXPORT = qw(getISODate getUTCISODate getFileDate getUniqueFileDate getLabelDate getDateAndTime
                 getWindowsDateAndTime fixDateField parseNaturalDate getShortFiledate getCurrentMinute 
                 getCurrentHour getCurrentDay getCurrentYear getISODate_nDaysOffset offsetISODate setmylocaltime
                 getLastModifiedWebdate isAprilFoolsDay getWebdate parseWebdate getScanspeedDate getDatetimeHash 
                 timeToSeconds eternalseptemberize secondsToInterval); ## no critic (Modules::ProhibitAutomaticExportation)


Readonly my $YEARBASEOFFSET => 1900;
my $lastUniqueDate = "";
my $UniqueDateCounter = 0;

my %timemap = (
    morning         => "06:00:00",
    premorning      => "05:45:00",
    afternoon       => "14:00:00",
    preafternoon    => "13:45:00",
    evening         => "22:00:00",
    preevening      => "21:45:00",
    night           => "22:00:00",
    prenight        => "21:45:00",
    noon            => "12:00:00",
    midnight        => "23:59:59",
    christmas       => "THISYEAR-12-24",
    "new year"      => "NEXTYEAR-01-01",
    "new years eve" => "THISYEAR-12-31",
);
my $timemap_updated = "";
my $timezoneoffset = 0;

sub setmylocaltime {
    my ($lt) = @_;

    $timezoneoffset = $lt;
    return 1;
}

sub getmylocaltime {
    return localtime ($timezoneoffset + time);
}

sub updateTimeMap {
    # calculate some variable date and time strings

    # atm, we need to run only once a day, so return quickly
    # it is the same date as last run
    my ($currentDate, undef) = getDateAndTime();
    if($timemap_updated eq $currentDate) {
        return;
    }
    $timemap_updated = $currentDate;

    Date_Init();
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    my $nextyear = $year+1;
    my $lastyear = $year-1;

    # a number of variable dates
    my %vardates = (
                    "sysadmin day"          => "last friday in june",
                    "towel day"             => "25th may",
                    "new years eve"         => "31st december",
                    "new year"              => "1st january",
                    "christmas eve"         => "24th december",
                    "christmas"             => "25th december",
                    "rene(s)* birthday"     => "9th november",
                    "frank(s)* birthday"    => "6th september",

                    );

    foreach my $varkey (keys %vardates) {
        my $varval = $vardates{$varkey};
        my $lastYearDay = UnixDate($varval . " $lastyear", "%Y-%m-%d");
        my $currentYearDay = UnixDate($varval . " $year", "%Y-%m-%d");
        my $nextYearDay = UnixDate($varval . " $nextyear", "%Y-%m-%d");

        my ($tmpyear, $tmpmon, $tmpday) = split/\-/, $currentYearDay;
        # normal
        if($mon < $tmpmon || ($mon == $tmpmon && $mday <= $tmpday)) {
            $timemap{$varkey} = $currentYearDay;
        } else {
            $timemap{$varkey} = $nextYearDay;
        }

        # "last ..."
        my $lastvarkey = "last " . $varkey;
        if($mon < $tmpmon || ($mon == $tmpmon && $mday <= $tmpday)) {
            $timemap{$lastvarkey} = $lastYearDay;
        } else {
            $timemap{$lastvarkey} = $currentYearDay;
        }
    }
    return;
}

sub getDatetimeHash {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);

    my %timehash = (
        year    => $year,
        month   => $mon,
        day     => $mday,
        hour    => $hour,
        minute  => $min,
        second  => $sec,
    );

    return \%timehash;
}


sub getISODate {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return "$year-$mon-$mday $hour:$min:$sec";
}

sub getUTCISODate {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = gmtime(time);
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return "$year-$mon-$mday $hour:$min:$sec";
}


sub getISODate_nDaysOffset {
    my ($nDays) = @_;
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = localtime(time + (86_400 * $nDays));
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return "$year-$mon-$mday $hour:$min:$sec";
}

sub getShortFiledate {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    return "$year$mon$mday";
}

sub getCurrentMinute {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    return "$year$mon$mday$hour$min";
}

sub getCurrentHour {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    return "$year$mon$mday$hour";
}

sub getCurrentDay {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);

    return "$year$mon$mday";
}

sub getCurrentYear {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;

    return "$year";
}

sub getFileDate {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return "$year$mon$mday$hour$min$sec";
}

sub getLabelDate {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);

    return "$mday.$mon.$year";
}

my %expiresmultiplier = (
    's' => 1,
    'm' => 60,
    'h' => 60*60,
    'd' => 60*60*24,
    'w' => 60*60*24*7,
    'M' => 60*60*24*30,
    'Y' => 60*60*24*365,
);

sub getWebdate {
    my ($num, $reloffset) = @_;

    if(!defined($num)) {
        $num = time;
    }

    if(defined($reloffset) && $reloffset =~ /^([\+\-])(\d+)([smhdwMY])/) {
        my ($dir, $val, $multi) = ($1, $2, $3);
        $val *= $expiresmultiplier{$multi};
        if($dir eq '-') {
            $val *= -1;
        }
        $num += $val;
    }

    return time2str($timezoneoffset + $num);
}

sub parseWebdate {
    my ($str) = @_;

    if($str =~ /^([+-])(\d+)(\w)/) {
        my %multipliers = (
            s   => 1,
            m   => 60,
            h   => 60*60,
            d   => 60*60*24,
            W   => 60*60*24*7,
            M   => 60*60*24*30,
            y   => 60*60*24*365,
        );
        my ($direction, $amount, $multiplier) = ($1, $2, $3);
        if(!defined($multipliers{$multiplier})) {
            croak("Undefined delta time multiplier $multiplier");
        }
        if($direction eq '-') {
            $amount = $amount * -1;
        }
        return time() + ($amount * $multipliers{$multiplier});
    }

    # normal time string
    return str2time($str);
}

sub getUniqueFileDate {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    my $date = "$year$mon$mday$hour$min$sec";

    if($date eq $lastUniqueDate) {
        $UniqueDateCounter++;
        if($UniqueDateCounter == 99) {
            my $newmin = $min;
            while($newmin == $min) {
                print "getUniqueFileDate is throtteling\n";
                sleep(1);
                (undef,$newmin) = getmylocaltime();
            }
        }
    } else {
        $UniqueDateCounter = 1;
        $lastUniqueDate = $date;
    }
    $date .= doFPad($UniqueDateCounter, 2);
    return $date;

}

sub getDateAndTime {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return ("$year-$mon-$mday", "$hour:$min:$sec");
}

sub getWindowsDateAndTime {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return ("$mday-$mon-$year", "$hour:$min:$sec");
}

sub getLastModifiedWebdate {
    my ($fname) = @_;

    my $epoch_timestamp = (stat($fname))[9];
    return time2str($epoch_timestamp);
}

sub isAprilFoolsDay {
    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();
    $year += $YEARBASEOFFSET;
    $mon += 1;

    #return 1; ## For testing
    if($mon == 4 && $mday == 1) {
        return 1;
    }

    return 0;
}

sub parseNaturalDate {
    my ($dateString) = @_;

    updateTimeMap();

    # parse some extra mappings
    my (undef,undef, undef, undef,undef, $thisyear) = getmylocaltime();
    $thisyear += $YEARBASEOFFSET;
    my $nextyear = $thisyear + 1;

    # remove unused characters
    $dateString =~ s/([^a-zA-Z0-9\ \-\:])//go;

    # reorder the form of "TIMENAME of DAYNAME"
    if($dateString =~ /(.*)\ (of|on|at)\ (.*)/) {
        $dateString = "$3 $1";
    }

    if($dateString =~ /last/) {
        # First try only keys with "last" in it
        foreach my $speakdate (keys %timemap) {
            next unless $speakdate =~ /last/;
            my $writedate = $timemap{$speakdate};
            $dateString =~ s/\b$speakdate\b/$writedate/g;
        }
    }

    foreach my $speakdate (keys %timemap) {
        my $writedate = $timemap{$speakdate};
        $dateString =~ s/\b$speakdate\b/$writedate/g;
    }
    $dateString =~ s/THISYEAR/$thisyear/g;
    $dateString =~ s/NEXTYEAR/$nextyear/g;

#    my $dt = $naturalDateParser->parse_datetime($dateString);
    my $newdate = UnixDate($dateString, "%Y-%m-%d %H:%M:%S");
    if(defined($newdate) && $newdate ne "") {
        return $newdate;
    } else {
        return $dateString;
    }
}

sub fixDateField {
    my ($date) = @_;

    if(!defined($date)) {
        return "";
    }

    if($date =~ /(\d\d\d\d\-\d\d\-\d\d\ \d\d\:\d\d\:\d\d)/o) {
        $date = $1;
    }
    if($date eq "1970-01-01 23:59:59" || $date eq "1970-01-01 01:00:00") {
        $date = "";
    }

    return $date;
}

sub offsetISODate {
    my($date, $offset) = @_;

    my $oldtime = str2time($date) + $offset;

    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = localtime $oldtime;
    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    my $newtime = "$year-$mon-$mday $hour:$min:$sec";

    return $newtime;
}

sub getScanspeedDate {
    my ($scanspeed) = @_;

    my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = getmylocaltime();

    if($scanspeed eq 'fast') {
        # Every 10 seconds
        $sec = int($sec / 10) * 10;
    } elsif($scanspeed eq 'medium' || $scanspeed eq 'minuteman') {
        # Top of every minute
        $sec = 0;
    } elsif($scanspeed eq 'slow') {
        # Every 5 minutes
        $sec = 0;
        $min = int($min / 5) * 5;
    } else {
        carp("Unknown scanspeed $scanspeed");
    }

    $year += $YEARBASEOFFSET;
    $mon += 1;

    $mon = doFPad($mon, 2);
    $mday = doFPad($mday, 2);
    $hour = doFPad($hour, 2);
    $min = doFPad($min, 2);
    $sec = doFPad($sec, 2);
    return "$year$mon$mday$hour$min$sec";
}

sub timeToSeconds {
    my ($timestring)  = @_;

    my ($hours, $minutes) = split/\:/, $timestring;

    my $seconds = ($hours * 60) + $minutes;

    return $seconds;
}

sub eternalseptemberize {
    # Change date&time string to "Eternal september" date string
    my ($indate) = @_;

    my $sepdate = '1993-09-01 00:00:00';

    my $inmangler = Date::Manip::Date->new();
    my $sepmangler = Date::Manip::Date->new();

    my ($inparseerr) = $inmangler->parse($indate);

    if(defined($inparseerr) && $inparseerr) {
        return '';
    }

    my ($sepparseerr) = $sepmangler->parse($sepdate);

    if(defined($sepparseerr) && $sepparseerr) {
        return '';
    }

    my $delta = $inmangler->calc($sepmangler, 1);
    my @deltafields = $delta->value();
    my $days = ordinate(int($deltafields[4] / 24) + 1);
    my $result = $inmangler->printf("%a, $days et. Sept.  1993 %H:%M:%S");

    return $result;
}

sub secondsToInterval {
    my ($seconds) = @_;

    my $interval = '';
    my @divisors = (60, 60, 24);
    foreach my $divisor (@divisors) {
        my $remain = $seconds % $divisor;
        $interval = ':' . doFPad($remain, 2) . $interval;
        $seconds = int($seconds / $divisor);
    }
    $interval = $seconds . $interval;

    return $interval;
}

    

1;
__END__

=head1 NAME

PageCamel::Helpers::DateStrings - get Datestrings in a lot of different forms

=head1 SYNOPSIS

  use PageCamel::Helpers::DateStrings;

=head1 DESCRIPTION

This is the basis of all (date bases) evil. Here, the multitude of different time- and datestrings for all PageCamel based projects are generated.

=head2 setmylocaltime

Evil helper function to simulate a different date than it really is. Useful for testing only.

=head2 getmylocaltime

Internal helper that wraps around the "time" function to include offsets calculated by setmylocaltime.

=head2 updateTimeMap

Internal helper for the "smart" date parser.

=head2 getDatetimeHash

Return a %hash of date/time parts.

=head2 getISODate

Get the date in the form of "YYYY-MM-DD hh:mm:ss"

=head2 getISODate_nDaysOffset

Same as getISODate(), but allow for an offset in days.

=head2 getShortFiledate

Get a "short" timestamp for filenames in the format "YYYYMMDD"

=head2 getCurrentMinute

Get a timestamp for minute accuracy in the format "YYYYMMDDhhmm"

This timestamp isn't meant for calculating anything, just for checking if we are
still in the same timeperiod or if we have moved into the next one. Format may
change in the future.

=head2 getCurrentHour

Get a timestamp for hour accuracy in the format "YYYYMMDDhh"

This timestamp isn't meant for calculating anything, just for checking if we are
still in the same timeperiod or if we have moved into the next one. Format may
change in the future.

=head2 getCurrentDay

Get a timestamp for day accuracy in the format "YYYYMMDD"

This timestamp isn't meant for calculating anything, just for checking if we are
still in the same timeperiod or if we have moved into the next one. Format may
change in the future.

=head2 getCurrentYear

Get a timestamp for year accuracy in the format "YYYY"

This timestamp isn't meant for calculating anything, just for checking if we are
still in the same timeperiod or if we have moved into the next one. Format may
change in the future.

=head2 getFileDate

Get a timestamp for use in filenames in the format "YYYYMMDDhhmmss"

=head2 getWebdate

Get a webdate, as used in HTTP and SMTP headers. Call to function can include an offset like "+10m", "+4d" or similar.

=head2 parseWebdate

Parses a webdate and returns a time() compatible number.

=head2 getUniqueFileDate

Backwards compatibility function that provides guaranteed-Unique file timestamps in the format "YYYYMMDDhhmmss". A slight twist here is that the seconds can go up to 99. This is only used in a very specific project.

=head2 getDateAndTime

Returns two values, date and time. In the formats "YYYY-MM-DD" and "hh:mm:ss"

=head2 getWindowsDateAndTime

Returns two values, similar to getDateAndTime, but in the formats "DD-MM-YYYY" and "hh:mm:ss". This is mainly used to communicate with some windows command line tools.


=head2 getLastModifiedWebdate

Returns the last modified timestamp of a file in webdate format.

=head2 isAprilFoolsDay

Returns true in April Fools day (1st of April).

=head2 parseNaturalDate

Parse a "natural" (or "smart") date, for example "tomorrow morning".


=head2 fixDateField

Helper for working around issues with webforms.

=head2 offsetISODate

Returns the same as getISODate, but with a specified offset in seconds

=head2 getScanspeedDate

Returns a timestamp fixed to a "scanspeed". Used in Logging workers.

This timestamp isn't meant for calculating anything, just for checking if we are
still in the same timeperiod or if we have moved into the next one. Format may
change in the future.

=head2 timeToSeconds

Helper to turn a timestamp in the form of "hh:mm" into seconds.

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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
