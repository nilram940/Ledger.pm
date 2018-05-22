package Ledger;
use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);
use Ledger::Transaction;
use Ledger::OFX;
use Ledger::XML;
use Ledger::CSV;

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

sub fromCSV{
    my $self=shift;
    my ($fields, $file, $pipe)=@_;
    my $dir=$pipe?'-|':'<';
    open(my $csv, $dir, $file) || die qq(Can't open csv "$file" : $!);
    Ledger::CSV::parsefile($self,$fields, $csv);
    close($csv);
    return $self;
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
				  $self->getTransactions('uncleared'));
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
    
sub gettable{
    my $self=shift;
    my $table={};    

    foreach my $transaction ($self->getTransactions()){
	my $source=$transaction->getPosting(0)->{account};
	my $amount=$transaction->getPosting(0)->{quantity};
	my $bracket=($amount<0?-1:1);
	my $dest=$transaction->getPosting(-1)->{account};
	my $payee=$transaction->{payee};
	$table->{$source}||={};
	$table->{$source}->{$payee}||={total =>0 ,$dest => 0};
	$table->{$source}->{$payee}->{total}++;
	$table->{$source}->{$payee}->{$dest.'-'.$bracket}++;

	$payee='@@account default@@';
	$bracket=($amount<0?-1:1);
	$dest=join(':',(split(/:/,$dest))[0,1]);
	$table->{$source}->{$payee}||={total =>0 ,$dest => 0};
	$table->{$source}->{$payee}->{total}++;
	$table->{$source}->{$payee}->{$dest.'-'.$bracket}++;
    }
    return ($table);
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

sub print{
    my $self=shift;
    my $file='';
    my $fh;
	
    foreach my $transaction (@{$self->{transactions}}){
	
	if ($transaction->{file} ne $file){
	    $file=$transaction->{file};
	    close($fh) if $fh;
	    open ($fh, "<", $file);
	}
	unless ($transaction->{bpos}){
	    my $len=200;
	    my $pos=$transaction->getPosting(0)->{bpos}-$len;
	    if ($pos<0){
		$len+=$pos;
		$pos=0;
	    }
	    seek ($fh, $pos, SEEK_SET);
	    read $fh, (my $str), $len-1; 
	    my $idx=rindex $str,"\n";
	    $idx=0 if $idx<0;
	    $transaction->{bpos}=$pos+$idx;
	}
	seek ($fh, $transaction->{bpos}, SEEK_SET);
	read $fh, (my $trstr), ($transaction->{epos}-$transaction->{bpos});
	print $trstr;#."\n";
    }
    
}

# sub update{
#     my $self=shift;
#     my $file='';
#     my $readh,$writeh;
#     my $lastpos;
	
#     foreach my $transaction (@{$self->{transactions}}){
# 	if ($transaction->{edit}){
# 	    if ($transaction->{file}){
# 		if ($transaction->{file} ne $file){
# 		    $file=$transaction->{file};
# 		    rename($file,"$file.bak");
# 		    if ($readh){
# 			seek ($readh, $lastpos, SEEK_SET);
# 			my $len=1024;
# 			my $buffer;
# 			my $readlen=$len;
# 			while ($readlen==$len){
# 			    $readlen=read $readh, $buffer, $len
# 			    print $writeh $buffer;
# 			} 
# 			close($readh);
# 			close($writeh);
# 		    }
# 		    open ($writeh, ">", $file);
# 		    open ($readh, "<", "$file.bak");
# 		    $lastpos=0;
# 		}
# 		print $writeh $transaction->toString();
# 	    }
# 	}	
#     }
#     if ($readh){
# 	seek ($readh, $lastpos, SEEK_SET);
# 	my $len=1024;
# 	my $buffer;
# 	my $readlen=$len;
# 	while ($readlen==$len){
# 	    $readlen=read $readh, $buffer, $len
# 		print $writeh $buffer;
# 	} 
# 	close($readh);
# 	close($writeh);
#     }

    
# }


sub update{
    my $self=shift;
    my $file='';
    my ($readh,$writeh);
    my $lastpos;

    my @uncleared= $self->getTransactions('uncleared');
    my @transactions=((grep {  $_->{edit}} @{$self->{transactions}}),
		      @uncleared);
    if (@transactions){
	$file=$transactions[-1]->{file}; #assume only one file
    }else{
	$file=$self->{transactions}->[-1]->{file}; # all writes go to last file read
    }
    print STDERR "file=$file\n";
    #rename($file,"$file.bak");
    open ($writeh, ">&", \*STDOUT);
    open ($readh, "<", "$file");
    $lastpos=0;
    foreach my $transaction (@transactions){
	next unless $transaction->{file} eq $file;
	unless ($transaction->{bpos}){
	    my $len=200;
	    my $pos=$transaction->getPosting(0)->{bpos}-$len;
	    if ($pos<0){
		$len+=$pos;
		$pos=0;
	    }
	    seek ($readh, $pos, SEEK_SET);
	    read $readh, (my $str), $len-1; 
	    my $idx=rindex $str,"\n";
	    #$idx=0 if $idx<0;
	    $transaction->{bpos}=$pos+$idx+1;
	}
	my $len=$transaction->{bpos}-$lastpos-1;
	seek ($readh, $lastpos, SEEK_SET);     # read from last read
	read $readh, (my $buffer), $len;       #  to beginning of transaction 
	print $writeh $buffer;                 # copy to new file
	$lastpos=$transaction->{epos};         # keep transaction til end of file
	unless ($transaction->{original}){
	    seek ($readh, $transaction->{bpos}, SEEK_SET);
	    read $readh, (my $trstr), 
		($transaction->{epos}-$transaction->{bpos});
	    #$trstr=~s/^/; /mg;
	    $transaction->{original}=$trstr;
	}
    }
    # copy to end of file.
    seek ($readh, $lastpos, SEEK_SET);
    my $len=1024;
    my $buffer;
    my $readlen=$len;
    while ($readlen==$len){
	$readlen=read $readh, $buffer, $len;
	print $writeh $buffer;
    } 
    close($readh);

    my @cleared=grep {$_->{state} eq 'cleared' && 
     			  (! $_->{file} || $_->{edit})} 
    @{$self->{transactions}};
    
    # my @cleared=grep { ! $_->{file}} @{$self->{transactions}};

    print $writeh '; '.localtime."\n\n";
    print $writeh join("\n",(map {$_->toString} 
			       (sort {$a->{date} <=> $b->{date}} @cleared),
			       (sort {$a->{date} <=> $b->{date}} 
				@{$self->{balance}}),
			       (sort {$a->{date} <=> $b->{date}} 
				@uncleared)))."\n\n";
		       
    close($writeh);
}
    

1;
