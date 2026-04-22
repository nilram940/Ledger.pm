package Ledger;
use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);
use Storable;
use YAML::Tiny;
use Ledger::Transaction;
use Ledger::OFX;
use Ledger::JSON;
use Ledger::XML;
use Ledger::CSV;
use POSIX qw(strftime);
#use Data::Dumper;

sub new{
    my $class=shift;
    my %args=@_;

    if ($args{file} && $args{useCache}) {
        my $store = "$args{file}.store";
        if (-f $store && (stat($args{file}))[9] <= (stat($store))[9]) {
            print STDERR "store cache: $store\n";
            return retrieve($store);
        }
    }

    my $self={ transactions => [],
	       balance=>{}};
    bless $self, $class;
    $self->{desc}=($args{payeetab} && (-f $args{payeetab}))
	? _read_payeetab($args{payeetab}):{};
    $self->{accounts}=$args{accounttab}?$self->getacctnum($args{accounttab}):{};
    $self->{id}={};
    $self->{payeetab}=$args{payeetab};
    $self->{idtag}=$args{idtag} || 'ID';

    Ledger::CSV::ledgerCSV($self, $args{file});

    $self->gentable unless $args{noClassify};

    if ($args{file} && $args{useCache}) {
        my $store = "$args{file}.store";
        my $tmp   = "$store.$$";
        eval { store($self, $tmp) && rename($tmp, $store) };
        warn "object cache write failed: $@\n" if $@;
    }

    return $self;
}

