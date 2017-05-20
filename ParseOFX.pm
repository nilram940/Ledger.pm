#!/usr/bin/perl -w
package ParseOFX;

use strict;
use Date::Parse;

my %XML=(lt => '<',
      amp => '&',
      gt => '>',
      quot => '"',
      apos => "'");


sub parse{
    my $text=shift;
    my %header=();
    $text=~s/\r//g;
    my ($header,$body)=split(/\n\n/,$text,2);

    $body=~s/^\s+//;
    $body=~s/\s+$//;
    $body=~s/>\s+/>/g;
    my @ofx=parsebody($body);
    my $ofx=cleanofx(\@ofx);
    
    %header=split(/[:\n]/,$header);

    $ofx->{header}=\%header;
    
   

    return $ofx;
}

sub parsebody{
    my $body=shift;
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
	my @ret=("\L$tag",$descend?[&parsebody($arg)]:$arg);
	if($rest){
	    return (@ret,&parsebody($rest));
	}else{
	    return @ret;
	}
    }
}

sub cleanofx{
    my $ofxlist=shift;
    my %ofx;
    my ($tag,$value);

    while (@$ofxlist){
	$tag=shift @$ofxlist;
	$value=shift @$ofxlist;
	$value=&cleanofx($value) if (ref $value);

	if ($ofx{$tag}){
	    $ofx{$tag}=[$ofx{$tag}] unless (ref $ofx{$tag} eq 'ARRAY');
	    push @{$ofx{$tag}}, $value;
	}else{
	    if ($tag=~/^dt/){

		my $timestr=
		    substr($value,0,4,'').':'.
		    substr($value,0,2,'').':'.
		    substr($value,0,2,'').'T';

		if (length($value)>8){
		    $timestr.=
			substr($value,0,2,'').':'.
			substr($value,0,2,'').':';
		
		    $value=~/^(\d+(?:\.\d+)?)/;
		    $timestr.="$1 ";
		    if($value=~/\[-?\d+:(\w+)\]/){
			$timestr.='"'.$1.'"';
		    }
		}else{
		    $timestr.='00:00:00 ';
		}
		$ofx{$tag}=str2time($timestr);
		print STDERR $timestr."\n" unless ($ofx{$tag});
		
	    }else{
		$ofx{$tag}=$value;
	    }
	}
    }
    return \%ofx;
}
