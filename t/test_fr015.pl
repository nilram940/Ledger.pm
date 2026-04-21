#!/usr/bin/perl
# FR-015: Fidelity brokerage CSV import.
# Verifies multi-account dispatch via account_map closure, action-based
# share/cash routing, symbol suffix on account, and contrib_type suffix for 401k.

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
copy('fr015_fidelity.csv', "$dir/Fidelity-2026-03.csv") or die "copy csv: $!";

my $ledger = Ledger->new(file => $ldg);

my $buy_re  = qr/bought|buy|contribution|reinvestment/i;
my $sell_re = qr/sold|sell|redemption/i;

my %account_map = (
    'Z12345678' => 'Assets:Investments:Fidelity',
    'Z87654321' => 'Assets:Investments:Fidelity401k',
);

my $csv_config = {
    Fidelity => {
        header_map => {
            date           => 'Run Date',
            account_number => 'Account Number',
            action         => 'Action',
            symbol         => 'Symbol',
            payee          => 'Description',
            contrib_type   => 'Type',
            price_col      => 'Price ($)',
            shares         => 'Quantity',
            quantity       => 'Amount ($)',
        },
        process => sub {
            my $csv = shift;
            my $action = $csv->{action}       // '';
            my $symbol = $csv->{symbol}       // '';
            my $type   = $csv->{contrib_type} // '';
            my $base   = $account_map{$csv->{account_number}} // $csv->{account_number};

            if ($action =~ $buy_re || $action =~ $sell_re) {
                my $amt = $csv->{quantity} + 0;
                $amt = $csv->{price_col} * abs($csv->{shares})
                    if !$amt && $csv->{price_col};
                $csv->{cost}     = abs($amt);
                $csv->{quantity} = $csv->{shares} + 0;
                $csv->{quantity} = -$csv->{quantity} if $action =~ $sell_re;
                $csv->{commodity} = $symbol;
                $base .= ":$symbol" if $symbol =~ /\S/;
            }

            $base .= ":$type" if $type =~ /\S/;
            $csv->{account} = $base;
            $csv->{state}   = 'cleared';
        },
    },
};

print "=== Importing Fidelity-2026-03.csv ===\n";
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

    my ($buy)  = grep { $_->{payee} =~ /FIDELITY 500/i
                        && $_->getPosting(0)->{quantity} > 0 } @txns;
    my ($div)  = grep { $_->{payee} =~ /FIDELITY 500/i
                        && ($_->getPosting(0)->{commodity}//'') eq '$' } @txns;
    my ($cont) = grep { $_->getPosting(0)->{account} =~ /Fidelity401k/ } @txns;

    my $buy_acct  = $buy  ? $buy->getPosting(0)->{account}   : '(none)';
    my $buy_qty   = $buy  ? $buy->getPosting(0)->{quantity}   : undef;
    my $buy_cost  = $buy  ? $buy->getPosting(0)->{cost}       : undef;
    my $buy_comm  = $buy  ? $buy->getPosting(0)->{commodity}  : '(none)';

    my $div_acct  = $div  ? $div->getPosting(0)->{account}   : '(none)';
    my $div_qty   = $div  ? $div->getPosting(0)->{quantity}   : undef;

    my $cont_acct = $cont ? $cont->getPosting(0)->{account}  : '(none)';
    my $cont_qty  = $cont ? $cont->getPosting(0)->{quantity}  : undef;
    my $cont_cost = $cont ? $cont->getPosting(0)->{cost}      : undef;

    print "\n=== FR-015 Fidelity RESULT ===\n";

    printf "Buy found:                           %s  (want yes)\n",
        $buy ? 'yes' : 'NO';
    printf "Buy account = ...Fidelity:FXAIX:     %s\n  (want: Assets:Investments:Fidelity:FXAIX\n   got:  %s)\n",
        ($buy_acct eq 'Assets:Investments:Fidelity:FXAIX') ? 'yes' : 'NO', $buy_acct;
    printf "Buy qty = 2.0:                       %s  (want yes, got %s)\n",
        (defined $buy_qty && abs($buy_qty - 2.0) < 0.001) ? 'yes' : 'NO',
        $buy_qty // 'undef';
    printf "Buy cost = 250.00:                   %s  (want yes, got %s)\n",
        (defined $buy_cost && abs($buy_cost - 250.00) < 0.01) ? 'yes' : 'NO',
        $buy_cost // 'undef';
    printf "Buy commodity = FXAIX:               %s  (want yes, got %s)\n",
        ($buy_comm eq 'FXAIX') ? 'yes' : 'NO', $buy_comm;

    printf "Dividend found:                      %s  (want yes)\n",
        $div ? 'yes' : 'NO';
    printf "Dividend account = Fidelity (no sym):%s\n  (want: Assets:Investments:Fidelity\n   got:  %s)\n",
        ($div_acct eq 'Assets:Investments:Fidelity') ? 'yes' : 'NO', $div_acct;
    printf "Dividend qty = 15.00:                %s  (want yes, got %s)\n",
        (defined $div_qty && abs($div_qty - 15.00) < 0.01) ? 'yes' : 'NO',
        $div_qty // 'undef';

    printf "Contribution found:                  %s  (want yes)\n",
        $cont ? 'yes' : 'NO';
    printf "Contribution account = ...401k:FXAIX:PRETAX: %s\n  (want: Assets:Investments:Fidelity401k:FXAIX:PRETAX\n   got:  %s)\n",
        ($cont_acct eq 'Assets:Investments:Fidelity401k:FXAIX:PRETAX') ? 'yes' : 'NO',
        $cont_acct;
    printf "Contribution qty = 1.0:              %s  (want yes, got %s)\n",
        (defined $cont_qty && abs($cont_qty - 1.0) < 0.001) ? 'yes' : 'NO',
        $cont_qty // 'undef';
    printf "Contribution cost = 125.00:          %s  (want yes, got %s)\n",
        (defined $cont_cost && abs($cont_cost - 125.00) < 0.01) ? 'yes' : 'NO',
        $cont_cost // 'undef';

    if ($buy  && $buy_acct  eq 'Assets:Investments:Fidelity:FXAIX'
             && abs($buy_qty  - 2.0)   < 0.001
             && abs($buy_cost - 250.0) < 0.01
             && $buy_comm eq 'FXAIX'
        && $div  && $div_acct  eq 'Assets:Investments:Fidelity'
             && abs($div_qty  - 15.0)  < 0.01
        && $cont && $cont_acct eq 'Assets:Investments:Fidelity401k:FXAIX:PRETAX'
             && abs($cont_qty  - 1.0)  < 0.001
             && abs($cont_cost - 125.0) < 0.01) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
