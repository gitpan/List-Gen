#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use lib qw(../lib lib t/lib);
use List::Gen::Testing;

BEGIN {use_ok 'List::Generator'}

t "List::Gen == List::Generator",
    is => \%List::Gen::, \%List::Generator::,
    is =>  *List::Gen::,  *List::Generator::;

for (@List::Generator::EXPORT) {
    t "List::Generator $_",
        ok => defined &$_;
}
t 'List::Generator not import',
    ok => not defined &gather;

{package test2;
    BEGIN {::use_ok 'List::Generator', '*'}

    for (@List::Generator::EXPORT_OK) {
        ::t "List::Generator $_",
            ok => defined &$_;
    }
}

plan tests => @List::Gen::EXPORT + @List::Gen::EXPORT_OK + 5;
