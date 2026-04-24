#!/usr/bin/perl
# BUG-010: makeid() date+amount collision and account-name coupling.
#
# Two CSV rows with the same date and amount but different payees (and no
# bank-supplied FITID) previously generated identical IDs, so the second
# transaction was silently deduplicated.  The fix hashes (date, payee,
# quantity) for CSV sources without a FITID, producing a distinct key for
# each row.
#
# This test also checks:
#   - IDs are written in CSV-{hash} format (not account-initials prefix)
#   - Re-importing the same CSV deduplicates both transactions correctly

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "BUG-010: same-date/same-amount CSV collision\n";
print "=" x 60, "\n\n";

my $ldg = "$dir/bug010.ldg";
copy('bug010.ldg', $ldg)                              or die "copy ldg: $!";
copy('bug010.csv', "$dir/Checking-2026-01.csv")       or die "copy csv: $!";

my $handlers = {};
my $csv = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "--- First import ---\n";
my $ledger = Ledger->new(file => $ldg);
$ledger->fromStmt("$dir/Checking-2026-01.csv", $handlers, $csv);
$ledger->update();
unlink "$ldg.store";

open(my $fh, '<', $ldg) or die $!;
my $content1 = do { local $/; <$fh> };
close $fh;
print $content1;
print "-" x 40, "\n\n";

print "--- Second import (should deduplicate) ---\n";
my $ledger2 = Ledger->new(file => $ldg);
$ledger2->fromStmt("$dir/Checking-2026-01.csv", $handlers, $csv);
$ledger2->update();
unlink "$ldg.store";

open($fh, '<', $ldg) or die $!;
my $content2 = do { local $/; <$fh> };
close $fh;
print $content2;
print "-" x 40, "\n";

check($content1, $content2);

sub check {
    my ($c1, $c2) = @_;

    my $coffee_count1  = () = $c1 =~ /^\d{4}\/\d{2}\/\d{2}.*Coffee Shop/mg;
    my $pharmacy_count1 = () = $c1 =~ /^\d{4}\/\d{2}\/\d{2}.*Pharmacy/mg;
    my $has_csv_id     = ($c1 =~ /ID: CSV-/);
    my $no_old_prefix  = ($c1 !~ /ID: C-/);
    my $bal_995        = ($c1 =~ /= \$980\.00/);

    my $coffee_count2  = () = $c2 =~ /^\d{4}\/\d{2}\/\d{2}.*Coffee Shop/mg;
    my $pharmacy_count2 = () = $c2 =~ /^\d{4}\/\d{2}\/\d{2}.*Pharmacy/mg;

    print "\n--- BUG-010 RESULT ---\n";
    printf "Coffee Shop imported (want 1):       %s  (got %d)\n",
        $coffee_count1 == 1 ? 'yes' : 'NO', $coffee_count1;
    printf "Pharmacy imported (want 1):          %s  (got %d)\n",
        $pharmacy_count1 == 1 ? 'yes' : 'NO', $pharmacy_count1;
    printf "ID: CSV- prefix present:             %s  (want yes)\n",
        $has_csv_id ? 'yes' : 'NO';
    printf "No old C- prefix:                    %s  (want yes)\n",
        $no_old_prefix ? 'yes' : 'NO';
    printf "Balance assertion written:           %s  (want yes)\n",
        $bal_995 ? 'yes' : 'NO';
    printf "Coffee Shop deduplicated (want 1):   %s  (got %d)\n",
        $coffee_count2 == 1 ? 'yes' : 'NO', $coffee_count2;
    printf "Pharmacy deduplicated (want 1):      %s  (got %d)\n",
        $pharmacy_count2 == 1 ? 'yes' : 'NO', $pharmacy_count2;

    if ($coffee_count1 == 1 && $pharmacy_count1 == 1
        && $has_csv_id && $no_old_prefix && $bal_995
        && $coffee_count2 == 1 && $pharmacy_count2 == 1) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
