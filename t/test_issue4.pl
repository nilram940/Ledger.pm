#!/usr/bin/perl
# Reproduction script for issues 4a and 4b in issues.org.
#
# Issue 4a: A pending transaction that checkpending matches is left in the file
#           because update_file overwrites posmap{ofxpos} with -1, losing the
#           in-place edit.  Expected: one cleared transaction; actual: the cleared
#           version is inserted at ofxpos AND the old pending bytes remain.
#
# Issue 4b: The same posmap[ofxpos]=-1 clobber also destroys CC in-place edits.
#           CC import matches the uncleared via the ledgerCSV transfer queue; the
#           Checking import finds no queue match and parks as an orphaned append.
#           posmap{ofxpos}=-1 wipes the CC edit; result is the uncleared left in
#           place plus an extra Checking+Equity transaction (double debit).

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use POSIX qw(strftime);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

# ============================================================
# ISSUE 4a
# ============================================================
print "=" x 60, "\n";
print "ISSUE 4a: pending transaction left in place after clearing\n";
print "=" x 60, "\n\n";

my $f4a = "$dir/issue4a.ldg";
copy('issue4a.ldg', $f4a) or die "copy: $!";
copy('issue4a.csv', "$dir/Checking-2026-04.csv") or die "copy: $!";

my $ledger4a = Ledger->new(file => $f4a);

# Simple handler: no transfer routing.
my $handlers4a = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv4a = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "--- Ledger state before import ---\n";
dump_ledger($ledger4a);
printf "ofxfile: %s\n\n", $ledger4a->{ofxfile}//'(none)';

$ledger4a->fromStmt("$dir/Checking-2026-04.csv", $handlers4a, $csv4a);

print "\n--- Transactions after import (before write) ---\n";
dump_ledger($ledger4a);

printf "ofxpos: %d\n", $ledger4a->{ofxpos}//-1;

print "\n--- Writing changes ---\n";
$ledger4a->update();

print "\n--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh4a, '<', $f4a) or die $!;
print while <$fh4a>;
close $fh4a;
print "-" x 40, "\n";

check_4a($f4a);

# ============================================================
# ISSUE 4b
# ============================================================
print "\n", "=" x 60, "\n";
print "ISSUE 4b: CC import replaces checking split\n";
print "=" x 60, "\n\n";

my $f4b = "$dir/issue4b.ldg";
copy('issue4b.ldg',          $f4b)                          or die "copy: $!";
copy('issue4b-Visa.csv',     "$dir/Visa-2026-04.csv")       or die "copy: $!";
copy('issue4b-Checking.csv', "$dir/Checking-2026-04b.csv")  or die "copy: $!";

my $ledger4b = Ledger->new(file => $f4b);

