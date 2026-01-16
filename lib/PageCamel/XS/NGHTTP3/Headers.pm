package PageCamel::XS::NGHTTP3::Headers;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# High-level wrapper for HTTP/3 headers

sub new($class, @pairs) {
    my $self = bless {
        headers => [],
        pseudo_headers => {},
    }, $class;

    while (@pairs) {
        my $name = shift @pairs;
        my $value = shift @pairs // '';
        $self->add($name, $value);
    }

    return $self;
}

sub add($self, $name, $value) {
    # Normalize header name to lowercase (HTTP/3 requirement)
    $name = lc($name);

    # Track pseudo-headers separately
    if ($name =~ /^:/) {
        $self->{pseudo_headers}{$name} = $value;
    }

    push @{$self->{headers}}, [$name, $value];
    return $self;
}

sub set($self, $name, $value) {
    $name = lc($name);

    # Remove existing headers with this name
    $self->{headers} = [
        grep { $_->[0] ne $name } @{$self->{headers}}
    ];

    # Add the new value
    return $self->add($name, $value);
}

sub get($self, $name) {
    $name = lc($name);

    for my $header (@{$self->{headers}}) {
        return $header->[1] if $header->[0] eq $name;
    }

    return undef;
}

sub get_all($self, $name) {
    $name = lc($name);
    return map { $_->[1] } grep { $_->[0] eq $name } @{$self->{headers}};
}

sub remove($self, $name) {
    $name = lc($name);
    $self->{headers} = [
        grep { $_->[0] ne $name } @{$self->{headers}}
    ];

    delete $self->{pseudo_headers}{$name} if $name =~ /^:/;
    return $self;
}

sub has($self, $name) {
    return defined $self->get($name);
}

# Get pseudo-headers
sub method($self)    { return $self->{pseudo_headers}{':method'}; }
sub scheme($self)    { return $self->{pseudo_headers}{':scheme'}; }
sub authority($self) { return $self->{pseudo_headers}{':authority'}; }
sub path($self)      { return $self->{pseudo_headers}{':path'}; }
sub status($self)    { return $self->{pseudo_headers}{':status'}; }
sub protocol($self)  { return $self->{pseudo_headers}{':protocol'}; }

# Convert to flat array for XS functions
sub to_array($self) {
    my @result;
    for my $header (@{$self->{headers}}) {
        push @result, $header->[0], $header->[1];
    }
    return @result;
}

# Convert to array reference for XS functions
sub to_arrayref($self) {
    return [$self->to_array()];
}

# Convert to hash (note: loses duplicate headers)
sub to_hash($self) {
    my %hash;
    for my $header (@{$self->{headers}}) {
        $hash{$header->[0]} = $header->[1];
    }
    return %hash;
}

# Iterate over headers
sub each($self, $callback) {
    for my $header (@{$self->{headers}}) {
        $callback->($header->[0], $header->[1]);
    }
}

# Get all header names
sub names($self) {
    my %seen;
    return grep { !$seen{$_}++ } map { $_->[0] } @{$self->{headers}};
}

# Get count of headers
sub count($self) {
    return scalar @{$self->{headers}};
}

# Clone headers
sub clone($self) {
    my $new = ref($self)->new();
    for my $header (@{$self->{headers}}) {
        $new->add($header->[0], $header->[1]);
    }
    return $new;
}

