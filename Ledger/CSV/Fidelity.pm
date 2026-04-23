package Ledger::CSV::Fidelity;
use strict;
use warnings;

sub fingerprint { qr/^Run Date,Account,Account Number,Action/ }

sub config {
    my ($class, %opts) = @_;
    my $account_map = $opts{account_map} // {};
    my $buy_re  = qr/bought|buy|contribution|reinvestment/i;
    my $sell_re = qr/sold|sell|redemption/i;
    return {
        header_map => {
            date           => 'Run Date',
            account_number => 'Account Number',
            action         => 'Action',
            symbol         => 'Symbol',
            payee          => 'Description',
            contrib_type   => 'Type',
            price_col      => 'Price ($)',
            shares         => 'Quantity',
            quantity       => 'Amount ($)',
        },
        process => sub {
            my $csv = shift;
            my $base = $account_map->{$csv->{account_number}}
                       // $csv->{account_number};
            my $action = $csv->{action} // '';
            if ($action =~ $buy_re || $action =~ $sell_re) {
                my $amt = $csv->{quantity} + 0;
                $amt = $csv->{price_col} * abs($csv->{shares})
                    if !$amt && $csv->{price_col};
                $csv->{cost}      = abs($amt);
                $csv->{quantity}  = $csv->{shares} + 0;
                $csv->{quantity}  = -$csv->{quantity} if $action =~ $sell_re;
                $csv->{commodity} = $csv->{symbol};
                $base .= ":$csv->{symbol}" if ($csv->{symbol}//'') =~ /\S/;
            }
            $base .= ":$csv->{contrib_type}"
                if ($csv->{contrib_type}//'') =~ /\S/;
            $csv->{account} = $base;
            $csv->{state}   = 'cleared';
        },
    };
}

1;
