#!/usr/bin/perl

# $Id: web_blast.pl,v 1.10 2016/07/13 14:32:50 merezhuk Exp $
# ===========================================================================
#
# return codes:
#     0 - success
#     1 - invalid arguments
#     2 - no hits found
#     3 - rid expired
#     4 - search failed
#     5 - unknown error
#
# ===========================================================================

use strict;
#use warnings;
use URI::Escape;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use HTML::TreeBuilder;
use HTML::Form;

my $ua = LWP::UserAgent->new;

my $argc = $#ARGV + 1;

if ($argc < 3)
    {
    print "usage: web_blast.pl program database query [query]...\n";
    print "where program = megablast, blastn, blastp, rpsblast, blastx, tblastn, tblastx\n\n";
    print "example: web_blast.pl blastp nr protein.fasta\n";
    print "example: web_blast.pl rpsblast cdd protein.fasta\n";
    print "example: web_blast.pl megablast nt dna1.fasta dna2.fasta\n";

    exit 1;
}

my $program = shift;
my $database = shift;

if ($program eq "megablast")
    {
    $program = "blastn&MEGABLAST=on";
    }

if ($program eq "rpsblast")
    {
    $program = "blastx&SERVICE=rpsblast";
    }

# read and encode the queries
my $query;
my $encoded_query;

foreach $query (@ARGV)
    {
    open(QUERY, $query);
    while(<QUERY>)
        {
        $encoded_query = $encoded_query . uri_escape($_);
        }
    }

# build the request
my $args = "db=cdd&evalue=0.010000&compbasedadj=T&maxhits=500&mode=rep&filter=false";
print STDERR "Query content: ", $args, "\n";
$args = $args . "&seqinput=" . $encoded_query;

#$req = new HTTP::Request POST => 'https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi';
my $req = new HTTP::Request POST => 'https://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi';
$req->content_type('application/x-www-form-urlencoded');
$req->content($args);

# get the response
my $response = $ua->request($req);

# parse out the request id
#print STDERR "Response content: ", $response->content, "\n";
my @forms = HTML::Form->parse($response);
my $dhandle = $forms[0]->find_input('dhandle')->value;
print STDERR "Found dhandle: ", $dhandle, "\n";

if($dhandle eq "")
{
    print STDERR "Cannot find dhandle .. exiting\n";
    my $tr = HTML::TreeBuilder->new_from_content($response->content);
    foreach my $atag ($tr->look_down( _tag => q{p}, 'class' => 'error' ))
    {
        print STDERR $atag->content_list;
    }
    exit 6;
}

# wait for search to complete
print STDERR "Waiting for 3 seconds\n";
sleep 3;
print STDERR "Starting poll every 5 seconds\n";
my $trial=0;
# poll for results
while (true)
{
    $trial++;
    if ($trial eq 7)
    {
        print STDERR "Trial exhausted .. exiting\n";
        exit 7;
    }
    my $request = @forms[0]->make_request;
    my $resp = $ua->request($request);
    if ($resp->is_success())
    {
        print STDERR "Request #$trial success .. parsing content\n";
        #do something with content
        my $tree = HTML::TreeBuilder->new_from_content($resp->content);
        my $div_sumtables = $tree->look_down( _tag => 'div', id => qr/div_sumtables/ );
        sleep 5;
        next unless defined($div_sumtables);
        my @full_table = $div_sumtables->look_down( _tag => 'table' );
        #print STDERR @full_table[0]->as_HTML, "\n";
        open(my $fh, '>', 'report.html');
        print $fh @full_table[0]->as_HTML;
        close $fh;
        last;
    }
    else
    {
        # if we get here, something unexpected happened.
        print STDERR $resp->message, "\n";
        # exit 5;
        sleep 5;
    }

} # end poll loop

# retrieve and display results
print STDERR "Table saved now downloading image\n";
my $fileIWantToDownload = "https://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi?dhandle=$dhandle&show_feat=true&mode=full&gwidth=900&output=graph";
my $fileIWantToSaveAs   = 'out.png';

getstore($fileIWantToDownload, $fileIWantToSaveAs);

print STDERR "Image saved successfully\n";

exit 0;
