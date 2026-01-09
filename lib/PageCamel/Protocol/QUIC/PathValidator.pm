package PageCamel::Protocol::QUIC::PathValidator;
use v5.38;
use strict;
use warnings;

use Time::HiRes qw(time);
use Carp qw(croak);

our $VERSION = '0.01';

# Path validation states
use constant {
    PATH_UNKNOWN    => 0,
    PATH_VALIDATING => 1,
    PATH_VALIDATED  => 2,
    PATH_FAILED     => 3,
};

# Validation parameters
use constant {
    CHALLENGE_SIZE     => 8,      # 8 bytes for PATH_CHALLENGE data
    VALIDATION_TIMEOUT => 3,      # 3 seconds for validation
    MAX_RETRIES        => 3,      # Maximum validation attempts
};

sub new($class, %config) {
    my $self = bless {
        # Configuration
        validationTimeout => $config{validation_timeout} // VALIDATION_TIMEOUT,
        maxRetries        => $config{max_retries} // MAX_RETRIES,

        # Pending validations
        pendingValidations => {},  # path_key -> validation_state

        # Validated paths
        validatedPaths     => {},  # path_key -> validation_time

        # Associated connection
        connection         => $config{connection},

        # Statistics
        validationsStarted   => 0,
        validationsSucceeded => 0,
        validationsFailed    => 0,
    }, $class;

    return $self;
}

sub initiateValidation($self, $newPath) {
    my $pathKey = $self->_pathKey($newPath);

    # Generate challenge data
    my $challengeData = $self->_generateChallenge();

    my $validation = {
        path          => $newPath,
        state         => PATH_VALIDATING,
        challengeData => $challengeData,
        startedAt     => time(),
        retryCount    => 0,
        expiresAt     => time() + $self->{validationTimeout},
    };

    $self->{pendingValidations}->{$pathKey} = $validation;
    $self->{validationsStarted}++;

    return {
        pathKey       => $pathKey,
        challengeData => $challengeData,
    };
}

sub handleChallenge($self, $challengeData, $fromPath) {
    # Respond to a PATH_CHALLENGE with PATH_RESPONSE
    # The response data must match the challenge data exactly

    return {
        responseData => $challengeData,
        toPath       => $fromPath,
    };
}

sub handleResponse($self, $responseData, $fromPath) {
    my $pathKey = $self->_pathKey($fromPath);
    my $validation = $self->{pendingValidations}->{$pathKey};

    return 0 unless(defined($validation));
    return 0 if($validation->{state} != PATH_VALIDATING);

    # Verify response matches challenge
    if($responseData eq $validation->{challengeData}) {
        # Validation succeeded
        $validation->{state} = PATH_VALIDATED;
        $validation->{validatedAt} = time();

        # Move to validated paths
        $self->{validatedPaths}->{$pathKey} = time();
        delete $self->{pendingValidations}->{$pathKey};

        $self->{validationsSucceeded}++;

        return 1;
    }

    return 0;
}

sub isPathValidated($self, $path) {
    my $pathKey = $self->_pathKey($path);
    return defined($self->{validatedPaths}->{$pathKey});
}

sub getPathState($self, $path) {
    my $pathKey = $self->_pathKey($path);

    if(defined($self->{validatedPaths}->{$pathKey})) {
        return PATH_VALIDATED;
    }

    my $validation = $self->{pendingValidations}->{$pathKey};
    if(defined($validation)) {
        return $validation->{state};
    }

    return PATH_UNKNOWN;
}

sub getPendingValidations($self) {
    my @pending;

    for my $pathKey (keys %{$self->{pendingValidations}}) {
        my $validation = $self->{pendingValidations}->{$pathKey};
        push @pending, {
            pathKey       => $pathKey,
            path          => $validation->{path},
            state         => $validation->{state},
            challengeData => $validation->{challengeData},
            retryCount    => $validation->{retryCount},
            expiresAt     => $validation->{expiresAt},
        };
    }

    return @pending;
}

sub checkTimeouts($self) {
    my $now = time();
    my @expired;

    for my $pathKey (keys %{$self->{pendingValidations}}) {
        my $validation = $self->{pendingValidations}->{$pathKey};

        if($validation->{expiresAt} < $now) {
            if($validation->{retryCount} < $self->{maxRetries}) {
                # Retry with new challenge
                $validation->{challengeData} = $self->_generateChallenge();
                $validation->{retryCount}++;
                $validation->{expiresAt} = $now + $self->{validationTimeout};

                push @expired, {
                    pathKey       => $pathKey,
                    action        => 'retry',
                    challengeData => $validation->{challengeData},
                    path          => $validation->{path},
                };
            } else {
                # Validation failed
                $validation->{state} = PATH_FAILED;
                $self->{validationsFailed}++;

                push @expired, {
                    pathKey => $pathKey,
                    action  => 'failed',
                    path    => $validation->{path},
                };

                delete $self->{pendingValidations}->{$pathKey};
            }
        }
    }

    return @expired;
}

