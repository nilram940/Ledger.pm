package Ledger::Transaction;
use strict;
use warnings;
use Ledger::Posting;
use Date::Parse;
use POSIX qw(strftime);
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);
    
sub new{
    my $class=shift;
    # my $self={ date  => 0,
    # 	       state => "",
    # 	       payee => "",
    # 	       code  => "",
    # 	       note  => "",
    # 	       postings => []};
    my $self={postings => []};
    @{$self}{qw(date state code payee note)}=@_;
    $self->{$_}||='' foreach (qw(date state code payee note));
    bless $self, $class;
    return $self;
}

sub scheduleEdit {
    my ($self, $file) = @_;
    $file //= $self->{file};
    $self->findtext if $file && !$self->{bpos};
    $self->{edit}     = $file;
    $self->{edit_pos} = $self->{bpos} || 0;
    $self->{edit_end} = $self->{epos};
}

sub scheduleAppend {
    my ($self, $file) = @_;
    $self->{edit}     = $file;
    $self->{edit_pos} = -1;
}

sub scheduleDelete {
    my ($self, $file) = @_;
    $file //= $self->{file};
    $self->findtext if $file && !$self->{bpos};
    $self->{edit}     = $file;
    $self->{edit_pos} = $self->{bpos} || 0;
    $self->{edit_end} = $self->{epos};
    $self->{deleted}  = 1;
}

sub findtext{
    my ($self, $fh)=@_;
    my $close=0;
    unless ($fh){
	open($fh,'<',$self->{file}) || die "Can't open ".$self->{file}.": $!";
	$close=1;
    }
    #assume no bpos
    
    my $len=200;
    my $bpos=$self->getPosting(0)->{bpos};
    unless ($bpos){
	$self->{bpos}=-1;
	return $self;
    }
    my $pos=$bpos-$len;
    if ($pos<0){
	$len+=$pos;
	$pos=0;
    }
    #read $len bytes prior to begining of first posting
    #from file and find the last newline
    seek ($fh, $pos, SEEK_SET);
    read $fh, (my $str), $len-1; 
    my $idx=rindex $str,"\n";

    #set character after last newline as beginning of transaction.
    $self->{bpos}=$pos+$idx+1;
    
    # read characters between bpos and epos as transaction text;
    seek ($fh, $self->{bpos}, SEEK_SET);
    if ($self->{bpos}>$self->{epos}){
	die "Negative length $self->{payee}";
    }
    read $fh, (my $trstr), ($self->{epos}-$self->{bpos});
    $self->{text}=$trstr;
    close($fh) if $close;
    return $self;
}

sub addPosting{
    my $self=shift;
    my $posting;
    if (ref $_[0]){
	$posting=shift;
    }else{
	$posting=new Ledger::Posting(@_);
    }
    push @{$self->{postings}},$posting; 
    return $posting;
}

sub getPosting{
    my $self=shift;
    my $num=shift;
    return $self->{postings}->[$num];
}

sub getPostings{
    my $self=shift;
    return @{$self->{postings}};
}

sub setPosting{
    my $self=shift;
    my $num=shift;
    my $posting;
    if (ref $_[0]){
	$posting=shift;
    }else{
	$posting=new Ledger::Posting(@_);
    }
    $self->{postings}->[$num]=$posting; 
}
    
    
	
my %STATE=(
    'cleared' => " * ",
    'pending' => " ! "
    );

sub toString{
    my $self = shift;
    return unless $self->{date};
    if ($self->{text} && !$self->{edit}){
	return $self->{text};
    }
    my $str=strftime('%Y/%m/%d', localtime $self->{date});
    $str.="=".strftime('%Y/%m/%d', localtime $self->{'aux-date'}) 
	if $self->{'aux-date'};
    $str.=($self->{state} && $STATE{$self->{state}})?$STATE{$self->{state}}:"   ";
    $str.='('.$self->{code}.') ' if $self->{code};
    $str.=$self->{payee};
    $str.='     ;'.$self->{note} if ($self->{note});
    $str.="\n";
    $str.=join("\n",map {$_->toString()} (@{$self->{postings}}))."\n";
    # if ($self->{text}){
    # 	my $orig=$self->{text};
    # 	$orig=~s/^/; /mg;
    # 	$str.="\n".$orig;
    # }
    return $str;
}

