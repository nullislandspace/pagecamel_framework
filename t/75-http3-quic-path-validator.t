#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time sleep);

# Test QUIC Path Validator

use_ok('PageCamel::Protocol::QUIC::PathValidator');

# Test basic creation
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();
    ok($validator, 'Created path validator');

    my $stats = $validator->stats();
    is($stats->{validationsStarted}, 0, 'Initial validations started is 0');
    is($stats->{validationsSucceeded}, 0, 'Initial validations succeeded is 0');
}

# Test path states
{
    ok(PageCamel::Protocol::QUIC::PathValidator::PATH_UNKNOWN() == 0, 'PATH_UNKNOWN is 0');
    ok(PageCamel::Protocol::QUIC::PathValidator::PATH_VALIDATING() == 1, 'PATH_VALIDATING is 1');
    ok(PageCamel::Protocol::QUIC::PathValidator::PATH_VALIDATED() == 2, 'PATH_VALIDATED is 2');
    ok(PageCamel::Protocol::QUIC::PathValidator::PATH_FAILED() == 3, 'PATH_FAILED is 3');
}

# Test initiating validation
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path = {
        local  => { host => '192.168.1.1', port => 443 },
        remote => { host => '10.0.0.1', port => 54321 },
    };

    my $challenge = $validator->initiateValidation($path);
    ok($challenge, 'Initiated validation');
    ok($challenge->{pathKey}, 'Has path key');
    ok($challenge->{challengeData}, 'Has challenge data');
    is(length($challenge->{challengeData}), 8, 'Challenge data is 8 bytes');

    my $stats = $validator->stats();
    is($stats->{validationsStarted}, 1, 'Validations started is 1');
    is($stats->{pendingCount}, 1, 'Pending count is 1');
}

# Test handling PATH_CHALLENGE
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $challengeData = 'testdata';
    my $fromPath = { host => '10.0.0.1', port => 54321 };

    my $response = $validator->handleChallenge($challengeData, $fromPath);
    ok($response, 'Generated response');
    is($response->{responseData}, $challengeData, 'Response data matches challenge');
    is($response->{toPath}, $fromPath, 'Response directed to correct path');
}

# Test successful path validation
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path = {
        local  => { host => '192.168.1.1', port => 443 },
        remote => { host => '10.0.0.1', port => 54321 },
    };

    # Initiate validation
    my $challenge = $validator->initiateValidation($path);

    # Check initial state
    my $state = $validator->getPathState($path);
    is($state, PageCamel::Protocol::QUIC::PathValidator::PATH_VALIDATING(), 'Path is validating');
    ok(!$validator->isPathValidated($path), 'Path not yet validated');

    # Handle response with correct data
    my $result = $validator->handleResponse($challenge->{challengeData}, $path);
    ok($result, 'Response accepted');

    # Check final state
    $state = $validator->getPathState($path);
    is($state, PageCamel::Protocol::QUIC::PathValidator::PATH_VALIDATED(), 'Path is validated');
    ok($validator->isPathValidated($path), 'isPathValidated returns true');

    my $stats = $validator->stats();
    is($stats->{validationsSucceeded}, 1, 'Validations succeeded is 1');
}

# Test failed response (wrong data)
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path = { remote => { host => '10.0.0.2', port => 12345 } };

    my $challenge = $validator->initiateValidation($path);

    # Send wrong response data
    my $result = $validator->handleResponse('wrongdata', $path);
    ok(!$result, 'Wrong response rejected');

    # Path should still be validating
    ok(!$validator->isPathValidated($path), 'Path not validated after wrong response');
}

# Test unknown path
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $unknownPath = { remote => { host => '1.2.3.4', port => 9999 } };

    my $state = $validator->getPathState($unknownPath);
    is($state, PageCamel::Protocol::QUIC::PathValidator::PATH_UNKNOWN(), 'Unknown path state is UNKNOWN');
}

