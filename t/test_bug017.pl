#!/usr/bin/perl
# BUG-017: investment OFX with multiple commodities and mixed PRETAX/MATCH sources
# produces only one balance assertion per commodity instead of one per commodity+source.
# E.g. AAPL in both PRETAX and MATCH should yield two separate balance assertions.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger;

my $dir = tempdir(CLEANUP => 0);
print "Working dir: $dir\n\n";

my $ldg = "$dir/test.ldg";
copy('fr013_base.ldg', $ldg) or die "copy base: $!";
copy('fr013_ofx_401k.ofx', "$dir/401k-2026-02.ofx") or die "copy ofx: $!";

my $ledger = Ledger->new(file => $ldg);

print "=== Importing 401k-2026-02.ofx (AAPL+AMZN in PRETAX and MATCH) ===\n";
$ledger->fromStmt("$dir/401k-2026-02.ofx", {}, {});

print "\n=== Writing changes ===\n";
$ledger->update();

open(my $fh, '<', $ldg) or die $!;
my $content = do { local $/; <$fh> };
close $fh;

print "\n=== Resulting ledger file ===\n";
print "-" x 40, "\n";
print $content;
print "-" x 40, "\n";

check($content);

sub check {
    my ($content) = @_;

    # Expect four separate balance assertions: AAPL×PRETAX, AAPL×MATCH, AMZN×PRETAX, AMZN×MATCH
    my $aapl_pretax = ($content =~ /\[Investments:401k:PRETAX:AAPL\]/);
    my $aapl_match  = ($content =~ /\[Investments:401k:MATCH:AAPL\]/);
    my $amzn_pretax = ($content =~ /\[Investments:401k:PRETAX:AMZN\]/);
    my $amzn_match  = ($content =~ /\[Investments:401k:MATCH:AMZN\]/);

    print "\n=== BUG-017 401k multi-source balance assertions RESULT ===\n";
    printf "PRETAX:AAPL balance assertion present: %s  (want yes)\n", $aapl_pretax ? 'yes' : 'NO';
    printf "MATCH:AAPL  balance assertion present: %s  (want yes)\n", $aapl_match  ? 'yes' : 'NO';
    printf "PRETAX:AMZN balance assertion present: %s  (want yes)\n", $amzn_pretax ? 'yes' : 'NO';
    printf "MATCH:AMZN  balance assertion present: %s  (want yes)\n", $amzn_match  ? 'yes' : 'NO';

    if ($aapl_pretax && $aapl_match && $amzn_pretax && $amzn_match) {
        print "PASS\n";
    } else {
        print "FAIL\n";
        exit 1;
    }
}
