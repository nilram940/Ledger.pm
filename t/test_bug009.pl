#!/usr/bin/perl
# BUG-009: LEDGERNAME: in OFX free-form header overrides filename-derived account.
# Verifies that a LEDGERNAME: line in the OFX header is used as the posting account
# instead of the prefix extracted from the filename.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg) or die "copy base: $!";

# Filename prefix "BankStmt" is deliberately wrong; LEDGERNAME: should win
copy('fr013_ofx_named.ofx', "$dir/BankStmt-2026-03.ofx") or die "copy ofx: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing BankStmt-2026-03.ofx (has LEDGERNAME: Assets:Checking:MyBank) ===\n";
$ledger->fromStmt("$dir/BankStmt-2026-03.ofx", {}, {});

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
    my ($grocery) = grep { $_->{payee} eq 'Grocery Store' } @txns;

    my $acct      = $grocery ? $grocery->getPosting(0)->{account} : '(none)';
    my $bal       = ($content =~ /= \$488\.00/);
    my $bal_acct  = ($content =~ /\[Assets:Checking:MyBank\]/);
    my $correct   = ($acct eq 'Assets:Checking:MyBank');
    my $not_stub  = ($acct !~ /^BankStmt/);

    print "\n=== BUG-009 RESULT ===\n";

    printf "Grocery Store found:                         %s  (want yes)\n",
        $grocery ? 'yes' : 'NO';
    printf "Account = Assets:Checking:MyBank:            %s  (want yes, got %s)\n",
        $correct ? 'yes' : 'NO', $acct;
    printf "Account is not filename-derived (BankStmt):  %s  (want yes)\n",
        $not_stub ? 'yes' : 'NO';
    printf "Balance assertion \$488.00 in file:           %s  (want yes)\n",
        $bal ? 'yes' : 'NO';
    printf "Balance acct = [Assets:Checking:MyBank]:     %s  (want yes)\n",
        $bal_acct ? 'yes' : 'NO';

    if ($grocery && $correct && $not_stub && $bal && $bal_acct) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
