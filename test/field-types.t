use strict;
use lib (-e 't' ? 't' : 'test'), 'inc';

use Test::More;

BEGIN {
    eval { require Types::Standard; }
        ? plan(tests    => 1)
        : plan(skip_all => 'test require Types::Standard')
};

package Foo;
use base 'TestFieldBase';
use Class::Field 'field';
use Types::Standard qw( ArrayRef );

field 'x', -isa => sub { not ref };
field 'y' => [], -isa => ArrayRef;
field 'z' => {}, -isa => sub { die "not hash" unless ref eq 'HASH' };
field 'i', -init => '$self->hello';

sub hello {
    my $self = shift;
    return 'Howdy';
}

package main;

my $foo = Foo->new;

$foo->y( [] );
is_deeply($foo->y, []);

{
    local $@;
    my $e;
    eval { $foo->x([]); 1 } or $e = $@;
    like($e, qr/failed isa check for x/);
}

{
    local $@;
    my $e;
    eval { $foo->y(123); 1 } or $e = $@;
    like($e, qr/did not pass type/);
}

{
    local $@;
    my $e;
    eval { $foo->z(123); 1 } or $e = $@;
    like($e, qr/not hash/);
}