sub balance{
    my $self=shift;
    my $table=shift;
    my @pending=@_;
    my $tag;
    return if ($self->checkpending(@pending) ||
	       $self->getPosting(1));

    my ($account,$prob)=&finddest($self->{postings}->[0]->{account},
				  $self->{postings}->[0]->{quantity},
				  $self->{payee},
				  $table);
    my $info=$prob>0?"INFO: UNKNOWN ($prob%)":'';
    unless($account){
	$account=($self->{postings}->[0]->{quantity}>0)?
	    'Income:Miscellaneous':
	    'Expenses:Miscellaneous';
	$info="INFO: UNKNOWN (0.00%)";
    }
    if ($account=~/^Equity:Transfers:(.+)/){
        $tag=$1;
    }elsif ($account=~/^Lia|^Ass/){
        if ($self->{postings}->[0]->{quantity}<0){
            $tag=$account
        }else{
            $tag=$self->{postings}->[0]->{account}
        }
        $tag=(split(/:/, $tag))[-1];
    }else{
        $self->addPosting($account,undef,undef,undef,$info)
    }
    return $tag;
	
}

sub checkpending{
    my $self=shift;
    return 0 unless ($self->{state} eq "cleared" || $self->{state} eq "pending");
    my @pending=@_;
    #print STDERR $self->{payee}."\n";
    my $candidate=(sort {$a->[0] <=> $b->[0]}
		   (map {[$self->distance($_), $_]}
		    grep { $_ -> {date} }
		    @pending))[0];
    return 0 unless ($candidate && $candidate->[0] < 1);
    my $match=$candidate->[1];
    if (0){
	print "Found Match...\n";
	print $candidate->[-1]->toString();
	print "\n\n";
	print $self->toString();
	print "\n\nScore: ",$candidate->[0],"\n\n";
    }
    

    $candidate=$candidate->[-1];

    if ($self->{transfer}){
	my $posting=$candidate->getPosting(1 - $match); #Assumes only 2 postings
	if ($posting->{account} !~/^Equity/ &&
	    $posting->{account} !~/^(Assets|Liabilities)/ &&
	    $posting->{account} ne $self->getPosting(1)->{account}){
	    $candidate->scheduleEdit();
	    $candidate->setPosting($match, 
				   'Equity:Transfers:'.$self->{transfer});
	    return 1;
	}
    }
    my $orig_state=$candidate->{state};
    $candidate->{state}=$self->{state};
    $candidate->{'aux-date'}=$candidate->{date}
           unless ($candidate->{'aux-date'} || ($candidate->{date} == $self->{date}));
    $candidate->{date}=$self->{date};
    if ($self->{file}){
	# Imported transaction is itself in a file — write it at that position
	$self->findtext unless $self->{bpos};
	$candidate->{edit}=$self->{edit}||$self->{file};
	$candidate->{edit_pos}=$self->{bpos};
	$candidate->{edit_end}=$self->{epos};
    }elsif($candidate->{file}){
	if ($orig_state ne 'cleared' && $candidate->{state} eq 'cleared'){
	    # Pending → cleared: delete from pending position, append at cleared_pos.
	    # Use the incoming statement transaction's edit file (cleared_file) when
	    # available, so multi-file setups route to the right destination.
	    $candidate->scheduleAppend($self->{edit} || $candidate->{file});
	}else{
	    # New import matched an existing uncleared — overwrite in the ledger
	    $candidate->scheduleEdit();
	}
    }else{
	$candidate->scheduleAppend($self->{edit}||$self->{file});
    }
    #$candidate->{edit_pos}=$self->{bpos};
    $self->getPosting(0)->{bpos}=$candidate->getPosting($match)->{bpos};
    $self->getPosting(0)->{epos}=$candidate->getPosting($match)->{epos};
    $candidate->setPosting($match, $self->getPosting(0));
    my $last = $#{$candidate->{postings}};
    $candidate->getPosting($last)->{quantity}='' if $match < $last;
    %{$self}=%{$candidate};

    $candidate->{date} = 0;
    $candidate->{edit} = '';
    return 1;
}


