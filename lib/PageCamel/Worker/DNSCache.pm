package PageCamel::Worker::DNSCache;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class


    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");

    return;
}

sub crossregister {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $self->{cachedelsth} = $dbh->prepare_cached("DELETE FROM nameserver_extern_cache
                                           WHERE validuntil < now()")
            or croak($dbh->errstr);

    $dbh->commit;

    return;

}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    if(!$self->{cachedelsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }

    $workCount++;
    $dbh->commit;

    return $workCount;
}

1;
__END__
