#!/usr/bin/perl
# FR-014: state-aware insertion points (cleared/pending/uncleared).
#
# Two scenarios:
#   A) Single-file: one file holds cleared, pending, and uncleared transactions.
#      Cleared imports must land before existing pending; pending imports before
#      existing uncleared.
#   B) Multi-file: three !include sub-files, one per state.
#      Each import must land in the correct sub-file and leave the others
#      unchanged.

use strict;
use warnings;
use File::Temp  qw(tempdir);
use File::Copy  qw(copy);
use POSIX       qw(strftime);
use lib '..';
use Ledger;

my $pass = 0;
my $fail = 0;

sub ok {
    my ($cond, $label) = @_;
    if ($cond) { print "PASS: $label\n"; $pass++ }
    else        { print "FAIL: $label\n"; $fail++ }
}

sub slurp { open my $fh, '<', $_[0] or die $_[0].": $!"; local $/; <$fh> }

# CSV config: fields include a 'state' column so we can import pending txns.
# addStmtTran uses ($stmttrn->{state} || "cleared"), so an empty state column
# defaults to cleared; the value 'pending' is used verbatim.
my $csv_config = {
    Checking => {
        fields   => [qw(date id payee quantity account state)],
        csv_args => {},
    },
};
my $handlers = { 'Assets:Checking' => { '' => sub { return shift } } };

# -------------------------------------------------------------------------
# SCENARIO A: single-file
# -------------------------------------------------------------------------
print "\n", "=" x 60, "\n";
print "FR-014 A: single-file insertion order\n";
print "=" x 60, "\n\n";

{
    my $dir = tempdir(CLEANUP => 1);
    my $ldg = "$dir/fr014_single.ldg";
    copy('fr014_single.ldg', $ldg) or die "copy: $!";

    # Write import CSV: one cleared, one pending import
    my $stmt = "$dir/Checking-2026-02.csv";
    open my $fh, '>', $stmt or die $!;
    print $fh "2026/02/01,SF-NEW1,New Cleared,-40.00,Assets:Checking,\n";
    print $fh "2026/02/02,SF-NEW2,New Pending,-50.00,Assets:Checking,pending\n";
    close $fh;

    my $ledger = Ledger->new(file => $ldg);
    $ledger->fromStmt($stmt, $handlers, $csv_config);

    # Check computed insertion points
    ok(defined $ledger->{cleared_file},   'A: cleared_file defined');
    ok(defined $ledger->{pending_file},   'A: pending_file defined');
    ok(defined $ledger->{uncleared_file}, 'A: uncleared_file defined');
    ok($ledger->{cleared_file}   eq $ldg, 'A: cleared_file is the single file');
    ok($ledger->{pending_file}   eq $ldg, 'A: pending_file is the single file');
    ok($ledger->{uncleared_file} eq $ldg, 'A: uncleared_file is the single file');

    my $cp = $ledger->{cleared_pos};
    my $pp = $ledger->{pending_pos};
    my $up = $ledger->{uncleared_pos};
    ok(defined $cp && $cp > 0, 'A: cleared_pos is set');
    ok(defined $pp && $pp > 0, 'A: pending_pos is set');
    ok(defined $up && $up > 0, 'A: uncleared_pos is set (EOF)');
    ok($cp < $pp,              'A: cleared_pos < pending_pos');
    ok($pp < $up,              'A: pending_pos < uncleared_pos');

    # Backward-compat aliases still work
    ok($ledger->{ofxfile} eq $ldg, 'A: ofxfile alias = cleared_file');
    ok($ledger->{ofxpos}  == $cp,  'A: ofxpos alias = cleared_pos');

    $ledger->update();

    my $content = slurp($ldg);
    print "\n--- Resulting file (single) ---\n$content---\n\n";

    # Use date-prefixed patterns to avoid matching comment text
    my $alpha_pos   = index($content, '2026/01/10 * Alpha');
    my $new_c_pos   = index($content, '* New Cleared');
    my $beta_pos    = index($content, '2026/01/20 ! Beta');
    my $new_p_pos   = index($content, '! New Pending');
    my $gamma_pos   = index($content, '2026/01/30 Gamma');

    ok($alpha_pos   >= 0, 'A: Alpha (existing cleared) present');
    ok($new_c_pos   >= 0, 'A: New Cleared import present');
    ok($beta_pos    >= 0, 'A: Beta (existing pending) present');
    ok($new_p_pos   >= 0, 'A: New Pending import present');
    ok($gamma_pos   >= 0, 'A: Gamma (existing uncleared) present');

    ok($alpha_pos   < $new_c_pos, 'A: Alpha before New Cleared');
    ok($new_c_pos   < $beta_pos,  'A: New Cleared before Beta (cleared_pos)');
    ok($beta_pos    < $new_p_pos, 'A: Beta before New Pending');
    ok($new_p_pos   < $gamma_pos, 'A: New Pending before Gamma (pending_pos)');
}

