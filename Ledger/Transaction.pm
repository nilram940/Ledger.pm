package Ledger::Transaction;
use strict;
use warnings;
use Ledger::Posting;
use Date::Parse;
use Text::Levenshtein;
use POSIX qw(strftime);
    
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
    
    
	
	
sub toString{
    my $self=shift;
    return unless $self->{date};
    my $str=strftime('%Y/%m/%d', localtime $self->{date});
    $str.=($self->{state} && $self->{state} eq "cleared")?" * ":"   ";
    $str.='('.$self->{code}.') ' if $self->{code};
    $str.=$self->{payee};
    $str.='     ;'.$self->{note} if ($self->{note});
    $str.="\n";
    $str.=join("\n",map {$_->toString} (@{$self->{postings}}));
    return $str;
}

sub balance{
    my $self=shift;
    my $table=shift;
    my @pending=@_;
    return if ($self->checkpending(@pending) ||
	       $self->getPosting(1));

    my ($account,$prob)=&finddest($self->{postings}->[0]->{account},
				  $self->{payee},
				  $table);
    $self->addPosting($account,undef,undef,undef,"INFO: UNKNOWN ($prob)")
	
	
}

sub checkpending{
    my $self=shift;
    my @pending=@_;
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
    $candidate->{state}='cleared';

    return 1 if ($self->{transfer});

    $candidate->{date}=$self->{date};
    $candidate->setPosting($match, $self->getPosting(0));
    $candidate->getPosting(-1)->{quantity}='';
    %{$self}=%{$candidate};
    $candidate->{date} = 0;
    return 1;
}


sub finddest{
    my ($account,$desc,$table)=@_;
    my $dcount=$table->{$account}->{$desc}||
	$table->{$account}->{'@@account default@@'};
    my $dest=(sort {$dcount->{$b} <=> $dcount->{$a}} 
	      grep (!/total/, keys %{$dcount}))[0];

    my $prob=$dest?sprintf("%.2f%%",100*$dcount->{$dest}/$dcount->{total}):0;
    return ($dest,$prob);
}

sub distance{
    my $self=shift;
    my $comp=shift;
    if ($self->{code}=~/^\d+$/){
	if ($comp->{code}=~/^\d+$/ && $self->{code} == $comp->{code}){
	    return 0;
	}else{
	    return 10;
	}
    } #Check numbers are the gold standard
    
    my ($account,$quantity)=@{$self->getPosting(0)}{qw(account quantity)};
    my $subdist=($self->{date}-$comp->{date})/(4*24*3600);
    my $dist=$subdist*$subdist;
    my $num=-1;
    my $lim=$#{$comp->{postings}}+1;

    #print "lim: $lim\n";
    ++$num while ($num < $lim) && 
	($account ne $comp->getPosting($num)->{account});
    #print "num: $num\n";
    if ($num<$lim){
	if ($quantity==0){
	    $subdist+=10*($comp->getPosting($num)->{quantity}-$quantity);
	}else{
	    $subdist+=10*($comp->getPosting($num)->{quantity}-$quantity)/$quantity;
	}
    }else{
	$subdist=10;
    }
    $dist+=$subdist*$subdist;

    
    $subdist=Text::Levenshtein::distance(lc($self->{payee}),lc($comp->{payee}));
    $subdist=10*$subdist/length($self->{payee});
    $dist+=$subdist*$subdist;
				
    return sqrt($dist), $num;
}

1;
    