my $handlers4b = {
    # CC side: tag='Visa' matches the 'Visa-500.00' ledgerCSV queue entry.
    # Checking side: tag='Checking' matches the 'Checking-500.00' ledgerCSV
    # queue entry.  setPosting then uses account-matching to update posting[0]
    # (Assets:Checking) rather than always clobbering posting[1].
    'Liabilities:Visa' => { '' => sub { return $ledger4b->transfer(shift, 'Visa')     } },
    'Assets:Checking'  => { '' => sub { return $ledger4b->transfer(shift, 'Checking') } },
};
my $csv4b = {
    Visa     => { fields => [qw(date id payee quantity account)], csv_args => {} },
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

print "--- Ledger state before import ---\n";
dump_ledger($ledger4b);

print "--- Step 1: import Visa (CC) statement ---\n";
$ledger4b->fromStmt("$dir/Visa-2026-04.csv", $handlers4b, $csv4b);

print "Transfer queue after CC import:\n";
dump_transfer($ledger4b);
print "\nTransactions after CC import:\n";
dump_ledger($ledger4b);

print "--- Step 2: import Checking statement ---\n";
$ledger4b->fromStmt("$dir/Checking-2026-04b.csv", $handlers4b, $csv4b);

print "Transfer queue after Checking import:\n";
dump_transfer($ledger4b);
print "\nTransactions after both imports:\n";
dump_ledger($ledger4b);

print "--- Writing changes ---\n";
$ledger4b->update();

print "\n--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh4b, '<', $f4b) or die $!;
print while <$fh4b>;
close $fh4b;
print "-" x 40, "\n";

check_4b($f4b);

# ============================================================
# Helpers
# ============================================================

sub dump_ledger {
    my $ledger = shift;
    for my $tx (sort { ($a->{date}||0) <=> ($b->{date}||0) }
                $ledger->getTransactions()) {
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

sub dump_transfer {
    my $ledger = shift;
    my $store = $ledger->{transfer};
    if ($store && %$store) {
        for my $key (sort keys %$store) {
            printf "  %-30s  %d entr%s\n", $key,
                scalar @{$store->{$key}},
                @{$store->{$key}} == 1 ? 'y' : 'ies';
            for my $entry (@{$store->{$key}}) {
                my ($tx, $post) = @$entry;
                printf "    txn: %-28s  posting.account=%-30s  cost=%.2f\n",
                    $tx->{payee}//'?', $post->{account}//'?', $post->cost()//0;
                # build_transfer always creates a copy hashref, so posting != getPosting(0).
                # Check staleness by seeing if the account still matches posting[0].
                my $live_acct = ($tx->getPosting(0) && $tx->getPosting(0)->{account}) // '';
                printf "    posting[0].account now: %-30s  (queue entry account: %s)%s\n",
                    $live_acct, $post->{account},
                    ($live_acct ne $post->{account} ? ' STALE' : ' ok');
            }
        }
    } else {
        print "  (empty)\n";
    }
}

sub check_4a {
    my $file = shift;
    open my $fh, '<', $file or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;

    my $pending_count = () = $content =~ /^2026\/04\/02\s+!/mg;
    my $cleared_count = () = $content =~ /^2026\/04\/02\s+\*/mg;

    print "\n--- Issue 4a RESULT ---\n";
    printf "Grocery Store (04/02) pending occurrences: %d  (want 0)\n", $pending_count;
    printf "Grocery Store (04/02) cleared occurrences: %d  (want 1)\n", $cleared_count;

    if ($pending_count == 0 && $cleared_count == 1) {
        print "PASS: pending transaction correctly cleared in-place\n";
    } else {
        print "FAIL: pending left in file or cleared version duplicated\n";
    }
}

sub check_4b {
    my $file = shift;
    open my $fh, '<', $file or die $!;
    my $content = do { local $/; <$fh> };
    close $fh;

    print "\n--- Issue 4b RESULT ---\n";

    # Count Visa Payment transaction blocks in the file.
    my @visa_txns = ($content =~ /((?:^|\n)(?:[\d\/]+ [!* ] Visa Payment[^\n]*\n)(?:(?![\d\/]{4}\/)[^\n]*\n)*)/mg);
    printf "Visa Payment transaction blocks in file: %d (want 1)\n", scalar @visa_txns;

    my $has_visa_id  = $content =~ /VISA-PAY-001/;
    my $has_check_id = $content =~ /CHK-PAY-001/;
    my $uncleared    = $content =~ /\d ! Visa Payment/;
    printf "Has VISA-PAY-001 ID:       %s  (want yes)\n", $has_visa_id  ? 'yes' : 'NO';
    printf "Has CHK-PAY-001 ID:        %s\n", $has_check_id ? 'yes' : 'no';
    printf "Uncleared Visa Payment:    %s  (want no)\n",  $uncleared    ? 'YES' : 'no';

    if (@visa_txns == 1 && $has_visa_id && !$uncleared) {
        print "PASS: single cleared Visa Payment with CC ID\n";
    } else {
        print "FAIL: uncleared left in file, or duplicate, or CC ID missing\n";
    }
}
