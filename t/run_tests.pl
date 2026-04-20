#!/usr/bin/perl
# Run all test_*.pl files in t/ and print a summary.
# Exit 0 if all pass, 1 if any fail.
#
# Usage (from repo root):   perl Ledger.pm/t/run_tests.pl
#        (from Ledger.pm/): perl t/run_tests.pl
#        (from t/):         perl run_tests.pl
use strict;
use warnings;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

chdir dirname(abs_path($0)) or die "chdir: $!";

my @tests = sort glob('test_*.pl');
die "No test_*.pl files found in " . abs_path('.') . "\n" unless @tests;

my ($pass, $fail) = (0, 0);
my @failures;

printf "%-42s %s\n", 'Test', 'Result';
print '-' x 52, "\n";

for my $test (@tests) {
    printf '%-42s ', $test;
    STDOUT->flush;
    my $output = `perl -I.. "$test" 2>&1`;
    if ($? == 0) {
        print "PASS\n";
        $pass++;
    } else {
        print "FAIL\n";
        $fail++;
        push @failures, [$test, $output];
    }
}

printf "\n%d passed, %d failed\n", $pass, $fail;

for my $f (@failures) {
    print "\n", '=' x 60, "\n";
    print "FAILED: $f->[0]\n";
    print '=' x 60, "\n";
    print $f->[1];
}

exit($fail ? 1 : 0);
