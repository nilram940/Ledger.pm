package Ledger::CSV::HSA;
use strict;
use warnings;

sub fingerprint { qr/^Transaction Date,Transaction Type,Claimant,Description/ }

sub config {
    my ($class, %opts) = @_;
    return {
        header_map => {
            date              => 'Transaction Date',
            payee             => 'Description',
            quantity          => 'Amount',
            status            => 'Status',
            available_balance => 'Available Balance',
        },
        running_balance => 'available_balance',
        process => sub {
            my $csv = shift;
            $csv->{state} = ($csv->{status} =~ /pending/i) ? 'pending' : 'cleared';
        },
    };
}

1;
