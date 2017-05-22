package Ledger;

sub new{
    my $class=shift;
    my $self={ transactions => [] }
    bless $self, $class;
    return $self;
}


       
