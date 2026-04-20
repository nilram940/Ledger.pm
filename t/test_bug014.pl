#!/usr/bin/perl
# BUG-014 regression: date comment must not be written when only balance entries
# are added and @append is empty.
#
# The "; Mon Apr..." separator comment in update_file was written unconditionally
# in the elsif($ofx) block and the EOF block, even when @append was empty and
# only @balance_entries were being written.  This pollutes the file with a
# spurious comment between the cleared and pending sections.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "BUG-014: date comment written even when \@append is empty\n";
print "=" x 60, "\n\n";

my $ldg = "$dir/bug014.ldg";
copy('bug014.ldg', $ldg)                        or die "copy: $!";
copy('bug014.csv', "$dir/Checking-2026-01.csv") or die "copy: $!";

my $ledger = Ledger->new(file => $ldg);

my $handlers = {
    'Assets:Checking' => { '' => sub { return shift } },
};
my $csv = {
    Checking => { fields => [qw(date id payee quantity account)], csv_args => {} },
};

printf "ofxfile: %s\nofxpos:  %d\n\n",
    $ledger->{ofxfile} // '(none)', $ledger->{ofxpos} // -1;

$ledger->fromStmt("$dir/Checking-2026-01.csv", $handlers, $csv);

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

    # Balance assertion must still appear (regression: BUG-011).
    my $bal_pos     = index($content, '= $-5.00');

    # Pending transaction must still appear.
    my $pending_pos = index($content, 'Pending Purchase');

    # No "; Mon Apr..." date comment line should appear anywhere.
    my ($date_comment) = ($content =~ /^(; [A-Z][a-z]{2} [A-Z][a-z]{2}.*)/m);

    # Balance assertion must come before the pending transaction.
    my $order_ok = ($bal_pos >= 0 && $pending_pos >= 0 && $bal_pos < $pending_pos);

    print "\n--- BUG-014 RESULT ---\n";
    printf "Balance assertion present (want yes):       %s\n",
        $bal_pos >= 0   ? 'yes' : 'NO';
    printf "Pending transaction present (want yes):     %s\n",
        $pending_pos >= 0 ? 'yes' : 'NO';
    printf "Balance before pending (want yes):          %s\n",
        $order_ok       ? 'yes' : 'NO';
    printf "Date comment absent (want yes):             %s\n",
        defined($date_comment) ? "NO  (found: $date_comment)" : 'yes';

    if ($bal_pos >= 0 && $pending_pos >= 0 && $order_ok && !defined($date_comment)) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
