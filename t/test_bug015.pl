#!/usr/bin/perl
# BUG-015: Bayesian classifier predicts Equity:Transfers: destination.
#
# gentable now includes Equity:Transfers:* in training data (excluding other
# Equity: entries).  When the classifier has seen enough examples of a payee
# routing to a specific Equity:Transfers:X account, balance() should return
# that transfer tag for a new transaction with the same source account and
# payee tokens, even when no handler is provided.
#
# Fixture: three cleared "PAYMENT THANK YOU" transactions on Liabilities:Visa,
# all routed to Equity:Transfers:Checking.  New import: a fourth payment for
# a different amount (no existing transfer-queue stub to accidentally match).
# Expected: classifier predicts Equity:Transfers:Checking with high confidence;
# no INFO: annotation; no handler needed.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('bug015.ldg', $ldg)                    or die "copy ldg: $!";
copy('bug015.csv', "$dir/Visa-2026-04.csv") or die "copy csv: $!";

my $ledger = Ledger->new(file => $ldg);

my $csv_config = {
    Visa => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "=== Importing Visa-2026-04.csv (no handlers) ===\n";
$ledger->fromStmt("$dir/Visa-2026-04.csv", {}, $csv_config);

print "\n=== Transactions after import ===\n";
for my $tx (sort { $a->{date} <=> $b->{date} } grep { $_->{date} } $ledger->getTransactions()) {
    printf "  %s %s\n", $tx->{state} // 'uncleared', $tx->{payee};
    for my $p ($tx->getPostings()) {
        my $qty = defined($p->{quantity}) && length($p->{quantity})
                  ? sprintf('$%.2f', $p->{quantity}) : '(inferred)';
        printf "    %-42s %s%s\n",
            $p->{account}, $qty,
            ($p->{note} ? "  ; $p->{note}" : '');
    }
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

    my ($new_txn) = grep {
        $_->{date}
        && $_->{payee} eq 'PAYMENT THANK YOU'
        && abs(($_->getPosting(0)->{quantity} // 0) - 250) < 0.01
    } $ledger->getTransactions();

    my $has_new       = defined $new_txn;
    my $dest_account  = $has_new ? ($new_txn->getPosting(1)->{account} // '') : '';
    my $correct_dest  = $dest_account eq 'Equity:Transfers:Visa';
    my $no_info       = $content !~ /INFO:/;
    my $in_file       = $content =~ /Equity:Transfers:Visa/;

    print "\n=== BUG-015 RESULT ===\n";
    printf "New \$250 transaction found:               %s  (want yes)\n",
        $has_new ? 'yes' : 'NO';
    printf "Posting[1] = Equity:Transfers:Visa:       %s  (want yes, got: %s)\n",
        $correct_dest ? 'yes' : 'NO', $dest_account || '(none)';
    printf "No INFO: annotation (>=90%% confidence):  %s  (want yes)\n",
        $no_info ? 'yes' : 'NO';
    printf "Written to file:                          %s  (want yes)\n",
        $in_file ? 'yes' : 'NO';

    if ($has_new && $correct_dest && $no_info && $in_file) {
        print "PASS: classifier predicted Equity:Transfers:Visa without a handler\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
