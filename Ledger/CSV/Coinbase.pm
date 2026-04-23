package Ledger::CSV::Coinbase;
use strict;
use warnings;

sub fingerprint { qr/^Timestamp,Transaction Type,Asset,Quantity Transacted/ }

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
            date     => 'Timestamp',
            txn_type => 'Transaction Type',
            asset    => 'Asset',
            quantity => 'Quantity Transacted',
            total    => 'Total (inclusive of fees and/or spread)',
        },
        process => sub {
            my $csv  = shift;
            my $type  = $csv->{txn_type} // '';
            my $asset = $csv->{asset}    // '';
            if ($type =~ /^buy$/i) {
                $csv->{commodity} = $asset;
                $csv->{cost}      = abs($csv->{total} + 0);
                $csv->{account}  .= ":$asset" if $asset =~ /\S/;
            } elsif ($type =~ /^sell$/i) {
                $csv->{commodity} = $asset;
                $csv->{cost}      = abs($csv->{total} + 0);
                $csv->{quantity}  = -abs($csv->{quantity} + 0);
                $csv->{account}  .= ":$asset" if $asset =~ /\S/;
            } elsif ($type =~ /^(?:receive|send)$/i) {
                $csv->{account} = "Equity:Transfers:$asset";
            } elsif ($type =~ /rewards income/i) {
                $csv->{commodity} = $asset;
                $csv->{account}  .= ":$asset" if $asset =~ /\S/;
            }
            $csv->{state} = 'cleared';
        },
    };
}

1;
