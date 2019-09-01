use strict;
use warnings;

package PageCamel::Net::Server::Tracker;
our $VERSION = 2.2;
# ABSTRACT: shared status file for PageCamel::Net::Server children

use Carp ();
use IO::File qw(O_CREAT O_EXLOCK O_NONBLOCK O_RDWR);
use SUPER;

sub post_configure_hook {
  my ($self) = @_;
  my $max_servers = $self->{server}{max_servers};
  die "can't cope with 0 max_servers" unless $max_servers;

  my $line_length = defined $self->{server}{tracker}{line_length}
                  ?  $self->{server}{tracker}{line_length}
                  : 80;

  Carp::confess("tracker line length must be at least 80")
    if $line_length < 80;

  $self->{tracker} = {
    array => [ (undef) x $max_servers ],
    slot  => {},
    line_length => $line_length,
    filename    => defined $self->{server}{tracker}{filename}
                 ? $self->{server}{tracker}{filename}
                 : "tracker.status",
    time_format => defined $self->{server}{tracker}{time_format}
                 ? $self->{server}{tracker}{time_format}
                 : "local",
  };

  Carp::confess("unknown time_format: $self->{tracker}{time_format}")
    unless $self->{tracker}{time_format} =~ /\A(?:local|gm|epoch)\z/;

  my $fh = IO::File->new(
    $self->{tracker}{filename},
    O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK
  );

  die "can't open tracker with exclusive lock: $!" unless $fh;

  $self->{tracker}{lock_fh} = $fh;

  my $line = " " x ($self->{tracker}{line_length} - 1)
           . "\n";

  print {$fh} $line x $max_servers;

  return $self->SUPER;
}

