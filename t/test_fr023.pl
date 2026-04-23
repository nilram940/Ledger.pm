#!/usr/bin/perl
# FR-023: OO file imports.
# Verifies new() + parse() on parser modules work independently of fromStmt/Ledger,
# and that importCallback() bridges the OO parsers to a Ledger object.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use POSIX qw(strftime);
use lib '..';
use Ledger;
use Ledger::OFX;
use Ledger::CSV::HSA;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg)              or die "copy base: $!";
copy('fr013.ofx',    "$dir/Checking-2026-02.ofx") or die "copy ofx: $!";
copy('fr016_hsa.csv', "$dir/HSA-2026-03.csv")     or die "copy csv: $!";

# --- Raw parse without Ledger object ---
print "=== Parsing OFX via Ledger::OFX->new->parse ===\n";
my @ofx_rows;
my $ofx = Ledger::OFX->new("$dir/Checking-2026-02.ofx");
$ofx->parse(sub { push @ofx_rows, shift; return (1, undef) });

print "=== Parsing HSA CSV via Ledger::CSV::HSA->new->parse ===\n";
my @hsa_rows;
my $hsa = Ledger::CSV::HSA->new("$dir/HSA-2026-03.csv");
$hsa->parse(sub { push @hsa_rows, shift });

# --- Full import using importCallback + OO parsers ---
print "=== Importing OFX via importCallback ===\n";
my $ledger = Ledger->new(file => $ldg);
$ledger->getinsertionpoints;
my $cb = $ledger->importCallback('Checking', {});
Ledger::OFX->new("$dir/Checking-2026-02.ofx")->parse($cb);

check(\@ofx_rows, \@hsa_rows, $ledger);

sub check {
    my ($ofx, $hsa, $ledger) = @_;

    my ($coffee)   = grep { ($_->{payee}//'') eq 'Coffee Shop'   } @$ofx;
    my ($hardware) = grep { ($_->{payee}//'') eq 'Hardware Store' } @$ofx;
    my ($ofx_bal)  = grep { ($_->{cost}//'') eq 'BAL' } @$ofx;

    my $coffee_qty   = $coffee   ? $coffee->{quantity}   : undef;
    my $hardware_qty = $hardware ? $hardware->{quantity} : undef;
    my $hardware_num = $hardware ? $hardware->{number}   : undef;
    my $coffee_date  = $coffee   ? strftime('%Y/%m/%d', localtime $coffee->{date}) : '(none)';
    my $ofx_bal_qty  = $ofx_bal  ? $ofx_bal->{quantity}  : undef;

    my ($pharmacy) = grep { ($_->{payee}//'') eq 'Pharmacy'      } @$hsa;
    my ($eye)      = grep { ($_->{payee}//'') eq 'Eye Doctor'    } @$hsa;
    my ($pending)  = grep { ($_->{payee}//'') eq 'Pending Claim' } @$hsa;
    my ($hsa_bal)  = grep { ($_->{cost}//'') eq 'BAL' } @$hsa;

    my $pharm_qty   = $pharmacy ? $pharmacy->{quantity} : undef;
    my $eye_qty     = $eye      ? $eye->{quantity}      : undef;
    my $pend_qty    = $pending  ? $pending->{quantity}  : undef;
    my $hsa_bal_qty = $hsa_bal  ? $hsa_bal->{quantity}  : undef;

    print "\n=== FR-023 OO IMPORTS RESULT ===\n";

    printf "OFX: Coffee Shop qty = -5.50:         %s  (want yes, got %s)\n",
        (defined $coffee_qty && $coffee_qty == -5.50) ? 'yes' : 'NO',
        $coffee_qty // 'undef';
    printf "OFX: Coffee Shop date = 2026/02/05:   %s  (want yes, got %s)\n",
        ($coffee_date eq '2026/02/05') ? 'yes' : 'NO', $coffee_date;
    printf "OFX: Hardware Store qty = -42.00:     %s  (want yes, got %s)\n",
        (defined $hardware_qty && $hardware_qty == -42.00) ? 'yes' : 'NO',
        $hardware_qty // 'undef';
    printf "OFX: Hardware check# = 1001:          %s  (want yes, got %s)\n",
        ($hardware_num && $hardware_num eq '1001') ? 'yes' : 'NO',
        $hardware_num // '(none)';
    printf "OFX: balance qty = 552.50:            %s  (want yes, got %s)\n",
        (defined $ofx_bal_qty && $ofx_bal_qty == 552.50) ? 'yes' : 'NO',
        $ofx_bal_qty // 'undef';

    printf "HSA: Pharmacy qty = -25.00:           %s  (want yes, got %s)\n",
        (defined $pharm_qty && $pharm_qty == -25.00) ? 'yes' : 'NO',
        $pharm_qty // 'undef';
    printf "HSA: Eye Doctor qty = -80.00:         %s  (want yes, got %s)\n",
        (defined $eye_qty && $eye_qty == -80.00) ? 'yes' : 'NO',
        $eye_qty // 'undef';
    printf "HSA: Pending Claim state = pending:   %s  (want yes, got %s)\n",
        ($pending && $pending->{state} eq 'pending') ? 'yes' : 'NO',
        $pending ? ($pending->{state} || 'uncleared') : '(none)';
    printf "HSA: Pending Claim qty = -50.00:      %s  (want yes, got %s)\n",
        (defined $pend_qty && $pend_qty == -50.00) ? 'yes' : 'NO',
        $pend_qty // 'undef';
    printf "HSA: balance qty = 395.00:            %s  (want yes, got %s)\n",
        (defined $hsa_bal_qty && $hsa_bal_qty == 395.00) ? 'yes' : 'NO',
        $hsa_bal_qty // 'undef';

    my @ldg_txns    = grep { $_->{date} } $ledger->getTransactions();
    my ($ldg_coffee) = grep { $_->{payee} eq 'Coffee Shop' } @ldg_txns;
    my $ldg_coffee_qty = $ldg_coffee ? $ldg_coffee->getPosting(0)->{quantity} : undef;

    printf "importCallback: Coffee Shop in ledger: %s  (want yes, got %s)\n",
        (defined $ldg_coffee_qty && $ldg_coffee_qty == -5.50) ? 'yes' : 'NO',
        $ldg_coffee_qty // 'undef';

    if (defined $coffee_qty   && $coffee_qty   == -5.50
        && $coffee_date eq '2026/02/05'
        && defined $hardware_qty && $hardware_qty == -42.00
        && $hardware_num && $hardware_num eq '1001'
        && defined $ofx_bal_qty  && $ofx_bal_qty  == 552.50
        && defined $pharm_qty    && $pharm_qty    == -25.00
        && defined $eye_qty      && $eye_qty      == -80.00
        && $pending && $pending->{state} eq 'pending'
        && defined $pend_qty     && $pend_qty     == -50.00
        && defined $hsa_bal_qty  && $hsa_bal_qty  == 395.00
        && defined $ldg_coffee_qty && $ldg_coffee_qty == -5.50) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
