package Ledger::XML;
use strict;
use warnings;
use Date::Parse;
use XML::Parser;
use Ledger;


my %HANDLERS=(
    Init  => \&init,
    Start => \&start,
    End   => \&end,
    Char  => \&char,
    Final => \&stop);


my @TREE;
my ($ledger,$transaction,$posting);

#($LEDGER,undef,$TRANSACTION,undef,$POSTING)

 
sub parsefile{
    my $self=shift;
    my $file=shift;
    my $parser=new XML::Parser('Handlers' => \%HANDLERS);
    $ledger=$self;
    return $parser->parsefile($file);
}

sub parse{
    my $self=shift;
    my $str=shift;
    my $parser=new XML::Parser('Handlers' => \%HANDLERS);
    $ledger=$self;
    return $parser->parse($str);
}

sub init{
    my $p=shift;
    $ledger||=new Ledger();
    @TREE=();
}

sub start{
    my ($p,$elt,%arg)=@_;
    #unshift @TREE,$elt;
    if ($elt eq 'transaction'){
	$transaction=$ledger->addTransaction();
	$transaction->{state}=$arg{state}||'';
    }elsif ($elt eq 'posting'){
	$posting=$transaction->addPosting();
    }
}

{
    my %post=(
	'account->name' => 'account',
	'note' => 'note',
	'post-amount->amount->quantity' => 'quantity',
	'post-amount->amount->commodity->symbol' => 'symbol',
	'cost->quantity' => 'cost',
	);
	
    sub char{
	my ($p,$str)=@_;
	return unless ($str=~/\S/);
	my $tree=$p->{Context};
	if ($tree->[2] eq 'transaction'){
	    if (@{$tree} == 4){
		if ($tree->[-1] eq "date"){
		    $transaction->{date}=str2time($str);
		}else{
		    $transaction->{$tree->[-1]} = $str;
		}
	    }elsif($tree->[4] eq 'posting'){
		my $key=$post{join('->',@{$tree}[(5..$#{$tree})])};
		$posting->{$key}=$str if $key;
	    }
	}
    }
}    

sub oldchar{
    my ($p,$str)=@_;
    return unless ($str=~/\S/);
    if ($TREE[1] eq 'transaction'){
	if ($TREE[0] eq 'date'){
	    $transaction->{date}=str2time($str);
	}else{
	    $transaction->{$TREE[0]} = $str;
	}
    }elsif($TREE[1] eq 'posting' && $TREE[0] eq 'note'){
	$posting->{note}=$str;
	
    }elsif ($TREE[0] eq 'quantity'){
	if ($TREE[2] eq 'posting'){
	    $posting->{cost}=$str;
	}elsif($TREE[2] eq 'post-amount'){
	    $posting->{quantity}=$str;
	}
    }elsif($TREE[2] eq 'posting' && $TREE[0] eq 'name'){ 
	    $posting->{account}=$str;
	    
    }elsif($TREE[0] eq 'symbol' && $TREE[3] eq 'post-amount'){
	$posting->{commodity}=$str;
    }
	
}

sub end{
    my ($p,$elt)=@_;
#    shift @TREE if ($TREE[0] eq $elt);
    if ($elt eq 'transaction'){
	#&gettransinfo();
	undef $transaction;
    }elsif ($elt eq 'posting'){
	undef $posting;
    }
}

sub stop{
    my $p=shift;
    @TREE=();
    my $ret=$ledger;
    undef $ledger;
    undef $transaction;
    undef $posting;
    return $ret;
}

sub gettransinfo{
    my $table=$ledger->{table};
    my $id=$ledger->{id};
    my $payee=$transaction->{payee};
    my @postings=$transaction->getPostings();

    foreach my $post (@postings){
	my $note=$post->{note};
	if ($note && $note=~/^\s*ID:\s*(\S+)/){
	    $id->{$1}=$payee;
	}
    }
    return unless @postings == 2;
    my $source=$postings[0]->{account};
    my $dest=$postings[1]->{account};

    return unless $source=~/^Assets|^Liabili/;
    $table->{$source}||={};
    $table->{$source}||={};
    $table->{$source}->{$payee}||={total =>0 ,$dest => 0};
    $table->{$source}->{$payee}->{total}++;
    $table->{$source}->{$payee}->{$dest}++;
    
    $payee='@@account default@@';
    $dest=join(':',(split(/:/,$dest))[0,1]); 
       #default accounts are only 2 levels deep
    $table->{$source}->{$payee}||={total =>0 ,$dest => 0};
    $table->{$source}->{$payee}->{total}++;
    $table->{$source}->{$payee}->{$dest}++;
    
}

1;
