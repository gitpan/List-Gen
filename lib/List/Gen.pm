package List::Gen;
    use warnings;
    use strict;
    use Carp;
    use Symbol       'delete_package';
    use Scalar::Util 'reftype';
    use List::Util
    our @list_util   = qw/first max maxstr min minstr reduce shuffle sum/;
    our @EXPORT      = qw/mapn by every range gen cap filter test cache apply
                        zip min max reduce/;
    our @EXPORT_OK   = (our @list_util, @EXPORT, qw/glob mapkey cartesian d
                        sequence deref slide flip expand contract collect
                        makegen genzip overlay curse iterate gather/);
    our %EXPORT_TAGS = (base => \@EXPORT, all => \@EXPORT_OK);
    our $VERSION     = '0.70';
    our $LIST        = 0;
    our $FILTER_LOOKAHEAD = 1;
    BEGIN {
        require Exporter;
        require overload;
    }

    sub import {
        return unless @_;
        if (@_ == 2 and !$_[1] || $_[1] eq '*')
            {splice @_, 1, 1, ':all'}
        goto &{Exporter->can('import')}
    }

=head1 NAME

List::Gen - provides functions for generating lists

=head1 VERSION

version 0.70

=head1 SYNOPSIS

this module provides higher order functions, generators, iterators, and other
utility functions for working with lists. walk lists with any step size you
want, create lazy ranges and arrays with a map like syntax that generate values
on demand. there are several other hopefully useful functions, and all functions
from List::Util are available.

    use List::Gen;

    print "@$_\n" for every 5 => 1 .. 15;
    # 1 2 3 4 5
    # 6 7 8 9 10
    # 11 12 13 14 15

    print mapn {"$_[0]: $_[1]\n"} 2 => %myhash;

    for (@{range 0.345, -21.5, -0.5}) {
        # loops over 0.345, -0.155, -0.655, -1.155 ... -21.155
    }

    my $fib; $fib = cache gen {$_ < 2  ? $_ : $$fib[$_ - 1] + $$fib[$_ - 2]};
    my $fac; $fac = cache gen {$_ < 2 or $_ * $$fac[$_ - 1]};

    say "@$fib[0 .. 15]";  #  0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610
    say "@$fac[0 .. 10]";  #  1 1 2 6 24 120 720 5040 40320 362880 3628800

=head1 EXPORT

    use List::Gen; # is the same as
    use List::Gen qw/mapn by every range gen cap filter test cache apply zip
                     min max reduce/;

    the following functions are available:
        mapn by every range gen cap filter test cache apply zip min max reduce
        glob mapkey cartesian sequence d deref slide flip expand contract
        collect makegen genzip overlay iterate gather curse

    and from List::Util => first max maxstr min minstr reduce shuffle sum

    use List::Gen '*';     # everything
    use List::Gen ':all';  # same
    use List::Gen ':base'; # same as 'use List::Gen;'

=head1 FUNCTIONS

=over 8

=item C< mapn CODE NUM LIST >

this function works like the builtin C< map > but takes C< NUM > sized steps
over the list, rather than one element at a time. inside the C< CODE > block,
the current slice is in C< @_ > and C< $_ > is set to C< $_[0] >. slice elements
are aliases to the original list. if C< mapn > is called in void context, the
C< CODE > block will be executed in void context for efficiency.

    print mapn {$_ % 2 ? "@_" : " [@_] "} 3 => 1..20;
    #  1 2 3 [4 5 6] 7 8 9 [10 11 12] 13 14 15 [16 17 18] 19 20

    print "student grades: \n";
    mapn {
        print shift, ": ", (reduce {$a + $b} @_)/@_, "\n";
    } 5 => qw {
        bob   90 80 65 85
        alice 75 95 70 100
        eve   80 90 80 75
    };

=cut
    sub mapn (&$@) {
        my ($sub, $n, @ret) = splice @_, 0, 2;
        croak '$_[1] must be >= 1' unless $n >= 1;

        return map $sub->($_) => @_ if $n == 1;

        my $want = defined wantarray;
        while (@_) {
            local *_ = \$_[0];
            if ($want) {push @ret =>
                  $sub->(splice @_, 0, $n)}
            else {$sub->(splice @_, 0, $n)}
        }
        @ret
    }

    sub packager {
        unshift @_, split /\s+/ => shift;
        my $pkg = shift;
        my @isa = deref(shift);

        for ($pkg, @isa) {/:/ or s/^/List::Gen::/}

        no strict 'refs';
        *{$pkg.'::ISA'} = \@isa;
        mapn {*{$pkg.'::'.$_} = pop} 2 => @_;
        1
    }

    sub generator {
        splice @_, 1, 0, 'Generator', @_ > 1 ? 'TIEARRAY' : ();
        goto &packager
    }

    {my $id;
    sub curse {
        my ($obj,  $class) = @_;
        my $pkg = ($class ||= caller) .'::_'. ++$id;

        no strict 'refs';
        croak "package $pkg not empty" if %{$pkg.'::'};

        *{$pkg.'::DESTROY'} = sub {delete_package $pkg};
        @{$pkg.'::ISA'}     = $class;
        *{$pkg.'::'.$_}     = $$obj{$_}
            for grep {not /^-/ and ref $$obj{$_} eq 'CODE'}
                keys %$obj;

        if ($$obj{-overload}) {
            eval "package $pkg;"
               . 'use overload @{$$obj{-overload}}'
        }
        bless $$obj{-bless} || $obj => $pkg
    }}


