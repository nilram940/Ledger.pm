package Ledger;
use strict;
use warnings;
use Ledger::Transaction;
use Ledger::OFX;

sub new{
    my $class=shift;
    my $self={ transactions => [], 
	       balance=>[], 
	       table=>{}, 
	       id=>{}};
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

sub fromXMLstruct{
    my $self=shift;
    my $xml=shift;
    my $transactions=$xml->{transactions}->{transaction};
    $self->{transactions}=[map {Ledger::Transaction->new()->fromXMLstruct($_)} @{$transactions}];
    return $self
}

sub fromOFX{
    my $self=shift;
    my $ofx=shift;
    my $hints=shift;
    my $ofxdat=Ledger::OFX::parse($ofx);
    my ($account,$code)=&getaccount($ofxdat->{acctid},$hints->{accounts});
    
    foreach my $stmttrn (@{$ofxdat->{transactions}}){
	my $key;
	my $payee=$stmttrn->{payee};
	if ($stmttrn->{id}){
	    $key=$code.'-'.$stmttrn->{id};
	    if ($hints->{id}->{$key}){
		$hints->{desc}->{$payee}=$hints->{id}->{$key};
		next;
	    }
	}
	my $handler=$hints->{handlers}->{$account}->{$payee}||
	    $hints->{handlers}->{$account}->{$hints->{desc}->{$payee}};

	if ($handler && ref ($handler) eq 'HASH'){
	    $payee=$handler->{payee}; 
	}
	elsif ($hints->{desc}->{$payee}){
	    $payee=$hints->{desc}->{$payee};
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
	}else{
	    $transaction->balance($hints);
	}
	push @{$self->{transactions}}, $transaction if $transaction;


    }
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
	
    return $self;
    
}

sub transfer{
    my ($self,$transaction,$tag)=@_;
    $self->{transfer}||={};
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

	
    


sub toString{
    my $self=shift;
    my $str=join("\n\n",map {$_->toString} (sort {$a->{date} <=> $b->{date}} @{$self->{transactions}}),@{$self->{balance}});
    $str.="\n\n";
    return $str;
}
    
       
1;