# -------------------------------------------------------------------------
# SCENARIO B: multi-file (!include cleared/pending/uncleared sub-files)
# -------------------------------------------------------------------------
print "\n", "=" x 60, "\n";
print "FR-014 B: multi-file routing\n";
print "=" x 60, "\n\n";

{
    my $dir = tempdir(CLEANUP => 1);

    my $f_cleared   = "$dir/fr014_cleared.ldg";
    my $f_pending   = "$dir/fr014_pending.ldg";
    my $f_uncleared = "$dir/fr014_uncleared.ldg";
    my $f_main      = "$dir/fr014_main.ldg";

    copy('fr014_cleared.ldg',   $f_cleared)   or die "copy: $!";
    copy('fr014_pending.ldg',   $f_pending)   or die "copy: $!";
    copy('fr014_uncleared.ldg', $f_uncleared) or die "copy: $!";

    # Main file uses absolute paths so ledger resolves them correctly
    open my $mfh, '>', $f_main or die $!;
    print $mfh "!include $f_cleared\n";
    print $mfh "!include $f_pending\n";
    print $mfh "!include $f_uncleared\n";
    close $mfh;

    # Capture original content of each sub-file for change-detection
    my $orig_pending   = slurp($f_pending);
    my $orig_uncleared = slurp($f_uncleared);

    my $stmt = "$dir/Checking-2026-02.csv";
    open my $fh, '>', $stmt or die $!;
    print $fh "2026/02/01,MF-NEW1,New Cleared,-40.00,Assets:Checking,\n";
    print $fh "2026/02/02,MF-NEW2,New Pending,-50.00,Assets:Checking,pending\n";
    close $fh;

    my $ledger = Ledger->new(file => $f_main);
    $ledger->fromStmt($stmt, $handlers, $csv_config);

    # Check file routing
    ok($ledger->{cleared_file}   eq $f_cleared,   'B: cleared_file -> cleared sub-file');
    ok($ledger->{pending_file}   eq $f_pending,   'B: pending_file -> pending sub-file');
    ok($ledger->{uncleared_file} eq $f_uncleared, 'B: uncleared_file -> uncleared sub-file');

    # Each sub-file has only one transaction with no later-state blockers,
    # so all insertion points should be at EOF of their respective file
    ok($ledger->{cleared_pos}   == (stat($f_cleared))[7],
       'B: cleared_pos = EOF of cleared sub-file');
    ok($ledger->{pending_pos}   == (stat($f_pending))[7],
       'B: pending_pos = EOF of pending sub-file');
    ok($ledger->{uncleared_pos} == (stat($f_uncleared))[7],
       'B: uncleared_pos = EOF of uncleared sub-file');

    $ledger->update();

    my $c_content = slurp($f_cleared);
    my $p_content = slurp($f_pending);
    my $u_content = slurp($f_uncleared);

    print "--- cleared.ldg ---\n$c_content---\n\n";
    print "--- pending.ldg ---\n$p_content---\n\n";
    print "--- uncleared.ldg ---\n$u_content---\n\n";

    ok($c_content =~ /New Cleared/, 'B: cleared sub-file received cleared import');
    ok($p_content =~ /New Pending/, 'B: pending sub-file received pending import');
    ok($u_content eq $orig_uncleared,
       'B: uncleared sub-file unchanged (no uncleared import)');

    # Cross-contamination checks
    ok($c_content !~ /New Pending/, 'B: cleared sub-file has no pending import');
    ok($p_content !~ /New Cleared/, 'B: pending sub-file has no cleared import');
    ok($u_content !~ /New Cleared/ && $u_content !~ /New Pending/,
       'B: uncleared sub-file has no imported transactions');
}

# -------------------------------------------------------------------------
print "\n", "-" x 60, "\n";
printf "%d passed, %d failed\n", $pass, $fail;
exit($fail ? 1 : 0);