=item C< by NUM LIST >

=item C< every NUM LIST >

C< by > and C< every > are exactly the same, and allow you to add variable step
size to any other list control structure with whichever reads better to you.

    for (every 2 => @_) {do something with pairs in @$_}

    grep {do something with triples in @$_} by 3 => @list;

the functions generate an array of array references to C< NUM > sized slices of
C< LIST >. the elements in each slice are aliases to the original list.

in list context, returns a real array.
in scalar context, returns a generator.

    my @slices = every 2 => 1 .. 10;     # real array
    my $slices = every 2 => 1 .. 10;     # generator
    for (every 2 => 1 .. 10) { ... }     # real array
    for (@{every 2 => 1 .. 10}) { ... }  # generator

if you plan to use all the slices, the real array is better. if you only need a
few, the generator won't need to compute all of the other slices.

    print "@$_\n" for every 3 => 1..9;
    # 1 2 3
    # 4 5 6
    # 7 8 9

    my @a = 1 .. 10;
    for (every 2 => @a) {
        @$_[0, 1] = @$_[1, 0]  # flip each pair
    }
    print "@a";
    # 2 1 4 3 6 5 8 7 10 9

    print "@$_\n" for grep {$$_[0] % 2} by 3 => 1 .. 9;
    # 1 2 3
    # 7 8 9

=cut
    sub by ($@) {
        croak '$_[0] must be >= 1' unless $_[0] >= 1;
        if (wantarray) {
            unshift @_, \&cap;
            goto &mapn
        }
        tie my @ret => 'List::Gen::By', shift, \@_;
        List::Gen::erator->new(\@ret)
    }
    BEGIN {*every = \&by}
    generator By => sub {
        my ($class, $n, $source) = @_;
        my $size = @$source / $n;
        my $last = $#$source;

        $size ++ if $size > int $size;
        $size = int $size;
        curse {
            FETCH => sub {
                my $i = $n * $_[1];
                $i < @$source
                   ? cap (@$source[$i .. min( $last, $i + $n - 1)])
                   : croak "index $_[1] out of bounds [0 .. @{[int( $#$source / $n )]}]"
            },
            realsize => sub {$size}
        } => $class
    };


=item C< apply {CODE} LIST >

apply a function that modifies C< $_ > to a shallow copy of C< LIST > and
returns the copy

    print join ", " => apply {s/$/ one/} "this", "and that";
    > this one, and that one

=cut
    sub apply (&@) {
        my ($sub, @ret) = @_;
        $sub->() for @ret;
        wantarray ? @ret : pop @ret
    }


=item C< zip LIST_of_ARRAYREF >

interleaves the passed in lists to create a new list. C< zip > continues until
the end of the longest list, C< undef > is returned for missing elements of
shorter lists.

    %hash = zip [qw/a b c/], [1..3]; # same as
    %hash = (a => 1, b => 2, c => 3);

=cut
    sub zip {
        map {my $i = $_;
            map $$_[$i] => @_
        } 0 .. max map $#$_ => @_
    }


=item C< cap LIST >

C< cap > captures a list, it is exactly the same as C<< sub{\@_}->(LIST) >>

note that this method of constructing an array ref from a list is roughly 40%
faster than C< [ LIST ]>, but with the caveat and feature that elements are
aliases to the original list

=cut
    sub cap {\@_}

=back

=head2 generators

in this document, generators will refer to tied arrays that generate their
elements on demand. generators can be used as iterators in perl's list control
structures such as C< for >, C< map > or C< grep >. since generators are lazy,
infinite generators can be created. slow generators can also be cached.

=over 8

=item scalar context

all generator functions, in scalar context, will return a reference to a tied
array. elements are created on demand as they are dereferenced.

    my $range = range 0, 1_000_000, 0.2;
        # will produce 0.0, 0.2, 0.4, ... 1000000.0

    say map sprintf('% -5s', $_)=> @$range[10 .. 15]; # calculates 5 values
    >>  2  2.2  2.4  2.6  2.8  3

    my $gen = gen {$_**2} $range;  # attaches a generator function to a range

    say map sprintf('% -5s', $_)=> @$gen[10 .. 15];
    >>  4  4.84 5.76 6.76 7.84 9

the returned reference also has the following methods:

    $gen->next           # iterates over generator ~~ $gen->get($gen->index++)
    $gen->()             # same.  iterators return undef when past the end

    $gen->more           # test if $gen->index not past end
    $gen->reset          # reset iterator to start
    $gen->reset(4)       # $gen->next returns $$gen[4]
    $gen->index          # fetches the current position
    $gen->index = 4      # same as $gen->reset(4)

    $gen->get(index)     # returns $$gen[index]
    $gen->(index)        # same

    $gen->slice(4 .. 12) # returns @$gen[4 .. 12]
    $gen->(4 .. 12)      # same

    $gen->size           # returns scalar @$gen
    $gen->all            # same as @$gen but faster
    $gen->purge          # purge any caches in the source chain
    $gen->span           # collects $gen->next calls until one
                         # returns undef, then returns the collection.
                         # ->span starts from and moves the ->index

the methods duplicate/extend the tied functionality and are necessary when
working with indices outside of perl's limit C< (0 .. 2**31 - 1) > or when
fetching a list return value (perl clamps the return to a scalar with the array
syntax). in most cases, they are also a little faster than the tied interface.

