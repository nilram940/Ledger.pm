#!/usr/bin/perl
# BUG-009 (investment): LEDGERNAME: in OFX free-form header overrides filename-derived
# account for investment transactions (INVBUY) and position balances (INVPOS).
# Verifies that inv/invpos handlers use LEDGERNAME, not the filename prefix.

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

# Filename prefix "BrokerStmt" is deliberately wrong; LEDGERNAME: should win
copy('fr013_ofx_inv_named.ofx', "$dir/BrokerStmt-2026-02.ofx") or die "copy ofx: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing BrokerStmt-2026-02.ofx (has LEDGERNAME: Assets:Brokerage:Fidelity) ===\n";
$ledger->fromStmt("$dir/BrokerStmt-2026-02.ofx", {}, {});

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

    my @txns = grep { $_->{date} && $_->{payee} } $ledger->getTransactions();
    my ($buy) = grep { $_->{payee} eq 'Buy Apple Inc' } @txns;

    my $acct      = $buy ? ($buy->getPosting(0)->{account} // '') : '(none)';
    my $want      = 'Assets:Brokerage:Fidelity:AAPL';
    my $correct   = ($acct eq $want);
    my $not_stub  = ($acct !~ /^BrokerStmt/);
    my $bal_acct  = ($content =~ /\[Assets:Brokerage:Fidelity:AAPL\]/);

    print "\n=== BUG-009 Investment RESULT ===\n";

    printf "Buy Apple Inc found:                         %s  (want yes)\n",
        $buy ? 'yes' : 'NO';
    printf "Account = Assets:Brokerage:Fidelity:AAPL:   %s\n  (want: %s\n   got:  %s)\n",
        $correct ? 'yes' : 'NO', $want, $acct;
    printf "Account is not filename-derived (BrokerStmt):%s  (want yes)\n",
        $not_stub ? 'yes' : 'NO';
    printf "INVPOS balance [Assets:Brokerage:Fidelity:AAPL] in file: %s  (want yes)\n",
        $bal_acct ? 'yes' : 'NO';

    if ($buy && $correct && $not_stub && $bal_acct) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
