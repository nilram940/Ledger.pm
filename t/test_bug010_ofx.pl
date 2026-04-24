#!/usr/bin/perl
# BUG-010 (OFX): OFX transactions written with OFX-{FITID} prefix.
#
# Before this fix, makeid() used account-initials prefix for OFX (e.g. C-20260205001).
# After the fix, OFX sets source='OFX' so the ID becomes OFX-{FITID}.
#
# This test also checks:
#   - Re-importing the same OFX deduplicates both transactions correctly.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "BUG-010 OFX: OFX-{FITID} id prefix\n";
print "=" x 60, "\n\n";

my $ldg = "$dir/bug010.ldg";
copy('fr013_base.ldg', $ldg)                          or die "copy ldg: $!";
copy('bug010.ofx', "$dir/Checking-2026-02.ofx")       or die "copy ofx: $!";

my $handlers = {};

print "--- First import ---\n";
my $ledger = Ledger->new(file => $ldg);
$ledger->fromStmt("$dir/Checking-2026-02.ofx", $handlers);
$ledger->update();
unlink "$ldg.store";

open(my $fh, '<', $ldg) or die $!;
my $content1 = do { local $/; <$fh> };
close $fh;
print $content1;
print "-" x 40, "\n\n";

print "--- Second import (should deduplicate) ---\n";
my $ledger2 = Ledger->new(file => $ldg);
$ledger2->fromStmt("$dir/Checking-2026-02.ofx", $handlers);
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
    my $has_ofx_id     = ($c1 =~ /ID: OFX-\d+/);
    my $no_old_prefix  = ($c1 !~ /ID: C-/);

    my $coffee_count2  = () = $c2 =~ /^\d{4}\/\d{2}\/\d{2}.*Coffee Shop/mg;
    my $pharmacy_count2 = () = $c2 =~ /^\d{4}\/\d{2}\/\d{2}.*Pharmacy/mg;

    print "\n--- BUG-010 OFX RESULT ---\n";
    printf "Coffee Shop imported (want 1):       %s  (got %d)\n",
        $coffee_count1 == 1 ? 'yes' : 'NO', $coffee_count1;
    printf "Pharmacy imported (want 1):          %s  (got %d)\n",
        $pharmacy_count1 == 1 ? 'yes' : 'NO', $pharmacy_count1;
    printf "ID: OFX-{digits} prefix present:    %s  (want yes)\n",
        $has_ofx_id ? 'yes' : 'NO';
    printf "No old C- prefix:                    %s  (want yes)\n",
        $no_old_prefix ? 'yes' : 'NO';
    printf "Coffee Shop deduplicated (want 1):   %s  (got %d)\n",
        $coffee_count2 == 1 ? 'yes' : 'NO', $coffee_count2;
    printf "Pharmacy deduplicated (want 1):      %s  (got %d)\n",
        $pharmacy_count2 == 1 ? 'yes' : 'NO', $pharmacy_count2;

    if ($coffee_count1 == 1 && $pharmacy_count1 == 1
        && $has_ofx_id && $no_old_prefix
        && $coffee_count2 == 1 && $pharmacy_count2 == 1) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
