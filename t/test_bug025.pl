#!/usr/bin/perl
# BUG-025: Ledger::CSV::Fidelity fails to parse real Fidelity exports.
# Real exports have blank preamble lines before the column header and
# "Cash" in the Type column for non-retirement rows.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;
use Ledger::CSV::Fidelity;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg) or die "copy base: $!";
copy('bug025_fidelity.csv', "$dir/Fidelity-2026-03.csv") or die "copy csv: $!";

my $ledger = Ledger->new(file => $ldg);

my %account_map = (
    'Individual - TOD (...1234)' => 'Assets:Investments:Fidelity',
    '401K (...5678)'             => 'Assets:Investments:Fidelity401k',
);

my $csv_config = {
    Fidelity => Ledger::CSV::Fidelity->config(account_map => \%account_map),
};

print "=== Importing Fidelity-2026-03.csv (preamble + Cash Type) ===\n";
$ledger->fromStmt("$dir/Fidelity-2026-03.csv", {}, $csv_config);

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

    my ($buy)  = grep { $_->{payee} =~ /You Bought/i } @txns;
    my ($div)  = grep { $_->{payee} =~ /Dividend/i
                        && ($_->getPosting(0)->{commodity}//'') eq '$' } @txns;
    my ($cont) = grep { $_->getPosting(0)->{account} =~ /Fidelity401k/ } @txns;

    my $imported = grep { $_->getPosting(0)->{account} =~ /Fidelity/ } @txns;

    my $buy_acct  = $buy  ? $buy->getPosting(0)->{account}  : '(none)';
    my $div_acct  = $div  ? $div->getPosting(0)->{account}  : '(none)';
    my $cont_acct = $cont ? $cont->getPosting(0)->{account} : '(none)';

    my $buy_qty   = $buy  ? $buy->getPosting(0)->{quantity}  : undef;
    my $buy_cost  = $buy  ? $buy->getPosting(0)->{cost}      : undef;
    my $div_qty   = $div  ? $div->getPosting(0)->{quantity}  : undef;
    my $cont_qty  = $cont ? $cont->getPosting(0)->{quantity} : undef;
    my $cont_cost = $cont ? $cont->getPosting(0)->{cost}     : undef;

    print "\n=== BUG-025 RESULT ===\n";

    printf "Imported count = 3:                  %s  (want yes, got %d)\n",
        ($imported == 3) ? 'yes' : 'NO', $imported;

    printf "Buy found:                           %s  (want yes)\n",
        $buy ? 'yes' : 'NO';
    printf "Buy account (no :Cash suffix):       %s\n  (want: Assets:Investments:Fidelity:FXAIX\n   got:  %s)\n",
        ($buy_acct eq 'Assets:Investments:Fidelity:FXAIX') ? 'yes' : 'NO', $buy_acct;
    printf "Buy qty = 2.0:                       %s  (want yes, got %s)\n",
        (defined $buy_qty && abs($buy_qty - 2.0) < 0.001) ? 'yes' : 'NO',
        $buy_qty // 'undef';
    printf "Buy cost = 250.00:                   %s  (want yes, got %s)\n",
        (defined $buy_cost && abs($buy_cost - 250.00) < 0.01) ? 'yes' : 'NO',
        $buy_cost // 'undef';

    printf "Dividend found:                      %s  (want yes)\n",
        $div ? 'yes' : 'NO';
    printf "Dividend account (no :Cash suffix):  %s\n  (want: Assets:Investments:Fidelity\n   got:  %s)\n",
        ($div_acct eq 'Assets:Investments:Fidelity') ? 'yes' : 'NO', $div_acct;
    printf "Dividend qty = 15.00:                %s  (want yes, got %s)\n",
        (defined $div_qty && abs($div_qty - 15.00) < 0.01) ? 'yes' : 'NO',
        $div_qty // 'undef';

    printf "Contribution found:                  %s  (want yes)\n",
        $cont ? 'yes' : 'NO';
    printf "Contribution account (PRETAX kept):  %s\n  (want: Assets:Investments:Fidelity401k:FXAIX:PRETAX\n   got:  %s)\n",
        ($cont_acct eq 'Assets:Investments:Fidelity401k:FXAIX:PRETAX') ? 'yes' : 'NO', $cont_acct;
    printf "Contribution qty = 1.0:              %s  (want yes, got %s)\n",
        (defined $cont_qty && abs($cont_qty - 1.0) < 0.001) ? 'yes' : 'NO',
        $cont_qty // 'undef';
    printf "Contribution cost = 125.00:          %s  (want yes, got %s)\n",
        (defined $cont_cost && abs($cont_cost - 125.00) < 0.01) ? 'yes' : 'NO',
        $cont_cost // 'undef';

    if ($imported == 3
        && $buy  && $buy_acct  eq 'Assets:Investments:Fidelity:FXAIX'
                 && abs($buy_qty  - 2.0)    < 0.001
                 && abs($buy_cost - 250.0)  < 0.01
        && $div  && $div_acct  eq 'Assets:Investments:Fidelity'
                 && abs($div_qty  - 15.0)   < 0.01
        && $cont && $cont_acct eq 'Assets:Investments:Fidelity401k:FXAIX:PRETAX'
                 && abs($cont_qty  - 1.0)   < 0.001
                 && abs($cont_cost - 125.0) < 0.01) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
