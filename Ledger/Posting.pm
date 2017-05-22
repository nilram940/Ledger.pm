package Ledger::Posting;
use strict;
use warnings;

sub new{
    my $class=shift;
    my $self={};
    @{$self}{qw(account quantity commodity cost note)}=@_;
    
    # my $self={ account   => "",
    # 	       amount    => "",
    # 	       commodity => "",
    # 	       price     => "",
    # 	       note      => ""
    # }
    
    bless $self, $class;
    return $self;
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
    my $str=sprintf('     %-40s  ',$self->{account});
    if ($self->{commodity} eq '$'){
	$str.=sprintf('$%0.2f',$self->{quantity});
    }else{
	$str.=$self->{quantity}.' '.$self->{commodity}.
	    ' @@ $'.sprintf('%0.2f',$self->{cost});
    }
    $str.=' ; '.$self->{note} if $self->{note};
    return $str;
}

1;