# Test pending validations list
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path1 = { remote => { host => '10.0.0.1', port => 1111 } };
    my $path2 = { remote => { host => '10.0.0.2', port => 2222 } };

    $validator->initiateValidation($path1);
    $validator->initiateValidation($path2);

    my @pending = $validator->getPendingValidations();
    is(scalar(@pending), 2, 'Two pending validations');
}

# Test cancel validation
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path = { remote => { host => '10.0.0.3', port => 3333 } };
    $validator->initiateValidation($path);

    ok(scalar($validator->getPendingValidations()) == 1, 'One pending');

    $validator->cancelValidation($path);

    ok(scalar($validator->getPendingValidations()) == 0, 'No pending after cancel');
}

# Test invalidate path
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path = { remote => { host => '10.0.0.4', port => 4444 } };

    # Validate a path
    my $challenge = $validator->initiateValidation($path);
    $validator->handleResponse($challenge->{challengeData}, $path);
    ok($validator->isPathValidated($path), 'Path validated');

    # Invalidate it
    $validator->invalidatePath($path);
    ok(!$validator->isPathValidated($path), 'Path no longer validated');
}

# Test timeout and retry
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new(
        validation_timeout => 0.1,  # 100ms timeout
        max_retries        => 2,
    );

    my $path = { remote => { host => '10.0.0.5', port => 5555 } };
    my $challenge = $validator->initiateValidation($path);

    # Wait for timeout
    sleep(0.15);

    my @expired = $validator->checkTimeouts();
    is(scalar(@expired), 1, 'One expired validation');
    is($expired[0]->{action}, 'retry', 'Action is retry');
    ok($expired[0]->{challengeData} ne $challenge->{challengeData}, 'New challenge generated');
}

# Test max retries exceeded
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new(
        validation_timeout => 0.05,  # 50ms timeout
        max_retries        => 1,
    );

    my $path = { remote => { host => '10.0.0.6', port => 6666 } };
    $validator->initiateValidation($path);

    # First timeout - retry
    sleep(0.06);
    my @expired1 = $validator->checkTimeouts();
    is($expired1[0]->{action}, 'retry', 'First timeout is retry');

    # Second timeout - fail
    sleep(0.06);
    my @expired2 = $validator->checkTimeouts();
    is($expired2[0]->{action}, 'failed', 'Second timeout is failed');

    my $stats = $validator->stats();
    is($stats->{validationsFailed}, 1, 'Validation failed count is 1');
}

# Test different paths for same remote address with different ports
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new();

    my $path1 = { remote => { host => '10.0.0.7', port => 7777 } };
    my $path2 = { remote => { host => '10.0.0.7', port => 8888 } };

    my $challenge1 = $validator->initiateValidation($path1);
    my $challenge2 = $validator->initiateValidation($path2);

    # Validate path1
    $validator->handleResponse($challenge1->{challengeData}, $path1);

    ok($validator->isPathValidated($path1), 'Path1 validated');
    ok(!$validator->isPathValidated($path2), 'Path2 not validated (different port)');
}

# Test stats tracking
{
    my $validator = PageCamel::Protocol::QUIC::PathValidator->new(
        validation_timeout => 0.05,
        max_retries        => 0,
    );

    # Start and succeed one validation
    my $path1 = { remote => { host => '10.1.0.1', port => 1111 } };
    my $challenge1 = $validator->initiateValidation($path1);
    $validator->handleResponse($challenge1->{challengeData}, $path1);

    # Start and let one fail
    my $path2 = { remote => { host => '10.1.0.2', port => 2222 } };
    $validator->initiateValidation($path2);
    sleep(0.06);
    $validator->checkTimeouts();

    my $stats = $validator->stats();
    is($stats->{validationsStarted}, 2, 'Started 2');
    is($stats->{validationsSucceeded}, 1, 'Succeeded 1');
    is($stats->{validationsFailed}, 1, 'Failed 1');
    is($stats->{validatedCount}, 1, 'Validated count 1');
}

done_testing();