sub cancelValidation($self, $path) {
    my $pathKey = $self->_pathKey($path);
    delete $self->{pendingValidations}->{$pathKey};
    return 1;
}

sub invalidatePath($self, $path) {
    my $pathKey = $self->_pathKey($path);
    delete $self->{validatedPaths}->{$pathKey};
    delete $self->{pendingValidations}->{$pathKey};
    return 1;
}

sub _pathKey($self, $path) {
    # Create a unique key for a path
    my $localAddr = $path->{local} // $path->{localAddr} // {};
    my $remoteAddr = $path->{remote} // $path->{remoteAddr} // $path;

    my $localHost = $localAddr->{host} // $localAddr->{ip} // '*';
    my $localPort = $localAddr->{port} // '*';
    my $remoteHost = $remoteAddr->{host} // $remoteAddr->{ip} // '';
    my $remotePort = $remoteAddr->{port} // '';

    return "$localHost:$localPort-$remoteHost:$remotePort";
}

sub _generateChallenge($self) {
    my $challenge = '';
    for my $i (1 .. CHALLENGE_SIZE) {
        $challenge .= chr(int(rand(256)));
    }
    return $challenge;
}

sub stats($self) {
    return {
        validationsStarted   => $self->{validationsStarted},
        validationsSucceeded => $self->{validationsSucceeded},
        validationsFailed    => $self->{validationsFailed},
        pendingCount         => scalar(keys %{$self->{pendingValidations}}),
        validatedCount       => scalar(keys %{$self->{validatedPaths}}),
    };
}

1;

__END__

=head1 NAME

PageCamel::Protocol::QUIC::PathValidator - QUIC path validation for connection migration

=head1 SYNOPSIS

    use PageCamel::Protocol::QUIC::PathValidator;

    my $validator = PageCamel::Protocol::QUIC::PathValidator->new(
        validation_timeout => 3,
        max_retries        => 3,
    );

    # Start validation for a new path
    my $challenge = $validator->initiateValidation($newPath);
    # Send PATH_CHALLENGE frame with $challenge->{challengeData}

    # Handle incoming PATH_CHALLENGE
    my $response = $validator->handleChallenge($data, $fromPath);
    # Send PATH_RESPONSE with $response->{responseData}

    # Handle incoming PATH_RESPONSE
    if($validator->handleResponse($data, $fromPath)) {
        # Path is now validated, migration can proceed
    }

    # Check if path is validated
    if($validator->isPathValidated($path)) {
        # Safe to use this path
    }

=head1 DESCRIPTION

This module implements QUIC path validation as defined in RFC 9000
Section 8.2. Path validation is required before a connection can
migrate to a new network path.

=head1 PATH VALIDATION PROCESS

1. When a packet arrives from a new source address, initiate path validation
2. Send PATH_CHALLENGE frame containing random 8-byte data
3. Wait for PATH_RESPONSE frame with the same data
4. If response received within timeout, path is validated
5. If timeout expires, retry or mark path as failed

=head1 METHODS

=head2 new(%config)

Create a new path validator.

Options:

=over 4

=item validation_timeout - Timeout in seconds (default: 3)

=item max_retries - Maximum retry attempts (default: 3)

=item connection - Associated QUIC connection

=back

=head2 initiateValidation($newPath)

Start validation for a new path. Returns challenge data to send.

=head2 handleChallenge($data, $fromPath)

Process an incoming PATH_CHALLENGE. Returns response data.

=head2 handleResponse($data, $fromPath)

Process an incoming PATH_RESPONSE. Returns true if path validated.

=head2 isPathValidated($path)

Check if a path has been validated.

=head2 getPathState($path)

Get the current state of a path (UNKNOWN, VALIDATING, VALIDATED, FAILED).

=head2 getPendingValidations()

Get list of pending validations.

=head2 checkTimeouts()

Check for expired validations and trigger retries or failures.

=head2 cancelValidation($path)

Cancel an in-progress validation.

=head2 invalidatePath($path)

Remove a path from the validated list.

=head1 CONSTANTS

=over 4

=item PATH_UNKNOWN - Path not known

=item PATH_VALIDATING - Validation in progress

=item PATH_VALIDATED - Path validated successfully

=item PATH_FAILED - Validation failed

=back

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::ConnectionIDManager>,
L<PageCamel::Protocol::QUIC::Connection>,
RFC 9000 Section 8.2

=cut
