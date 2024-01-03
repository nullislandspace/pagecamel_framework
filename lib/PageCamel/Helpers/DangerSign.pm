package PageCamel::Helpers::DangerSign;
#---AUTOPRAGMASTART---
use v5.38;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(Exporter);
our @EXPORT= qw(DangerSign DangerSignUTF8); ## no critic (Modules::ProhibitAutomaticExportation)


sub DangerSign() {
    my $sign = "
                                       ██                                          
                                     ██░░██                                        
         ░░                        ██░░░░░░██                                      
                                 ██░░░░░░░░░░██                                    
                                 ██░░░░░░░░░░██                                    
                               ██░░░░░░░░░░░░░░██                                  
                             ██░░░░░░██████░░░░░░██                                
                             ██░░░░░░██████░░░░░░██                                
                           ██░░░░░░░░██████░░░░░░░░██                              
                           ██░░░░░░░░██████░░░░░░░░██                              
                         ██░░░░░░░░░░██████░░░░░░░░░░██                            
                       ██░░░░░░░░░░░░██████░░░░░░░░░░░░██                          
                       ██░░░░░░░░░░░░██████░░░░░░░░░░░░██                          
                     ██░░░░░░░░░░░░░░██████░░░░░░░░░░░░░░██                        
                     ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                        
                   ██░░░░░░░░░░░░░░░░██████░░░░░░░░░░░░░░░░██                      
                   ██░░░░░░░░░░░░░░░░██████░░░░░░░░░░░░░░░░██                      
                 ██░░░░░░░░░░░░░░░░░░██████░░░░░░░░░░░░░░░░░░██                    
                 ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                    
                   ██████████████████████████████████████████                      
";

    return $sign;
}

sub DangerSignUTF8() {
    return encode_utf8(DangerSign());
}

1;
__END__

=head1 NAME

PageCamel::Helpers::Logo - print the PageCamel logo

=head1 SYNOPSIS

  use PageCamel::Helpers::Logo;

=head1 DESCRIPTION

Prints the standardized PageCamel logo, including application name and version.

=head2 PageCamelLogo

Print the logo.

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
