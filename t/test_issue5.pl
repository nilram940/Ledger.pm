#!/usr/bin/perl
# Issue 5: pending transaction cleared in-place instead of moved.
#
# When a pending transaction (not at ofxpos) is matched and cleared by an
# import, it should be deleted from its pending position and appended at
# ofxpos (the cleared section boundary).  Before the fix, edit_pos was set
# to bpos, so the transaction was simply overwritten in-place, leaving it
# below other pending transactions in the file.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use POSIX qw(strftime);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "ISSUE 5: pending transaction cleared in place\n";
print "=" x 60, "\n\n";

my $f5 = "$dir/issue5.ldg";
copy('issue5.ldg', $f5)           or die "copy: $!";
copy('issue5.csv', "$dir/Checking-2026-02.csv") or die "copy: $!";

my $ledger = Ledger->new(file => $f5);

my $handlers = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "--- Ledger state before import ---\n";
dump_ledger($ledger);
printf "ofxfile: %s\n", $ledger->{ofxfile} // '(none)';
printf "ofxpos:  %d\n\n", $ledger->{ofxpos} // -1;

$ledger->fromStmt("$dir/Checking-2026-02.csv", $handlers, $csv);

print "--- Transactions after import (before write) ---\n";
dump_ledger($ledger);

print "--- Writing changes ---\n";
$ledger->update();

print "\n--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh, '<', $f5) or die $!;
my $content = do { local $/; <$fh> };
close $fh;
print $content;
print "-" x 40, "\n";

check($content);

sub dump_ledger {
    my $l = shift;
    for my $tx (sort { ($a->{date}||0) <=> ($b->{date}||0) }
                $l->getTransactions()) {
        next unless $tx->{date};
        my $state = $tx->{state} eq 'cleared' ? '*'
                  : $tx->{state} eq 'pending'  ? '!'
                  : ' ';
        printf "  %s %s %s\n",
            strftime('%Y/%m/%d', localtime $tx->{date}),
            $state, $tx->{payee};
        for my $p ($tx->getPostings()) {
            my $qty = defined($p->{quantity}) && length($p->{quantity})
                      ? sprintf('$%.2f', $p->{quantity}) : '(blank)';
            printf "      %-40s %8s%s\n",
                $p->{account}, $qty,
                ($p->{note} ? "  ; $p->{note}" : '');
        }
        printf "    [edit=%s  pos=%s]\n",
            $tx->{edit}//'', $tx->{edit_pos}//'undef'
            if $tx->{edit};
        print "\n";
    }
}

sub check {
    my $content = shift;

    my $walmart_pos = index($content, '* Wal-Mart');
    my $kfc_pos     = index($content, '! KFC');
    my $bal65_pos   = index($content, '= $65.00');

    my $walmart_cleared = $content =~ /\* Wal-Mart/;
    my $kfc_pending     = $content =~ /! KFC/;
    my $walmart_pending = $content =~ /! Wal-Mart/;

    print "\n--- Issue 5 RESULT ---\n";
    printf "Wal-Mart offset in file:          %d\n", $walmart_pos;
    printf "Balance \$65 offset in file:       %d\n", $bal65_pos;
    printf "KFC offset in file:               %d\n", $kfc_pos;
    printf "Wal-Mart is cleared:              %s  (want yes)\n", $walmart_cleared ? 'yes' : 'NO';
    printf "Wal-Mart is pending:              %s  (want no)\n",  $walmart_pending ? 'YES' : 'no';
    printf "KFC is still pending:             %s  (want yes)\n", $kfc_pending     ? 'yes' : 'NO';
    printf "Wal-Mart before balance \$65:      %s  (want yes)\n",
        ($walmart_pos >= 0 && $bal65_pos > $walmart_pos) ? 'yes' : 'NO';
    printf "Balance \$65 before KFC:           %s  (want yes)\n",
        ($bal65_pos >= 0 && $bal65_pos < $kfc_pos) ? 'yes' : 'NO';

    if ($walmart_cleared && !$walmart_pending && $kfc_pending
            && $walmart_pos >= 0 && $walmart_pos < $bal65_pos
            && $bal65_pos >= 0  && $bal65_pos < $kfc_pos) {
        print "PASS: Wal-Mart moved to cleared section; balance assertion written; KFC remains pending\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
