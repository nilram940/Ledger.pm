#!/usr/bin/perl
# Inline balance assertion for investment (non-dollar commodity) postings.
#
# Uses bug017 fixtures: 401k OFX with AAPL and AMZN buys in PRETAX and MATCH
# sub-accounts, each with a corresponding INVPOS balance entry.
#
# After update(), the last buy posting for each account/commodity must carry
# an inline "= N TICKER" balance assertion instead of (or in addition to) the
# standalone [Account] = N TICKER transaction.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

print "=" x 60, "\n";
print "Inline balance assertion on investment postings\n";
print "=" x 60, "\n\n";

my $ldg = "$dir/inv.ldg";
copy('fr013_base.ldg',       $ldg)                         or die "copy: $!";
copy('fr013_ofx_401k.ofx',   "$dir/401k-2026-02.ofx")      or die "copy: $!";

my $ledger = Ledger->new(file => $ldg);
$ledger->fromStmt("$dir/401k-2026-02.ofx", {}, {});
$ledger->update();

print "--- Resulting file ---\n";
print "-" x 40, "\n";
open(my $fh, '<', $ldg) or die $!;
my $content = do { local $/; <$fh> };
close $fh;
print $content;
print "-" x 40, "\n\n";

check($content);

sub check {
    my $content = shift;

    # Inline assertions expected on each buy posting, using the INVPOS balance quantity:
    #   Investments:401k:PRETAX:AAPL  5 AAPL @@ $900.00 = 5 AAPL  (INVPOS PRETAX:AAPL = 5)
    #   Investments:401k:MATCH:AMZN  10 AMZN @@ $1900.00 = 2 AMZN  (INVPOS MATCH:AMZN = 2)
    # MATCH:AAPL and PRETAX:AMZN have no buy transaction; they appear only as standalone BAL.

    my $aapl_pretax_inline = $content =~ /5 AAPL \@\@ \$900\.00 = 5 AAPL/;
    my $amzn_match_inline  = $content =~ /10 AMZN \@\@ \$1900\.00 = 2 AMZN/;

    print "--- RESULT ---\n";
    printf "AAPL PRETAX buy has inline '= 5 AAPL':   %s  (want yes)\n",
        $aapl_pretax_inline ? 'yes' : 'NO';
    printf "AMZN MATCH  buy has inline '= 2 AMZN':   %s  (want yes)\n",
        $amzn_match_inline  ? 'yes' : 'NO';

    if ($aapl_pretax_inline && $amzn_match_inline) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
