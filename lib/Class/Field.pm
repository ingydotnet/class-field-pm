use strict; use warnings;
package Class::Field;
our $VERSION = '0.24';

use base 'Exporter';

our @EXPORT_OK = qw(field const);

use Encode;

my %code = (
    sub_start =>
      "sub {\n  local \*__ANON__ = \"%s::%s\";\n",
    set_default =>
      "  \$_[0]->{%s} = %s\n    unless exists \$_[0]->{%s};\n",
    init =>
      "  return \$_[0]->{%s} = do { my \$self = \$_[0]; %s }\n" .
      "    unless \$#_ > 0 or defined \$_[0]->{%s};\n",
    weak_init =>
      "  return do {\n" .
      "    \$_[0]->{%s} = do { my \$self = \$_[0]; %s };\n" .
      "    Scalar::Util::weaken(\$_[0]->{%s}) if ref \$_[0]->{%s};\n" .
      "    \$_[0]->{%s};\n" .
      "  } unless \$#_ > 0 or defined \$_[0]->{%s};\n",
    return_if_get =>
      "  return \$_[0]->{%s} unless \$#_ > 0;\n",
    isa_exception => "die('failed isa check for %s')",
    isa =>
      "  do { local \$_ = \$_[1]; \$type->(\$_[1]) } or %s;\n",
    isa_typetiny =>
      "  %s;",
    isa_inline_check =>
      "  do { %s } or %s;",
    isa_check =>
      "  \$type->check(\$_[1]) or %s;",
    set =>
      "  \$_[0]->{%s} = \$_[1];\n",
    weaken =>
      "  Scalar::Util::weaken(\$_[0]->{%s}) if ref \$_[0]->{%s};\n",
    sub_end =>
      "  return \$_[0]->{%s};\n}\n",
);

sub field {
    my $package = caller;
    my ($args, @values) = do {
        no warnings;
        local *boolean_arguments = sub { (qw(-weak)) };
        local *paired_arguments = sub { (qw(-package -init -isa)) };
        Class::Field->parse_arguments(@_);
    };
    my ($field, $default) = @values;
    $package = $args->{-package} if defined $args->{-package};
    die "Cannot have a default for a weakened field ($field)"
        if defined $default && $args->{-weak};
    return if defined &{"${package}::$field"};
    require Scalar::Util if $args->{-weak};
    my $default_string =
        ( ref($default) eq 'ARRAY' and not @$default )
        ? '[]'
        : (ref($default) eq 'HASH' and not keys %$default )
          ? '{}'
          : default_as_code($default);

    my $code = sprintf $code{sub_start}, $package, $field;
    if ($args->{-init}) {
        if ($args->{-weak}) {
            $code .= sprintf $code{weak_init}, $field, $args->{-init}, ($field) x 4;
        } else {
            $code .= sprintf $code{init}, $field, $args->{-init}, $field;
        }
    }
    $code .= sprintf $code{set_default}, $field, $default_string, $field
      if defined $default;
    $code .= sprintf $code{return_if_get}, $field;
    
    my $type; # if type cannot be inlined, this will be closed over
    if ($type = $args->{-isa}) {
        my $ecode = sprintf $code{isa_exception}, $field;
        if (ref($type) eq 'CODE') {
            $code .= sprintf $code{isa}, $ecode;
        }
        elsif (eval { $type->isa('Type::Tiny'); Type::Tiny->VERSION('1.008') }) {
            $code .= sprintf $code{isa_typetiny}, $type->inline_assert('$_[1]', '$type', attribute_name => $field, attribute_step => 'isa check');
        }
        elsif (eval { $type->can_be_inlined }) {
            my $i = $type->can('inline_check') || $type->can('_inline_check');
            $code .= sprintf $code{isa_inline_check}, $type->$i('$_[1]'), $ecode;
        }
        elsif (eval { $type->can('check') }) {
            $code .= sprintf $code{isa_check}, $ecode;
        }
        else {
            die 'cannot handle -isa';
        }
    }
    
    $code .= sprintf $code{set}, $field;
    $code .= sprintf $code{weaken}, $field, $field
      if $args->{-weak};
    $code .= sprintf $code{sub_end}, $field;

    my $sub = eval $code;
    die $@ if $@;
    no strict 'refs';
    use utf8;
    my $method = "${package}::$field";
    $method = Encode::decode_utf8($method);
    *{$method} = $sub;
    return $code if defined wantarray;
}

sub default_as_code {
    no warnings 'once';
    require Data::Dumper;
    local $Data::Dumper::Sortkeys = 1;
    my $code = Data::Dumper::Dumper(shift);
    $code =~ s/^\$VAR1 = //;
    $code =~ s/;$//;
    return $code;
}

sub const {
    my $package = caller;
    my ($args, @values) = do {
        no warnings;
        local *paired_arguments = sub { (qw(-package)) };
        Class::Field->parse_arguments(@_);
    };
    my ($field, $default) = @values;
    $package = $args->{-package} if defined $args->{-package};
    no strict 'refs';
    return if defined &{"${package}::$field"};
    *{"${package}::$field"} = sub { $default }
}

sub parse_arguments {
    my $class = shift;
    my ($args, @values) = ({}, ());
    my %booleans = map { ($_, 1) } $class->boolean_arguments;
    my %pairs = map { ($_, 1) } $class->paired_arguments;
    while (@_) {
        my $elem = shift;
        if (defined $elem and defined $booleans{$elem}) {
            $args->{$elem} = (@_ and $_[0] =~ /^[01]$/)
            ? shift
            : 1;
        }
        elsif (defined $elem and defined $pairs{$elem} and @_) {
            $args->{$elem} = shift;
        }
        else {
            push @values, $elem;
        }
    }
    return wantarray ? ($args, @values) : $args;
}

sub boolean_arguments { () }
sub paired_arguments { () }

1;
