package Ledger;
use strict;
use warnings;
use Ledger::Transaction;
use Ledger::OFX;

sub new{
    my $class=shift;
    my $self={ transactions => [], accounts=>{} };
    bless $self, $class;
    return $self;
}

sub fromXMLstruct{
    my $self=shift;
    my $xml=shift;
    my $transactions=$xml->{transactions}->{transaction};
    $self->{transactions}=[map {Ledger::Transaction->new()->fromXMLstruct($_)} @{$transactions}];
    return $self
}

sub fromOFX{
    my $self=shift;
    my $ofx=shift;
    my $hints=shift;
    my $ofxdat=Ledger::OFX::parse($ofx);
    my ($account,$code)=&getaccount($ofxdat->{acctid},$hints->{accounts});
    
    foreach my $stmttrn (@{$ofxdat->{transactions}}){
	my $id=$code.'-'.$stmttrn->{id};
	my $payee=$stmttrn->{payee};
			
	my $transaction=new Ledger::Transaction 
	    ($stmttrn->{date}, "cleared", $stmttrn->{number}, 
	     $payee);
	push @{$self->{transactions}}, $transaction;
			
	my $commodity;
	if ($stmttrn->{commodity}){
	    $commodity=$ofxdat->{ticker}->{$stmttrn->{commodity}};
	}
	$transaction->addPosting($account, $stmttrn->{quantity},$commodity,
				 $stmttrn->{cost}," ID: $id");
	$transaction->balance($hints);
    }


    return $self;
    
}

sub getaccount{
    my ($acctid, $accounts)=@_;
    $acctid=~s/.*(....)$/$1/g;
    my $account=$accounts->{$acctid};
    my $code=(split(/:/,$account))[-1];
    $code=join ("", (map {substr ($_,0,1)} split (/\s+/, $code)));

    return ($account,$code);
}

# sub OFXbank{
#     my $self=shift;
#     my $ofx=shift;
#     my @transactions;
#     my ($stmtrs,$acctid);
#     if ($ofx->{'bankmsgsrsv1'}){
# 	$stmtrs=$ofx->{'bankmsgsrsv1'}->{'stmttrnrs'}->{'stmtrs'};
# 	$acctid=$stmtrs->{bankacctfrom}->{acctid}
#     }else{
# 	$stmtrs=$ofx->{'creditcardmsgsrsv1'}->{'ccstmttrnrs'}->{'ccstmtrs'};
# 	$acctid=$stmtrs->{ccacctfrom}->{acctid}
#     }
#     $acctid=~s/.*(....)$/$1/g;
#     my 	$stmttrns=$stmtrs->{'banktranlist'}->{'stmttrn'};    
#     $stmttrns=[$stmttrns] unless (ref($stmttrns) eq 'ARRAY');
#     foreach my $stmttrn (@{$stmttrns}){
# 	my $tran=new Ledger::Transaction($stmttrn->{date},
# 					 "cleared", $stmttrn->{checknum},  
# 					 $stmttrn->{memo}||$stmttrn->{name});
	
    


sub toString{
    my $self=shift;
    my $str=join("\n\n",map {$_->toString} @{$self->{transactions}});
    $str.="\n\n";
    return $str;
}
    
       
1;
