#!/usr/bin/perl
use strict;
use warnings;

my $file = shift // 'issues.org';
open my $fh, '<', $file or die "Cannot open $file: $!\n";

my (@issues, $cur_status, $cur_title);
while (<$fh>) {
    chomp;
    if (/^\*\* /) {
        undef $cur_status;
        if (/^\*\* (\S+) +(.+?)\s*$/) {
            ($cur_status, $cur_title) = ($1, $2);
            $cur_title =~ s/\s+(?::\w+:)+\s*$//;
        }
    } elsif (/^:ID:\s*(\S+)/ && defined $cur_status) {
        push @issues, [$1, $cur_status, $cur_title];
        undef $cur_status;
    }
}
close $fh;

@issues = sort { _key($a->[0]) cmp _key($b->[0]) } @issues;

printf "%-10s  %-14s  %s\n", @$_ for @issues;

sub _key {
    my ($pfx, $n) = ($_[0] =~ /^([A-Z]+)-(\d+)$/);
    sprintf "%s%04d", ($pfx eq 'BUG' ? 'A' : 'B'), $n // 0;
}
