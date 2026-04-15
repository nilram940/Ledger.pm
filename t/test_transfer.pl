#!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use POSIX qw(strftime);
use lib '..';
use Ledger;

# Work on a copy so the original test data is never modified
my $dir = tempdir(CLEANUP => 0);
my $ledger_file = "$dir/test.ldg";
copy('transfer.ldg', $ledger_file) or die "copy failed: $!";
print "Working copy: $ledger_file\n\n";

# -----------------------------------------------------------------------
# 1. Load the ledger — this runs ledgerCSV and builds the transfer store
# -----------------------------------------------------------------------
print "=== Loading ledger ===\n";
my $ledger = new Ledger(file => $ledger_file);

print "\n--- Transfer store after ledgerCSV ---\n";
dump_transfer_store($ledger);

# -----------------------------------------------------------------------
# 2. Import the Visa CC statement
# -----------------------------------------------------------------------
# Handler: any Liabilities:Visa transaction routes to a transfer.
# Key must match $stmttrn->{account} (the full account name from the CSV).
my $handlers = {
    'Liabilities:Visa'  => { '' => sub { return $ledger->transfer(shift, 'Visa') } },
    'Assets:Checking'   => { '' => sub { return shift } },
};

my $csv_config = {
    Visa => {
        fields   => [qw(date id payee quantity account)],
        csv_args => {},
    },
    Checking => {
        fields   => [qw(date id payee quantity account)],
        csv_args => {},
    },
};

print "\n=== Importing Visa-2026-03.csv ===\n";
$ledger->fromStmt('Visa-2026-03.csv', $handlers, $csv_config);

print "\n--- Transfer store after Visa import ---\n";
dump_transfer_store($ledger);

print "\n=== Importing Checking-2026-03.csv ===\n";
$ledger->fromStmt('Checking-2026-03.csv', $handlers, $csv_config);

print "\n--- Transfer store after Checking import ---\n";
dump_transfer_store($ledger);

# -----------------------------------------------------------------------
# 3. Show all transactions
# -----------------------------------------------------------------------
print "\n=== Transactions after import ===\n";
for my $tx (sort { $a->{date} <=> $b->{date} } $ledger->getTransactions()) {
    next unless $tx->{date};
    printf "%s %s %s\n",
        strftime('%Y/%m/%d', localtime $tx->{date}),
        ($tx->{state} eq 'cleared' ? '*' : ($tx->{state} eq 'pending' ? '!' : ' ')),
        $tx->{payee};
    for my $p ($tx->getPostings()) {
        my $qty = defined($p->{quantity}) && length($p->{quantity})
                  ? sprintf('$%.2f', $p->{quantity}) : '';
        printf "    %-42s %8s%s\n",
            $p->{account}, $qty,
            ($p->{note} ? "  ; $p->{note}" : '');
    }
    if ($tx->{edit}) {
        printf "    [edit -> %s  pos=%s]\n", $tx->{edit}, $tx->{edit_pos}//'undef';
    }
    print "\n";
}

# -----------------------------------------------------------------------
# 4. Write changes back and show resulting file
# -----------------------------------------------------------------------
print "=== Writing changes ===\n";
$ledger->update();

print "\n=== Resulting ledger file ===\n";
open(my $fh, '<', $ledger_file) or die $!;
print while <$fh>;
close $fh;

# -----------------------------------------------------------------------
sub dump_transfer_store {
    my $ledger = shift;
    my $store = $ledger->{transfer};
    if ($store && %$store) {
        for my $key (sort keys %$store) {
            printf "  %-30s  %d entry\n", $key, scalar @{$store->{$key}};
            for my $entry (@{$store->{$key}}) {
                my ($tx, $post) = @$entry;
                printf "    txn: %-28s  posting: %-35s cost=%.2f\n",
                    $tx->{payee},
                    $post->{account},
                    $post->cost() // 0;
            }
        }
    } else {
        print "  (empty)\n";
    }
}
