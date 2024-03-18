package Ledger::JSON::Teller;
use warnings;
use strict;
use Date::Parse;
use JSON;

sub getTeller{
    my ($json,$callback)=@_;
    my $accounts=&getaccounts($json,$callback);


    return 1; #(transactions=>\@trlist);

}

    
my %lia=(
    credit => 1,
    loan => 1
);

sub getaccounts{
    my $account_list=shift;
    my $callback=shift;
    my $accounts={};
    foreach my $account (@{$account_list}){
        my $islia=$lia{$account->{type}}||0;
        my $ledgername=($islia)?"Liabilities":"Assets";
        $ledgername.=":".$account->{subtype}.":".($account->{official_name}||$account->{name});
        $ledgername=~s/\s+/ /g;
        $ledgername=~s/[^: A-Z]//gi;
        $ledgername=~s/([\w']+)/\u\L$1/g;
        my $balance=$account->{balances}->{ledger};
        $balance=-$balance if ($islia);
        my $acct={
            ledgername => $ledgername,
            balance => $balance,
            islia => $islia,
            lasttrans => 0,
        };
        $accounts->{$account->{account_id}}=$acct;
        &addtransactions($acct,$callback,$account->{transactions});
        &addbalance($acct,$callback) if ($acct->{lasttrans}>0);
        
    }
    return $accounts;
}

sub addtransactions{
    my $account=shift;
    my $callback=shift;
    my $transactions=shift;
    foreach my $transaction (@{$transactions}){
        my %tran;
        @tran{qw(quantity payee id)}=
            @{$transaction}{qw(amount description id)};
        if ($tran{payee}=~/CHECK.*?(\d+)/){
            $tran{number}=int($1);
        }
            
        $tran{state}=($transaction->{details}->{processing_status} eq 'complete')?'cleared':'pending';
        $tran{payee}||=$transaction->{details}->{counterparty};
        $tran{date}=str2time($transaction->{date});
        #$tran{quantity}=-$tran{quantity} if $account->{islia};
        $tran{account}=$account->{ledgername};
        $tran{pendid}=$transaction->{pending_transaction_id}
                    if $transaction->{pending_transaction_id};
        my ($t,$p)=&{$callback}(\%tran);
        if ($t && ($tran{state} eq 'cleared')){
            $account->{lasttrans}=$tran{date}  if ($tran{date}>$account->{lasttrans});
        }
    }
    
}



sub addbalance{
    my $account=shift;
    my $callback=shift;
    return unless $account->{lasttrans}>0;
    my %balance;
    @balance{qw(account date quantity cost)}=
        (@{$account}{qw(ledgername lasttrans balance)}, 'BAL');
    &{$callback}(\%balance);
        
    
}


1;	
