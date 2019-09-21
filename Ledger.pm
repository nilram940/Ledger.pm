package Ledger;
use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);
use Storable;
use Ledger::Transaction;
use Ledger::OFX;
use Ledger::XML;
use Ledger::CSV;
use POSIX qw(strftime);

sub new{
    my $class=shift;
    my %args=@_;
    my $self={ transactions => [], 
	       balance=>{}}; 
    bless $self, $class;
    $self->{desc}=($args{payeetab} && (-f $args{payeetab}))
	? retrieve($args{payeetab}):{};
    $self->{accounts}=$args{accounttab}?$self->getacctnum($args{accounttab}):{};
    $self->{id}={};
    $self->{payeetab}=$args{payeetab};
    $self->{idtag}=$args{idtag} || 'ID';
    
    Ledger::CSV::ledgerCSV($self, $args{file});

    $self->gentable;

    return $self;
}

sub getacctnum{
    my $self=shift;
    my $accfile=shift;
    my %num;
    open (my $accounts,"<",$accfile) || die "Can't open $accfile: $!";
    while (<$accounts>){
	chomp;
	s/ *$//;
	%num=(%num,split(/ \| /));
    }
    close($accounts);
    $self->{accounts}=\%num;
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

sub addBalance{
    my $self=shift;
    my $account=shift;
    my $transaction;
    if (ref $_[0]){
	$transaction=shift;
    }else{
	$transaction=new Ledger::Transaction(@_);
    }
    unless ($self->{balance}->{$account} &&
	$transaction->{date}< $self->{balance}->{$account}->{date}){
	$self->{balance}->{$account}=$transaction;

    }
    return $self->{balance}->{$account};
}

sub fromXML{
    my $self=shift;
    my $xml=shift;
    Ledger::XML::parse($self,$xml);
    return $self
}

sub fromCSV{
    my ($file, $csv)=@_;
    return Ledger::CSV::parsefile($file, $csv);
}
	
sub fromStmt{
    # read Stmt and convert to Ledger data structure.
    # expects files to be named $account-$data.$type
    # Supports OFX
    
    my $self=shift;
    my $stmt=shift;
    my $handlers=shift;
    my $csv=shift;
    my %trdat;


    my $account=$stmt;
    $account=~s/-.*//;
    $account=~s!.*/!!;
    $account=~s/\..*//;

    if ($stmt=~/.[oq]fx$/i){
	%trdat=&fromOFX2($stmt);
    }elsif ($stmt=~/.csv$/i){
	%trdat=&fromCSV($stmt,$csv->{$account});
    }

    unless ($self->{ofxfile}){
	$self->{ofxfile}=($self->getTransactions('cleared'))[-1]->{file};
	$self->getofxpos;
    }
    my $count=0;
    
    foreach my $stmttrn (@{$trdat{transactions}}){
	my $key=&makeid($account,$stmttrn);
	my $payee=$stmttrn->{payee};
	if ($self->{id}->{$key}){
	    $self->{desc}->{$payee}=$self->{id}->{$key};
	    next;
	}
	$self->{id}->{$key}=$payee;
	next if ($stmttrn->{quantity} == 0);
	my $handler=$handlers->{$account}->{$payee}||
	    $handlers->{$account}->{$self->{desc}->{$payee}||""};

	unless ($handler){
	    my $key=(split(/\s+/,$payee))[0];
	    $handler=$handlers->{$account}->{$key}||'';
	}
	
	if ($handler && ref ($handler) eq 'HASH'){
	    $payee=$handler->{payee}; 
	}
	elsif ($self->{desc}->{$payee}){
	    $payee=$self->{desc}->{$payee};
	}
	
	my $transaction=new Ledger::Transaction 
	    ($stmttrn->{date}, "cleared", $stmttrn->{number}, 
	     $payee);
	$transaction->{edit}=$self->{ofxfile};
	$transaction->{edit_pos}=-1;
	
	$transaction->addPosting($account, $stmttrn->{quantity},
				 $stmttrn->{commodity},
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
	    $self->addTransaction($transaction);
	    $count++;
	}


    }
    if($count){
	my $payee=(split(/:/, $account))[-1];
	$payee.=' Balance';
	my $balance=$trdat{balance};
    
	my $transaction=new Ledger::Transaction
	    ($balance->{date},"cleared",undef,$payee);

	$transaction->addPosting($account,$balance->{quantity},$balance->{commodity},'BAL');
	$self->addBalance($account,$transaction);
    }
    return $self;


}
sub addStmtTran{
    my $self=shift;
    my $account=shift;
    my $handlers=shift;
    my $stmttrn=shift;
    
    my $key=&makeid($account,$stmttrn);
    my $payee=$stmttrn->{payee};

    if ($self->{id}->{$key}){
	$self->{desc}->{$payee}=$self->{id}->{$key};
	return;
    }
    return if ($stmttrn->{quantity} == 0);
    my $handler=$handlers->{$account}->{$payee}||
	$handlers->{$account}->{$self->{desc}->{$payee}||""};
    
    unless ($handler){
	my $key=(split(/\s+/,$payee))[0];
	$handler=$handlers->{$account}->{$key}||'';
    }
	
    if ($handler && ref ($handler) eq 'HASH'){
	$payee=$handler->{payee}; 
    }elsif ($self->{desc}->{$payee}){
	$payee=$self->{desc}->{$payee};
    }
	
    my $transaction=new Ledger::Transaction 
	($stmttrn->{date}, "cleared", $stmttrn->{number}, 
	 $payee);
    $transaction->{edit}=$self->{ofxfile};
    $transaction->{edit_pos}=-1;
    
    $transaction->addPosting($account, $stmttrn->{quantity},
			     $stmttrn->{commodity},
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
	$self->addTransaction($transaction);
    }
    return $transaction;

}


sub fromOFX2{
    my $ofxfile=shift;
    my $ofxdat=Ledger::OFX::parsefile($ofxfile);
    my %trlist=();
    $trlist{transactions}=$ofxdat->{transactions};
    $trlist{balance}=$ofxdat->{balance};
    return %trlist;

    
    foreach my $stmttrn (@{$ofxdat->{transactions}}){
	my $trans={};

	if ($stmttrn->{commodity}){
	    $trans->{commodity}=$ofxdat->{ticker}->{$stmttrn->{commodity}};
	}

	my @copy=qw(payee quantity cost id date number);
	@{$trans}{@copy}= @{$stmttrn}{@copy};
	push @{$trlist{transactions}}, $trans;
    }
    my $balance={};
    my $ofxbal=$ofxdat->{balance};
    
    if ($ofxbal->{commodity}){
	$balance->{commodity}=$ofxdat->{ticker}->{$ofxbal->{commodity}};
    }
    $balance->{date}=$ofxbal->{date};
    $balance->{quantity}=$ofxbal->{quantity};
    $trlist{balance}=$balance;
    
    return %trlist
}

sub fromOFX{
    my $self=shift;
    my $ofx=shift;
    my $handlers=shift;
    my $ofxdat=Ledger::OFX::parse($ofx);
    my ($account,$code)=&getaccount($ofxdat->{acctid},$self->{accounts});
    
    my $count=0;
    unless ($self->{ofxfile}){
	$self->{ofxfile}=($self->getTransactions('cleared'))[-1]->{file};
	$self->getofxpos;
    }
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
	#$transaction->{file}=$self->{ofxfile};
	$transaction->{edit}=$self->{ofxfile};
	$transaction->{edit_pos}=-1;
	#$transaction->{bpos}=-1;
	#$transaction->{epos}=-1;
			
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

sub getofxpos{
    my $self=shift;
    
    my @pending= (grep {$_-> {file} && 
			    $_->{date} >0 &&
			    $_->{file} eq $self->{ofxfile} &&
			    $_->{state} ne 'cleared'} 
		  @{$self->{transactions}});

    if (@pending){
	my $pending=(sort {$a->{epos} <=> $b->{epos}} @pending)[0];
	$pending->findtext;
	$self->{ofxpos}=$pending->{bpos};
    }else{
	$self->{ofxpos}=(stat($self->{ofxfile}))[7];
    }
}		  
		  
sub getTransactions{
    my $self=shift;
    my $filter=shift||'';
    
    if (ref($filter)){
	return grep {&{$filter}($_)} @{$self->{transactions}};
    }
    if ($filter eq 'cleared'){
	return grep {$_->{state} eq 'cleared'} @{$self->{transactions}};
    }    
    if ($filter eq 'uncleared'){
	return grep {$_->{state} ne 'cleared'} @{$self->{transactions}};
    }
    if ($filter eq 'balance'){
	return (values %{$self->{balance}});
    }
    if ($filter eq 'edit'){
	return grep {$_->{edit} } @{$self->{transactions}};
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

sub makeid{
    my $account=shift;
    my $trdat=shift;
    my $id=(split(/:/,$account))[-1];
    $id=join ("", (map {substr ($_,0,1)} split (/\s+/, $id)));
    $id.='-';
    
    if ($trdat->{id}){
	$id.=$trdat->{id};
	if ($account =~ /Discover/){
	    substr($id,-5,5,'0');
	}
    }else{
	$id.=strftime('%Y/%m/%d', localtime $trdat->{date}).
	    '+$'.sprintf('%.02f',$trdat->{quantity});
    }
    return $id;
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
    
sub gentable {
    my $self=shift;
    my $table={};    

    foreach my $transaction ($self->getTransactions()){
    	my $source=$transaction->getPosting(0)->{account};
    	my $amount=$transaction->getPosting(0)->{quantity};
    	my $bracket=($amount<0?-1:1)*length(sprintf('%.2f',abs($amount)));
    	my $dest=$transaction->getPosting(-1)->{account};
    	my $payee=$transaction->{payee}.'-'.$bracket;
    	$table->{$source}||={};
    	$table->{$source}->{$payee}||={total =>0 ,$dest => 0};
    	$table->{$source}->{$payee}->{total}++;
    	$table->{$source}->{$payee}->{$dest}++;
	
    	$payee='@@account default@@-'.$bracket;
    	# #$bracket=($amount<0?-1:1);
    	$dest=join(':',(split(/:/,$dest))[0,1]);
    	$table->{$source}->{$payee}||={total =>0 ,$dest => 0};
    	$table->{$source}->{$payee}->{total}++;
    	$table->{$source}->{$payee}->{$dest}++;
    }
    $self->{table}=$table;
    return ($self);
}

sub toString{
    my $self=shift;
    my $str=join("\n\n",map {$_->toString} (sort {$a->{date} <=> $b->{date}} @{$self->{transactions}}),(sort {$a->{date} <=> $b->{date}} (values %{$self->{balance}})));
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
    
sub update{
    my $self=shift;
    store ($self->{desc}, $self->{payeetab}) if $self->{payeetab};
    
    my @edit=(grep { $_->{edit} }
	       @{$self->{transactions}});

    my $file='';
    my $fd;
    foreach my $transaction (sort {$a->{file} cmp $b->{file}} 
			     grep {$_->{file}} @edit){
	next if $transaction->{bpos};
	
	unless ($transaction->{file} eq $file){
	    close($fd) if $fd;
	    $file=$transaction->{file};
	    print STDERR "findtext: $file\n";
	    open ($fd, "<", $file) || die "Can't open $file: $!";
	}
	$transaction->findtext($fd);
    }
    close($fd) if $fd;
    
			  
    my %files=map {($_->{file}?
		    ($_->{file}=>1, $_->{edit}=>1):
		    ($_->{edit}=>1))} @edit;

    foreach $file (keys %files){
	$self->update_file($file);
    }
}

sub update_file{
    my $self=shift;
    my $file=shift;
    my $ofx=($self->{ofxfile} && $self->{ofxfile} eq $file);
    
    my @edit= (grep {$_->{edit} &&
			 (($_->{file} && 
			   $_->{file} eq $file) ||
			  $_->{edit} eq $file)}
	       @{$self->{transactions}});
    my @append=grep {$_->{edit_pos}<0} @edit;

    my $posfilter=sub {
    	my $t=shift;
    	my %pos=();
	unless ($t->{edit}){
	    print STDERR "edit=".$t->toString."\n";
	}
    	if ($t->{edit} eq $file){
    	    $pos{$t->{edit_pos}}=$t;
    	}
    	if ($t->{file} && $t->{file} eq $file){
    	    $pos{$t->{bpos}}=$t;
    	}
    	%pos;
    };
    
    my %posmap = map { &{$posfilter}($_) }  (grep {$_->{edit_pos}>=0} @edit);

    if ($ofx && @append){
	$posmap{$self->{ofxpos}}=-1;
    }
    my $lastpos=0;
    print STDERR "file=$file\n";
    rename($file,"$file.bak");
    open (my $writeh, ">", $file);
    open (my $readh, "<", "$file.bak");

    foreach my $pos (sort {$a <=> $b} (keys %posmap)){
	my $transaction=$posmap{$pos};
	
	# unless ($transaction->{bpos}>0){
	#     print STDERR $transaction->toString.'\n';
	# }
	
	my $len=$pos-$lastpos-1;
	seek ($readh, $lastpos, SEEK_SET);   # read from last read
	read $readh, (my $buffer), $len;     #  to beginning of transaction 
	print $writeh $buffer;               # copy to new file

	
	if (ref($transaction)){
	    $lastpos=(($pos == $transaction->{bpos})?
		      $transaction->{epos}:
		      $transaction->{edit_end});
	    if (($transaction -> {edit} eq $file) && 
		($transaction->{edit_pos} == $pos)) {
		print $writeh "\n".$transaction->toString();
	    }
	}elsif($ofx){
	    my @cleared=grep {$_->{state} eq 'cleared' } @append;
	    my @uncleared=grep {$_->{state} ne 'cleared' } @append;
	    print $writeh "\n; ".localtime."\n\n";

	    print $writeh join("\n",(map {$_->toString} 
				 (sort {$a->{date} <=> $b->{date}} @cleared),
				     (sort {$a->{date} <=> $b->{date}} 
				      (values %{$self->{balance}})),
				     (sort {$a->{date} <=> $b->{date}} 
				      @uncleared)))."\n\n";
	    @append=();
	    $lastpos=$pos;
	}
	
	    
    }
    # copy to end of file.
    seek ($readh, $lastpos, SEEK_SET);
    my $len=1024;
    my $buffer;

    while (!eof($readh)){
	read $readh, $buffer, $len;
	print $writeh $buffer;
    } 
    close($readh);

    unless (@append){
	close ($writeh);
	return;
    }
    print $writeh '; '.localtime."\n\n";

    print $writeh join("\n",(map {$_->toString} 
			     (sort {$a->{date} <=> $b->{date}} 
			      @append)))."\n\n";

    close($writeh);

}

1;
