#!/usr/bin/perl
# Inline balance assertion: verify that the last cleared posting for each
# account gets an inline "= $x.xx" when a balance entry is present.
#
# Uses the bug016 fixtures: a cleared Coffee Shop, then KFC+Wal-Mart pending.
# The CSV clears KFC and supplies a $50.00 balance for Assets:Checking.
# After update(), the KFC posting for Assets:Checking must contain "= $50.00".

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "Inline balance assertion on last cleared transaction\n";
print "=" x 60, "\n\n";

my $ldg = "$dir/bal_inline.ldg";
copy('bug016.ldg', $ldg)                          or die "copy: $!";
copy('bug016.csv', "$dir/Checking-2026-03.csv")   or die "copy: $!";

my $ledger = Ledger->new(file => $ldg);

my $handlers = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

$ledger->fromStmt("$dir/Checking-2026-03.csv", $handlers, $csv);

print "--- Balance store after import ---\n";
for my $acct (sort keys %{$ledger->{balance}}) {
    for my $com (sort keys %{$ledger->{balance}{$acct}}) {
        my $t = $ledger->{balance}{$acct}{$com};
        my $qty = $t->{postings}[0]{quantity} // '(undef)';
        printf "  %-40s / %-5s = %s\n", $acct, $com, $qty;
    }
}
print "\n";

$ledger->update();

print "--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh, '<', $ldg) or die $!;
my $content = do { local $/; <$fh> };
close $fh;
print $content;
print "-" x 40, "\n\n";

check($content);

sub check {
    my $content = shift;

    my $kfc_cleared     = $content =~ /\* KFC/;
    my $inline_bal      = $content =~ /\$-15\.00 = \$50\.00/;
    my $walmart_pending = $content =~ /! Wal-Mart/;

    print "--- RESULT ---\n";
    printf "KFC cleared:                %s  (want yes)\n", $kfc_cleared     ? 'yes' : 'NO';
    printf "Inline '= \$50.00' on KFC: %s  (want yes)\n", $inline_bal      ? 'yes' : 'NO';
    printf "Wal-Mart still pending:     %s  (want yes)\n", $walmart_pending  ? 'yes' : 'NO';

    if ($kfc_cleared && $inline_bal && $walmart_pending) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