sub _tokenize {
    my $payee = lc(shift // '');
    return grep { /[a-z]/ } split(/[^a-z0-9]+/, $payee);
}

sub finddest {
    my ($account, $amount, $payee, $table) = @_;
    my $src = $table->{$account} or return (undef, 0);
    my $prior = $src->{prior}    or return (undef, 0);
    my $total = $prior->{__total__} || 1;

    my $bracket = ($amount < 0 ? 'neg' : 'pos') .
                  length(sprintf('%.2f', abs($amount // 0)));
    my @tokens = (_tokenize($payee), "__amt_$bracket");

    my $vocab_size = $src->{vocab_size} || 1;

    my %lp;
    for my $cat (grep { $_ ne '__total__' } keys %$prior) {
        my $tok_counts = $src->{tokens}{$cat} || {};
        my $tok_total  = $tok_counts->{__total__} || 0;

        $lp{$cat} = log($prior->{$cat} / $total);
        for my $tok (@tokens) {
            $lp{$cat} += log((($tok_counts->{$tok} || 0) + 1) /
                             ($tok_total + $vocab_size));
        }
    }

    return (undef, 0) unless %lp;

    my ($best) = sort { $lp{$b} <=> $lp{$a} } keys %lp;

    # Numerically stable softmax confidence
    my $max = $lp{$best};
    my $sum  = 0;
    $sum += exp($lp{$_} - $max) for keys %lp;
    my $conf = sprintf('%.2f', 100 / $sum);

    # Negative signals high confidence (>= 90%, >= 3 training examples)
    # Caller (balance()) adds an INFO: note when prob > 0
    my $prob = ($conf >= 90 && $prior->{$best} >= 3) ? -$conf : $conf;

    return ($best, $prob);
}

sub distance{
    my $self=shift;
    my $comp=shift;
    if ($self->{code}=~/^\d+$/){
	if ($comp->{code}=~/^\d+$/ && $self->{code} == $comp->{code}){
	    return (0,0);
	}else{
	    return (10,0);
	}
    } #Check numbers are the gold standard
    
    my ($account,$quantity,$id)=
        @{$self->getPosting(0)}{qw(account quantity pendid)};
    my $subdist=($self->{date}-$comp->{date})/(5*24*3600);
    my $dist=$subdist*$subdist;
    my $num=-1;
    my $lim=$#{$comp->{postings}}+1;

    #print "lim: $lim\n";
    ++$num while ($num < $lim) && 
	($account ne $comp->getPosting($num)->{account});
    #print "num: $num\n";
    if ($num<$lim){
        my $compid;
        if ($id && ($compid=$comp->getPosting($num)->getid())){
            $compid=~s/^[^-]*-//;
            if ($compid eq $id ){
                return (0,$num);
            }else{
                return (10,$num);
            }
        }
                
	if ($quantity==0){
	    $subdist=10*($comp->getPosting($num)->{quantity}-$quantity);
	}else{
	    $subdist=10*($comp->getPosting($num)->{quantity}-$quantity)/$quantity;
	}
    }else{
	$subdist=10;
    }
    $dist+=$subdist*$subdist;

    my @comp_tokens = _tokenize($comp->{payee});
    if (@comp_tokens) {
        my %self_toks = map { $_ => 1 } _tokenize($self->{payee});
        my $matches = grep { $self_toks{$_} } @comp_tokens;
        $subdist = 1 - $matches / scalar(@comp_tokens);
    } else {
        $subdist = 0;
    }
    $dist += $subdist * $subdist;

    return sqrt($dist), $num;
}
1;
    