# Create request headers
sub request($class, %opts) {
    my $self = $class->new();

    # Required pseudo-headers for requests
    $self->add(':method', $opts{method} // 'GET');
    $self->add(':scheme', $opts{scheme} // 'https');
    $self->add(':authority', $opts{authority}) if $opts{authority};
    $self->add(':path', $opts{path} // '/');

    # Extended CONNECT for WebSocket
    if ($opts{protocol}) {
        $self->add(':protocol', $opts{protocol});
    }

    return $self;
}

# Create response headers
sub response($class, %opts) {
    my $self = $class->new();

    # Required pseudo-header for responses
    $self->add(':status', $opts{status} // '200');

    # Common headers
    $self->add('content-type', $opts{content_type}) if $opts{content_type};
    $self->add('content-length', $opts{content_length}) if defined $opts{content_length};

    return $self;
}

# Validate request headers
sub validate_request($self) {
    my @errors;

    # Required pseudo-headers
    push @errors, "Missing :method" unless $self->method;
    push @errors, "Missing :scheme" unless $self->scheme;
    push @errors, "Missing :path" unless $self->path;

    # :authority or Host required (but not checked here for flexibility)

    # CONNECT requests have different requirements
    if ($self->method eq 'CONNECT') {
        if ($self->protocol) {
            # Extended CONNECT (RFC 8441)
            push @errors, "Extended CONNECT requires :scheme" unless $self->scheme;
            push @errors, "Extended CONNECT requires :path" unless $self->path;
        } else {
            # Regular CONNECT
            push @errors, "CONNECT must not have :scheme" if $self->scheme;
            push @errors, "CONNECT must not have :path" if $self->path;
        }
    }

    return @errors;
}

# Validate response headers
sub validate_response($self) {
    my @errors;

    push @errors, "Missing :status" unless $self->status;

    my $status = $self->status;
    if (defined $status && ($status < 100 || $status > 599)) {
        push @errors, "Invalid status code: $status";
    }

    return @errors;
}

1;

__END__

=head1 NAME

PageCamel::XS::NGHTTP3::Headers - High-level HTTP/3 headers wrapper

=head1 SYNOPSIS

    use PageCamel::XS::NGHTTP3::Headers;

    # Create headers from pairs
    my $headers = PageCamel::XS::NGHTTP3::Headers->new(
        'content-type' => 'text/html',
        'cache-control' => 'no-cache',
    );

    # Add more headers
    $headers->add('x-custom', 'value');

    # Get header value
    my $ct = $headers->get('content-type');

    # Convert to array for XS
    my @arr = $headers->to_array();

    # Create request headers
    my $req = PageCamel::XS::NGHTTP3::Headers->request(
        method    => 'GET',
        scheme    => 'https',
        authority => 'example.com',
        path      => '/api/data',
    );

    # Create response headers
    my $res = PageCamel::XS::NGHTTP3::Headers->response(
        status       => '200',
        content_type => 'application/json',
    );

=head1 DESCRIPTION

This class provides a high-level interface for working with HTTP/3 headers.
It handles header normalization (lowercase names), pseudo-headers, and
conversion to formats needed by the XS bindings.

=head1 HTTP/3 PSEUDO-HEADERS

HTTP/3 uses pseudo-headers (prefixed with ':') for request/response metadata:

=head2 Request Pseudo-Headers

=over 4

=item :method - HTTP method (GET, POST, etc.)

=item :scheme - URI scheme (https)

=item :authority - Host and optional port

=item :path - Request path and query string

=item :protocol - For extended CONNECT (WebSocket)

=back

=head2 Response Pseudo-Headers

=over 4

=item :status - HTTP status code

=back

=head1 CONSTRUCTOR

=head2 new(@pairs)

Create headers from name-value pairs.

=head2 request(%options)

Create request headers with proper pseudo-headers.

Options: method, scheme, authority, path, protocol

=head2 response(%options)

Create response headers with :status pseudo-header.

Options: status, content_type, content_length

=head1 METHODS

=head2 add($name, $value)

Add a header (allows duplicates).

=head2 set($name, $value)

Set a header (replaces existing).

=head2 get($name)

Get first header value.

=head2 get_all($name)

Get all values for a header.

=head2 remove($name)

Remove all headers with this name.

=head2 has($name)

Check if header exists.

=head2 to_array()

Convert to flat array: (name1, value1, name2, value2, ...)

=head2 to_arrayref()

Convert to array reference.

=head2 to_hash()

Convert to hash (loses duplicates).

=head2 each($callback)

Iterate over headers.

=head2 names()

Get unique header names.

=head2 count()

Get number of headers.

=head2 clone()

Create a copy of headers.

=head2 validate_request()

Validate request headers. Returns list of errors.

=head2 validate_response()

Validate response headers. Returns list of errors.

=head1 PSEUDO-HEADER ACCESSORS

=over 4

=item method() - :method value

=item scheme() - :scheme value

=item authority() - :authority value

=item path() - :path value

=item status() - :status value

=item protocol() - :protocol value (extended CONNECT)

=back

=head1 SEE ALSO

L<PageCamel::XS::NGHTTP3>, L<PageCamel::Protocol::HTTP3::Server>

=cut
