#!/usr/bin/perl
# BUG-019: Importer breaks when given an empty file or file with no cleared transactions.
#
# Scenario A: empty .ldg → getinsertionpoints has no anchor, cleared_pos=0 →
#   update_file sentinel at pos=0 hit $len=-1 and died.
# Scenario B: file with only pending transactions → cleared_file was undef →
#   insertionFileFor returned undef → scheduleAppend(undef) → transaction lost.
#
# Fix: store $self->{file} in new; use it as fallback in getinsertionpoints;
#   allow $len=-1 at pos=0 in update_file (empty-file sentinel at start).

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $handlers = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv_config = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

my $pass = 1;

# ── Scenario A: empty ledger file ────────────────────────────────────────────
print "=" x 60, "\n";
print "BUG-019 Scenario A: empty ledger file\n";
print "=" x 60, "\n\n";

my $ldg_a = "$dir/bug019_empty.ldg";
copy('bug019_empty.ldg', $ldg_a) or die "copy: $!";
copy('bug019.csv', "$dir/Checking-2026-03.csv") or die "copy: $!";

my $ledger_a = Ledger->new(file => $ldg_a);
$ledger_a->fromStmt("$dir/Checking-2026-03.csv", $handlers, $csv_config);
$ledger_a->update();

open(my $fh, '<', $ldg_a) or die $!;
my $content_a = do { local $/; <$fh> };
close $fh;
print $content_a;
print "-" x 40, "\n";

my $has_coffee   = $content_a =~ /Coffee Shop/;
my $has_gas      = $content_a =~ /Gas Station/;
my $has_balance  = $content_a =~ /= \$100\.00/;

printf "Coffee Shop transaction written: %s  (want yes)\n", $has_coffee  ? 'yes' : 'NO';
printf "Gas Station transaction written: %s  (want yes)\n", $has_gas     ? 'yes' : 'NO';
printf "Balance assertion written:       %s  (want yes)\n", $has_balance ? 'yes' : 'NO';

if ($has_coffee && $has_gas && $has_balance) {
    print "PASS: Scenario A\n";
} else {
    print "FAIL: Scenario A\n";
    $pass = 0;
}
print "\n";

# ── Scenario B: file with only pending transactions ───────────────────────────
print "=" x 60, "\n";
print "BUG-019 Scenario B: pending-only ledger file\n";
print "=" x 60, "\n\n";

my $ldg_b = "$dir/bug019_pending.ldg";
copy('bug019_pending.ldg', $ldg_b) or die "copy: $!";

my $ledger_b = Ledger->new(file => $ldg_b);
$ledger_b->fromStmt("$dir/Checking-2026-03.csv", $handlers, $csv_config);
$ledger_b->update();

open($fh, '<', $ldg_b) or die $!;
my $content_b = do { local $/; <$fh> };
close $fh;
print $content_b;
print "-" x 40, "\n";

my $coffee_pos  = index($content_b, 'Coffee Shop');
my $walmart_pos = index($content_b, 'Wal-Mart');
my $has_walmart = $content_b =~ /! Wal-Mart/;

printf "Coffee Shop written:              %s  (want yes)\n", ($coffee_pos >= 0)  ? 'yes' : 'NO';
printf "Wal-Mart still pending:           %s  (want yes)\n", $has_walmart        ? 'yes' : 'NO';
printf "Cleared Coffee before pending Wal-Mart: %s  (want yes)\n",
    ($coffee_pos >= 0 && $walmart_pos > $coffee_pos) ? 'yes' : 'NO';

if ($coffee_pos >= 0 && $has_walmart && $walmart_pos > $coffee_pos) {
    print "PASS: Scenario B\n";
} else {
    print "FAIL: Scenario B\n";
    $pass = 0;
}
print "\n";

if ($pass) {
    print "PASS\n";
    exit 0;
} else {
    print "FAIL\n";
    exit 1;
}
