#!/usr/bin/perl
# FR-019: CSV auto-detection via header fingerprinting.
# Verifies that fromStmt dispatches correctly when the filename prefix has no
# matching config key, by peeking the CSV header and calling CSV::detect().

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
# Deliberately unrecognised filename prefix: "export" != "HSA"
copy('fr016_hsa.csv', "$dir/export-2026-03.csv") or die "copy csv: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing export-2026-03.csv (empty csv config) ===\n";
$ledger->fromStmt("$dir/export-2026-03.csv", {}, {});

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

    my @txns = grep { $_->{date} } $ledger->getTransactions();

    my ($pharmacy) = grep { $_->{payee} eq 'Pharmacy'      } @txns;
    my ($eye)      = grep { $_->{payee} eq 'Eye Doctor'    } @txns;
    my ($pending)  = grep { $_->{payee} eq 'Pending Claim' } @txns;

    my $pharm_qty  = $pharmacy ? ($pharmacy->getPosting(0)->{quantity} // 0) : undef;
    my $pharm_date = $pharmacy ? strftime('%Y/%m/%d', localtime $pharmacy->{date}) : '(none)';
    my $eye_qty    = $eye      ? ($eye->getPosting(0)->{quantity} // 0) : undef;
    my $pend_qty   = $pending  ? ($pending->getPosting(0)->{quantity} // 0) : undef;
    my $bal_395    = ($content =~ /= \$395\.00/);
    my $bal_345    = ($content =~ /= \$345\.00/);

    print "\n=== FR-019 RESULT ===\n";

    printf "Pharmacy found:                      %s  (want yes)\n",
        $pharmacy ? 'yes' : 'NO';
    printf "Pharmacy qty = -25.00:               %s  (want yes, got %s)\n",
        (defined $pharm_qty && $pharm_qty == -25.00) ? 'yes' : 'NO',
        $pharm_qty // 'undef';
    printf "Pharmacy date = 2026/03/05:          %s  (want yes, got %s)\n",
        ($pharm_date eq '2026/03/05') ? 'yes' : 'NO', $pharm_date;
    printf "Pharmacy state = cleared:            %s  (want yes, got %s)\n",
        ($pharmacy && $pharmacy->{state} eq 'cleared') ? 'yes' : 'NO',
        $pharmacy ? ($pharmacy->{state} || 'uncleared') : '(none)';
    printf "Eye Doctor found:                    %s  (want yes)\n",
        $eye ? 'yes' : 'NO';
    printf "Eye Doctor qty = -80.00:             %s  (want yes, got %s)\n",
        (defined $eye_qty && $eye_qty == -80.00) ? 'yes' : 'NO',
        $eye_qty // 'undef';
    printf "Pending Claim found:                 %s  (want yes)\n",
        $pending ? 'yes' : 'NO';
    printf "Pending Claim state = pending:       %s  (want yes, got %s)\n",
        ($pending && $pending->{state} eq 'pending') ? 'yes' : 'NO',
        $pending ? ($pending->{state} || 'uncleared') : '(none)';
    printf "Pending Claim qty = -50.00:          %s  (want yes, got %s)\n",
        (defined $pend_qty && $pend_qty == -50.00) ? 'yes' : 'NO',
        $pend_qty // 'undef';
    printf "Balance \$395.00 (last cleared):      %s  (want yes)\n",
        $bal_395 ? 'yes' : 'NO';
    printf "Balance \$345.00 (pending) absent:    %s  (want yes)\n",
        $bal_345 ? 'NO' : 'yes';

    if ($pharmacy && $pharm_qty == -25.00 && $pharm_date eq '2026/03/05'
        && $pharmacy->{state} eq 'cleared'
        && $eye && $eye_qty == -80.00
        && $pending && $pending->{state} eq 'pending' && $pend_qty == -50.00
        && $bal_395 && !$bal_345) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
