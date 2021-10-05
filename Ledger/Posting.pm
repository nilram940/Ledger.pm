package Ledger::Posting;
use strict;
use warnings;

sub new{
    my $class=shift;
    my $self={};
    @{$self}{qw(account quantity commodity cost note)}=@_;
    $self->{commodity}||='$';
    
    # my $self={ account   => "",
    # 	       amount    => "",
    # 	       commodity => "",
    # 	       price     => "",
    # 	       note      => ""
    # }
    
    bless $self, $class;
    return $self;
}

sub cost{
    my $self=shift;
    return $self->{commodity} eq '$' ? $self->{quantity}:$self->{cost};
}

sub fromXMLstruct{
    my $self=shift;
    my $xml=shift;
    $self->{account}=$xml->{account}->{name};
    $self->{note}=$xml->{note};
    $self->{quantity}=$xml->{'post-amount'}->{amount}->{quantity};
    $self->{commodity}=$xml->{'post-amount'}->{amount}->{commodity}->{symbol};
    $self->{cost}=$xml->{cost}?$xml->{cost}->{quantity}:0;
    return $self;
}

sub toString{
    my $self=shift;
    my $bal=($self->{cost} && $self->{cost} eq 'BAL');
    my $str=$bal?sprintf('     %-40s   = ','['.$self->{account}.']'):
	sprintf('     %-40s   ',$self->{account});
    if (defined($self->{quantity})){
	if ($self->{commodity} eq '$'){
	    $str.=sprintf('$%0.2f',$self->{quantity});
	}else{
	    my $commodity=$self->{commodity};
	    $commodity = '"'.$commodity.'"' if $commodity =~/[^A-Z]/i;
	    $str.=$self->{quantity}.' '.$commodity;
	    if ($self->{cost} && ! $bal){
		$str.=' @@ $'.sprintf('%0.2f',$self->{cost});
	    }
	}
    }
    $str.=' ; '.$self->{note} if $self->{note};
    return $str;
}

1;
