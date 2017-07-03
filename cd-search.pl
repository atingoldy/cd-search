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
use URI::Escape;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use HTML::TreeBuilder;
use HTML::Form;
use File::Path qw(make_path);

my $argc = $#ARGV + 1;

if ( $argc < 2 ) {
    print "usage: cd-search.pl <input path> <output path>\n";
    print "example: cd-search.pl C:\abcd D:\abcd \n";
    exit 1;
}

my $inputFolder  = shift;
my $outputFolder = shift;
my $indexFile = "C:\\Users\\Atin\\Documents\\contigs\\F_atropurpurea_533_whole\\contig_atropurpurea.txt";
my $fileCount = 0;
my $maxFileCount=100;

# build the request
my $args = "db=cdd&evalue=0.010000&compbasedadj=T&maxhits=500&mode=rep&filter=false";
print STDERR "Query options: ", $args, "\n";
$outputFolder = "D:\\Users\\Atin\\output\\F_atropurpurea_533_whole";
make_path($outputFolder);
open(DAT, $indexFile ) || die "Could not open the file $indexFile";
while (<DAT>) {
    my $ua = LWP::UserAgent->new;
    $fileCount++;
    if ( $fileCount > $maxFileCount ) {
        print STDERR "Process completed successfully\n";
        exit 0;
    }
    my @line = split( /\t/, $_ );
    my $query = "C:\\Users\\Atin\\Documents\\contigs\\F_atropurpurea_533_whole\\contig_atropurpurea_whole\\@line[0].fas";
    my $outputPath = "$outputFolder\\@line[0]";

    # read and encode the queries
    my $encoded_query = undef;
    print STDERR "Processing: ", $query, "\n";
    open(QUERY, $query );
    while (<QUERY>) {
        $encoded_query = $encoded_query . uri_escape($_);
    }
    close QUERY;

    $args = $args . "&seqinput=" . $encoded_query;

    my $req = new HTTP::Request POST => 'https://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi';
    $req->content_type('application/x-www-form-urlencoded');
    $req->content($args);

    # get the response
    my $response = $ua->request($req);

    # parse out the request id
    print STDERR "Response content: ", $response->content, "\n";
    my @forms   = HTML::Form->parse($response);
    my $dhandle = $forms[0]->find_input('dhandle')->value;
    print STDERR "Found dhandle: ", $dhandle, "\n";

    if ( $dhandle eq "" ) {
        print STDERR "Cannot find dhandle .. exiting\n";
        my $tr = HTML::TreeBuilder->new_from_content( $response->content );
        foreach my $atag ( $tr->look_down( _tag => q{p}, 'class' => 'error' ) )
        {
            print STDERR $atag->content_list;
        }
        exit 6;
    }

    # wait for search to complete
    print STDERR "Waiting for 3 seconds\n";
    sleep 3;
    print STDERR "Starting poll every 5 seconds\n";
    my $trial = 0;

    # poll for results
    while (true) {
        $trial++;
        if ( $trial eq 7 ) {
            print STDERR "Trial exhausted .. exiting\n";
            exit 7;
        }
        my $request = @forms[0]->make_request;
        my $resp    = $ua->request($request);
        if ($resp->is_success()) {
            print STDERR "Request #$trial success .. parsing content\n";
            my $tree = HTML::TreeBuilder->new_from_content( $resp->content );
            my $div_sumtables =
              $tree->look_down( _tag => 'div', id => qr/div_sumtables/ );
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
    print STDERR "Table $outputPath.html saved now downloading image\n";
    my $fileIWantToDownload =
"https://www.ncbi.nlm.nih.gov/Structure/cdd/wrpsb.cgi?dhandle=$dhandle&show_feat=true&mode=full&gwidth=900&output=graph";
    my $fileIWantToSaveAs = "$outputPath.png";

    getstore($fileIWantToDownload, $fileIWantToSaveAs );

    print STDERR "Image $outputPath.png saved successfully\n";
    sleep 3;

}

exit 0;
