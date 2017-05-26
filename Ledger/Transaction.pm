package Ledger::Transaction;
use strict;
use warnings;
use Ledger::Posting;
use Date::Parse;
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
    
    
sub fromXMLstruct{
    my $self=shift;
    my $xml=shift;
    @{$self}{qw (state payee code note)}=
	@{$xml}{qw(state payee code note)};
    $self->{date}=str2time($xml->{date});
    my $postings=$xml->{postings}->{posting};
    $self->{postings}=[map {Ledger::Posting->new()->fromXMLstruct($_)} (@{$postings})];
    return $self;
}
	
	
sub toString{
    my $self=shift;
    my $str=strftime('%Y/%m/%d', localtime $self->{date});
    $str.=($self->{state} eq "cleared")?" * ":"   ";
    $str.='('.$self->{code}.') ' if $self->{code};
    $str.=$self->{payee};
    $str.='     ;'.$self->{note} if ($self->{note});
    $str.="\n";
    $str.=join("\n",map {$_->toString} (@{$self->{postings}}));
    return $str;
}

sub balance{
    my $self=shift;
    my $hints=shift;
    my ($account,$prob)=&finddest($self->{postings}->[0]->{account},
				  $self->{payee},
				  $hints->{table});
    $self->addPosting($account,undef,undef,undef,"INFO: UNKNOWN ($prob)")
	
	
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

1;
