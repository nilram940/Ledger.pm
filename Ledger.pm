package Ledger;
use strict;
use warnings;
use Ledger::Transaction;
use Ledger::OFX;
use Ledger::XML;

sub new{
    my $class=shift;
    my %args=@_;
    my $self={ transactions => [], 
	       balance=>[]}; 
    $self->{$_}=$args{$_}||{} foreach (qw( table id desc accounts));
    bless $self, $class;
    return $self;
}

sub addTransaction{
    my $self=shift;
    my $transaction;
    if (ref $_[0]){
	$transaction=shift;
    }else{
	$transaction=new Ledger::Transaction(@_);
    }
    push @{$self->{transactions}},$transaction;
    return $transaction;
}

sub fromXML{
    my $self=shift;
    my $xml=shift;
    Ledger::XML::parse($self,$xml);
    return $self
}

sub fromOFX{
    my $self=shift;
    my $ofx=shift;
    my $handlers=shift;
    my $ofxdat=Ledger::OFX::parse($ofx);
    my ($account,$code)=&getaccount($ofxdat->{acctid},$self->{accounts});

    my $count=0;
    foreach my $stmttrn (@{$ofxdat->{transactions}}){
	my $key;
	my $payee=$stmttrn->{payee};
	if ($stmttrn->{id}){
	    $key=$code.'-'.$stmttrn->{id};
	    if ($self->{id}->{$key}){
		$self->{desc}->{$payee}=$self->{id}->{$key};
		next;
	    }
	}
	my $handler=$handlers->{$account}->{$payee}||
	    $handlers->{$account}->{$self->{desc}->{$payee}||""};

	if ($handler && ref ($handler) eq 'HASH'){
	    $payee=$handler->{payee}; 
	}
	elsif ($self->{desc}->{$payee}){
	    $payee=$self->{desc}->{$payee};
	}
	
	my $transaction=new Ledger::Transaction 
	    ($stmttrn->{date}, "cleared", $stmttrn->{number}, 
	     $payee);
			
	my $commodity;
	if ($stmttrn->{commodity}){
	    $commodity=$ofxdat->{ticker}->{$stmttrn->{commodity}};
	}
	$transaction->addPosting($account, $stmttrn->{quantity},$commodity,
				 $stmttrn->{cost},"ID: $key");
	if ($handler){
	    if (ref ($handler) eq 'HASH'){
		$transaction=$self->transfer($transaction,$handler->{transfer})
	    }else{
		$transaction=&{$handler}($transaction);
	    }
	}
	if ($transaction){
	    $transaction->balance($self->{table},
				  $self->getTransactions('pending'));
	    push @{$self->{transactions}}, $transaction;
	    $count++;
	}


    }
    if($count){
	my $payee=(split(/:/, $account))[-1];
	$payee.=' Balance';
	my $balance=$ofxdat->{balance};
    
	my $transaction=new Ledger::Transaction
	    ($balance->{date},"cleared",undef,$payee);
	
	my $commodity;
	if ($balance->{commodity}){
	    $commodity=$ofxdat->{ticker}->{$balance->{commodity}};
	}

	$transaction->addPosting($account,$balance->{quantity},$commodity,'BAL');
	push @{$self->{balance}},$transaction;
    }
    return $self;
    
}

sub getTransactions{
    my $self=shift;
    my $filter=shift||'';
    if ($filter eq 'cleared'){
	return grep {$_->{state} eq 'cleared'} @{$self->{transactions}};
    }    
    if ($filter eq 'uncleared'){
	return grep {$_->{state} ne 'cleared'} @{$self->{transactions}};
    }
    if ($filter eq 'balance'){
	return @{$self->{balance}};
    }

    return @{$self->{transactions}};
}

sub transfer{
    my ($self,$transaction,$tag)=@_;
    $self->{transfer}||={};
    $transaction->{transfer}=$tag;
    my $account="Equity:Transfers:$tag";
    my $amount=abs($transaction->getPosting(0)->cost());
    my $date=int ($transaction->{date}/(24*3600));
    $tag.="-$date-$amount";
    $self->{transfer}->{$tag}||=[];
    my $transfer=$self->{transfer}->{$tag};
    my $idx=0;

    $idx++ while ($idx<@{$transfer} && 
		  abs($transfer->[$idx]->getPosting(0)->cost()+
		      $transaction->getPosting(0)->cost())>.0001);
    if ($idx < @{$transfer}){ 
	$transfer->[$idx]->setPosting(1,$transaction->getPosting(0));
	    $transfer->[$idx]->{payee}=$transaction->{payee} 
	          if (length ($transaction->{payee})>length($transfer->[$idx]->{payee}));
	    splice(@{$transfer},$idx,1);
	    $transaction=undef;
    }else{
	push @{$transfer},$transaction;
	$transaction->addPosting($account);
    }	
    return $transaction;
}

sub getaccount{
    my ($acctid, $accounts)=@_;
    $acctid=~s/.*(....)$/$1/g;
    my $account=$accounts->{$acctid};
    my $code=(split(/:/,$account))[-1];
    $code=join ("", (map {substr ($_,0,1)} split (/\s+/, $code)));

    return ($account,$code);
}


sub getCleared{
    my $self=shift;
    my $uncleared=@_ && not shift;
    grep {$uncleared xor $_->{state} eq "cleared"} $self->getTransactions();
}
    
    


sub toString{
    my $self=shift;
    my $str=join("\n\n",map {$_->toString} (sort {$a->{date} <=> $b->{date}} @{$self->{transactions}}),(sort {$a->{date} <=> $b->{date}} @{$self->{balance}}));
    $str.="\n\n";
    return $str;
}

sub toString2{
    my $self=shift;
    my $filter=shift;
    my $str;

    if ($filter){
	$str=join("\n\n", (map {$_->toString} 
			   (sort {$a->{date} <=> $b->{date}}
			    $self->getTransactions($filter))))."\n\n"
    }else{

	$str=join("\n\n",(map {$_->toString} 
		 (sort {$a->{date} <=> $b->{date}} 
		  $self->getTransactions("cleared")),
		 (sort {$a->{date} <=> $b->{date}} @{$self->{balance}})),
		 ";----UNCLEARED-----",
		  (map {$_->toString} 
		  (sort {$a->{date} <=> $b->{date}} 
		   $self->getTransactions("uncleared"))));
	$str.="\n\n";
     }
    return $str;
}
       
1;
