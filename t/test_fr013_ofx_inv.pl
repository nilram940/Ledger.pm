#!/usr/bin/perl
# FR-013: OFX investment account parser test.
# Verifies that Ledger::OFX parses INVBUY transactions correctly:
# - ticker symbol resolved from SECINFO (deferred via $data->{check})
# - share quantity, cost basis
# - account = filename-prefix + ':AAPL' after stop() fixup
# - INVPOS position balance assertion written

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
copy('fr013_ofx_inv.ofx', "$dir/Brokerage-2026-02.ofx") or die "copy ofx inv: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing Brokerage-2026-02.ofx (investment) ===\n";
$ledger->fromStmt("$dir/Brokerage-2026-02.ofx", {}, {});

my $expected_account = 'Brokerage:AAPL';

print "\n=== Transactions after import ===\n";
for my $tx (sort { $a->{date} <=> $b->{date} } $ledger->getTransactions()) {
    next unless $tx->{date};
    my $p = $tx->getPosting(0);
    printf "  %s %-10s %-20s  qty=%s  comm=%s  cost=%s\n",
        strftime('%Y/%m/%d', localtime $tx->{date}),
        $tx->{state} || 'uncleared',
        $tx->{payee},
        (defined $p->{quantity} ? $p->{quantity} : 'undef'),
        ($p->{commodity} // 'undef'),
        (defined $p->{cost}     ? $p->{cost}     : 'undef');
    printf "      account: %s\n", $p->{account} // '(none)';
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

check($ledger, $content, $expected_account);

sub check {
    my ($ledger, $content, $want_account) = @_;

    my @txns = grep { $_->{date} } $ledger->getTransactions();
    my ($buy) = grep { $_->{payee} eq 'Buy Apple Inc' } @txns;

    my $buy_qty  = $buy ? ($buy->getPosting(0)->{quantity}  // 'undef') : undef;
    my $buy_comm = $buy ? ($buy->getPosting(0)->{commodity} // 'undef') : undef;
    my $buy_cost = $buy ? ($buy->getPosting(0)->{cost}      // 'undef') : undef;
    my $buy_acct = $buy ? ($buy->getPosting(0)->{account}   // '')       : '';
    my $buy_date = $buy ? strftime('%Y/%m/%d', localtime $buy->{date})  : '(none)';

    my $pos_present = ($content =~ /= 5 AAPL/);

    print "\n=== FR-013 OFX Investment RESULT ===\n";

    printf "Buy Apple Inc found:                  %s  (want yes)\n",
        $buy ? 'yes' : 'NO';
    printf "qty = 5:                              %s  (want yes, got %s)\n",
        (defined $buy_qty && $buy_qty == 5) ? 'yes' : 'NO',
        $buy_qty // 'undef';
    printf "commodity = AAPL:                     %s  (want yes, got %s)\n",
        (defined $buy_comm && $buy_comm eq 'AAPL') ? 'yes' : 'NO',
        $buy_comm // 'undef';
    printf "cost = 900:                           %s  (want yes, got %s)\n",
        (defined $buy_cost && $buy_cost == 900) ? 'yes' : 'NO',
        $buy_cost // 'undef';
    printf "date = 2026/02/05:                    %s  (want yes, got %s)\n",
        ($buy_date eq '2026/02/05') ? 'yes' : 'NO',
        $buy_date;
    printf "account = Brokerage:AAPL:             %s\n  (want: %s\n   got:  %s)\n",
        ($buy_acct eq $want_account) ? 'yes' : 'NO',
        $want_account, $buy_acct;
    printf "INVPOS balance (= 5 AAPL) in file:    %s  (want yes)\n",
        $pos_present ? 'yes' : 'NO';

    if ($buy && $buy_qty == 5 && $buy_comm eq 'AAPL' && $buy_cost == 900
        && $buy_date eq '2026/02/05' && $buy_acct eq $want_account
        && $pos_present) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
