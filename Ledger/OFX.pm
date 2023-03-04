package Ledger::OFX;
use warnings;
use strict;
use Data::Dumper;
use Date::Parse;

my %XML=(lt => '<',
      amp => '&',
      gt => '>',
      quot => '"',
      apos => "'");

my %HANDLER=(
    'invbal' => \&invbal,
#    'invbal' => \&dump,
    'acctid' => \&acctid,
    'stmttrn' => \&stmttrn,
    'income' => \&inv,
    'invbuy' => \&inv,
    'invsell' => \&inv,
    'reinvest' => \&inv,
    'secinfo' => \&secinfo,
    'ledgerbal' => \&ledgerbal,
    'invpos' => \&invpos
);

my $xml;
my @xml;
my $data;
my $callback;

sub parsefile{
    my $file=shift;
    $callback=shift;
    local ($/);
    open (my $ofxh, '<', $file) || die "Can't open $file: $!"; 
    my $body=(<$ofxh>);
    close($ofxh);
    if ($body !~/OFXHEADER/){
	print STDERR "$file is not an OFX file\n";
	return "";
    }
    return &parse($body);
}

sub parse{
    my $body=shift;
    my %header=();
    my $header=substr $body,0,(index $body,'<'),'';
    
    return &parsebody($body);

}

sub parsebody{
    my $body=shift;
    my @context=();
    &init();
    while ($body){
	$body=~s/^\s+//;
	#print $body;
	if ($body=~/^</){
	    #start/end tag
	    my $start=index $body,'>';
	    my $tag=substr $body,0,$start+1,'';
	    chop $tag;
	    $tag=~s/^<//;
	    $tag="\L$tag";
	    if ($tag=~m@^/@){
		$tag=~s@^/@@;
		my $etag='';
		until ($etag eq $tag){
		     $etag=pop(@context);
		     &end(\@context,$etag);
		     
		}
		last if ($tag eq 'ofx');
	    }else{
		&start(\@context,$tag);

		push @context,$tag;
		
	    }
	}else{#if($body=~/\S/){
	    #char
	    my $start=index $body,'<';
	    my $str=substr $body,0,$start,'';
	    $str=~s/&(\w+);/$XML{$1}/ge;
	    $str=~s/\s+$//g;
	    &char(\@context,$str);
	    if ($body !~ m@^</@){
	     	my $tag=pop(@context);
	     	&end(\@context,$tag);
	    }
	   

	}
	
    }
    return &stop();
}


sub init{
    $xml=undef;
    @xml=();
    $data={};
}

sub start{
    my ($context,$tag)=@_;
    my $next={};
    $xml={} if $HANDLER{$tag};
    
    if ($xml && @{$context}){
	push @xml,$xml;
	if (ref($xml->{$context->[-1]}) eq 'HASH'){
	    if ($xml->{$context->[-1]}->{$tag}){
		$xml->{$context->[-1]}=[$xml->{$context->[-1]}];
		push @{$xml->{$context->[-1]}},$next;
	    }else{
		$next=$xml->{$context->[-1]}
	    }
	    
	}elsif(ref($xml->{$context->[-1]}) eq 'ARRAY'){
	    push @{$xml->{$context->[-1]}},$next;
	}else{
	    $xml->{$context->[-1]}=$next;
	    
	}
	$xml=$next;
    }
    
}

sub char{
    my ($context,$str)=@_;
    $xml->{$context->[-1]}=$str if $xml;
}

sub end{
     my ($context,$tag)=@_;
     if ($HANDLER{$tag}){
	 &{$HANDLER{$tag}}($xml->{$tag},$data);
	 undef $xml;
	 @xml=();
     }
     $xml=pop (@xml) if ($xml && @xml);
}

sub stop{
    foreach my $post (@{$data->{check}}){
	my $commodity=$data->{ticker}->{$post->{commodity}};
	$post->{commodity}=$commodity;
	if($post->{account}!~/$commodity$/){
	    $post->{account}.=":$commodity";
	}
    }
    $callback=undef;
    #print Dumper($data->{prices}); 
    return $data;
}

