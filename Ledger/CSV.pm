package Ledger::CSV;
use warnings;
use strict;
use Date::Parse;
use Text::CSV;

sub new {
    my ($class, $file, $args, %opts) = @_;
    unless (defined $args) {
        open(my $fh, '<', $file) or die "Can't open $file: $!";
        local $/ = "\n";
        my $line = <$fh>;
        $line = <$fh> if defined $line && $line =~ /^#LedgerName:/;
        close $fh;
        chomp($line) if defined $line;
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
    my $tcsv=Text::CSV->new($csvargs);
    my $fd;

    if (ref $file){
	$fd=$file;
    }else{
	open($fd, "<", $file) || die "Can't open $file: $!";
    }

    my $ledgername;
    if (!ref $file) {
        my $pos = tell($fd);
        local $/ = "\n";
        my $first = <$fd>;
        if (defined $first && $first =~ /^#LedgerName:\s*(.+?)\s*$/) {
            $ledgername = $1;
        } else {
            seek($fd, $pos, 0);
        }
    }

    if ($args->{header_map}) {
        my $header = $tcsv->getline($fd);
        my %col_to_field = reverse %{$args->{header_map}};
        $fields = [ map { $col_to_field{$_} // '' } @$header ];
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
            && ($csv{state}//'cleared') ne 'pending') {
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

sub ledgerCSV{
    my $ledger=shift;
    my $file=shift;
    $ledger->{transfer}||={};
    my @fields=qw(id file bpos epos xnote key price date code payee account 
    commodity amount state note); 

    my $csvformat=
	q["%(xact.id)","%S","%B","%E",].
	q[%(quoted(xact.note)),].
	q[%(quoted(meta("ID"))),].
	q[%(quoted(quantity(scrub(price)))),];

    my $ledgerargs=q( -E -L --prepend-format ') .$csvformat.q(');
    $ledgerargs.=' -f  "'. $file.'"' if $file;
	
    my $csv=q(ledger csv).$ledgerargs;

    print STDERR $csv."\n";

    my $tcsv=Text::CSV->new({escape_char => '\\'});
    my %csv;
    my $transaction;
    my $id=-1;
    my $last_file='';
    my $fd;

    open($fd, "-|", $csv) || die "Can't open $csv: $!";

    while(my $row=$tcsv->getline($fd)){
	@csv{@fields}=@$row;
	# A new transaction starts when the xact.id changes OR when the source
	# file changes (%(xact.id) resets per included file, so the same id can
	# appear in two different sub-files).
	if ($csv{id} != $id || $csv{file} ne $last_file){
	    my $state;
	    if ($csv{state} eq '*'){
		$state='cleared';
	    }elsif($csv{state} eq '!'){
		$state='pending';
	    }
	    $transaction=$ledger->addTransaction(str2time($csv{date}), 
						 $state, $csv{code}, 
						 $csv{payee},$csv{xnote});
	    $transaction->{id}=$csv{id};
	    $transaction->{file}=$csv{file};
	    
	}
	$csv{note}=~s/\Q$csv{xnote}\E//;
	#print STDERR 'note: '.$csv{note}."\n";
	if ($csv{key}){
	    $ledger->{id}->{$csv{key}}=$csv{payee};
	}
	my $price=(($csv{commodity} eq '$') ? '' : $csv{price});
	my $posting=$transaction->addPosting($csv{account}, $csv{amount}, 
					     $csv{commodity}, $price,
					     $csv{note});
	$posting->{bpos}=$csv{bpos};
	$posting->{epos}=$csv{epos};
	$transaction->{epos}=$csv{epos};
        if ($csv{account}=~/^Equity:Transfers:(.+)/){
            $transaction->{transfer}=$1;
            # Negate the posting cost so transfer() matching is sign-consistent with
            # the same-session path, which stores the opposing asset/liability posting.
            my %neg = %$posting;
            $neg{quantity} = -($posting->{quantity}||0);
            &build_transfer($ledger->{transfer}, $transaction, $1, $csv{amount},
                            bless(\%neg, ref $posting));
        }elsif ($csv{account}=~/^(Assets|Liabilities)/ &&
                (!$csv{note} || $csv{note}!~/ID:/)){
            my $tag=(split(/:/,$csv{account}))[-1];
            $transaction->{transfer}=$tag;
            my %neg = %$posting;
            $neg{quantity} = -($posting->{quantity}||0);
            &build_transfer($ledger->{transfer}, $transaction, $tag, $csv{amount},
                            bless(\%neg, ref $posting));
        }
	$id=$csv{id};
	$last_file=$csv{file};
    }
    $tcsv->eof or die $tcsv->error_diag();
    close($fd);
    return $ledger;
}

sub build_transfer{
    my $transfers=shift;
    my $transaction=shift;
    my $tag=shift;
    my $amount=shift;
    my $posting=shift;
    my $key=sprintf("$tag-%.2f",abs($amount));
    $transfers->{$key}||=[];
    my $transfer=$transfers->{$key};
    my $idx=0;
    $idx++ while ($idx < @{$transfer} &&
        !(abs($transfer->[$idx]->[1]->cost()+
              $posting->cost())<.0001
          && abs($transaction->{date}-$transfer->[$idx]->[0]->{date})<= 5*24*3600 ));
    if ($idx < @{$transfer}){
        splice(@{$transfer},$idx,1);
        delete $transfers->{$key} unless @{$transfer};
    }else{
        push @{$transfer},[$transaction, $posting];
    }
}    


1;	
