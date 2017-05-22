package Ledger::Transaction;

sub new{
    my $class=shift;
    my $self={ date  => 0,
	       state => "",
	       payee => "",
	       code  => "",
	       note  => "",
	       postings => []}
    bless $self, $class;
    return $self;
}
