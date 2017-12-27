#!/usr/bin/perl

# $Id: cd-search.pl,v 0.01 2017/06/25 11:20:00 ajain Exp $
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

#use strict;
#use warnings;
use File::Path qw(make_path);
use Getopt::Mixed;
use HTML::Form;
use HTTP::Request::Common qw(POST);
use HTML::TreeBuilder;
use LWP::Simple;
use LWP::UserAgent;
use URI::Escape;

use constant WRPSB => "https://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi";

my($readDir, $outDir, $filePrefix,  $mode, $verbose) =
  ( undef,     undef,     undef, "full",    undef);

Getopt::Mixed::init('r=s o=s f=s m:s readDirectory>r outputDirectory>o mode>m');

while(my( $option, $value, $pretty) = Getopt::Mixed::nextOption()) {
    $readDir = $value if $option eq 'r';
    $outDir = $value if $option eq 'o';
    $filePrefix = $value if $option eq 'f';
    $mode = $value if $option eq 'm';
    #    $verbose = $value if $option eq 'v';
}

#print STDERR "Read directory=$readDir\n";
#print STDERR "Output directory=$outDir\n";
#print STDERR "Contig file name=$filePrefix\n";
#print STDERR "Output mode=$mode\n";
##print STDERR "verbose=$verbose\n";

Getopt::Mixed::cleanup();

# build the request
my $args = "db=cdd&evalue=0.010000&compbasedadj=T&maxhits=500&mode=rep&filter=false";
#print STDERR "Query options: ", $args, "\n";
my $query = "$readDir\\$filePrefix.fas";
my $outputPath = "$outDir\\$filePrefix";

# read and encode the queries
my $encoded_query = undef;
#print STDERR "Processing: ", $query, "\n";
print STDERR "Processing: \"$filePrefix.fas\" ";
open(QUERY, $query );
while (<QUERY>) {
    $encoded_query = $encoded_query . uri_escape($_);
}
close QUERY;

$args = $args . "&seqinput=" . $encoded_query;

my $req = new HTTP::Request POST => WRPSB;
$req->content_type('application/x-www-form-urlencoded');
$req->content($args);

# get the response
my $ua = LWP::UserAgent->new;
my $response = $ua->request($req);

# parse out the request id
#print STDERR "Response content: ", $response->content, "\n";
my @forms = HTML::Form->parse($response);
my $inpDhandle = $forms[0]->find_input('dhandle');
if(!$inpDhandle){
    print STDERR "Something unexpected happened\n";
    print STDERR "Response content: ", $response->content, "\n";
#    print "$_\n" for @forms[0]->value;
    exit 7;
}

my $dhandle = $inpDhandle->value;
#print STDERR "Found dhandle: ", $dhandle, "\n";

if ($dhandle eq "") {
    print STDERR "Cannot find dhandle .. exiting\n";
    my $tr = HTML::TreeBuilder->new_from_content( $response->content );
    foreach my $atag ( $tr->look_down( _tag => q{p}, 'class' => 'error' ) )
    {
        print STDERR $atag->content_list;
    }
    exit 6;
}

# wait for search to complete
#print STDERR "Waiting for 3 seconds\n";
sleep 3;
#print STDERR "Starting poll every 5 seconds\n";
my $trial = 0;

# poll for results
while (true) {
    $trial++;
    if ($trial eq 20) {
        print STDERR "Trial exhausted .. exiting\n";
        exit 7;
    }
    my $request = @forms[0]->make_request;
    my $resp    = $ua->request($request);
    if ($resp->is_success()) {
#        print STDERR "Request #$trial success .. parsing content\n";
        print STDERR ".";
        my $tree = HTML::TreeBuilder->new_from_content( $resp->content );
        my $div_sumtables = $tree->look_down( _tag => 'div', id => qr/div_sumtables/ );
        sleep 5;
        next unless defined($div_sumtables);
        my @full_table = $div_sumtables->look_down( _tag => 'table' );

        #print STDERR @full_table[0]->as_HTML, "\n";
        my $reportFile = "$outputPath.html";
        open( my $fh, '>', $reportFile );
        print $fh @full_table[0]->as_HTML;
        close $fh;
        last;
    }
    else {
        # if we get here, something unexpected happened.
        print STDERR $resp->message, "\n";

        # exit 5;
        sleep 5;
    }

}    # end poll loop

# retrieve and display results
#print STDERR "Table $outputPath.html saved now downloading image\n";
my $fileIWantToDownload = WRPSB."?dhandle=$dhandle&show_feat=true&mode=$mode&gwidth=900&output=graph";
my $fileIWantToSaveAs = "$outputPath.png";

getstore($fileIWantToDownload, $fileIWantToSaveAs );

#print STDERR "Image $outputPath.png saved successfully\n";
print STDERR " done\n";
exit 0;
