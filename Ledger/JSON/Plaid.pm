package Ledger::JSON::Plaid;
use warnings;
use strict;
use Date::Parse;
use JSON;

sub getPlaid{
    my ($json,$callback)=@_;
    my $securities=&getsecurities($json->{securities});
    my $accounts=&getaccounts($json->{accounts},$securities);

    &addtransactions($accounts,$callback,$json->{transactions});
    &addinvestments($accounts,$callback,$json->{investment_transactions},$securities);
    &addbalances($accounts,$callback);

    return 1; #(transactions=>\@trlist);

}

    
my %lia=(
    credit => 1,
    loan => 1
);

sub getaccounts{
    my $account_list=shift;
    my $securities=shift;
    my $accounts={};
    foreach my $account (@{$account_list}){
        my $islia=$lia{$account->{type}}||0;
        my $ledgername=($islia)?"Liabilities":"Assets";
        $ledgername.=":".$account->{subtype}.":".($account->{official_name}||$account->{name});
        $ledgername=~s/\s+/ /g;
        $ledgername=~s/[^: A-Z]//gi;
        $ledgername=~s/([\w']+)/\u\L$1/g;
	$ledgername=~s/(\bMC\b)/\U$1/i;
        my $balance=$account->{balances}->{current};
        $balance=-$balance if ($islia);
        foreach my $sec (values %{$securities}){
            my $ledgename=$ledgername;
            my $commodity=$sec->{ticker_symbol};
            $ledgename.=":".$commodity
                   unless ($commodity=~/USD/); 
            $accounts->{$account->{account_id}}->{$commodity} = {
                ledgername => $ledgename,
                balance => $balance,
                islia => $islia,
                lasttrans => 0,
                commodity => $commodity,
            }
        }
    }
    return $accounts;
}

sub addtransactions{
    my $accounts=shift;
    my $callback=shift;
    my $transactions=shift;
    foreach my $transaction (@{$transactions}){
        my $account=$accounts->{$transaction->{account_id}}->{"CUR:USD"};
        my %tran;
        @tran{qw(quantity payee id number)}=
            @{$transaction}{qw(amount merchant_name transaction_id check_number)};
        $tran{state}=$transaction->{pending}?'pending':'cleared';
        $tran{payee}||=$transaction->{name};
        $tran{date}=str2time($transaction->{date});
        $tran{quantity}=-$tran{quantity}; #if $account->{islia};
        $tran{account}=$account->{ledgername};
        $tran{pendid}=$transaction->{pending_transaction_id}
                    if $transaction->{pending_transaction_id};
        my ($t,$p)=&{$callback}(\%tran);
        if ($t && ($tran{state} eq 'cleared')){
            $account->{lasttrans}=$tran{date}  if ($tran{date}>$account->{lasttrans});
        }
    }
}

sub addinvestments{
    my $accounts=shift;
    my $callback=shift;
    my $transactions=shift;
    my $securities=shift;
    foreach my $transaction (@{$transactions}){
        my $secid=$transaction->{security_id}||"USD";
        my $commodity=$securities->{$secid}->{ticker_symbol};
        my $account=$accounts->{$transaction->{account_id}}->{$commodity};
        my %tran;
        @tran{qw(payee id)}=
            @{$transaction}{qw(name investment_transaction_id)};
        $tran{state}='cleared';
        if ($commodity=~/USD/){
            $tran{quantity}=$transaction->{amount};
        }else{
            @tran{qw(quantity cost)}=
                @{$transaction}{qw(quantity amount)};
            $tran{commodity}=$commodity;
        }
        $tran{date}=str2time($transaction->{date});
        $tran{account}=$account->{ledgername};
        my ($t,$p)=&{$callback}(\%tran);
        if ($t && ($tran{state} eq 'cleared')){
            $account->{lasttrans}=$tran{date}
            if ($tran{date}>$account->{lasttrans});
        }
    }
}

sub getsecurities{
    my $seclist=shift;
    my $securities={USD =>{ticker_symbol => 'CUR:USD'}};
    foreach my $sec (@{$seclist}){
        $securities->{$sec->{security_id}}=$sec;
    }
    return $securities;
}

sub addbalances{
    my $accounts=shift;
    my $callback=shift;
    foreach my $security (values %{$accounts}){
        foreach my $account (values %{$security}){
            next unless $account->{lasttrans}>0;
            my %balance;
            @balance{qw(account date quantity cost)}=
                (@{$account}{qw(ledgername lasttrans balance)}, 'BAL');
            &{$callback}(\%balance);
        }
    }
}

1;	
