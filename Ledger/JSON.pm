package Ledger::JSON;
use warnings;
use strict;
use Date::Parse;
use JSON;

sub parsefile{
    my ($file,$callback)=@_;
    my $json=&readjson($file);
    my $accounts=&getaccounts($json->{accounts});

    &addtransactions($accounts,$callback,$json->{transactions});
    &addbalances($accounts,$callback);

    return 1; #(transactions=>\@trlist);

}

sub readjson{
    my $file=shift;
    my $fd;
    local $/;
    if (ref $file){
	$fd=$file;
    }else{
	open($fd, "<", $file) || die "Can't open $file: $!";
    }
    my $json=from_json(<$fd>);
    close($fd) unless $fd eq $file;
    return $json;
}
    
my %lia=(
    credit => 1,
    loan => 1
);

sub getaccounts{
    my $account_list=shift;
    my $accounts={};
    foreach my $account (@{$account_list}){
        my $islia=$lia{$account->{type}}||0;
        my $ledgername=($islia)?"Liabilities":"Assets";
        $ledgername.=":".$account->{subtype}.":".($account->{official_name}||$account->{name});
        $ledgername=~s/\s+/ /g;
        $ledgername=~s/[^: A-Z]//gi;
        $ledgername=~s/([\w']+)/\u\L$1/g;
        my $balance=$account->{balances}->{current};
        $balance=-$balance if ($islia);
        $accounts->{$account->{account_id}}={
            ledgername => $ledgername,
            balance => $balance,
            islia => $islia,
            lasttrans => 0,
        }
        
    }
    return $accounts;
}

sub addtransactions{
    my $accounts=shift;
    my $callback=shift;
    my $transactions=shift;
    foreach my $transaction (@{$transactions}){
        my $account=$accounts->{$transaction->{account_id}};
        my %tran;
        @tran{qw(quantity payee id number)}=
            @{$transaction}{qw(amount merchant_name transaction_id check_number)};
        $tran{state}=$transaction->{pending}?'pending':'cleared';
        $tran{payee}||=$transaction->{name};
        $tran{date}=str2time($transaction->{date});
        $tran{quantity}=-$tran{quantity} if $account->{islia};
        $tran{account}=$account->{ledgername};
        $tran{pendid}=$transaction->{pending_transaction_id}
                    if $transaction->{pending_transaction_id};
        my ($t,$p)=&{$callback}(\%tran);
        if ($t && ($tran{state} eq 'cleared')){
            $account->{lasttrans}=$tran{date}  if ($tran{date}>$account->{lasttrans});
        }
    }
}

sub addbalances{
    my $accounts=shift;
    my $callback=shift;
    foreach my $account (values %{$accounts}){
        next unless $account->{lasttrans}>0;
        my %balance;
        @balance{qw(account date quantity cost)}=
            (@{$account}{qw(ledgername lasttrans balance)}, 'BAL');
        &{$callback}(\%balance);
    }
}

1;	
