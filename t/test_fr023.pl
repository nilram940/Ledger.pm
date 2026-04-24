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
use Ledger::CSV::Fidelity;
use Ledger::CSV::Coinbase;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg)              or die "copy base: $!";
copy('fr013.ofx',      "$dir/Checking-2026-02.ofx")  or die "copy ofx: $!";
copy('fr016_hsa.csv',  "$dir/HSA-2026-03.csv")      or die "copy csv: $!";
copy('fr015_fidelity.csv', "$dir/Fidelity-2026-03.csv") or die "copy fidelity: $!";

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

# --- Method tests: type(), account(), account_map() ---
print "\n=== Testing type(), account(), account_map() ===\n";

my $hsa_class_type = Ledger::CSV::HSA->type;
my $fid_class_type = Ledger::CSV::Fidelity->type;
my $cb_class_type  = Ledger::CSV::Coinbase->type;
my $hsa_inst_type  = $hsa->type;

$hsa->account('Assets:Test:HSA');
my $got_acct = $hsa->account;

my %fid_map = ('Individual - TOD (...1234)' => 'Assets:Investments:Fidelity');
my $fid = Ledger::CSV::Fidelity->new("$dir/Fidelity-2026-03.csv");
$fid->account_map(\%fid_map);
my $got_map_key = $fid->account_map->{'Individual - TOD (...1234)'};

# account() functional: CSV without #LedgerName: gets account from setter
my $no_ln = "$dir/NoLedgerName.csv";
open(my $nl_fh, '>', $no_ln) or die "open $no_ln: $!";
print $nl_fh "Transaction Date,Transaction Type,Claimant,Description,Plan,Date of Service,Amount,Status,Available Balance\n";
print $nl_fh "03/05/2026,Distribution,John,Test Pharmacy,Medical,03/01/2026,-10.00,Completed,90.00\n";
close $nl_fh;
my $hsa3 = Ledger::CSV::HSA->new($no_ln);
$hsa3->account('Assets:Test:HSA');
my @no_ln_rows;
$hsa3->parse(sub { my $r = shift; push @no_ln_rows, $r unless ($r->{cost}//'') eq 'BAL' });
my $no_ln_acct = $no_ln_rows[0] ? $no_ln_rows[0]{account} : undef;

# account_map() functional: Fidelity parse uses map set via setter
my @fid_rows;
$fid->parse(sub { push @fid_rows, shift });
my ($fid_buy) = grep { ($_->{payee}//'') =~ /FIDELITY 500/ && ($_->{quantity}//0) > 0 } @fid_rows;
my $fid_buy_acct = $fid_buy ? $fid_buy->{account} : undef;

check_methods($hsa_class_type, $fid_class_type, $cb_class_type, $hsa_inst_type,
              $got_acct, $got_map_key, $no_ln_acct, $fid_buy_acct);

check(\@ofx_rows, \@hsa_rows, $ledger);

sub check_methods {
    my ($hsa_class, $fid_class, $cb_class, $hsa_inst,
        $got_acct, $got_map_key, $no_ln_acct, $fid_buy_acct) = @_;

    print "\n=== FR-023 METHOD RESULT ===\n";

    printf "type() class HSA = 'HSA':              %s  (got %s)\n",
        ($hsa_class eq 'HSA')       ? 'yes' : 'NO', $hsa_class // 'undef';
    printf "type() class Fidelity = 'Fidelity':    %s  (got %s)\n",
        ($fid_class eq 'Fidelity')  ? 'yes' : 'NO', $fid_class // 'undef';
    printf "type() class Coinbase = 'Coinbase':    %s  (got %s)\n",
        ($cb_class  eq 'Coinbase')  ? 'yes' : 'NO', $cb_class  // 'undef';
    printf "type() instance HSA = 'HSA':           %s  (got %s)\n",
        ($hsa_inst  eq 'HSA')       ? 'yes' : 'NO', $hsa_inst  // 'undef';
    printf "account() getter = 'Assets:Test:HSA':  %s  (got %s)\n",
        ($got_acct eq 'Assets:Test:HSA') ? 'yes' : 'NO', $got_acct // 'undef';
    printf "account_map() getter key present:      %s  (got %s)\n",
        ($got_map_key && $got_map_key eq 'Assets:Investments:Fidelity') ? 'yes' : 'NO',
        $got_map_key // 'undef';
    printf "account() fallback in parse:           %s  (got %s)\n",
        ($no_ln_acct && $no_ln_acct eq 'Assets:Test:HSA') ? 'yes' : 'NO',
        $no_ln_acct // 'undef';
    printf "account_map() setter used in parse:    %s  (got %s)\n",
        ($fid_buy_acct && $fid_buy_acct eq 'Assets:Investments:Fidelity:FXAIX') ? 'yes' : 'NO',
        $fid_buy_acct // 'undef';

    if ($hsa_class eq 'HSA' && $fid_class eq 'Fidelity' && $cb_class eq 'Coinbase'
        && $hsa_inst eq 'HSA'
        && $got_acct eq 'Assets:Test:HSA'
        && $got_map_key && $got_map_key eq 'Assets:Investments:Fidelity'
        && $no_ln_acct && $no_ln_acct eq 'Assets:Test:HSA'
        && $fid_buy_acct && $fid_buy_acct eq 'Assets:Investments:Fidelity:FXAIX') {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}

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
    my $pharm_qty    = $pharmacy ? $pharmacy->{quantity} : undef;
    my $pharm_assert = $pharmacy ? $pharmacy->{assert}   : undef;
    my $eye_qty      = $eye      ? $eye->{quantity}      : undef;
    my $eye_assert   = $eye      ? $eye->{assert}        : undef;
    my $pend_qty     = $pending  ? $pending->{quantity}  : undef;

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
    printf "HSA: Pharmacy assert = 475.00:        %s  (want yes, got %s)\n",
        (defined $pharm_assert && $pharm_assert == 475.00) ? 'yes' : 'NO',
        $pharm_assert // 'undef';
    printf "HSA: Eye Doctor qty = -80.00:         %s  (want yes, got %s)\n",
        (defined $eye_qty && $eye_qty == -80.00) ? 'yes' : 'NO',
        $eye_qty // 'undef';
    printf "HSA: Eye Doctor assert = 395.00:      %s  (want yes, got %s)\n",
        (defined $eye_assert && $eye_assert == 395.00) ? 'yes' : 'NO',
        $eye_assert // 'undef';
    printf "HSA: Pending Claim state = pending:   %s  (want yes, got %s)\n",
        ($pending && $pending->{state} eq 'pending') ? 'yes' : 'NO',
        $pending ? ($pending->{state} || 'uncleared') : '(none)';
    printf "HSA: Pending Claim qty = -50.00:      %s  (want yes, got %s)\n",
        (defined $pend_qty && $pend_qty == -50.00) ? 'yes' : 'NO',
        $pend_qty // 'undef';

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
        && defined $pharm_assert && $pharm_assert == 475.00
        && defined $eye_qty      && $eye_qty      == -80.00
        && defined $eye_assert   && $eye_assert   == 395.00
        && $pending && $pending->{state} eq 'pending'
        && defined $pend_qty     && $pend_qty     == -50.00
        && defined $ldg_coffee_qty && $ldg_coffee_qty == -5.50) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
