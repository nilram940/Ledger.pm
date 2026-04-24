package Ledger::CSV::HSA;
use strict;
use warnings;

sub fingerprint { qr/^Transaction Date,Transaction Type,Claimant,Description/ }

sub type { 'HSA' }

sub new {
    my ($class, $file, %opts) = @_;
    return bless {
        file    => $file,
        config  => $class->config(%opts),
        account => $opts{account},
    }, $class;
}

sub account {
    my ($self, $val) = @_;
    $self->{account} = $val if @_ > 1;
    return $self->{account};
}

sub parse {
    my ($self, $callback) = @_;
    require Ledger::CSV;
    my $account = $self->{account};
    my $cb = $account
        ? sub { my $csv = shift; $csv->{account} ||= $account; $callback->($csv) }
        : $callback;
    return Ledger::CSV::parsefile($self->{file}, $self->{config}, $cb);
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
            $csv->{assert} = $csv->{available_balance} + 0
                if $csv->{state} eq 'cleared'
                && defined $csv->{available_balance}
                && length $csv->{available_balance};
        },
    };
}

1;
