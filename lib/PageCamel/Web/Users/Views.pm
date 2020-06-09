package PageCamel::Web::Users::Views;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %aliases;
    $self->{aliases} = \%aliases;

    my @configured;
    $self->{configured} = \@configured;

    return $self;
}

sub register {
    my ($self) = @_;

    $self->register_late_defaultwebdata("get_late_defaultwebdata");

    return;
}

sub reload {
    my ($self) = @_;
    # We don't load anything, but we use the opportunity to update our redirect
    # links for our views
    #
    # This can't be done on "new" because at that time not all modules are
    # configured yet. On the other hand, this doesn't change on a regular basis,
    # so completly dynamic handling is not needed
    foreach my $view (@{$self->{views}->{view}}) {
        my $ok = 1;
        foreach my $required (qw[display startpage level]) {
            if(!defined($view->{$required})) {
                print STDERR "View does not define property $required!\n";
                $ok = 0;
            }
        }
        croak("Config errors detected!") unless $ok;

        print "    view ", $view->{display}, "\n";

        my $startpage = $view->{startpage};
        my $viewname = $view->{display};
        my $startpageok = 0;

        foreach my $menu (@{$view->{menu}}) {
            if(!defined($menu->{path})) {
                print STDERR "Menu entry does not define property path!\n";
                $ok = 0;
            } else {
                print "      menu ", $menu->{path}, "\n";
            }

            if(contains($menu->{path}, $self->{configured})) {
                print STDERR "Module with path ", $menu->{path}, " already configured!\n";
                $ok = 0;
            }
            push @{$self->{configured}}, $menu->{path};

            if(!defined($menu->{display}) && !defined($menu->{aliasfor})) {
                print STDERR "Menu entry does not define properties display or aliasfor!\n";
                $ok = 0;
            }
            if(defined($menu->{display}) && defined($menu->{aliasfor})) {
                print STDERR "Menu entry does define both properties display and aliasfor!\n";
                $ok = 0;
            }
            croak("Config errors detected!") unless $ok;

            if(!defined($menu->{aliasfor})) {
                my $modname = $menu->{display};
                if($modname eq $startpage) {
                    $startpageok = 1;
                }
            }

            $menu->{url} = $self->getURL($menu->{path});
            if(defined($menu->{aliasfor})) {
                $menu->{aliasurl} = $self->getURL($menu->{aliasfor});
                $self->{aliases}->{$menu->{url}} = $menu->{aliasurl};
            }

        }

        if(!$startpageok) {
            croak("VIEWS: Configuration error, Invalid startpage $startpage in view $viewname!");
        }
    }
    return;
}

sub getURL {
    my ($self, $path) = @_;

    my ($locmodname, $subvarname, $subsubvarname) = split/\//, $path;
    $subvarname = "" if(!defined($subvarname));
    $subsubvarname = "" if(!defined($subsubvarname));

    if(defined($self->{server}->{modules}->{$locmodname})) {
        my %mod;
        if($subvarname eq "") {
            if(!defined($self->{server}->{modules}->{$locmodname})) {
                croak("VIEWS: Module " . $path . " not found");
            }
            %mod = %{$self->{server}->{modules}->{$locmodname}};
        } elsif($subsubvarname eq "") {
            if(!defined($self->{server}->{modules}->{$locmodname}->{$subvarname})) {
                croak("VIEWS: Module " . $path . " not found");
            }

            %mod = %{$self->{server}->{modules}->{$locmodname}->{$subvarname}};
        } else {
            if(!defined($self->{server}->{modules}->{$locmodname}->{$subvarname}->{$subsubvarname})) {
                croak("VIEWS: Module " . $path . " not found");
            }
            %mod = %{$self->{server}->{modules}->{$locmodname}->{$subvarname}->{$subsubvarname}};
        }

        if(!defined($mod{webpath})) {
            croak("Module " . $path . " has no valid link");
        } else {
            return $mod{webpath};
        }

    } else {
        croak("VIEWS: Module " . $self->{server}->{modules}->{$locmodname} . " ($locmodname) not defined!");
    }

    return;
}

sub getstarturl {
    my ($self, $rights) = @_;

    my $starturl;

    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};

    foreach my $ul (@{$ulh->{userlevels}->{userlevel}}) {
        next if(!contains($ul->{db}, $rights));

        next if(!defined($ul->{path}) || !defined($ul->{defaultview}));

        foreach my $view (@{$self->{views}->{view}}) {
            #next if($view->{level} ne $ul->{level});
            next if($view->{display} ne $ul->{defaultview});

            my $startpage = $view->{startpage};

            foreach my $menu (@{$view->{menu}}) {
                if($startpage eq $menu->{display}) {
                    $starturl = $menu->{url};
                    last;
                }
            }

            last if(defined($starturl));
        }
        last if(defined($starturl));
    }

    if(!defined($starturl)) {
        # Ups, user has no page to start, go to root again
        $starturl = '/';
    }

    return $starturl;
}

sub get_late_defaultwebdata {
    my ($self, $webdata) = @_;

    if(!defined($webdata->{userData})) {
        return;
    }

    # First, fake the active url if it's some aliasfor entry
    my $activeURL = $webdata->{userData}->{activeurl};
    foreach my $aliasurl (keys %{$self->{aliases}}) {
        if($activeURL =~ /^$aliasurl/) {
            $activeURL = $self->{aliases}->{$aliasurl};
        }
    }

    # Calculate dropdownmenu
    my @rights = @{$webdata->{userData}->{rights}};
    my @dropdownmenu;
    my @activeview;

    foreach my $view (@{$self->{views}->{view}}) {
        next if(!contains($view->{level}, \@rights));

        my $thisactive = 0;

        my @items;
        my $defaultpath = '';
        foreach my $menu (@{$view->{menu}}) {
            next if(defined($menu->{aliasfor}));
            my %item = (
                title   => $menu->{display},
                path    => $menu->{url},
            );
            push @items, \%item;

            my $url = $menu->{url};
            if($activeURL =~ /^$url/) {
                $thisactive = 1;
            }
            
            if($view->{startpage} eq $menu->{display}) {
                $defaultpath = $menu->{url};
            }
        }

        my %mainitem = (
            title   => $view->{display},
            items   => \@items,
            defaultpath => $defaultpath,
        );
        push @dropdownmenu, \%mainitem;


        if($thisactive) {
            # Ok, found active view, generate quicknav bar
            foreach my $menu (@{$view->{menu}}) {
                next if(defined($menu->{aliasfor}));
                my %item = (
                    title   => $menu->{display},
                    path    => $menu->{url},
                    active  => 0,
                    warning => 0,
                );

                my $url = $menu->{url};
                if($activeURL =~ /^$url/) {
                    $item{active} = 1;
                }

                if(defined($menu->{warnvar})) {
                    if(defined($webdata->{$menu->{warnvar}}) && $webdata->{$menu->{warnvar}} > 0) {
                        $item{warning} = 1;
                        $item{warning_count} = $webdata->{$menu->{warnvar}};
                    }
                }

                push @activeview, \%item;
            }
        }

    }

    $webdata->{DropDownMenu} = \@dropdownmenu;
    $webdata->{DropDownMenuCount} = scalar @dropdownmenu;
    $webdata->{QuickNavBar} = \@activeview;

    return;
}


1;
__END__

=head1 NAME

PageCamel::Web::Users::Views -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Views;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 getURL



=head2 getstarturl



=head2 get_late_defaultwebdata



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
