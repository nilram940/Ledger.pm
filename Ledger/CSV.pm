package Ledger::CSV;
use warnings;
use strict;
use Date::Parse;
use Text::CSV;

sub new {
    my ($class, $file, $args, %opts) = @_;
    unless (defined $args) {
        open(my $fh, '<', $file) or die "Can't open $file: $!";
        my $line;
        while (<$fh>){
            if (/\w/ && !/^#/){
                $line=$_;
                chomp($line);
                last;
            }
        }
        close $fh;
        my $mod = detect($line) if defined $line;
        die "Unknown CSV format for $file: no fingerprint match\n" unless $mod;
        return $mod->new($file, %opts);
    }
    return bless { file => $file, args => $args }, $class;
}

sub parse {
    my ($self, $callback) = @_;
    return parsefile($self->{file}, $self->{args}, $callback);
}

sub parsefile{
    my ($file,$args,$callback)=@_;
    my $fields=$args->{fields};
    my $csvargs=$args->{csv_args}||{};
    my $tcsv=Text::CSV->new($csvargs) || die "Cannot use CSV: " . Text::CSV->error_diag();

    my $fd;

    if (ref $file){
	$fd=$file;
    }else{
	open($fd, "<", $file) || die "Can't open $file: $!";
    }

    my $ledgername;
    my $header;
    my $pos;

    while(1) {
        #consume blank / comment lines in header
        $pos = tell($fd);
        $header = $tcsv->getline($fd);
        if ($header){
            my $h0=$header->[0];
            if ($h0=~/^#/){
                if ($h0=~ /^#LedgerName:\s*(.+?)\s*$/) {
                    $ledgername = $1;
                }
            }elsif ($h0=~/\w/) {
                last
            }

        }
    }
    if ($args->{header_map}) {
        my %col_to_field = reverse %{$args->{header_map}};
        $fields = [ map { $col_to_field{$_} // '' } @{$header} ];
    }else{
        #reset to read the actual first line.
        seek($fd, $pos, 0);
    }


    my $rb_field = $args->{running_balance};
    my ($rb_val, $rb_date);

    while(1){
	last if $tcsv->eof;
        my %csv;
	my $row=$tcsv->getline($fd);
	next unless $row;
	@csv{@{$fields}}=@$row;
	next unless $csv{date};
	$csv{date}=str2time($csv{date});
	next unless $csv{date};
	$csv{cost}='BAL' if $csv{quantity}=~s/^\s*=\s*//;
	$csv{quantity}=~s/^(-?)[^-\d]*\$/$1/;
	$csv{quantity}=-$csv{quantity} if $args->{reverse} && !$csv{cost};
	$csv{payee}=~s/^\s*//;
	$csv{payee}=~s/~.*$//;
        $csv{account} ||= $ledgername if $ledgername;
        $csv{source} = 'CSV';
        $csv{idlist} = [$csv{date}, $csv{payee}, $csv{quantity}] unless $csv{id};
        &{$args->{process}}(\%csv) if $args->{process};
        if ($rb_field && defined $csv{$rb_field} && length $csv{$rb_field}
            && ($csv{state}//'cleared') ne 'pending'
            && $csv{date} > ($rb_date // 0)) {
            ($rb_val = $csv{$rb_field}) =~ s/^(-?)[^-\d]*\$/$1/;
            $rb_date = $csv{date};
        }
	&{$callback}(\%csv);
    }

    &{$callback}({cost=>'BAL', quantity=>$rb_val+0, date=>$rb_date})
        if defined $rb_val;

    $tcsv->eof or $tcsv->error_diag();
    close($fd) unless $fd eq $file;
    return 1;
}

my @KNOWN_MODULES = qw(
    Ledger::CSV::Fidelity
    Ledger::CSV::Coinbase
    Ledger::CSV::HSA
);


    
sub detect {
    my $header = shift;
    for my $mod (@KNOWN_MODULES) {
        (my $file = $mod) =~ s!::!/!g;
        require "$file.pm";
        return $mod if $header =~ $mod->fingerprint();
    }
    return undef;
}

1;

