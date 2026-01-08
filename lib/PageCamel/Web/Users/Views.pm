package PageCamel::Web::Users::Views;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
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

    my %aliases;
    $self->{aliases} = \%aliases;

    my @configured;
    $self->{configured} = \@configured;

    return $self;
}

sub register($self) {
    $self->register_late_defaultwebdata("get_late_defaultwebdata");

    return;
}

sub crossregister($self) {
    $self->iterateCheckViews($self->{views}->{view});

    return;
}

sub iterateCheckViews($self, $checkview, $dblevel = '') {
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};

    foreach my $view (@{$checkview}) {
        my $ok = 1;
        foreach my $required (qw[display]) {
            if(!defined($view->{$required})) {
                print STDERR "View does not define property $required!\n";
                $ok = 0;
            }
        }
        croak("Config errors detected!") unless $ok;

        if(defined($view->{type}) && $view->{type} eq 'submenu') {
            # This is a submenu, need to recursively check it
            $self->iterateCheckViews($view->{view}, $view->{level});
            next;
        }

        foreach my $required (qw[startpage]) {
            if(!defined($view->{$required})) {
                print STDERR "View does not define property $required!\n";
                $ok = 0;
            }
        }

        if($dblevel eq '' && !defined($view->{level})) {
            print STDERR "Root view ", $view->{display}, " MUST define a level\n";
            $ok = 0;
        } elsif($dblevel ne '' && defined($view->{level})) {
            print STDERR "Sub-Menu ", $view->{display}, " MUST NOT define a level\n";
            $ok = 0;
        }

        croak("Config errors detected!") unless $ok;

        #print "    view ", $view->{display}, "\n";

        my $startpage = $view->{startpage};
        my $viewname = $view->{display};
        my $startpageok = 0;

        foreach my $menu (@{$view->{menu}}) {
            if(!defined($menu->{path})) {
                print STDERR "Menu entry does not define property path!\n";
                $ok = 0;
            } else {
                #print "      menu ", $menu->{path}, "\n";
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

            my $basepermission;
            if($dblevel ne '') {
                $basepermission = $dblevel;
            } else {
                $basepermission = $view->{level};
            }
            my $path;
            if(defined($menu->{aliasfor})) {
                $path = $menu->{aliasfor};
            } else {
                $path = $menu->{path};
            }
            $path =~ s/\/$//g;
            $path =~ s/\//_/g;
            $menu->{permission} = $basepermission . '/' . $path;
            if(!defined($menu->{aliasfor})) {
                $ulh->register_userlevel($menu->{permission}, $menu->{display});
            }
            if(defined($menu->{url})) {
                $ulh->register_webpath($menu->{permission}, $menu->{url});
            }
        }

        if(!$startpageok) {
            croak("VIEWS: Configuration error, Invalid startpage $startpage in view $viewname!");
        }
    }
    return;
}

sub getURL($self, $path) {
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

sub getstarturl($self, $rights) {
    my $starturl;

    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};

    foreach my $ul (@{$ulh->{userlevels}->{userlevel}}) {
        if($ul->{db} =~ /\//) {
            # Starturls (via "defaultview") can only be defined on root-level permissions
            next;
        }

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

sub get_late_defaultwebdata($self, $webdata) {
    if(!defined($webdata->{userData})) {
        return;
    }

    # First, fake the active url if it's some aliasfor entry
    if(defined($webdata->{userData}->{activeurl})) {
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

        #print STDERR Dumper($self->{views}->{view}), "\n";

        $self->iterateViews($webdata, \@dropdownmenu, \@activeview, \@rights, $activeURL, $self->{views}->{view});

        $webdata->{DropDownMenu} = \@dropdownmenu;
        $webdata->{DropDownMenuCount} = scalar @dropdownmenu;
        $webdata->{QuickNavBar} = \@activeview;
    }

    return;
}

sub iterateViews($self, $webdata, $dropdownmenu, $activeview, $rights, $activeURL, $viewlist) {
    foreach my $view (@{$viewlist}) {
        next if(defined($view->{level}) && !contains($view->{level}, $rights));

        if(defined($view->{type}) && $view->{type} eq 'submenu') {
            my %startitem = (
                title => $view->{display},
                type => 'submenustart',
            );
            my %enditem = (
                type => 'submenuend',
            );
            push @{$dropdownmenu}, \%startitem;
            $self->iterateViews($webdata, $dropdownmenu, $activeview, $rights, $activeURL, $view->{view});

            if(defined($dropdownmenu->[-1]->{type}) && $dropdownmenu->[-1]->{type} eq 'submenustart') {
                # Ok, empty (sub) menu, pop it back out
                pop @{$dropdownmenu};
            } else {
                push @{$dropdownmenu}, \%enditem;
            }

            next;
        }

        my $thisactive = 0;

        my @items;
        my $defaultpath = '';
        foreach my $menu (@{$view->{menu}}) {
            next if(defined($menu->{aliasfor}));
            next if(!contains($menu->{permission}, $rights));
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
        push @{$dropdownmenu}, \%mainitem;


        if($thisactive) {
            # Ok, found active view, generate quicknav bar
            foreach my $menu (@{$view->{menu}}) {
                next if(defined($menu->{aliasfor}));
                next if(!contains($menu->{permission}, $rights));
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

                push @{$activeview}, \%item;
            }
        }

    }

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
