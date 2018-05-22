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
    'acctid' => \&acctid,
    'stmttrn' => \&stmttrn,
    'invbuy' => \&inv,
    'reinvest' => \&inv,
    'secinfo' => \&secinfo,
    'ledgerbal' => \&ledgerbal,
    'invpos' => \&invpos
);

my $xml;
my @xml;
my $data;

sub parse{
    my $text=shift;
    my $dat={};
    my %header=();
    $text=~s/\r//g;
    my ($header,$body)=split(/<OFX>/,$text,2);
    $body='<OFX>'.$body;

    #$body=~s/^\s+//;
    #$body=~s/\s+$//;
    #$body=~s/>\s+/>/g;
    return &parsebody($body);

    #return $dat;
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
	    }else{
		&start(\@context,$tag);

		push @context,$tag;
		
	    }
	}elsif($body=~/\S/){
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
    return if $data->{type};# eq 'inv';
    $data->{transactions}||=[];
    my %tran;
    @tran{qw(type quantity id number)}=
	@{$arg}{qw(trntype trnamt fitid checknum)};
    $tran{date}=&getdate($arg->{dtposted});
    $tran{payee}=$arg->{memo}||$arg->{name};
    push @{$data->{transactions}},{%tran};
}

sub inv{
    my ($arg,$data)=@_;
    my %tran;
    $data->{type}='inv';
    $data->{transactions}||=[];
    
    @tran{qw(id payee)}=@{$arg->{invtran}}{qw(fitid memo)};
    $tran{date}=&getdate($arg->{invtran}->{dttrade});
    $tran{commodity}=$data->{ticker}->{$arg->{secid}->{uniqueid}}||
	$arg->{secid}->{uniqueid};
    @tran{qw(quantity cost type)}=@{$arg}{qw(units total incometype)};
    $tran{cost}=-$tran{cost};
    push @{$data->{transactions}},{%tran};
}


sub secinfo{
    my ($arg,$data)=@_;
    $data->{ticker}||={};
    $data->{ticker}->{$arg->{secid}->{uniqueid}}=$arg->{ticker};
}

sub ledgerbal{
    my ($arg, $data)=@_;
    $data->{balance}={};
    @{$data->{balance}}{qw(date quantity)}=(&getdate($arg->{dtasof}),
						   $arg->{balamt});
}

sub invpos{
    my ($arg, $data)=@_;
    return if $arg->{units}==0;
    my %balance;
    
    @balance{qw(date quantity)}=(&getdate($arg->{dtpriceasof}),
				 $arg->{units});
    $balance{commodity}=$arg->{secid}->{uniqueid};
    $data->{balance}={%balance};
 
}


sub getdate{
    my $dtstr=shift;
    return str2time(substr($dtstr,0,8));
}



1;
