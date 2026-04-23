package Ledger::CSV::HSA;
use strict;
use warnings;

sub fingerprint { qr/^Transaction Date,Transaction Type,Claimant,Description/ }

sub new {
    my ($class, $file, %opts) = @_;
    return bless { file => $file, config => $class->config(%opts) }, $class;
}

sub parse {
    my ($self, $callback) = @_;
    require Ledger::CSV;
    return Ledger::CSV::parsefile($self->{file}, $self->{config}, $callback);
}

sub config {
    my ($class, %opts) = @_;
    return {
        header_map => {
            date              => 'Transaction Date',
            transaction_type  => 'Transaction Type',
            payee             => 'Description',
            quantity          => 'Amount',
            status            => 'Status',
            available_balance => 'Available Balance',
        },
        running_balance => 'available_balance',
        process => sub {
            my $csv = shift;
            # account set from #LedgerName: at top of file
            $csv->{state} = ($csv->{status} =~ /pending/i) ? 'pending' : 'cleared';
            # CSV amounts are always positive; Card transactions are debits.
            # Card refunds will be mis-signed here and should show as balance
            # assertion failures in ledger, to be corrected manually.
            $csv->{quantity} = -abs($csv->{quantity} + 0)
                if $csv->{transaction_type} =~ /\bcard\b/i;
            $csv->{payee} ||= $csv->{transaction_type};
        },
    };
}

1;
