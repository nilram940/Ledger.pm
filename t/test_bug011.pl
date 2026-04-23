#!/usr/bin/perl
# BUG-011 regression: balance assertion dropped when @append is empty.
#
# When all CSV transactions are deduplicated (already cleared in the ledger),
# @append is empty and the -1 sentinel is never inserted at ofxpos via //=.
# The balance assertion from addStmtBal must still be written to the file.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "BUG-011: balance assertion dropped when \@append is empty\n";
print "=" x 60, "\n\n";

my $ldg = "$dir/bug011.ldg";
copy('bug011.ldg', $ldg)                              or die "copy: $!";
copy('bug011.csv', "$dir/Checking-2026-01.csv")       or die "copy: $!";

my $ledger = Ledger->new(file => $ldg);

my $handlers = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "--- Ledger state before import ---\n";
for my $tx (sort { $a->{date} <=> $b->{date} } $ledger->getTransactions()) {
    next unless $tx->{date};
    printf "  %s %s %s\n", scalar(localtime($tx->{date})), $tx->{state}, $tx->{payee};
}
printf "cleared_file: %s\ncleared_pos:  %d\n\n",
    $ledger->{cleared_file} // '(none)', $ledger->{cleared_pos} // -1;

$ledger->fromStmt("$dir/Checking-2026-01.csv", $handlers, $csv);

print "--- Balance store after import ---\n";
for my $acct (sort keys %{$ledger->{balance}}) {
    for my $comm (sort keys %{$ledger->{balance}{$acct}}) {
        printf "  %s / %s\n", $acct, $comm;
    }
}
print "\n";

print "--- Writing changes ---\n";
$ledger->update();

print "\n--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh, '<', $ldg) or die $!;
my $content = do { local $/; <$fh> };
close $fh;
print $content;
print "-" x 40, "\n";

check($content);

sub check {
    my $content = shift;

    my $coffee_count = () = $content =~ /^\d{4}\/\d{2}\/\d{2}.*Coffee Shop/mg;
    my $bal_pos      = index($content, '= $995.00');

    print "\n--- BUG-011 RESULT ---\n";
    printf "Coffee Shop occurrences (want 1, not 2): %d\n", $coffee_count;
    printf "Balance assertion \$995 present:          %s  (want yes)\n",
        $bal_pos >= 0 ? 'yes' : 'NO';

    if ($coffee_count == 1 && $bal_pos >= 0) {
        print "PASS: transaction not duplicated; balance assertion written despite empty \@append\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
