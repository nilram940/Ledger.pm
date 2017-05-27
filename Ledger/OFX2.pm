package Ledger::OFX2;
use warnings;
use strict;
use Date::Parse;

my %XML=(lt => '<',
      amp => '&',
      gt => '>',
      quot => '"',
      apos => "'");

my %HANDLER=(
    'acctid' => \&acctid,
    'stmttrn' => \&stmttrn,
    'invbuy' => \&inv,
    'reinvest' => \&inv,
    'secinfo' => \&secinfo,
    'ledgerbal' => \&ledgerbal,
    'invpos' => \&invpos
);


sub parse{
    my $text=shift;
    my $dat={};
    my %header=();
    $text=~s/\r//g;
    my ($header,$body)=split(/\n\n/,$text,2);

    $body=~s/^\s+//;
    $body=~s/\s+$//;
    $body=~s/>\s+/>/g;
    &parsebody($body,$dat);

    return $dat;
}

sub parsebody{
    my $body=shift;
    my $data=shift || {};
    #print $body,"\n";
    if ($body=~/^</){
	my $start=index $body,'>';
	my $tag=substr $body,1,$start-1;
	my $descend=(substr($body,$start+1,1) eq '<');
	my $stop=index($body,$descend?"</$tag>":'<',$start);
	my $arg=($stop>-1)?substr($body,$start+1,$stop-$start-1):substr($body,$start+1);
	$arg=~s/&(\w+);/$XML{$1}/ge;
	$arg=~s/^\s+//g;
	$arg=~s/\s+$//g;

	my $rest=($stop>-1)?substr($body,$descend?length($tag)+3+$stop:$stop):"";
	$rest=~s/^<\/$tag>//;
	$tag="\L$tag";
	my @ret=("$tag",$descend?[&parsebody($arg,$data)]:$arg);
	#print "$tag ",$HANDLER{$tag},"\n";
	if ($HANDLER{$tag}){
	    &{$HANDLER{$tag}}(\@ret,$data);
	}
	if($rest){
	    return (@ret,&parsebody($rest,$data));
	}else{
	    return @ret;
	}
    }
}

sub acctid{
    my ($arg,$data)=@_;
    $data->{acctid}=$arg->[1];
}

sub dump{
    my ($arg,$data)=@_;
    print Dumper($arg);
}

sub stmttrn{
    my ($arg,$data)=@_;
    return if $data->{type};# eq 'inv';
    my %tran=(@{$arg->[1]});
    $data->{transactions}||=[];
    my %rtran;
    @rtran{qw(type quantity id number)}=
	@tran{qw(trntype trnamt fitid checknum)};
    $rtran{date}=&getdate($tran{dtposted});
    $rtran{payee}=$tran{memo}||$tran{name};
    push @{$data->{transactions}},{%rtran};
}

sub inv{
    my ($arg,$data)=@_;
    my %buy=(@{$arg->[1]});
    my %tran;
    $data->{type}='inv';
    $data->{transactions}||=[];
    my %invtran=(@{$buy{invtran}});
    my %secid=(@{$buy{secid}});
    
    @tran{qw(id payee)}=@invtran{qw(fitid memo)};
    $tran{date}=&getdate($invtran{dttrade});
    $tran{commodity}=$data->{ticker}->{$secid{uniqueid}}||$secid{uniqueid};
    @tran{qw(quantity cost type)}=@buy{qw(units total incometype)};
    $tran{cost}=-$tran{cost};
    push @{$data->{transactions}},{%tran};
}


sub secinfo{
    my ($arg,$data)=@_;
    my %secinfo=(@{$arg->[1]});
    my %secid=(@{$secinfo{secid}});
    $data->{ticker}||={};
    $data->{ticker}->{$secid{uniqueid}}=$secinfo{ticker};
}

sub ledgerbal{
    my ($arg, $data)=@_;
    my %ledgerbal=@{$arg->[1]};
    $data->{balance}={};
    @{$data->{balance}}{qw(date quantity)}=(&getdate($ledgerbal{dtasof}),
						   $ledgerbal{balamt});
}

sub invpos{
    my ($arg, $data)=@_;
    my %invpos=@{$arg->[1]};
    return if $invpos{units}==0;
    my %secid=(@{$invpos{secid}});
    my %balance;
    
    @balance{qw(date quantity)}=(&getdate($invpos{dtpriceasof}),
					$invpos{units});
    $balance{commodity}=$secid{uniqueid};
    $data->{balance}={%balance};
 
}


sub getdate{
    my $dtstr=shift;
    return str2time(substr($dtstr,0,8));
}

1;