sub acctid{
    my ($arg,$data)=@_;
    $data->{acctid}=$arg;
}

sub dump{
    my ($arg,$data)=@_;
    print Dumper($arg);
}

sub stmttrn{
    my ($arg,$data)=@_;
    #return if $data->{type};# eq 'inv';
    my %tran;
    @tran{qw(type quantity id number)}=
	@{$arg}{qw(trntype trnamt fitid checknum)};
    if (! $tran{number} && $tran{type} eq 'ATM'){
	$tran{number}='ATM';
    }

    $tran{date}=&getdate($arg->{dtposted});
    if ($arg->{memo} && $arg->{memo} !~/^\d+$/ &&
	$arg->{memo} !~/^\w+$/){
	$tran{payee}=$arg->{memo};
    }else{
	$tran{payee}=$arg->{name};
    }
    my ($transaction, $posting)=&{$callback}(\%tran);
    $data->{transactions}||=$transaction;
}

sub inv{
    my ($arg,$data)=@_;
    my %tran;
    my $commodity;
    $data->{type}='inv';
    $data->{check}||=[];
    
    @tran{qw(id payee)}=@{$arg->{invtran}}{qw(fitid memo)};
    $tran{date}=&getdate($arg->{invtran}->{dttrade});
    my $secid=$arg->{secid}->{uniqueid};
    $commodity=$data->{ticker}->{$secid};
    if (!$secid || ($arg->{incometype} && $arg->{incometype} eq 'DIV')){
	        #($arg->{subacctsec} && $arg->{subacctsec} eq 'CASH')){
	$tran{quantity}=$arg->{units}||$arg->{total};
	$tran{type}=$arg->{incometype};
	$commodity="USD";
    }else{
	@tran{qw(quantity cost type)}=@{$arg}{qw(units total incometype)};
	$tran{cost}=-$tran{cost};
	$tran{commodity}=$commodity||$arg->{secid}->{uniqueid};
    }
    my ($transaction, $posting)=&{$callback}(\%tran);
    push @{$data->{check}},$posting if $posting && !$commodity;
    $data->{transactions}||=$transaction;
}


sub secinfo{
    my ($arg,$data)=@_;
    my $ticker=$arg->{ticker};
    $data->{ticker}||={};
    if ($ticker){
	$data->{ticker}->{$arg->{secid}->{uniqueid}}=$ticker;
    }else{
	$ticker=$arg->{secid}->{uniqueid};
    }

    $data->{prices}||={};
    $data->{prices}->{$ticker}={
	date  => &getdate($arg->{dtasof}),
	price => $arg->{unitprice}
    }
}	    
    



sub ledgerbal{
    my ($arg, $data)=@_;
    my %balance;
    @balance{qw(date quantity cost)}=(&getdate($arg->{dtasof}),
				      $arg->{balamt}, 'BAL');
    &{$callback}(\%balance) if $data->{transactions};
   
}

sub invbal{
    my ($arg, $data)=@_;
    my %balance;
    $balance{quantity}=$arg->{availcash};
    #return if $balance{quantity}==0;
    $balance{date}=&getdate($arg->{ballist}->[0]->{bal}->{dtasof});
    $balance{cost}='BAL';
    &{$callback}(\%balance) if $data->{transactions};
   
}

sub invpos{
    my ($arg, $data)=@_;
    return if $arg->{units}==0;
    my %balance;
    
    @balance{qw(date quantity cost)}=(&getdate($arg->{dtpriceasof}),
				      $arg->{units}, 'BAL');
    $balance{commodity}=$arg->{secid}->{uniqueid};

    if ($data->{transactions}){
	my ($transaction,$posting)=&{$callback}(\%balance);
	push @{$data->{check}},$posting;
    }
 
}


sub getdate{
    my $dtstr=shift;
    return str2time(substr($dtstr,0,8));
}



1;
