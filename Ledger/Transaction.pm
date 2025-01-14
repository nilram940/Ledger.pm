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
    my $self=shift;
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
    $str.=join("\n",map {$_->toString} (@{$self->{postings}}))."\n";
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
    if ($account=~/^Lia|^Ass/){
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
	    $posting->{account} ne $self->getPosting(1)->{account}){ 
	    if ($candidate->{file} && ! $candidate->{bpos}){
		$candidate->findtext;
	    }
	    $candidate->{edit}=$candidate->{file};
	    $candidate->{edit_pos}=$candidate->{bpos};
	    $candidate->{edit_end}=$candidate->{epos};
	    $candidate->setPosting($match, 
				   'Equity:Transfers:'.$self->{transfer});
	    return 1;
	}
    }
    $candidate->{state}=$self->{state};
    $candidate->{'aux-date'}=$candidate->{date} 
           unless $candidate->{date} == $self->{date};
    $candidate->{date}=$self->{date};
    $candidate->{edit}=$self->{edit}||$self->{file};
    if ($self->{file}){
	$self->findtext unless $self->{bpos};
	$candidate->{edit_pos}=$self->{bpos};
    }else{
	$candidate->{edit_pos}=-1;
    }
    $candidate->{edit_end}=$self->{epos};
    #$candidate->{edit_pos}=$self->{bpos};
    $self->getPosting(0)->{bpos}=$candidate->getPosting($match)->{bpos};
    $self->getPosting(0)->{epos}=$candidate->getPosting($match)->{epos};
    $candidate->setPosting($match, $self->getPosting(0));
    $candidate->getPosting(-1)->{quantity}='';
    %{$self}=%{$candidate};

    $candidate->{date} = 0;
    $candidate->{edit} = '';
    return 1;
}


sub finddest{
    my ($account,$amount,$desc,$table)=@_;
    my $bracket=($amount<0?-1:1)*length(sprintf('%.2f',abs($amount)));
    my $dcount=$table->{$account}->{$desc.'-'.$bracket}||
	$table->{$account}->{'@@account default@@-'.$bracket};
    my $dest=(sort {$dcount->{$b} <=> $dcount->{$a}} 
	      grep (!/total/, keys %{$dcount}))[0];

    my $prob=$dest?sprintf("%.2f",100*$dcount->{$dest}/$dcount->{total}):0;
    if ($prob > 99.99999 && $dcount->{total}>12){
	$prob=-$prob;
    }
    return ($dest,$prob);
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

    my $len=length($comp->{payee});
    my $payee=lc(substr $self->{payee},0,$len);
    #print STDERR $payee."\n";
    #$subdist=Text::Levenshtein::distance($payee,lc($comp->{payee}));
    $subdist=strdist($payee,lc($comp->{payee}));
    $subdist=$subdist/$len;
    $dist+=$subdist*$subdist;
				
    return sqrt($dist), $num;
}
sub strdist{
    my ($str1, $str2)=@_;
    my $str1len=length($str1);
    my $str2len=length($str2);
    my $dist=($str1len-$str2len);
    my $stop=$str2len;
    
    if ($dist<0){
	$dist=-$dist;
	$stop=$str1len;
    }

    foreach my $i (0..$stop){
	if (substr($str1,$i,1) ne substr($str2,$i,1)){
	    $dist++;
	}
    }
    return $dist;
}
1;
    
