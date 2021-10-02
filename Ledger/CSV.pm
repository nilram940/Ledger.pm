package Ledger::CSV;
use warnings;
use strict;
use Date::Parse;
use Text::CSV;

sub parsefile{
    my ($file,$args,$callback)=@_;
    my $fields=$args->{fields};
    my $csvargs=$args->{csv_args}||{};
    my $tcsv=Text::CSV->new($csvargs);
    my %csv;
    my $fd;
    my @trlist;
    
    if (ref $file){
	$fd=$file;
    }else{
	open($fd, "<", $file) || die "Can't open $file: $!";
    }
    while(1){
	last if $tcsv->eof;
	my $row=$tcsv->getline($fd);
	next unless $row;
	@csv{@{$fields}}=@$row;
	next unless $csv{date};
	$csv{date}=str2time($csv{date});
	next unless $csv{date};
	$csv{quantity}=~s/^.*\$//;
	#next unless $csv{quantity}=~/^\d/;
	$csv{quantity}=-$csv{quantity} if $args->{reverse};
	$csv{payee}=~s/^\s*//;
	$csv{payee}=~s/~.*$//;
	&{$callback}(\%csv);
	#push @trlist,{%csv};
    }

    $tcsv->eof or $tcsv->error_diag();
    close($fd) unless $fd eq $file;
    return 1; #(transactions=>\@trlist);
}

sub ledgerCSV{
    my $ledger=shift;
    my $file=shift;
    
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
    my $fd;
	
    open($fd, "-|", $csv) || die "Can't open $csv: $!";
    
    while(my $row=$tcsv->getline($fd)){
	@csv{@fields}=@$row;
	if ($csv{id} != $id ){
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
	if ($csv{account}=~/^Equity:Transfers:(\w+)/){
	    $transaction->{transfer}=$1;
	}
	$id=$csv{id};
    }
    $tcsv->eof or die $tcsv->error_diag();
    close($fd);
    return $ledger;
}


1;	
