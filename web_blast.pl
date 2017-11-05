#!/usr/bin/perl

# $Id: web_blast.pl,v 1.10 2016/07/13 14:32:50 merezhuk Exp $
#
# ===========================================================================
#
#                            PUBLIC DOMAIN NOTICE
#               National Center for Biotechnology Information
#
# This software/database is a "United States Government Work" under the
# terms of the United States Copyright Act.  It was written as part of
# the author's official duties as a United States Government employee and
# thus cannot be copyrighted.  This software/database is freely available
# to the public for use. The National Library of Medicine and the U.S.
# Government have not placed any restriction on its use or reproduction.
#
# Although all reasonable efforts have been taken to ensure the accuracy
# and reliability of the software and data, the NLM and the U.S.
# Government do not and cannot warrant the performance or results that
# may be obtained by using this software or data. The NLM and the U.S.
# Government disclaim all warranties, express or implied, including
# warranties of performance, merchantability or fitness for any particular
# purpose.
#
# Please cite the author in any work or product based on this material.
#
# ===========================================================================
#
# This code is for example purposes only.
#
# Please refer to https://ncbi.github.io/blast-cloud/dev/api.html
# for a complete list of allowed parameters.
#
# Please do not submit or retrieve more than one request every two seconds.
#
# Results will be kept at NCBI for 24 hours. For best batch performance,
# we recommend that you submit requests after 2000 EST (0100 GMT) and
# retrieve results before 0500 EST (1000 GMT).
#
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

use URI::Escape;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use HTML::TreeBuilder;

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
    $program = "blastp&SERVICE=rpsblast";
    }

# read and encode the queries
my $encoded_query = "";
foreach my $query (@ARGV)
    {
    open(QUERY,$query);
    while(<QUERY>)
        {
        $encoded_query = $encoded_query . uri_escape($_);
        }
    }

# build the request
my $args = "CMD=Put&PROGRAM=$program&DATABASE=$database&HITLIST_SIZE=500&EXPECT=0.010000&COMPOSITION_BASED_STATISTICS=2&FILTER=F";
print STDERR "Query content: ", $args, "\n";
$args = $args . "&QUERY=" . $encoded_query;

my $req = new HTTP::Request POST => 'https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi';
#$req = new HTTP::Request POST => 'https://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi';
$req->content_type('application/x-www-form-urlencoded');
$req->content($args);

# get the response
my $response = $ua->request($req);

# parse out the request id
#print STDERR "Response content: ", $response->content, "\n";
$response->content =~ /^    RID = (.*$)/m;
my $rid=$1;

if($rid eq ""){
	print STDERR "Cannot find RID .. exiting\n";
	my $tr = HTML::TreeBuilder->new_from_content($response->content);
    foreach my $atag ( $tr->look_down( _tag => q{p}, 'class' => 'error' ) ) {
		print STDERR $atag->content_list;
	}
	exit 6;
}

print STDERR "Found RID: ", $rid, "\n";
# parse out the estimated time to completion
$response->content =~ /^    RTOE = (.*$)/m;
my $rtoe=$1;

# wait for search to complete
sleep $rtoe;

# poll for results
while (true)
    {
    sleep 5;

    $req = new HTTP::Request GET => "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Get&FORMAT_OBJECT=SearchInfo&RID=$rid";
    $response = $ua->request($req);

    if ($response->content =~ /\s+Status=WAITING/m)
        {
        print STDERR "Searching...\n";
        next;
        }

    if ($response->content =~ /\s+Status=FAILED/m)
        {
        print STDERR "Search $rid failed; please report to blast-help\@ncbi.nlm.nih.gov.\n";
        exit 4;
        }

    if ($response->content =~ /\s+Status=UNKNOWN/m)
        {
        print STDERR "Search $rid expired.\n";
        print STDERR "HTTP status: ", $response->code( ), "\n";
		print STDERR "Status Line: ", $response->status_line, "\n";
		print STDERR "HTTP Message: ",$response->message( ), "\n";
		print STDERR "HTTP Response as string: ", $response->as_string( );
		exit 3;
        }

    if ($response->content =~ /\s+Status=READY/m) 
        {
        if ($response->content =~ /\s+ThereAreHits=yes/m)
            {
            #  print STDERR "Search complete, retrieving results...\n";
            last;
            }
        else
            {
            print STDERR "No hits found.\n";
            print STDERR "HTTP status: ", $response->code( ), "\n";
			print STDERR "Status Line: ", $response->status_line, "\n";
			print STDERR "HTTP Message: ",$response->message( ), "\n";
			print STDERR "HTTP Response as string: ", $response->as_string( );
			exit 2;
            }
        }

    # if we get here, something unexpected happened.
    exit 5;
    } # end poll loop

# retrieve and display results
$req = new HTTP::Request GET => "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Get&FORMAT_TYPE=Text&RID=$rid";
$response = $ua->request($req);

print $response->content;
exit 0;
