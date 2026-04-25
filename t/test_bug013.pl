#!/usr/bin/perl
# BUG-013 / BUG-005: orphaned pending transactions after Plaid snapshot update.
#
# When a Plaid JSON import provides a complete snapshot of pending transactions,
# any existing pending transaction not in the snapshot is "orphaned".
#
# Scenario A (pending 1 "Pre-Auth Hold"):
#   - Disappeared from snapshot; cleared "Grocery Store" imported with same
#     account/amount/date — absence scan should delete the pending and annotate
#     the cleared transaction.
#
# Scenario B (pending 2 "Hotel Hold"):
#   - Disappeared from snapshot with no matching cleared transaction in this run
#     — absence scan should warn on stderr but leave the pending in place.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('bug013.ldg', $ldg) or die "copy ldg: $!";
copy('bug013.json', "$dir/bug013.json") or die "copy json: $!";

my $ledger = Ledger->new(file => $ldg);

# Capture stderr so we can assert on warning/info messages.
my $stderr_file = "$dir/stderr.txt";
open(my $old_stderr, '>&', \*STDERR) or die "Can't dup STDERR: $!";
open(STDERR, '>', $stderr_file)       or die "Can't redirect STDERR: $!";

$ledger->fromStmt("$dir/bug013.json", {});

open(STDERR, '>&', $old_stderr) or die "Can't restore STDERR: $!";
open(my $sf, '<', $stderr_file) or die "Can't read stderr: $!";
my $stderr_output = do { local $/; <$sf> };
close $sf;
print "=== Captured stderr ===\n$stderr_output\n";

print "=== Writing changes ===\n";
$ledger->update();

open(my $fh, '<', $ldg) or die $!;
my $content = do { local $/; <$fh> };
close $fh;

print "\n=== Resulting ledger file ===\n";
print "-" x 40, "\n";
print $content;
print "-" x 40, "\n";

check($ledger, $content, $stderr_output);

sub check {
    my ($ledger, $content, $stderr) = @_;

    # A1: Pending 1 ("Pre-Auth Hold") should no longer be a pending transaction
    # (it may still appear in the cleared transaction's note)
    my $pending1_gone = ($content !~ /! Pre-Auth Hold/);

    # A2: Cleared "Grocery Store" should appear with the absorbed-pending note
    my $cleared_present   = ($content =~ /Grocery Store/);
    my $note_present      = ($content =~ /absorbed orphaned pending/i);

    # A3: INFO message on stderr for the match case
    my $info_logged = ($stderr =~ /INFO.*Pre-Auth Hold.*Grocery Store/i
                    || $stderr =~ /INFO.*absorbed.*Pre-Auth Hold/i);

    # B1: Pending 2 ("Hotel Hold") should still be present
    my $pending2_present = ($content =~ /Hotel Hold/);

    # B2: WARNING message on stderr for the no-match case
    my $warn_logged = ($stderr =~ /WARNING.*Hotel Hold/i);

    print "\n=== BUG-013 RESULT ===\n";
    printf "A1 pending 1 deleted from file:         %s  (want yes)\n",
        $pending1_gone   ? 'yes' : 'NO';
    printf "A2 cleared Grocery Store present:       %s  (want yes)\n",
        $cleared_present ? 'yes' : 'NO';
    printf "A2 absorbed-pending note on cleared:    %s  (want yes)\n",
        $note_present    ? 'yes' : 'NO';
    printf "A3 INFO logged for match case:          %s  (want yes)\n",
        $info_logged     ? 'yes' : 'NO';
    printf "B1 pending 2 still in file:             %s  (want yes)\n",
        $pending2_present ? 'yes' : 'NO';
    printf "B2 WARNING logged for no-match case:    %s  (want yes)\n",
        $warn_logged     ? 'yes' : 'NO';

    if ($pending1_gone && $cleared_present && $note_present
        && $info_logged && $pending2_present && $warn_logged) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
