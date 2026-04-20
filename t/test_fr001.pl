#!/usr/bin/perl
# FR-001: scheduleEdit() and scheduleAppend() on Ledger::Transaction.
#
# Tests the two new API methods that replace direct field manipulation:
#
#   $tx->scheduleEdit($file?)   — in-place overwrite at current position;
#                                  calls findtext if bpos not yet set.
#   $tx->scheduleAppend($file)  — append at ofxpos (edit_pos = -1).
#
# Covers:
#   1. scheduleAppend sets edit / edit_pos=-1 and leaves edit_end unset.
#   2. scheduleEdit with bpos pre-set uses it without calling findtext.
#   3. scheduleEdit with an explicit $file arg overrides self->{file}.
#   4. scheduleEdit without bpos calls findtext to locate the transaction.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use lib '..';
use Ledger::Transaction;
use Ledger;

my ($pass, $fail) = (0, 0);

sub ok {
    my ($cond, $label) = @_;
    if ($cond) { print "PASS: $label\n"; $pass++ }
    else        { print "FAIL: $label\n"; $fail++ }
}

# -----------------------------------------------------------------------
# 1. scheduleAppend
# -----------------------------------------------------------------------
print "=== 1. scheduleAppend ===\n";
{
    my $tx = Ledger::Transaction->new(time, 'cleared', '', 'Coffee');
    $tx->addPosting('Assets:Checking', -5);

    $tx->scheduleAppend('/ledger/main.ldg');

    ok($tx->{edit}    eq '/ledger/main.ldg', 'scheduleAppend: edit set to given file');
    ok($tx->{edit_pos} == -1,                 'scheduleAppend: edit_pos=-1');
    ok(!defined $tx->{edit_end},              'scheduleAppend: edit_end left unset');
}

# -----------------------------------------------------------------------
# 2. scheduleEdit with bpos already set — no findtext call
# -----------------------------------------------------------------------
print "\n=== 2. scheduleEdit with bpos pre-set ===\n";
{
    my $tx = Ledger::Transaction->new(time, 'cleared', '', 'Groceries');
    $tx->addPosting('Assets:Checking', -75);
    $tx->{file} = '/ledger/main.ldg';
    $tx->{bpos} = 1024;
    $tx->{epos} = 1150;

    $tx->scheduleEdit();

    ok($tx->{edit}     eq '/ledger/main.ldg', 'scheduleEdit: edit set to self->{file}');
    ok($tx->{edit_pos} == 1024,                'scheduleEdit: edit_pos=bpos');
    ok($tx->{edit_end} == 1150,                'scheduleEdit: edit_end=epos');
}

# -----------------------------------------------------------------------
# 3. scheduleEdit with explicit $file arg
# -----------------------------------------------------------------------
print "\n=== 3. scheduleEdit with explicit file ===\n";
{
    my $tx = Ledger::Transaction->new(time, 'cleared', '', 'Rent');
    $tx->addPosting('Assets:Checking', -1000);
    $tx->{file} = '/original.ldg';
    $tx->{bpos} = 500;
    $tx->{epos} = 620;

    $tx->scheduleEdit('/override.ldg');

    ok($tx->{edit}     eq '/override.ldg', 'scheduleEdit: explicit file overrides self->{file}');
    ok($tx->{edit_pos} == 500,              'scheduleEdit: edit_pos still from bpos');
    ok($tx->{edit_end} == 620,              'scheduleEdit: edit_end still from epos');
}

# -----------------------------------------------------------------------
# 4. scheduleEdit without bpos — calls findtext
#
# Load transfer.ldg via Ledger->new so we get real posting bpos values
# from ledger csv.  Transaction-level bpos is unset until findtext runs.
# -----------------------------------------------------------------------
print "\n=== 4. scheduleEdit without bpos (findtext path) ===\n";
{
    my $dir = tempdir(CLEANUP => 1);
    my $ldg = "$dir/transfer.ldg";
    copy('transfer.ldg', $ldg) or die "copy: $!";

    my $ledger = Ledger->new(file => $ldg);

    # Grab any dated transaction — they all have posting bpos from ledger csv
    # but no transaction-level bpos yet.
    my ($tx) = grep { $_->{date} && $_->{file} }
                    $ledger->getTransactions();
    die "no suitable transaction found in transfer.ldg\n" unless $tx;

    ok(!defined($tx->{bpos}), '4a: bpos is unset before scheduleEdit');

    $tx->scheduleEdit();

    ok(defined($tx->{bpos}) && $tx->{bpos} > 0,
        '4b: scheduleEdit called findtext and populated bpos');
    ok($tx->{edit} eq $ldg,
        '4c: scheduleEdit set edit to self->{file}');
    ok($tx->{edit_pos} == $tx->{bpos},
        '4d: edit_pos equals bpos after findtext');
    ok(defined($tx->{edit_end}) && $tx->{edit_end} > $tx->{bpos},
        '4e: edit_end is set and greater than bpos');
}

# -----------------------------------------------------------------------
print "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
