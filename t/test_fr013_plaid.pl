#!/usr/bin/perl
# FR-013: Plaid JSON parser test.
# Verifies that Ledger::JSON::Plaid parses correctly:
# - ledger_name override is used instead of official_name/name
# - cleared vs pending state is set from the "pending" field
# - amounts are negated (Plaid sign → ledger sign)
# - balance assertion is written for cleared transactions

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
copy('fr013_plaid.json', "$dir/Plaid-2026-02.json") or die "copy plaid: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing Plaid-2026-02.json ===\n";
$ledger->fromStmt("$dir/Plaid-2026-02.json", {}, {});

my $expected_account = 'Assets:Current Assets:My Checking';

print "\n=== Transactions after import ===\n";
for my $tx (sort { $a->{date} <=> $b->{date} } $ledger->getTransactions()) {
    next unless $tx->{date};
    printf "  %s %-10s %-22s  qty=%.2f  acct=%s\n",
        strftime('%Y/%m/%d', localtime $tx->{date}),
        $tx->{state} || 'uncleared',
        $tx->{payee},
        ($tx->getPosting(0)->{quantity} // 0),
        ($tx->getPosting(0)->{account}  // '');
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

    my ($coffee)  = grep { $_->{payee} eq 'Coffee Shop'  } @txns;
    my ($grocery) = grep { $_->{payee} eq 'Grocery Store' } @txns;

    my $coffee_qty     = $coffee  ? ($coffee->getPosting(0)->{quantity}  // 0) : undef;
    my $coffee_acct    = $coffee  ? ($coffee->getPosting(0)->{account}   // '') : '';
    my $grocery_qty    = $grocery ? ($grocery->getPosting(0)->{quantity} // 0) : undef;

    my $coffee_date  = $coffee  ? strftime('%Y/%m/%d', localtime $coffee->{date})  : '(none)';
    my $grocery_date = $grocery ? strftime('%Y/%m/%d', localtime $grocery->{date}) : '(none)';

    my $bal_present = ($content =~ /= \$994\.50/);

    print "\n=== FR-013 Plaid RESULT ===\n";

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
    printf "Coffee Shop account = correct:        %s\n  (want: %s\n   got:  %s)\n",
        ($coffee_acct eq $want_account) ? 'yes' : 'NO',
        $want_account, $coffee_acct;

    printf "Grocery Store found:                  %s  (want yes)\n",
        $grocery ? 'yes' : 'NO';
    printf "Grocery Store qty = -20.00:           %s  (want yes, got %s)\n",
        (defined $grocery_qty && $grocery_qty == -20.00) ? 'yes' : 'NO',
        $grocery_qty // 'undef';
    printf "Grocery Store state = pending:        %s  (want yes, got %s)\n",
        ($grocery && $grocery->{state} eq 'pending') ? 'yes' : 'NO',
        $grocery ? ($grocery->{state} || 'uncleared') : '(none)';

    printf "Balance assertion \$994.50 in file:    %s  (want yes)\n",
        $bal_present ? 'yes' : 'NO';

    if ($coffee && $coffee_qty == -5.50 && $coffee_date eq '2026/02/05'
        && $coffee->{state} eq 'cleared'
        && $coffee_acct eq $want_account
        && $grocery && $grocery_qty == -20.00
        && $grocery->{state} eq 'pending'
        && $bal_present) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
