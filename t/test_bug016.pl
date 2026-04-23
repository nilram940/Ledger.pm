#!/usr/bin/perl
# BUG-016: cleared transaction written at EOF instead of cleared section.
#
# When the FIRST pending transaction (at cleared_pos) is matched by an import,
# its bpos == cleared_pos, so posfilter registers posmap{cleared_pos} = $tx_ref.
# The sentinel registration (//=) then skips that position, leaving
# append_for{cleared} unhandled until EOF.
#
# Fix: in the ref-branch of update_file, when pos == cleared_pos, emit
# append_for{cleared} and balance entries immediately after the in-place skip.

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
print "BUG-016: first pending tx cleared falls to EOF\n";
print "=" x 60, "\n\n";

my $f16 = "$dir/bug016.ldg";
copy('bug016.ldg', $f16)                      or die "copy: $!";
copy('bug016.csv', "$dir/Checking-2026-03.csv") or die "copy: $!";

my $ledger = Ledger->new(file => $f16);

my $handlers = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "--- Ledger state before import ---\n";
dump_ledger($ledger);
printf "cleared_pos: %d\n\n", $ledger->{cleared_pos} // -1;

$ledger->fromStmt("$dir/Checking-2026-03.csv", $handlers, $csv);

print "--- Transactions after import (before write) ---\n";
dump_ledger($ledger);

print "--- Writing changes ---\n";
$ledger->update();

print "\n--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh, '<', $f16) or die $!;
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

    my $kfc_cleared_pos  = index($content, '* KFC');
    my $kfc_pending_pos  = index($content, '! KFC');
    my $bal50_pos        = index($content, '= $50.00');
    my $walmart_pos      = index($content, '! Wal-Mart');

    my $kfc_cleared  = $content =~ /\* KFC/;
    my $kfc_pending  = $content =~ /! KFC/;
    my $walmart_pending = $content =~ /! Wal-Mart/;

    print "\n--- BUG-016 RESULT ---\n";
    printf "KFC cleared offset in file:       %d\n", $kfc_cleared_pos;
    printf "Balance \$50 offset in file:       %d\n", $bal50_pos;
    printf "Wal-Mart offset in file:          %d\n", $walmart_pos;
    printf "KFC is cleared:                   %s  (want yes)\n", $kfc_cleared    ? 'yes' : 'NO';
    printf "KFC is still pending:             %s  (want no)\n",  $kfc_pending    ? 'YES' : 'no';
    printf "Wal-Mart is still pending:        %s  (want yes)\n", $walmart_pending ? 'yes' : 'NO';
    printf "KFC cleared before balance \$50:   %s  (want yes)\n",
        ($kfc_cleared_pos >= 0 && $bal50_pos > $kfc_cleared_pos) ? 'yes' : 'NO';
    printf "Balance \$50 before Wal-Mart:      %s  (want yes)\n",
        ($bal50_pos >= 0 && $bal50_pos < $walmart_pos) ? 'yes' : 'NO';

    if ($kfc_cleared && !$kfc_pending && $walmart_pending
            && $kfc_cleared_pos >= 0 && $kfc_cleared_pos < $bal50_pos
            && $bal50_pos >= 0       && $bal50_pos < $walmart_pos) {
        print "PASS: KFC moved to cleared section; balance assertion written; Wal-Mart remains pending\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
