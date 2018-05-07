package Ledger::CSV;
use warnings;
use strict;
use Data::Dumper;
use Date::Parse;
use Text::CSV;

sub parsefile{
    my ($ledger,$fields,$file)=@_;
    my $tcsv=Text::CSV->new();
    my %csv;
    my $transaction;
    my $id=-1;
    my $fd;
    if (ref $file){
	$fd=$file;
    }else{
	open($fd, "<", $file) || die "Can't open $file: $!";
    }
   #fields=( id, file, bpos, date, code, payee, account, commodity, amount, state, note ) 
    #while(my $row=$tcsv->getline($fd)){
    while (<$fd>){
	#@csv{@{$fields}}=@$row;
	chomp;
	@csv{@{$fields}}=map { s/^\s*"//;s/"\s*$//;$_} split (',');
	if ($csv{id} != $id ){
	    if ($transaction){ 
		if ($transaction->{file} eq $csv{file}){
		    $transaction->{epos}=$csv{bpos}-1;
		}else{
		    $transaction->{epos}=-1;
		}
	    }
	    my $state;
	    if ($csv{state} eq '*'){
		$state='cleared';
	    }
	    $transaction=$ledger->addTransaction(str2time($csv{date}), $state, $csv{code}, 
						 $csv{payee},$csv{note});
	    $transaction->{id}=$csv{id};
	    $transaction->{bpos}=$csv{bpos};
	    $transaction->{file}=$csv{file};
	    
	}
	$transaction->addPosting($csv{account}, $csv{amount}, $csv{commodity}, '', $csv{note});
	$id=$csv{id};
    }
    close($fd);
    return $ledger;
}
	    

1;	