gen, filter, test, cache, flip, reverse (alias of flip), expand, and collect
are also methods of generators.

    my $gen = (range 0, 1_000_000)->gen(sub{$_**2})->filter(sub{$_ % 2});
    #same as: filter {$_ % 2} gen {$_**2} 0, 1_000_000;

=item list context

generator functions, in list context, can return the actual tied array. this
functionality, since potentially confusing, is disabled by default.

set C< $List::Gen::LIST = 1; > to enable list context returns. when false, both
scalar and list context return the reference.

it only makes sense to use this syntax directly in list control structures such
as a C< for > loop, in other situations all of the elements will be generated
during the initial assignment from the function, which in some cases may be
useful, but mostly would be a bad thing (especially for large ranges). the real
tied array also does not have the above accessor methods, and can not be passed
to another generator function.

due to memory allocation issues with infinite generators, this feature will be
removed by version 1.0 or sooner. its function (without the allocation problem)
can always be achieved by wrapping a generator with C< @{...} >

=back

=cut

{package
    List::Gen::Generator;
    for my $sub qw(TIEARRAY FETCH STORE STORESIZE CLEAR PUSH
                   POP SHIFT UNSHIFT SPLICE UNTIE EXTEND) {
        no strict 'refs';
        *$sub = sub {Carp::confess "$sub not supported"}
    }
    sub DESTROY {}
    sub source  {}
    sub FETCHSIZE {
        my $self      = shift;
        my $install   = (ref $self).'::FETCHSIZE';
        my $realsize  = $$self{realsize};
        my $fetchsize = sub {
            my $size  = $realsize->();
            $size > 2**31-1
                  ? 2**31-1
                  : $size
        };
        no strict 'refs';
        my $size  = $fetchsize->();
        *$install = $self->mutable
                  ? $fetchsize
                  : sub {$size};
        $size
    }
    sub mutable {
       my @src = shift;
       while (my $src = shift @src) {
            return 1 if $src->isa('List::Gen::Mutable');
            if (my $source = $src->source) {
                push @src, ref $source eq 'ARRAY' ? @$source : $source
            }
       }
       return;
    }
}
{package
    List::Gen::erator;
    use overload fallback => 1,
        '&{}' => sub {$_[0]->_overloader};
    sub new {
        my ($class, $gen) = @_;
        my $src = tied @$gen;
        my ($fetch, $realsize) = @$src{qw/FETCH realsize/};
        my $index    = 0;
        my $mutable  = $src->mutable;
        my $size     = $mutable || $realsize->();
        my $overload = sub {
            @_ ? @_ == 1
                    ? $fetch->(undef, $_[0])
                    : map $fetch->(undef, $_) => @_
               : $index < ($mutable ? $realsize->() : $size)
                    ? $fetch->(undef, $index++)
                    : undef
        };
        List::Gen::curse {
            -bless      => $gen,
            _overloader => sub {
                eval qq {
                    package @{[ref $_[0]]};
                    use overload fallback => 1, '&{}' => sub {\$overload};
                    local *DESTROY;
                    bless []; 1
                };
                $overload
            },
            size  => $realsize,
            get   => sub {$fetch->(undef, $_[1])},
            slice => sub {shift; map $fetch->(undef, $_) => @_},
            index => sub :lvalue {$index},
            reset => sub {$index = $_[1] || 0; $_[0]},
            more  => sub {$index < ($mutable ? $realsize->() : $size)},
            next  => sub {
                $index < ($mutable ? $realsize->() : $size)
                    ? $fetch->(undef, $index++)
                    : undef
            },
            all   => sub {
                map $fetch->(undef, $_) =>
                    0 .. $#{$mutable ? $_[0]->apply : $_[0]}
            },
            span  => sub {
                my (@i, @ret);
                while ($index < ($mutable ? $realsize->() : $size)) {
                    last unless @i = $fetch->(undef, $index++);
                    push @ret, @i;
                }
                wantarray ? @ret : \@ret
            },
            map {
                my $proxy = $_;
                $proxy => sub {
                    my @src;
                    my @todo = $src;
                    while (my $next = shift @todo) {
                        unshift @src, $next;
                        if (my $source = $next->source) {
                            unshift @todo, ref $source eq 'ARRAY'
                                            ? @$source
                                            :  $source
                        }
                    }
                    ($_->can($proxy) or next)->() for @src;
                    $_[0]
                }
            } qw/apply purge/
        } => $class
    }
    for my $sub qw(gen filter test cache expand contract collect flip iterate gather) {
        no strict 'refs';
        *$sub = sub {"List::Gen::$sub"->(@_[1 .. $#_, 0])}
    }
    sub reverse   {goto &List::Gen::flip}
    sub overlay   {goto &List::Gen::overlay}
    sub recursive {goto &List::Gen::recursive}
}

sub isagen (;$) {
    my ($gen) = (@_, $_);
    eval {$gen->isa('List::Gen::erator')} and $gen
}
sub tiegen {
    my @ret;
    eval {tie @ret => 'List::Gen::'.shift, @_}
        or croak 'invalid arguments, ',
           $@ =~ /^(.+) at .+?List-Gen.*$/s ? $1 : $@;
    $LIST && (caller 1)[5]
        ? @ret
        : List::Gen::erator->new(\@ret)
}

=over 8

=item C< range START STOP [STEP] >

returns a generator for values from C< START > to C< STOP > by C< STEP >,
inclusive.

C< STEP > defaults to 1 but can be fractional and negative. depending on your
choice of C< STEP >, the last value returned may not always be C< STOP >.

    range(0, 3, 0.4) will return (0, 0.4, 0.8, 1.2, 1.6, 2, 2.4, 2.8)

    print "$_ " for @{range 0, 1, 0.1};
    # 0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1

    print "$_ " for @{range 5, 0, -1};
    # 5 4 3 2 1 0

    my $nums = range 0, 1_000_000, 2;
    print "@$nums[10, 100, 1000]";
    # gets the tenth, hundredth, and thousandth numbers in the range
    # without calculating any other values

=cut
    sub range ($$;$) {
       tiegen Range => @_
    }
    generator Range => sub {
        my ($class, $low, $high, $step, $size) = (@_, 1);
        $size = $high < 9**9**9
            ? do {
                $size = $step > 0 ? $high - $low : $low - $high;
                $size = 1 + $size / abs $step;
                $size > 0 ? int $size : 0
            } : $high;
        curse {
            FETCH => sub {
                my $i = $_[1];
                $i < $size
                   ? $low + $step * $i
                   : croak "range index $i out of bounds [0 .. @{[$size - 1]}]"
            },
            realsize => sub {$size},
            range    => sub {$low, $step, $size},
        } => $class
    };


=item C< gen CODE GENERATOR >

=item C< gen CODE ARRAYREF >

=item C< gen CODE [START STOP [STEP]] >

C< gen > is the equivalent of C< map > for generators. it returns a generator
that will apply the C< CODE > block to its source when accessed. C< gen > takes
a generator, array ref, or suitable arguments for C< range > as its source. with
no arguments, C< gen > uses the range C< 0 .. infinity >.

    my @result = map {slow($_)} @source;  # slow() called @source times
    my $result = gen {slow($_)} \@source; # slow() not called

    my ($x, $y) = @$result[4, 7]; # slow()  called twice

    my $lazy = gen {slow($_)} range 1, 1_000_000_000;
      same:    gen {slow($_)} 1, 1_000_000_000;

    print $$lazy[1_000_000]; # slow() only called once

C< gen {...} cap LIST > is a replacement for C< [ map {...} LIST ] > and is
faster than C< gen {...} [ LIST ] >.

note that while effort has gone into making generators as fast as possible there
is overhead involved with lazy generation. simply replacing all calls to
C< map > with C< gen > will almost certainly slow down your code. use these
functions in situations where the time / memory required to completely generate
the list is unacceptable.

=cut
    sub gen (&;$$$) {
        tiegen Gen => shift, tied @{&dwim}
    }
    sub dwim {
        @_ or @_ = (0 => 9**9**9);
        local *_ = \$_[0];
        $#_ and &range
             or isagen
             or eval {&makegen}
             or range 0 => int
    }
    generator Gen => sub {
        my ($class, $code, $source) = @_;
        my ($fetch, $realsize     ) = @$source{qw/FETCH realsize/};
        curse {
            FETCH => (
                do {{
                    my ($low, $step, $size)
                        = ($source->can('range') or next)->();
                    sub {
                        my $i = $_[1];
                        local *_ = \($i < $size
                                 ? $low + $step * $i
                                 : $fetch->(undef, $i));
                        $code->()
                    }
                }} or do {{
                    my $cap = ($source->can('capture') or next)->();
                    sub {
                        local *_ = \$$cap[ $_[1] ];
                        $code->()
                    }
                }} or sub {
                    local *_ = \$fetch->(undef, $_[1]);
                    $code->()
                }
            ),
            realsize => $realsize,
            source   => sub {$source}
        } => $class
    };


=item C< glob >

if you export the C< glob > function from this package, that function and the
C<< <*.glob> >> operator will have one special case overridden.  if given an
argument that matches the following pattern:

   /^ ( .+ : )? number .. number ( (by | += | -= | [-+,]) number )?
                                 ( (if | when) .+ )? $/

then the arguments will be passed to C< range >, C< gen >, and C< filter > as
appropriate. any argument that doesn't match that pattern will be passed to
perl's builtin C< glob > function.  here are a few examples:

    <1 .. 10>                    ~~  range 1, 10
    <1 .. 10 by 2>               ~~  range 1, 10, 2
    <10 .. 1 -= 2>               ~~  range 10, 1, -2
    <x * x: 1 .. 10>             ~~  gen {$_ * $_} 1, 10
    <sin: 0 .. 3.14 += 0.01>     ~~  gen {sin} 0, 3.14, 0.01
    <1 .. 10 if x % 2>           ~~  filter {$_ % 2} 1, 10
    <sin: 0 .. 100 by 3 if /5/>  ~~  filter {/5/} gen {sin} 0, 100, 3

    for (@{< 0 .. 1_000_000_000 by 2 >}) { # starts instantly
        print "$_\n";
        last if $_ >= 100;        # exits the loop with only 51 values generated
    }

    my @files = <*.txt>;  # works as normal

=cut

    {my $number = '-?(?: \d[\d_]* | (?:\d*\.\d+) )(?: e -? \d+)?';
     my $glob   = sub {glob $_[0]};
     sub glob {
        my $arg = shift;
        if (my ($gen, $low, $high, $step, $filter) = $arg =~ /^
                (?: (.+): )? \s*
                 ($number)   \s*
                    \.\.     \s*
                 ($number)   \s*
                (?:
                    (?: by | [+-]= | [+,] | ) \s*
                    ($number)
                )? \s*
                (?:
                    (?: if | when )
                    (.+)
                )? \s*
            $/xo) {
            $_ and s/_//g for $low, $high, $step;
            if ($step and $arg =~ /-=/) {
                $step *= -1
            }
            @_ = (\&range, $low, $high, $step || 1);

            for ([$gen, \&gen], [$filter, \&filter]) {
                $$_[0] or next;
                $$_[0] =~ s'\bx\b'$_'g;
                if (my $sub = eval 'package '.(caller)."; sub {$$_[0]}") {
                    @_ = ($$_[1], $sub, scalar &{shift @_});
                } else {
                    croak "syntax error: sub {$$_[0]}: $@"
                }
            }
            goto &{shift @_}
        } else {
            $glob->($arg)
        }
    }}


=item C< iterate CODE [START STOP [STEP]] >

C< iterate > returns a generator that is created iteratively. C< iterate >
implicitly caches its values, this allows random access normally not
possible with an iterative algorithm

    my $fib = do {
        my ($an, $bn) = (0, 1);
        iterate {
            my $return = $an;
            ($an, $bn) = ($bn, $an + $bn);
            $return
        }
    };

=cut
    sub iterate (&;$$$) {
        my ($code, @list) = shift;
        gen {
            if ($_ > $#list) {
                 push @list, map $code->(), @list .. $_
            }
            $list[$_]
        } &dwim
    }


=item C< gather CODE [START STOP [STEP]] >

C< gather > returns a generator that is created iteratively.  rather than
returning a value, you call C< take($return_value) > within the C< CODE >
block. note that since perl does not have continuations, C< take(...) > does
not pause execution of the block.  rather, it stores the return value, the
block finishes, and then the generator returns the stored value.

you can not import the C< take(...) > function from this module.
C< take(...) > will be installed automatically into your namespace during
the execution of the C< CODE > block. because of this, you must always call
C< take(...) > with parenthesis. C< take > returns its argument unchanged.

gather implicitly caches its values, this allows random access normally not
possible with an iterative algorithm.  the algorithm in C< iterate > is a
bit cleaner here, but C< gather > is slower than C< iterate >, so benchmark
if speed is a concern

    my $fib = do {
        my ($x, $y) = (0, 1);
        gather {
            ($x, $y) = ($y, take($x) + $y)
        }
    };

=cut
    sub gather (&;$$$) {
        my $code   = shift;
        my $caller = (caller).'::take';
        unshift @_, sub {
            my $take;
            no strict 'refs';
            local *$caller = sub {$take = shift};
            $code->();
            $take
        };
        goto &iterate;
    }


=item C< makegen ARRAY >

C< makegen > converts an array to a generator. this is normally not needed as
most generator functions will call it automatically if passed an array reference

=cut
    sub makegen (\@) {
       tiegen Capture => @_
    }
    generator Capture => sub {
        my ($class, $source) = @_;
        my $size = @$source;
        curse {
            FETCH    => sub {$$source[ $_[1] ]},
            realsize => sub {$size},
            capture  => sub {$source}
        } => $class
    };


=item C< sequence LIST >

string generators together.  the C<< ->apply >> method is called on each
argument

=cut
    sub sequence {
       tiegen Sequence => @_
    }
    generator Sequence => sub {
        my $class  = shift;
        my $size   = 0;
        my @source = map {
            isagen or croak "seq takes a list of generators, not '$_'";
            $_->apply;
            [tied(@$_)->{FETCH}, $size+0, $size += $_->size]
        }@_;
        curse {
            FETCH => sub {
                my $i = $_[1];
                croak "seq index $i out of bounds [0 .. @{[$size - 1]}]"
                    if $i >= $size;

                my $pos = @source >> 1;
                my ($src, $low, $high) = @{$source[$pos]};

                until ($low <= $i and $i < $high) {
                    $pos = ($i < $low ? $pos : $pos + @source) >> 1;
                    ($src, $low, $high) = @{$source[$pos]};
                }
                $src->(undef, $i - $low)
            },
            realsize => sub {$size},
            source   => do {
                my @src = map tied(@$_), @_;
                sub {\@src}
            }
        } => $class
    };


=item C< filter CODE GENERATOR >

=item C< filter CODE ARRAYREF >

=item C< filter CODE [START STOP [STEP]] >

C< filter > is a lazy version of C< grep > which attaches a code block to a
generator or range. it returns a generator that will test elements with the code
block on demand. with no arguments, C< filter > uses the range C< 0 .. infinity>

normal generators, such as those produced by C< range > or C< gen >, have a
fixed length, and that is used to allow random access within the range. however,
there is no way to know how many elements will pass a filter. because of this,
random access within the filter is not always C< O(1) >. C< filter > will
attempt to be as lazy as possible, but to access the 10th element of a filter,
the first 9 passing elements must be found first. depending on the coderef and
the source, the filter may need to process significantly more elements from its
source than just 10.

in addition, since filters don't know their true size, entire filter arrays do
not expand to the correct number of elements in list context. to correct this,
call the C<< ->apply >> method which will test the filter on all of its source
elements. after that, the filter will return a properly sized array. calling
C<< ->apply >> on an infinite (or very large) range wouldn't be a good idea. if
you are using C<< ->apply >> frequently, you should probably just be using
C< grep >. you can call C<< ->apply >> on any stack of generator functions, it
will start from the deepest filter and move up.

the method C<< ->all >> will first call C<< ->apply >> on itself and then return
the complete list

filters implicitly cache their elements. accessing any element below the highest
element already accessed is C< O(1) >.

accessing individual elements or slices works as you would expect.

    my $filter = filter {$_ % 2} 0, 100;

    say $#$filter;   # incorrectly reports 100

    say "@$filter[5 .. 10]"; # reads the source range up to element 23
                             # prints 11 13 15 17 19 21

    say $#$filter;   # reports 88, closer but still wrong

    $filter->apply;  # reads remaining elements from the source

    say $#$filter;   # 49 as it should be

note: C< filter > now reads one element past the last element accessed, this
allows filters to behave properly when dereferenced in a foreach loop (without
having to call C<< ->apply >>).  if you prefer the old behavior, set
C< $List::Gen::FILTER_LOOKAHEAD = 0 >

=cut
    sub filter (&;$$$) {
        tiegen Filter => shift, tied @{&dwim}
    }
    generator 'Mutable';
    packager 'Filter Mutable TIEARRAY' => sub {
        my ($class, $code, $source) = @_;
        my ($fetch, $realsize     ) = @$source{qw/FETCH realsize/};
        my ($pos, @list) = 0;
        my $mutable = $source->mutable;
        my $srcsize = my $size = $realsize->();
        curse {
            FETCH => sub {
                my $i = $_[1];
                local *_;
                while ($#list < $i+$FILTER_LOOKAHEAD) {
                    last unless $pos < ($mutable
                                        ? $srcsize = $realsize->()
                                        : $srcsize);
                    *_ = \$fetch->(undef, $pos++);
                    $code->() ? push @list, $_
                              : $size--
                }
                $i < $size ? $list[$i] : ()
            },
            realsize => (
                $mutable
                    ? sub {
                        $srcsize = $realsize->();
                        $size = $pos < $srcsize
                            ? @list + ($srcsize - $pos)
                            : @list
                    }
                    : sub {$size}
            ),
            source => sub {$source},
            purge  => sub {$pos = 0; @list = ();
                           $srcsize = $size = $realsize->()},
            apply  => sub {
                return if $pos == 9**9**9;
                $srcsize = $realsize->();
                for ($pos .. $srcsize - 1) {
                    local *_ = \scalar $fetch->(undef, $_);
                    $code->() and push @list, $_
                }
                $pos  = 9**9**9;
                $size = @list;
            }
        } => $class
    };


=item C< test CODE GENERATOR >

=item C< test CODE ARRAYREF >

=item C< test CODE [START STOP [STEP]] >

C< test > attaches a code block to a generator or range. accessing an element of
the returned generator will call the code block first with the element in
C< $_ >, and if it returns true, the element is returned, otherwise an empty
list (undef in scalar context) is returned.

when accessing a slice of a tested generator, if you use the C<< ->(x .. y) >>
syntax, the the empty lists will collapse and you may receive a shorter slice.
an array dereference slice will always be the size you ask for, and will have
undef in each failed slot

=cut
    sub test (&;$$$) {
        my $code = shift;
        unshift @_, sub {$code->() ? $_ : ()};
        goto &gen
    }


=item C< cache CODE >

=item C< cache GENERATOR >

=item C<< cache list => ... >>

C< cache > will return a cached version of the generators returned by functions
in this package. when passed a code reference, cache returns a memoized code ref
(arguments joined with C< $; >). when in 'list' mode, the source is in list
context, otherwise scalar context is used.

    my $gen = cache gen {slow($_)} \@source; # calls = 0

    print $gen->[123]; # calls += 1
    ...
    print @$gen[123, 456] # calls += 1

=cut
    sub cache ($;$) {
        my $gen = pop;
        my $list = "@_" =~ /list/i;
        if (isagen $gen) {
            tiegen Cache => tied @$gen, $list
        } elsif (ref $gen eq 'CODE') {
            my %cache;
            $list
                ? sub {@{$cache{join $; => @_} ||= cap &$gen}}
                : sub {
                    my $arg = join $; => @_;
                    exists $cache{$arg}
                         ? $cache{$arg}
                         :($cache{$arg} = &$gen)
                }
        } else {croak 'cache takes generator or coderef'}
    }
    generator Cache => sub {
        my ($class, $source,   $list ) = @_;
        my ($fetch, $realsize, %cache) = @$source{qw/FETCH realsize/};
        curse {
            FETCH => (
                $list ? sub {
                    my $arg = $_[1];
                    @{$cache{$arg} ||= cap $fetch->(undef, $arg)}
                } : sub {
                    my $arg = $_[1];
                    exists $cache{$arg}
                         ? $cache{$arg}
                         :($cache{$arg} = $fetch->(undef, $arg))
                }
            ),
            realsize => $realsize,
            source   => sub {$source},
            purge    => sub {%cache = ()},
        } => $class
    };


=item C< flip GENERATOR >

C< flip > is C< reverse > for generators. the C<< ->apply >> method is called on
C< GENERATOR >.

    flip gen {$_**2} 0, 10   ~~   gen {$_**2} 10, 0, -1

=cut
    sub flip ($) {
        croak 'not generator' unless isagen $_[0];
        my $gen = tied @{$_[0]};
        $_[0]->apply;
        tiegen Flip => $gen
    }
    generator Flip => sub {
        my ($class, $source) = @_;
        my $size  = $source->realsize;
        my $end   = $size - 1;
        my $fetch = $$source{FETCH};
        curse {
            FETCH    => sub {$fetch->(undef, $end - $_[1])},
            realsize => sub {$size},
            source   => sub {$source}
        } => $class
    };


=item C< expand GENERATOR >

=item C< expand SCALE GENERATOR >

C< expand > scales a generator with elements that return equal sized lists. it
can be passed a list length, or will automatically determine it from the length
of the list returned by the first element of the generator. C< expand >
implicitly caches its returned generator.

    my $multigen = gen {$_, $_/2, $_/4} 1, 10;   # each element returns a list

    say join ' '=> $$multigen[0];  # 0.25        # only last element
    say join ' '=> &$multigen(0);  # 1 0.5 0.25  # works
    say scalar @$multigen;         # 10
    say $multigen->size;           # 10

    my $expanded = expand $multigen;

    say join ' '=> @$expanded[0 .. 2];  # 1 0.5 0.25
    say join ' '=> &$expanded(0 .. 2);  # 1 0.5 0.25
    say scalar @$expanded;              # 30
    say $expanded->size;                # 30

    my $expanded = expand gen {$_, $_/2, $_/4} 1, 10; # in one line

=cut
    sub expand ($;$) {
        my $gen = pop;
        my $scale = shift || -1;
        croak "not generator" unless isagen $gen;
        tiegen Expand => tied @$gen, $scale
    }
    generator Expand => sub {
        my ($class, $source,    $scale) = @_;
        my ($fetch, $realsize, %cache) = @$source{qw/FETCH realsize/};
        if ($scale == -1) {
            $scale = my @first = $fetch->(undef, 0);
            @cache{0 .. $#first} = @first;
        }
        curse {
            FETCH => sub {
                my $i  = $_[1];
                unless (exists $cache{$i}) {
                    my $src_i = int ($i / $scale);
                    my $ret_i =  $src_i * $scale;
                    @cache{$ret_i .. $ret_i + $scale - 1}
                        = $fetch->(undef, $src_i);
                }
                $cache{$i}
            },
            realsize => (
                $source->mutable
                    ? sub {$scale * $realsize->()}
                    : do {
                        my $size = $scale * $realsize->();
                        sub {$size}
                    }
            ),
            source => sub {$source},
            purge  => sub {%cache = ()},
        } => $class
    };


=item C< contract SCALE GENERATOR >

C< contract > is the inverse of C< expand >

also called C< collect >

=cut
    sub contract ($$) {
        my ($scale, $gen) = @_;
        croak '$_[0] >= 1' if $scale < 1;
        croak 'not generator' unless isagen $gen;
        $scale == 1
            ? $gen
            :  gen {&$gen($_ .. $_ + $scale - 1)} 0 => $gen->size - 1, $scale
    }
    BEGIN {*collect = \&contract}


=item C< genzip LIST >

C< genzip > is a lazy version of C< zip >. it takes any combination of
generators and array refs and returns a generator.

=cut
    sub genzip {
        my @src   = map tied @{isagen or makegen @$_} => @_;
        my @fetch = map $_->{FETCH}     => @src;
        my @size  = map $_->{realsize} => @src;
        gen {
            my ($src, $i) = (($_ % @src), int ($_ / @src));
            $i < $size[$src]() ? $fetch[$src](undef, $i) : undef
        } 0 => @src * max(map $_->() => @size) - 1
    }

=item C< overlay GENERATOR PAIRS >

overlay allows you to replace the values of specific generator cells.  to set
the values, either pass the overlay constructor a list of pairs in the form
C<< index => value, ... >>, or assign values to the returned generator using
normal array ref syntax

    my $fib; $fib = overlay gen {$$fib[$_ - 1] + $$fib[$_ - 2]};
    @$fib[0, 1] = (0, 1);

    # or
    my $fib; $fib = gen {$$fib[$_ - 1] + $$fib[$_ - 2]}
                  ->overlay( 0 => 0, 1 => 1 );

    print "@$fib[0 .. 15]";  # '0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610'

=cut
    sub overlay ($%) {
        isagen my $source = shift
            or croak '$_[0] to overlay must be a generator';
        tiegen Overlay => tied @$source, @_
    }
    generator Overlay => sub {
        my ($class, $source, %overlay) = @_;
        my ($fetch, $realsize) = @$source{qw/FETCH realsize/};
        curse {
            FETCH => sub {
                exists $overlay{$_[1]}
                     ? $overlay{$_[1]}
                     : $fetch->(undef, $_[1])
            },
            STORE    => sub {$overlay{$_[1]} = $_[2]},
            realsize => $realsize,
            source   => sub {$source}
        } => $class
    };


=item C< recursive GENERATOR >

    my $fib = gen {self($_ - 1) + self($_ - 2)}
            ->overlay( 0 => 0, 1 => 1 )
            ->cache
            ->recursive;

    print "@$fib[0 .. 15]";  # '0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610'

=cut
    sub recursive ($) {
        isagen my $source = shift
            or croak '$_[0] to recursive must be a generator';
        tiegen Recursive => tied @$source, scalar caller;
    }
    generator Recursive => sub {
        my ($class, $source) = @_;
        my ($fetch, $realsize) = @$source{qw/FETCH realsize/};
        my $caller = "$_[2]::self";
        my $rec_fetch;
        my $self_sub = sub {$rec_fetch->(undef, $_[0])};
        curse {
            FETCH => $rec_fetch = sub {
                no strict 'refs';
                no warnings 'redefine';
                local *$caller = $self_sub;
                $fetch->(undef, $_[1])
            },
            realsize => $realsize,
            source   => sub {$source}
        } => $class
    };


=item C< d >

=item C< d SCALAR >

=item C< deref >

=item C< deref SCALAR >

dereference a C< SCALAR >, C< ARRAY >, or C< HASH > reference. any other value
is returned unchanged

    print join " " => map deref, 1, [2, 3, 4], \5, {6 => 7}, 8, 9, 10;
    # prints 1 2 3 4 5 6 7 8 9 10

=cut
    sub d (;$) {
        local *_ = \$_[0] if @_;
        my $type = reftype $_;
        $type ?
            $type eq 'ARRAY'  ? @$_ :
            $type eq 'HASH'   ? %$_ :
            $type eq 'SCALAR' ? $$_ : $_
        : $_
    }
    BEGIN {*deref = \&d}

=item C< mapkey CODE KEY LIST >

this function is syntactic sugar for the following idiom

    my @cartesian_product =
        map {
            my $first = $_;
            map {
                my $second = $_
                map {
                    $first . $second . $_
                } 1 .. 3
            } qw/x y z/
        } qw/a b c/;

    my @cartesian_product =
        mapkey {
            mapkey {
                mapkey {
                    $_{first} . $_{second} . $_{third}
                } third => 1 .. 3
            } second => qw/x y z/
        } first => qw/a b c/;

=cut
    sub mapkey (&$@) {
        my ($code, $key) = splice @_, 0, 2;
        local $_{$key};
        map {
            $_{$key} = $_;
            $code->();
        } @_
    }


=item C< cartesian CODE LIST_of_ARRAYREF >

C< cartesian > computes the cartesian product of any number of array refs, each
which can be any size. returns a generator

    my $product = cartesian {$_[0] . $_[1]} [qw/a b/], [1, 2];

    @$product == qw( a1 a2 b1 b2 );

=cut
    sub cartesian (&@) {
        my $code  = shift;
        my @src   = @_;
        my @size  = map {0+@$_} @src;
        my $size  = 1;
        my @cycle = map {$size / $_}
                    map {$size *= $size[$_] || 1} 0 .. $#src;
        gen {
            my $i = $_;
            $code->(map {
              $size[$_] ? $src[$_][ $i / $cycle[$_] % $size[$_] ] : ()
            } 0 .. $#src)
        } 0 => $size - 1
    }


=item C< slide {CODE} WINDOW LIST >

slides a C< WINDOW > sized slice over C< LIST >, calling C< CODE > for each
slice and collecting the result

as the window reaches the end, the passed in slice will shrink

    print slide {"@_\n"} 2 => 1 .. 4
    # 1 2
    # 2 3
    # 3 4
    # 4         # only one element here

=cut
    sub slide (&$@) {
        my ($code, $n, @ret) = splice @_, 0, 2;

        push @ret, $code->( @_[ $_ .. $_ + $n ] )
            for 0 .. $#_ - --$n;

        push @ret, $code->( @_[ $_ .. $#_ ])
            for $#_ - $n + 1 .. $#_;
        @ret
    }


=item C< curse HASHREF PACKAGE >

many of the functions in this package utilize closure objects to avoid the speed
penalty of dereferencing fields in their object during each access. C< curse >
is similar to C< bless > for these objects and while a blessing makes a
reference into a member of an existing package, a curse conjures a new package
to do the reference's bidding

    package Closure::Object;
        sub new {
            my ($class, $name, $value) = @_;
            curse {
                get  => sub {$value},
                set  => sub {$value = $_[1]},
                name => sub {$name},
            } => $class
        }

C<< Closure::Object >> is functionally equivalent to the following normal perl
object, but with faster method calls since there are no hash lookups or other
dereferences (around 40-50% faster for short getter/setter type methods)

    package Normal::Object;
        sub new {
            my ($class, $name, $value) = @_;
            bless {
                name  => $name,
                value => $value,
            } => $class
        }
        sub get  {$_[0]{value}}
        sub set  {$_[0]{value} = $_[1]}
        sub name {$_[0]{name}}

the trade off is in creation time / memory, since any good curse requires
drawing at least a few pentagrams in the blood of an innocent package.

the returned object is blessed into the conjured package, which inherits from
the provided C< PACKAGE >. always use C<< $obj->isa(...) >> rather than
C< ref $obj eq ... > due to this. the conjured package name matches
C<< /${PACKAGE}::_\d+/ >>

special keys:

    -bless    => $reference  # returned instead of HASHREF
    -overload => [fallback => 1, '""' => sub {...}]

when fast just isn't fast enough, since most cursed methods don't need to be
passed their object, the fastest way to call the method is:

    my $obj = Closure::Object->new('tim', 3);
    my $set = $obj->{set};                  # fetch the closure
         # or $obj->can('set')

    $set->(undef, $_) for 1 .. 1_000_000;   # call without first arg

which is around 70% faster than pre-caching a method from a normal object for
short getter/setter methods.

=back

=head1 AUTHOR

Eric Strom, C<< <ejstrom at gmail.com> >>

=head1 BUGS

version 0.70 comes with a bunch of new features, if anything is broken, please
let me know.  see C< filter > for a minor behavior change

versions 0.50 and 0.60 break some of the syntax from previous versions,
for the better.

report any bugs / feature requests to C<bug-list-gen at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=List-Gen>.

comments / feedback / patches are also welcome.

=head1 COPYRIGHT & LICENSE

copyright 2009 Eric Strom.

this program is free software; you can redistribute it and/or modify it under
the terms of either: the GNU General Public License as published by the Free
Software Foundation; or the Artistic License.

see http://dev.perl.org/licenses/ for more information.

=cut

__PACKAGE__ if 'first require';