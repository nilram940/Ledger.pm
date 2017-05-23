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
    push @{$self->{postings}}, new Ledger::Posting(@_);
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
}

1;
