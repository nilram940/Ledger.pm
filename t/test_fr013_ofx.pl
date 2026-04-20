#!/usr/bin/perl
# FR-013: OFX parser test.
# Verifies that Ledger::OFX parses a standard SGML OFX file correctly:
# payee, amount, date, state, and LEDGERBAL balance assertion.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use POSIX qw(strftime);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg) or die "copy base: $!";
copy('fr013.ofx', "$dir/Checking-2026-02.ofx") or die "copy ofx: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing Checking-2026-02.ofx ===\n";
$ledger->fromStmt("$dir/Checking-2026-02.ofx", {}, {});

print "\n=== Transactions after import ===\n";
for my $tx (sort { $a->{date} <=> $b->{date} } $ledger->getTransactions()) {
    next unless $tx->{date};
    printf "  %s %s %s  qty=%.2f\n",
        strftime('%Y/%m/%d', localtime $tx->{date}),
        $tx->{state} || 'uncleared',
        $tx->{payee},
        ($tx->getPosting(0)->{quantity} // 0);
}

print "\n=== Writing changes ===\n";
$ledger->update();

open(my $fh, '<', $ldg) or die $!;
my $content = do { local $/; <$fh> };
close $fh;

print "\n=== Resulting ledger file ===\n";
print "-" x 40, "\n";
print $content;
print "-" x 40, "\n";

check($ledger, $content);

sub check {
    my ($ledger, $content) = @_;

    my @txns = grep { $_->{date} } $ledger->getTransactions();

    my ($coffee)   = grep { $_->{payee} eq 'Coffee Shop'   } @txns;
    my ($hardware) = grep { $_->{payee} eq 'Hardware Store' } @txns;

    my $coffee_qty   = $coffee   ? ($coffee->getPosting(0)->{quantity}   // 0) : undef;
    my $hardware_qty = $hardware ? ($hardware->getPosting(0)->{quantity}  // 0) : undef;
    my $hardware_num = $hardware ? $hardware->{code} : undef;

    my $coffee_date   = $coffee   ? strftime('%Y/%m/%d', localtime $coffee->{date})   : '(none)';
    my $hardware_date = $hardware ? strftime('%Y/%m/%d', localtime $hardware->{date}) : '(none)';

    my $bal_present = ($content =~ /= \$552\.50/);

    print "\n=== FR-013 OFX RESULT ===\n";

    printf "Coffee Shop found:                    %s  (want yes)\n",
        $coffee ? 'yes' : 'NO';
    printf "Coffee Shop qty = -5.50:              %s  (want yes, got %s)\n",
        (defined $coffee_qty && $coffee_qty == -5.50) ? 'yes' : 'NO',
        $coffee_qty // 'undef';
    printf "Coffee Shop date = 2026/02/05:        %s  (want yes, got %s)\n",
        ($coffee_date eq '2026/02/05') ? 'yes' : 'NO',
        $coffee_date;
    printf "Coffee Shop state = cleared:          %s  (want yes, got %s)\n",
        ($coffee && $coffee->{state} eq 'cleared') ? 'yes' : 'NO',
        $coffee ? ($coffee->{state} || 'uncleared') : '(none)';

    printf "Hardware Store found:                 %s  (want yes)\n",
        $hardware ? 'yes' : 'NO';
    printf "Hardware Store qty = -42.00:          %s  (want yes, got %s)\n",
        (defined $hardware_qty && $hardware_qty == -42.00) ? 'yes' : 'NO',
        $hardware_qty // 'undef';
    printf "Hardware Store date = 2026/02/10:     %s  (want yes, got %s)\n",
        ($hardware_date eq '2026/02/10') ? 'yes' : 'NO',
        $hardware_date;
    printf "Hardware Store check# = 1001:         %s  (want yes, got %s)\n",
        ($hardware_num && $hardware_num eq '1001') ? 'yes' : 'NO',
        $hardware_num // '(none)';

    printf "Balance assertion \$552.50 in file:    %s  (want yes)\n",
        $bal_present ? 'yes' : 'NO';

    if ($coffee && $coffee_qty == -5.50 && $coffee_date eq '2026/02/05'
        && $coffee->{state} eq 'cleared'
        && $hardware && $hardware_qty == -42.00 && $hardware_date eq '2026/02/10'
        && $hardware_num && $hardware_num eq '1001'
        && $bal_present) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
