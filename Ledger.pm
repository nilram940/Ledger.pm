package Ledger;
use strict;
use warnings;
use Ledger::Transaction;

sub new{
    my $class=shift;
    my $self={ transactions => [] };
    bless $self, $class;
    return $self;
}

sub fromXMLstruct{
    my $self=shift;
    my $xml=shift;
    my $transactions=$xml->{transactions}->{transaction};
    $self->{transactions}=[map {Ledger::Transaction->new()->fromXMLstruct($_)} @{$transactions}];
    return $self
}

sub toString{
    my $self=shift;
    my $str=join("\n\n",map {$_->toString} @{$self->{transactions}});
    return $str;
}
    
       
1;
