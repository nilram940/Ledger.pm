#!/usr/bin/perl
# FR-020: Ledger::CSV::Coinbase module.
# Verifies Buy (commodity+cost), Sell (negative qty+cost), and Rewards Income
# (commodity, no cost) using the Coinbase Advanced Trade CSV export format.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;
use Ledger::CSV::Coinbase;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg) or die "copy base: $!";
copy('fr020_coinbase.csv', "$dir/Coinbase-2026-03.csv") or die "copy csv: $!";

my $ledger = Ledger->new(file => $ldg);

my $csv_config = {
    Coinbase => Ledger::CSV::Coinbase->config(),
};

print "=== Importing Coinbase-2026-03.csv ===\n";
$ledger->fromStmt("$dir/Coinbase-2026-03.csv", {}, $csv_config);

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

    my ($buy)     = grep { $_->getPosting(0)->{account} =~ /Coinbase:ETH/
                           && ($_->getPosting(0)->{quantity}//0) > 0 } @txns;
    my ($sell)    = grep { $_->getPosting(0)->{account} =~ /Coinbase:ETH/
                           && ($_->getPosting(0)->{quantity}//0) < 0 } @txns;
    my ($rewards) = grep { $_->getPosting(0)->{account} =~ /Coinbase:BTC/ } @txns;

    my $buy_acct  = $buy     ? $buy->getPosting(0)->{account}    : '(none)';
    my $buy_qty   = $buy     ? $buy->getPosting(0)->{quantity}    : undef;
    my $buy_cost  = $buy     ? $buy->getPosting(0)->{cost}        : undef;
    my $buy_comm  = $buy     ? $buy->getPosting(0)->{commodity}   : '(none)';

    my $sell_acct = $sell    ? $sell->getPosting(0)->{account}   : '(none)';
    my $sell_qty  = $sell    ? $sell->getPosting(0)->{quantity}   : undef;
    my $sell_cost = $sell    ? $sell->getPosting(0)->{cost}       : undef;
    my $sell_comm = $sell    ? $sell->getPosting(0)->{commodity}  : '(none)';

    my $rew_acct  = $rewards ? $rewards->getPosting(0)->{account}   : '(none)';
    my $rew_qty   = $rewards ? $rewards->getPosting(0)->{quantity}   : undef;
    my $rew_cost  = $rewards ? $rewards->getPosting(0)->{cost}       : undef;
    my $rew_comm  = $rewards ? $rewards->getPosting(0)->{commodity}  : '(none)';

    print "\n=== FR-020 Coinbase RESULT ===\n";

    printf "Buy found:                           %s  (want yes)\n",
        $buy ? 'yes' : 'NO';
    printf "Buy account = Assets:Coinbase:ETH:   %s\n  (want: Assets:Coinbase:ETH\n   got:  %s)\n",
        ($buy_acct eq 'Assets:Coinbase:ETH') ? 'yes' : 'NO', $buy_acct;
    printf "Buy qty = 1.5:                       %s  (want yes, got %s)\n",
        (defined $buy_qty && abs($buy_qty - 1.5) < 0.001) ? 'yes' : 'NO',
        $buy_qty // 'undef';
    printf "Buy cost = 3007.50:                  %s  (want yes, got %s)\n",
        (defined $buy_cost && abs($buy_cost - 3007.50) < 0.01) ? 'yes' : 'NO',
        $buy_cost // 'undef';
    printf "Buy commodity = ETH:                 %s  (want yes, got %s)\n",
        ($buy_comm eq 'ETH') ? 'yes' : 'NO', $buy_comm;

    printf "Sell found:                          %s  (want yes)\n",
        $sell ? 'yes' : 'NO';
    printf "Sell account = Assets:Coinbase:ETH:  %s\n  (want: Assets:Coinbase:ETH\n   got:  %s)\n",
        ($sell_acct eq 'Assets:Coinbase:ETH') ? 'yes' : 'NO', $sell_acct;
    printf "Sell qty = -0.5:                     %s  (want yes, got %s)\n",
        (defined $sell_qty && abs($sell_qty - (-0.5)) < 0.001) ? 'yes' : 'NO',
        $sell_qty // 'undef';
    printf "Sell cost = 1096.50:                 %s  (want yes, got %s)\n",
        (defined $sell_cost && abs($sell_cost - 1096.50) < 0.01) ? 'yes' : 'NO',
        $sell_cost // 'undef';
    printf "Sell commodity = ETH:                %s  (want yes, got %s)\n",
        ($sell_comm eq 'ETH') ? 'yes' : 'NO', $sell_comm;

    printf "Rewards Income found:                %s  (want yes)\n",
        $rewards ? 'yes' : 'NO';
    printf "Rewards account = Assets:Coinbase:BTC: %s\n  (want: Assets:Coinbase:BTC\n   got:  %s)\n",
        ($rew_acct eq 'Assets:Coinbase:BTC') ? 'yes' : 'NO', $rew_acct;
    printf "Rewards qty = 0.001:                 %s  (want yes, got %s)\n",
        (defined $rew_qty && abs($rew_qty - 0.001) < 0.0001) ? 'yes' : 'NO',
        $rew_qty // 'undef';
    printf "Rewards commodity = BTC:             %s  (want yes, got %s)\n",
        ($rew_comm eq 'BTC') ? 'yes' : 'NO', $rew_comm;
    printf "Rewards cost absent:                 %s  (want yes, got %s)\n",
        (!defined $rew_cost || $rew_cost == 0) ? 'yes' : 'NO',
        $rew_cost // 'undef';

    if ($buy  && $buy_acct  eq 'Assets:Coinbase:ETH'
             && abs($buy_qty  - 1.5)     < 0.001
             && abs($buy_cost - 3007.50) < 0.01
             && $buy_comm eq 'ETH'
        && $sell && $sell_acct eq 'Assets:Coinbase:ETH'
             && abs($sell_qty  - (-0.5))   < 0.001
             && abs($sell_cost - 1096.50)  < 0.01
             && $sell_comm eq 'ETH'
        && $rewards && $rew_acct eq 'Assets:Coinbase:BTC'
             && abs($rew_qty - 0.001) < 0.0001
             && $rew_comm eq 'BTC'
             && (!defined $rew_cost || $rew_cost == 0)) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
