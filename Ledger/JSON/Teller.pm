package Ledger::JSON::Teller;
use warnings;
use strict;
use Date::Parse;
use Data::Dumper;
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

my %typemap=(
    'credit' => 'Credit Card',
    'depository' => 'Current Assets'
    );
sub getaccounts{
    my $account_list=shift;
    my $callback=shift;
    my $accounts={};
    foreach my $account (@{$account_list}){
        my $islia=$lia{$account->{type}}||0;
        my $ledgername=($islia)?"Liabilities":"Assets";
	my $accname=($account->{official_name}||$account->{name});
	my $insname=$account->{institution}->{name};
	if (lc(substr $accname,0,4) ne lc(substr $insname,0,4)) {
	    $accname=$insname.' '.$accname;
	}
        $ledgername.=":".$typemap{$account->{type}}.":".$accname;
        $ledgername=~s/_/ /g;
        $ledgername=~s/\s+/ /g;
        $ledgername=~s/[^: A-Z]//gi;
        $ledgername=~s/\s+$//;
        $ledgername=~s/([\w']+)/\u\L$1/g;
        $ledgername=~s/(usaa )/\U$1/gi;
        my $balance=$account->{balances}->{ledger};
        $balance=-$balance if ($islia);
        my $acct={
            ledgername => $ledgername,
            balance => $balance,
            islia => $islia,
            lasttrans => 0,
        };
        $accounts->{$account->{id}}=$acct;
        &addtransactions($acct,$callback,$account->{transactions});
        &addbalance($acct,$callback) if ($acct->{lasttrans}>0);
        
    }
    return $accounts;
}

sub addtransactions{
    my $account=shift;
    my $callback=shift;
    my $transactions=shift;
    my $neg=0;
    if ($account->{islia}) {
	if ($transactions->[0]->{type} ne 'payment') {
	    $neg= ($transactions->[0]->{amount} > 0)
	}else{
	    $neg = ($transactions->[0]->{amount} < 0)
	}
    }
    foreach my $transaction (@{$transactions}){
        my %tran;
        @tran{qw(quantity payee id)}=
            @{$transaction}{qw(amount description id)};
        if ($tran{payee}=~/CHECK.*?(\d+)/){
            $tran{number}=int($1);
        }
            
        $tran{state}=($transaction->{status} eq 'pending')?'pending':'cleared';
	# if ($transaction->{details}->{counterparty}->{name}){
	#     $tran{payee}=$transaction->{details}->{counterparty}->{name};
	# }
        $tran{date}=str2time($transaction->{date});
        $tran{quantity}=-$tran{quantity} if $neg;
        $tran{account}=$account->{ledgername};
        $tran{pendid}=$transaction->{pending_transaction_id}
                    if $transaction->{pending_transaction_id};
        my ($t,$p)=&{$callback}(\%tran);
        if ($t && ($tran{state} eq 'cleared') && ($tran{date}>$account->{lasttrans})){
	    print STDERR "Updating lasttrans:", $account->{ledgername}, "\n";
	    print STDERR Dumper($transaction);
            $account->{lasttrans}=$tran{date};  
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
