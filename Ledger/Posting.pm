package Ledger::Posting;

sub new{
    my $class=shift;
    my $self={ account   => "",
	       amount    => "",
	       commodity => "",
	       price     => "",
	       note      => ""
    }
    bless $self, $class;
    return $self;
}

