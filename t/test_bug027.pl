#!/usr/bin/perl
# BUG-027: Fidelity money market reinvestments (FDRXX, SPAXX) should be skipped.
# A "Dividend Received" for a cash fund is kept; the paired "Reinvestment" row
# that debits the same amount back out is skipped.  Non-cash buys (FXAIX) are
# unaffected.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;
use Ledger::CSV::Fidelity;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg) or die "copy base: $!";
copy('bug027_cashfund.csv', "$dir/Fidelity-2026-03.csv") or die "copy csv: $!";

my $ledger = Ledger->new(file => $ldg);

my %account_map = (
    'Individual - TOD (...1234)' => 'Assets:Investments:Fidelity',
);

my $csv_config = {
    Fidelity => Ledger::CSV::Fidelity->config(account_map => \%account_map),
};

print "=== Importing Fidelity-2026-03.csv ===\n";
$ledger->fromStmt("$dir/Fidelity-2026-03.csv", {}, $csv_config);

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

    # All imported transactions (new appends, state=cleared)
    my @new = grep {
        ($_->{state}//'') eq 'cleared'
        && defined($_->{edit_pos}) && $_->{edit_pos} < 0
    } @txns;

    my @reinvest = grep { ($_->{payee}//'') =~ /reinvestment/i } @new;

    # Dividend accounts end with 'Fidelity' (no :SYMBOL suffix)
    my ($fdrxx_div) = grep {
        ($_->{payee}//'') =~ /Dividend/i
        && ($_->getPosting(0)->{account}//'') =~ /Fidelity$/
        && abs(($_->getPosting(0)->{quantity}//0) - 1.23) < 0.01
    } @new;

    my ($spaxx_div) = grep {
        ($_->{payee}//'') =~ /Dividend/i
        && ($_->getPosting(0)->{account}//'') =~ /Fidelity$/
        && abs(($_->getPosting(0)->{quantity}//0) - 0.50) < 0.01
    } @new;

    my ($fxaix_buy) = grep {
        ($_->{payee}//'') =~ /You Bought/i
        && ($_->getPosting(0)->{commodity}//'') eq 'FXAIX'
    } @new;

    my $fdrxx_acct = $fdrxx_div ? $fdrxx_div->getPosting(0)->{account} : '(none)';
    my $spaxx_acct = $spaxx_div ? $spaxx_div->getPosting(0)->{account} : '(none)';
    my $buy_acct   = $fxaix_buy ? $fxaix_buy->getPosting(0)->{account}  : '(none)';
    my $buy_qty    = $fxaix_buy ? $fxaix_buy->getPosting(0)->{quantity}  : undef;
    my $buy_cost   = $fxaix_buy ? $fxaix_buy->getPosting(0)->{cost}      : undef;

    print "\n=== BUG-027 cash fund reinvestment skip RESULT ===\n";

    printf "Reinvestment rows skipped:           %s  (want 0, got %d)\n",
        (@reinvest == 0) ? 'yes' : 'NO', scalar @reinvest;

    printf "FDRXX dividend imported:             %s  (want yes)\n",
        $fdrxx_div ? 'yes' : 'NO';
    printf "FDRXX dividend account (no sym):     %s\n  (want: Assets:Investments:Fidelity\n   got:  %s)\n",
        ($fdrxx_acct eq 'Assets:Investments:Fidelity') ? 'yes' : 'NO', $fdrxx_acct;

    printf "SPAXX dividend imported:             %s  (want yes)\n",
        $spaxx_div ? 'yes' : 'NO';
    printf "SPAXX dividend account (no sym):     %s\n  (want: Assets:Investments:Fidelity\n   got:  %s)\n",
        ($spaxx_acct eq 'Assets:Investments:Fidelity') ? 'yes' : 'NO', $spaxx_acct;

    printf "FXAIX buy imported:                  %s  (want yes)\n",
        $fxaix_buy ? 'yes' : 'NO';
    printf "FXAIX buy account = ...Fidelity:FXAIX: %s\n  (want: Assets:Investments:Fidelity:FXAIX\n   got:  %s)\n",
        ($buy_acct eq 'Assets:Investments:Fidelity:FXAIX') ? 'yes' : 'NO', $buy_acct;
    printf "FXAIX buy qty = 2.0:                 %s  (want yes, got %s)\n",
        (defined $buy_qty && abs($buy_qty - 2.0) < 0.001) ? 'yes' : 'NO',
        $buy_qty // 'undef';
    printf "FXAIX buy cost = 250.00:             %s  (want yes, got %s)\n",
        (defined $buy_cost && abs($buy_cost - 250.0) < 0.01) ? 'yes' : 'NO',
        $buy_cost // 'undef';

    # Verify reinvestment rows are absent from the written ledger file
    my $no_reinvest_in_file = ($content !~ /Reinvestment/i);
    printf "No 'Reinvestment' in ledger file:    %s  (want yes)\n",
        $no_reinvest_in_file ? 'yes' : 'NO';

    if (@reinvest == 0
        && $fdrxx_div && $fdrxx_acct eq 'Assets:Investments:Fidelity'
        && $spaxx_div && $spaxx_acct eq 'Assets:Investments:Fidelity'
        && $fxaix_buy && $buy_acct eq 'Assets:Investments:Fidelity:FXAIX'
                      && defined $buy_qty  && abs($buy_qty  - 2.0)   < 0.001
                      && defined $buy_cost && abs($buy_cost - 250.0) < 0.01
        && $no_reinvest_in_file) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
