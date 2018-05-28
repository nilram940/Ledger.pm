package Ledger::CSV;
use warnings;
use strict;
#use Data::Dumper;
use Date::Parse;
use Text::CSV;

sub parsefile{
    my ($ledger,$fields,$file)=@_;
    my $tcsv=Text::CSV->new({escape_char => '\\'});
    my %csv;
    my $transaction;
    my $id=-1;
    my $fd;
	
    if (ref $file){
	$fd=$file;
    }else{
	open($fd, "<", $file) || die "Can't open $file: $!";
    }
    while(my $row=$tcsv->getline($fd)){
	@csv{@{$fields}}=@$row;
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
	my $posting=$transaction->addPosting($csv{account}, $csv{amount}, 
					     $csv{commodity}, '', $csv{note});
	$posting->{bpos}=$csv{bpos};
	$posting->{epos}=$csv{epos};
	$transaction->{epos}=$csv{epos};
	$id=$csv{id};
    }
    $tcsv->eof or $tcsv->error_diag();
    close($fd) unless $fd == $file;
    return $ledger;
}


1;	