sub _tracker_first_empty_index {
  my ($self) = @_;
  my @tracker = @{ $self->{tracker}{array} };
  grep { defined($tracker[$_]) || return $_ } (0 .. $#tracker);
  Carp::confess("no empty slots in tracker!");
}

sub register_child {
  my ($self, $pid) = @_;
  # Almost identical to child_init_hook
  my $slot_idx = $self->_tracker_first_empty_index;
  $self->{tracker}{array}[ $slot_idx ] = $pid;
  $self->{tracker}{slot}{$pid} = $slot_idx;
  return $self->SUPER($pid);
}

sub child_init_hook {
  my ($self, @rest) = @_;
  # Almost identical to register_child
  my $slot_idx = $self->_tracker_first_empty_index;
  $self->{tracker}{array}[ $slot_idx ] = $$;
  $self->{tracker}{slot}{$$} = $slot_idx;

  my $fh = IO::File->new($self->{tracker}{filename}, "+<");
  $fh->autoflush(1);

  $self->{tracker}{write_fh} = $fh;

  $self->update_tracking("child online");

  return $self->SUPER(@rest);
}

sub post_accept_hook {
  my ($self, @rest) = @_;
  $self->update_tracking("accepted request for processing");
  $self->SUPER(@rest);
}

sub post_process_request_hook {
  my ($self, @rest) = @_;
  $self->update_tracking("request processing complete");
  $self->SUPER(@rest);
}

sub child_finish_hook {
  my ($self, @rest) = @_;
  $self->update_tracking("child shutting down");
  return $self->SUPER(@rest);
}


sub update_tracking {
  my ($self, $message) = @_;
  $message = 'ping' if not defined $message;

  my $tracker = $self->{tracker};

  my $slot = $tracker->{slot}{$$};
  unless (defined $slot) {
    $self->log(1, "!!! can't update tracking for unregistered pid $$");
    return;
  }

  my $ts;
  if ($tracker->{time_format} eq 'epoch') {
    $ts = time;
  } else {
    my @t = $tracker->{time_format} eq 'gm' ? gmtime : localtime;
    $ts = sprintf '%04u-%02u-%02uT%02u:%02u:%02u',
      $t[5] + 1900,
      $t[4] + 1,
      @t[3, 2, 1, 0];
  }

  my $reserved =  7  # pid, space
               + length($ts)
               +  1  # space
               +  1; # newline

  my $len = $self->{tracker}{line_length};
  my $fit = $len - $reserved;

  # This would be \v if we lived in a more civilized time. -- rjbs, 2016-05-23
  if ($message =~ s/[\x0A-\x0D\x85\x{2028}\x{2029}]/ /g) {
    $self->log(1, "!!! replaced vertical whitespace with horizontal");
  }

  # So, this is probably never going to be needed, but let's not get into a
  # place where we're writing the first byte of a multibyte sequence at a line
  # boundary, and then the next byte gets overwritten, etc...
  # -- rjbs, 2016-05-20
  utf8::encode($message);

  if (length $message > $fit) {
    $self->log(1, "!!! truncating message to fit in slot");
    $message = substr $message, 0, $fit;
  }

  $message = sprintf "%-6s %s %-*s\n", $$, $ts, $fit, $message;

  my $fh = $self->{tracker}{write_fh};
  my $offset = $slot * $len;
  seek $fh, $offset, 0;
  print {$fh} $message;

  return;
}

sub delete_child {
  my ($self, $pid) = @_;
  my $slot = delete $self->{tracker}{slot}{$pid};

  if (defined $slot) {
    $self->{tracker}{array}[$slot] = undef;
  } else {
    $self->log(1, "!!! just reaped an unregistered child, pid $pid");
  }

  return $self->SUPER($pid);
}

1;
__END__

=head1 NAME

PageCamel::Net::Server::Tracker - useful debugging shim

=head1 WARNING

This is a debugging shim that has seen very limited testing. AND it relies on a patch
to PageCamel::Net::Server that ALSO has seen limited testing. So it would be best to make sure you do NOT use
this in production, only ofor testing.

=head1 SYNOPSIS

This package is a shim to stick between a PageCamel::Net::Server personality and your server code. 
It creates a tracking file for the server and every worker can update one line in the
file. By looking at this file, you can see which servers are active, whether some are
stuck, and maybe what they're stuck on.

Sometimes this sort of thing is done by updating the contents of $0, but this isn't portable
(to Solaris, for example). It is also length-limited and might have some other side effects
(like "killall" not working correctly)

=head1 DESCRIPTION

Add some tracking points in your server...

    package Your::Cool::Server;
    use parent 'PageCamel::Net::Server::Tracker', 'PageCamel::Net::Server::PreFork';
    
    sub process_request ($self) {
        #... do some stuff
        $self->update_tracking("just did some stuff");
    
        # ... more stuff
        $self->update_tracking("did some more stuff, okay?");
    
        # ... finish up
    }

...and configure your runner with the filename...

    use Your::Cool::Server;
    
    my $server = Your::Cool::Server->new({
        # ... your usual configuration ...
        tracker => { filename => "/var/run/cool.tracker" }
    });
    
    $server->run;

...then, in /var/run/cool.tracker you'll find a file something like this:

    20466  2016-05-20T16:46:01 child online
    20467  2016-05-20T16:46:01 child online
    20468  2016-05-20T16:46:01 child online
    20469  2016-05-20T16:46:02 child online
    20470  2016-05-20T16:46:02 child online
    20472  2016-05-20T16:46:02 child online

(There will be lots of trailing spaces and blank lines. Don't sweat it.)

The lines will be updated by processes as they run, and will be reused by new servers when old servers exit after processing all the requests in their lifetime.

=head1 AUTHOR

Original author:
Ricardo Signes L<https://github.com/rjbs>

This fork:
Rene Schickbauer L<cavac@cpan.org>

=head1 LICENSE

This package may be distributed under the terms of either the
GNU General Public License
or the
Perl Artistic License

=head1 SEE ALSO

Please see also
L<PageCamel::Net::Server>,
L<PageCamel::Net::Server::Fork>,
L<PageCamel::Net::Server::INET>,
L<PageCamel::Net::Server::PreForkSimple>,
L<PageCamel::Net::Server::MultiType>,
L<PageCamel::Net::Server::Single>,
L<PageCamel::Net::Server::SIG>,
L<PageCamel::Net::Server::Daemonize>,
L<PageCamel::Net::Server::Proto>

=cut

