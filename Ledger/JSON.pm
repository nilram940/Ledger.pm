package Ledger::JSON;
use Ledger::JSON::Plaid;
use Ledger::JSON::Teller;
use warnings;
use strict;
use Date::Parse;
use JSON;

sub new {
    my ($class, $file) = @_;
    return bless { file => $file }, $class;
}

sub parse {
    my ($self, $callback) = @_;
    return parsefile($self->{file}, $callback);
}

sub parsefile{
    my ($file,$callback)=@_;
    my $json=&readjson($file);
    if (ref $json eq ref {}){
        return &Ledger::JSON::Plaid::getPlaid($json,$callback);
    }else{
        return &Ledger::JSON::Teller::getTeller($json,$callback);
    }
    
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
    

1;	
