package PageCamel::Web::Tools::ContentSecurityPolicyViolation;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use JSON::XS;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get", qw[POST]);
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $plain;
    my $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $plain = decode_json $ua->{postdata};
        $ok = 1;
    };

    if(!$ok) {
        return (status => 400); # Unspecified client error
    }
    
    my $userAgent = $ua->{headers}->{'User-Agent'} || '';
    my $host = $ua->{remote_addr} || '';

    my $sth = $dbh->prepare_cached("INSERT INTO content_policy_violations
                                   (blocked_uri, document_uri, effective_directive,
                                    original_policy, status_code, violated_directive,
                                    referer, useragent, remotehost)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);
    if(!$sth->execute($plain->{"csp-report"}->{"blocked-uri"},
                      $plain->{"csp-report"}->{"document-uri"},
                      $plain->{"csp-report"}->{"effective-directive"},
                      $plain->{"csp-report"}->{"original-policy"},
                      $plain->{"csp-report"}->{"status-code"},
                      $plain->{"csp-report"}->{"violated-directive"},
                      $plain->{"csp-report"}->{"referrer"},
                      $userAgent,
                      $host,
                      )) {
        $dbh->rollback;
        return (status => 500);
    }

    $dbh->commit;

    return (status  =>  204); # OK, no content
}


1;
__END__

=head1 NAME

PageCamel::Web::Tools::ContentSecurityPolicyViolation -

=head1 SYNOPSIS

  use PageCamel::Web::Tools::ContentSecurityPolicyViolation;



=head1 DESCRIPTION



=head2 new



=head2 register



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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