sub _read_payeetab {
    my $file = shift;
    my $yaml = eval { YAML::Tiny->read($file) };
    my $h = ($yaml && ref $yaml->[0] eq 'HASH') ? $yaml->[0]
           : (Storable::retrieve($file) // {});
    my ($first) = values %$h;
    # Old flat format has string values; migrate to read-only __global__ bucket.
    return defined($first) && !ref($first) ? { __global__ => $h } : $h;
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
    my $commodity=$transaction->{postings}->[0]->{commodity};
    return unless $commodity;

    $self->{balance}->{$account} ||={};

    my $bal=$self->{balance}->{$account};

    unless ($bal->{$commodity} &&
	$transaction->{date}< $bal->{$commodity}->{date}){
	$bal->{$commodity}=$transaction;
    }
    
    # if ($self->{balance}->{$account}){
    # 	if ($transaction->{date}>$self->{balance}->{$account}->[0]->{date}){
    # 	    $self->{balance}->{$account}=[$transaction];
    # 	}elsif($transaction->{date}==$self->{balance}->{$account}->[0]->{date}){
    # 	    push @{$self->{balance}->{$account}},$transaction;
    # 	}
    # }else{
    # 	$self->{balance}->{$account}=[$transaction];
    # }
    #print STDERR Dumper ($self->{balance});
    return $bal->{$commodity};
}

sub fromXML{
    my $self=shift;
    my $xml=shift;
    Ledger::XML::parse($self,$xml);
    return $self
}

sub fromStmt{
    # read Stmt and convert to Ledger data structure.
    # expects files to be named $account-$date.$type
    # Supports OFX and CSV;
    
    my $self=shift;
    my $stmt=shift;
    my $handlers=shift;
    my $csv=shift;

    if (-z $stmt) {
        print STDERR "Skipping empty file $stmt\n";
        return
    }
            
    
    my $account=$stmt;
    $account=~s/-.*//;
    $account=~s!.*/!!;
    $account=~s/\..*//;

    my $callback=sub{
	my $stmtrns=shift;
	if ($stmtrns->{cost} && $stmtrns->{cost} eq 'BAL'){
	    $self->addStmtBal($account,$stmtrns);
	}else{
	    $self->addStmtTran($account,$handlers,$stmtrns);
	}
    };

    unless (exists $self->{cleared_file}){
	$self->getinsertionpoints;
    }

    if ($stmt=~/.[oq]fx$/i){
	&Ledger::OFX::parsefile($stmt, $callback);
    }elsif ($stmt=~/.csv$/i){
	&Ledger::CSV::parsefile($stmt, $csv->{$account}, $callback);
    }elsif ($stmt=~/.json$/i){
        &Ledger::JSON::parsefile($stmt, $callback);
    }
    return $self;

}


sub StmtHandler{
    my $self=shift;
    return ($_[2]->{cost} && $_[2]->{cost} eq 'BAL') ? $self->addStmtBal(@_):
	$self->addStmtTran(@_);
}
	
sub addStmtBal{
    my $self=shift;
    my $accdef=shift;
    my $balance=shift;
    my $account=$balance->{account}||$accdef;
    
    my $payee=(split(/:/, $account))[-1];
    $payee.=' Balance';
	
    my $transaction=new Ledger::Transaction
	($balance->{date},"cleared",undef,$payee);

    my $posting=$transaction->addPosting($account,$balance->{quantity}+0,$balance->{commodity},'BAL');
    $self->addBalance($account,$transaction);
    $posting=undef unless ($balance->{commodity} && $balance->{commodity}=~/^\d+/);
    return ($transaction,$posting);
    
}


sub addStmtTran{
    my $self=shift;
    my $accdef=shift;
    my $handlers=shift;
    my $stmttrn=shift;
    my $account=$stmttrn->{account}||$accdef;
    
    my $key=&makeid($account,$stmttrn);
    my $payee=$stmttrn->{payee};

    
    if ($self->{id}->{$key}){
	$self->{desc}->{$account} //= {};
	$self->{desc}->{$account}->{$payee}=$self->{id}->{$key};
	$self->{desc}->{__global__} //= {};
	$self->{desc}->{__global__}->{$payee}=$self->{id}->{$key};
	return;
    }
    $self->{id}->{$key}=$payee;
    return if ($stmttrn->{quantity} == 0);
    my $cleanpay=$payee;
    $cleanpay=~s/\s+\*{3}.*$//;
        
    my $acct_handlers = $handlers->{$account} || {};
    my $acct_desc     = { %{$self->{desc}->{__global__} || {}},
                          %{$self->{desc}->{$account}  || {}} };

    my $handler = $acct_handlers->{$payee}
               || $acct_handlers->{$acct_desc->{$payee} || ""}
               || $acct_handlers->{$cleanpay}
               || _token_lookup($acct_handlers, $payee);

    if ($handler && ref ($handler) eq 'HASH'){
	$payee=$handler->{payee};
    } elsif ($acct_desc->{$payee}) {
	$payee=$acct_desc->{$payee};
    } else {
        my $desc_payee = _token_lookup($acct_desc, $payee);
        $payee = $desc_payee if $desc_payee;
    }
    my $transaction=new Ledger::Transaction 
	($stmttrn->{date}, $stmttrn->{state} || "cleared", $stmttrn->{number}, 
	 $payee);
    $transaction->scheduleAppend($self->insertionFileFor($transaction->{state}));
    
    my $posting=$transaction->addPosting($account, $stmttrn->{quantity}+0,
					 $stmttrn->{commodity},
					 ($stmttrn->{cost}||0)+0,"ID: $key");
    if ($handler){
	if (ref ($handler) eq 'HASH'){
	    $transaction=$self->transfer($transaction,$handler->{transfer})
	}else{
	    $transaction=&{$handler}($transaction);
	}
    }
    if ($transaction) {
        $posting->{pendid}=$stmttrn->{pendid} if $stmttrn->{pendid};
        my $tag=$transaction->balance($self->{table},
                                      $self->getTransactions('uncleared'));
        $transaction=$self->transfer($transaction,$tag) if $tag;
        $self->addTransaction($transaction);
    }

    $posting=undef unless ($stmttrn->{commodity} && $stmttrn->{commodity}=~/^\d+/);
    return ($transaction,$posting);

}

sub getinsertionpoints {
    my $self = shift;
    my @txns = grep { $_->{file} && $_->{date} > 0 } @{$self->{transactions}};

    # Last transaction of each state (determines which file owns each state)
    my ($lc) = reverse grep { $_->{state} eq 'cleared' } @txns;
    my ($lp) = reverse grep { $_->{state} eq 'pending' } @txns;
    my ($lu) = reverse grep { $_->{state} eq ''        } @txns;

    # File routing with fallbacks per FR-014 spec
    $self->{cleared_file}   = $lc ? $lc->{file} : undef;
    $self->{pending_file}   = $lp ? $lp->{file}
                            : ($lu ? $lu->{file} : undef);
    $self->{uncleared_file} = $lu ? $lu->{file} : $self->{cleared_file};

    # Backward-compat aliases
    $self->{ofxfile} = $self->{cleared_file};

    # Insertion point within each file: bpos of the first later-state txn, else EOF
    for my $target (qw(cleared pending uncleared)) {
        my $file = $self->{"${target}_file"} or next;
        my @in_file = grep { $_->{file} eq $file } @txns;
        my @blockers =
            $target eq 'cleared' ? grep { $_->{state} ne 'cleared' } @in_file :
            $target eq 'pending' ? grep { $_->{state} eq ''        } @in_file :
                                   ();  # uncleared always goes to EOF

        if (@blockers) {
            my $first = (sort { $a->{epos} <=> $b->{epos} } @blockers)[0];
            $first->findtext;
            $self->{"${target}_pos"} = $first->{bpos};
        } else {
            $self->{"${target}_pos"} = (stat($file))[7];
        }
    }

    # Backward-compat alias
    $self->{ofxpos} = $self->{cleared_pos};
}

sub insertionFileFor {
    my ($self, $state) = @_;
    return $self->{cleared_file}   if $state eq 'cleared';
    return $self->{pending_file}   if $state eq 'pending';
    return $self->{uncleared_file};
}


sub getTransactions{
    my $self=shift;
    my $filter=shift||'';
    
    if (ref($filter)){
	return grep &{$filter}($_), @{$self->{transactions}};
    }
    if ($filter eq 'cleared'){
	return grep {$_->{state} eq 'cleared'} @{$self->{transactions}};
    }    
    if ($filter eq 'uncleared'){
	return grep {$_->{state} ne 'cleared'} @{$self->{transactions}};
    }
    if ($filter eq 'balance'){
	return (map {values %$_} (values %{$self->{balance}}));
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
    my $amtkey=sprintf('%.2f',$amount);
    my $key="$tag-$amtkey";

    $self->{transfer}->{$key}||=[];
    my $transfer=$self->{transfer}->{$key};
    my $idx=0;

    while ($idx < @{$transfer}){
        my ($other,$opost)=@{$transfer->[$idx]};
        my $datediff=abs($transaction->{date}-$other->{date})/(24*3600);
        if (abs($opost->cost()+
                $transaction->getPosting(0)->cost())<.0001
            && $datediff <= 5){
            splice(@{$transfer},$idx,1);
            delete $self->{transfer}->{$key} unless @{$transfer};

            # Ensure edit markers are set so the matched transaction gets rewritten.
            $other->scheduleEdit() unless $other->{edit};
            # Rewrite the matched posting to Equity for uncleared/pending transactions
            # (e.g. auto-categorised as Expenses/Assets before the transfer was recognised).
            if ($opost->{account} ne $account && $other->{state} ne 'cleared'){
                $opost->{account}=$account;
            }

            if ($datediff < 1){
                $other->{state}=$transaction->{state}
                    if $transaction->{state} eq 'cleared';
                # Find the posting whose account matches the incoming account so
                # we update the right slot (e.g. posting[0] for a Checking import
                # that matches a 'Checking-N' queue entry).  Fall back to 1 when
                # not found (the normal Equity:Transfers placeholder case).
                my $new_acct=$transaction->getPosting(0)->{account};
                my $target=1;
                for my $i (0..$#{$other->{postings}}){
                    if ($other->getPosting($i)->{account} eq $new_acct){
                        $target=$i; last;
                    }
                }
                $other->setPosting($target,$transaction->getPosting(0));
                $other->{payee}=$transaction->{payee}
                    if (length($transaction->{payee})>length($other->{payee}));
                return undef;
            }else{
                $transaction->addPosting($account);
                return $transaction;
            }
        }
        $idx++;
    }

    # No match — park it
    push @{$transfer},[$transaction, $transaction->getPosting(0)];
    $transaction->addPosting($account);
    return $transaction;
}

sub transfer2{
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
    $id.='!' if $trdat->{state} && ($trdat->{state} eq 'pending');
    $id.='-';
    $id.=$trdat->{salt}.'-' if $trdat->{salt};
    
    if ($trdat->{id}){
	$id.=$trdat->{id};
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

    
sub gentable {
    my $self = shift;
    my $table = {};

    foreach my $transaction ($self->getTransactions()) {
        my $source = $transaction->getPosting(0)->{account};
        my $amount = $transaction->getPosting(0)->{quantity} // 0;
        my $dest_p = $transaction->getPosting(-1);
        next unless $dest_p;
        my $dest   = $dest_p->{account} // '';
        my $note   = $dest_p->{note}    // '';

        # Skip equity postings except learned transfer destinations
        next if $dest =~ /^Equity:/ && $dest !~ /^Equity:Transfers:/;
        # Skip balance assertion pseudo-postings
        next if $dest_p->{cost} && $dest_p->{cost} eq 'BAL';
        # Skip auto-categorised results — INFO: means the library was uncertain
        next if $note =~ /INFO:/;

        my @tokens = Ledger::Transaction::_tokenize($transaction->{payee});
        # Encode amount magnitude as a feature token
        my $bracket = ($amount < 0 ? 'neg' : 'pos') .
                      length(sprintf('%.2f', abs($amount)));
        push @tokens, "__amt_$bracket";

        $table->{$source} ||= { prior => { __total__ => 0 },
                                 tokens => {}, vocab => {} };
        my $src = $table->{$source};

        $src->{prior}{$dest}++;
        $src->{prior}{__total__}++;

        for my $tok (@tokens) {
            $src->{tokens}{$dest}{$tok}++;
            $src->{tokens}{$dest}{__total__}++;
            $src->{vocab}{$tok} = 1;
        }
    }

    # Precompute vocab size once for Laplace smoothing in finddest
    for my $src (values %$table) {
        $src->{vocab_size} = scalar keys %{$src->{vocab}};
    }

    $self->{table} = $table;
    return $self;
}

sub _token_lookup {
    my ($map, $payee) = @_;
    my @tokens = Ledger::Transaction::_tokenize($payee);
    return undef unless @tokens;

    my $best_val;
    my $best_len = 0;
    for my $key (keys %$map) {
        my @key_toks = Ledger::Transaction::_tokenize($key);
        next unless @key_toks;
        # All key tokens must appear in the payee tokens
        my %pay_toks = map { $_ => 1 } @tokens;
        next if grep { !$pay_toks{$_} } @key_toks;
        # Prefer the most-specific (longest-key-token) match
        if (scalar(@key_toks) > $best_len) {
            $best_len = scalar(@key_toks);
            $best_val = $map->{$key};
        }
    }
    return $best_val;
}

sub toString{
    my $self=shift;
    my $str=join("\n\n",map {$_->toString} (sort {$a->{date} <=> $b->{date}} @{$self->{transactions}}),(sort {$a->{date} <=> $b->{date}} map {@$_} (values %{$self->{balance}})));
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

    
sub update{
    my $self=shift;
    YAML::Tiny->new($self->{desc})->write($self->{payeetab}) if $self->{payeetab};
    
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
        $transaction->{edit_pos} ||= $transaction->{bpos};
    }
    close($fd) if $fd;
    
			  
    my %files=map {($_->{file}?
		    ($_->{file}=>1, $_->{edit}=>1):
		    ($_->{edit}=>1))} @edit;

    # Ensure the cleared_file is written even when @edit is empty (e.g. all
    # incoming transactions were deduplicated but balance entries remain).
    $files{$self->{cleared_file}} = 1
        if $self->{cleared_file} && %{$self->{balance}};

    foreach $file (keys %files){
	$self->update_file($file);
    }
}

sub update_file{
    my $self=shift;
    my $file=shift;

    # Sentinels for this file: pos => [states] for each state whose file matches
    my %sentinels;
    for my $state (qw(cleared pending uncleared)) {
        my $sfile = $self->{"${state}_file"} // next;
        next unless $sfile eq $file;
        push @{$sentinels{$self->{"${state}_pos"}}}, $state;
    }
    my $is_cleared_file = ($self->{cleared_file} && $self->{cleared_file} eq $file);

    my @edit= (grep {$_->{edit} &&
			 (($_->{file} &&
			   $_->{file} eq $file) ||
			  $_->{edit} eq $file)}
	       @{$self->{transactions}});
    my @append=grep {$_->{edit} eq $file && $_->{edit_pos}<0} @edit;

    # Partition @append by state so each sentinel writes only its own transactions
    my %append_for = (
        cleared   => [grep { $_->{state} eq 'cleared' } @append],
        pending   => [grep { $_->{state} eq 'pending' } @append],
        uncleared => [grep { $_->{state} eq ''        } @append],
    );

    my $posfilter=sub {
    	my $t=shift;
    	my %pos=();
	unless ($t->{edit}){
	    print STDERR "edit=".$t->toString."\n";
	}
    	if ($t->{edit} eq $file && $t->{edit_pos}>=0){
    	    $pos{$t->{edit_pos}}=$t;
    	}
    	if ($t->{file} && $t->{file} eq $file){
    	    $pos{$t->{bpos}}=$t;
    	}
    	%pos;
    };

    my %posmap = map &{$posfilter}($_),  (@edit);

    my @balance_entries = sort { $a->{date} <=> $b->{date} }
                              map { values %$_ } (values %{$self->{balance}});

    # Register sentinels in posmap for each state that has transactions or balance entries.
    # Use //= so an existing in-place edit at a sentinel position is not overwritten;
    # the @append_for entries then fall through to the EOF block instead.
    for my $spos (keys %sentinels) {
        my $has_content = 0;
        for my $state (@{$sentinels{$spos}}) {
            $has_content = 1 if @{$append_for{$state}};
            $has_content = 1 if $state eq 'cleared' && @balance_entries;
        }
        $posmap{$spos} //= -1 if $has_content;
    }

    my $lastpos=0;
    my $balance_written = 0;
    print STDERR "file=$file\n";

    # Write to a temp file first so a crash never destroys the original.
    # The .bak is kept as a safety copy regardless of outcome.
    my $tmpfile = "$file.tmp$$";
    rename($file, "$file.bak") || die "Cannot backup $file: $!";

    eval {
        open(my $writeh, '>', $tmpfile) || die "Cannot write $tmpfile: $!";
        open(my $readh,  '<', "$file.bak") || die "Cannot read $file.bak: $!";

        foreach my $pos (sort {$a <=> $b} (keys %posmap)){
            my $transaction=$posmap{$pos};

            my $len=$pos-$lastpos-1;
            die "update_file: negative offset (pos=$pos lastpos=$lastpos) in $file\n"
                if $len < 0;
            seek ($readh, $lastpos, SEEK_SET);
            read $readh, (my $buffer), $len;
            print $writeh $buffer;

            if (ref($transaction)){
                $lastpos=(($pos == $transaction->{bpos})?
                          $transaction->{epos}:
                          $transaction->{edit_end});
                if (($transaction->{edit} eq $file) &&
                    ($transaction->{edit_pos} == $pos)) {
                    print $writeh "\n".$transaction->toString();
                }
                # When the cleared sentinel position is claimed by a ref entry
                # (in-place edit or bpos skip), emit pending cleared appends and
                # balance entries here instead of at EOF.
                if ($is_cleared_file && $pos == $self->{cleared_pos}) {
                    my @to_write = sort { $a->{date} <=> $b->{date} } @{$append_for{cleared}};
                    my @bal = $balance_written ? () : @balance_entries;
                    if (@to_write || @bal) {
                        print $writeh "\n; ".localtime."\n\n" if @to_write;
                        print $writeh join("\n", map { $_->toString } (@to_write, @bal))."\n\n";
                        $append_for{cleared} = [] if @to_write;
                        $balance_written = 1 if @bal;
                    }
                }
            } elsif (exists $sentinels{$pos}) {
                # Sentinel: write each state's transactions at this position
                for my $state (@{$sentinels{$pos}}) {
                    my @to_write = sort { $a->{date} <=> $b->{date} } @{$append_for{$state}};
                    my @bal = ($state eq 'cleared') ? @balance_entries : ();
                    next unless @to_write || @bal;
                    print $writeh "\n; ".localtime."\n\n" if @to_write;
                    print $writeh join("\n",
                        (map { $_->toString } (@to_write, @bal))
                    )."\n\n";
                    $append_for{$state} = [];
                    $balance_written = 1 if $state eq 'cleared';
                }
                $lastpos=$pos;
            }
        }

        # copy remainder of file
        seek ($readh, $lastpos, SEEK_SET);
        my $buflen = 1024;
        my $buffer;
        while (!eof($readh)) {
            read $readh, $buffer, $buflen;
            print $writeh $buffer;
        }
        close($readh);

        my @remaining_bal = ($is_cleared_file && !$balance_written) ? @balance_entries : ();
        my @remaining_append = map { @{$append_for{$_}} } qw(cleared pending uncleared);
        if (@remaining_append || @remaining_bal) {
            my @cleared   = grep { $_->{state} eq 'cleared'  } @remaining_append;
            my @uncleared = grep { $_->{state} ne 'cleared'  } @remaining_append;
            print $writeh '; '.localtime."\n\n" if @cleared || @uncleared;
            print $writeh join("\n",
                (map { $_->toString }
                    (sort { $a->{date} <=> $b->{date} } @cleared),
                    @remaining_bal,
                    (sort { $a->{date} <=> $b->{date} } @uncleared)
                ))."\n\n";
        }
        close($writeh);

        rename($tmpfile, $file) || die "Cannot install $tmpfile as $file: $!";
    };
    if ($@) {
        my $err = $@;
        unlink $tmpfile if -f $tmpfile;
        # Restore original if the destination is absent or zero-length
        rename("$file.bak", $file) unless -s $file;
        die $err;
    }

}

1;
