package PageCamel::Web::RootFiles;
#---AUTOPRAGMASTART---
use 5.030;
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
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = @_;

    # Can load files only once due to register(),
    # and we ain't doing it here

    return;
}

sub load_files {
    my ($self) = shift;

    # Empty cache
    my %files;
    $self->{cache} = \%files;

    my $fcount = 0;

    my $extrabase = "";
    if($self->{path} =~ /Images/i) {
        $extrabase = "/PageCamel/Web/Images";
    } elsif($self->{path} =~ /Static/i) {
        $extrabase = "/PageCamel/Web/Static";
    }

    my @DIRS = reverse @INC;
    if(defined($self->{EXTRAINC})) {
        push @DIRS, @{$self->{EXTRAINC}};
    }

    foreach my $bdir (@DIRS) {
        next if($bdir eq ".");
        my $fulldir = $bdir . $extrabase;
        print "   ** checking $fulldir \n";
        if(-d $fulldir) {
            #print "   **** loading extra static files\n";
            $fcount += $self->load_dir($fulldir);
        }
    }

    if(-d $self->{path}) {
        $fcount += $self->load_dir($self->{path});
    } else {
        #print "   **** WARNING: configured dir " . $self->{path} . " does not exist!\n";
    }
    $fcount += 0; # Dummy for debug breakpoint
    return;

}

sub load_dir {
    my ($self, $basedir) = @_;

    my $fcount = 0;

    opendir(my $dfh, $basedir) or croak($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname =~ /^\./);
        my $nfname = $basedir . "/" . $fname;
        if(-d $nfname) {
            # Got ourself a directory, go recursive
            $fcount += $self->load_dir($nfname);
            next;
        }

        next if(!contains($fname, $self->{rootfile}));

        #print STDERR "Load $nfname\n";
        if($fname =~ /(.*)\.([a-zA-Z0-9]*)/) {
            my ($kname, $type) = ($1, $2);
            if($type =~ /jpg/i) {
                $type = "image/jpeg";
            } elsif($type =~ /bmp/i) {
                $type = "image/bitmap";
            } elsif($type =~ /htm/i) {
                $type = "text/html";
            } elsif($type =~ /txt/i) {
                $type = "text/plain";
            } elsif($type =~ /css/i) {
                $type = "text/css";
            } elsif($type =~ /js/i) {
                $type = "application/javascript";
            } elsif($type =~ /ico/i) {
                $type = "image/vnd.microsoft.icon";
            }

            my $data = slurpBinFile($nfname);
            my %entry = (name   => $kname,
                        fullname=> $nfname,
                        type    => $type,
                        data    => $data,
                        );
            $self->{cache}->{'/' . $fname} = \%entry; # Store under full name
            $fcount++;
        }
    }
    closedir($dfh);
    return $fcount;
}

sub register {
    my $self = shift;

    $self->load_files;

    return;
}


sub crossregister {
    my $self = shift;

    # Register every file on its own
    foreach my $url (keys %{$self->{cache}}) {
        $self->register_webpath($url, "get");

        $self->register_public_url($url);
    }
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $name = $ua->{url};

    return (status  =>  404) unless defined($self->{cache}->{$name});
    return (status          =>  200,
            type            => $self->{cache}->{$name}->{type},
            data            => $self->{cache}->{$name}->{data},
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            );
}

1;
__END__

=head1 NAME

PageCamel::Web::RootFiles -

=head1 SYNOPSIS

  use PageCamel::Web::RootFiles;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 load_files



=head2 load_dir



=head2 register



=head2 crossregister



=head2 get



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
