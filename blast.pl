#!/usr/bin/perl

use File::Path qw(make_path);
use Getopt::Mixed;
use HTML::Form;
use HTTP::Request::Common qw(POST);
use HTML::TreeBuilder;
use LWP::Simple;
use LWP::UserAgent;
use URI::Escape;
use File::Basename;

use constant BLAST_URL => "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi";

my($inFile, $outDir) =
    (undef,  undef);

Getopt::Mixed::init('o=s f=s inputFile>f outputDirectory>o');

while(my( $option, $value, $pretty) = Getopt::Mixed::nextOption()) {
    $outDir = $value if $option eq 'o';
    $inFile = $value if $option eq 'f';
}

#print STDERR "Output directory=$outDir\n";
#print STDERR "Contig file name=$inFile\n";

Getopt::Mixed::cleanup();

# build the request (this one as per 'Somewhat similar sequences (blastn)')
my $args = "CMD=Put&PROGRAM=blastn&DATABASE=nt&WORD_SIZE=11&NUCL_REWARD=2&NUCL_PENALTY=-3&GAPCOSTS=5 2";
#print STDERR "Query options: ", $args, "\n";
$inFile =~ s/^"(.*)"$/$1/;
$outDir =~ s/^"(.*)"$/$1/;
my ($filePrefix, $dir, $ext) = fileparse($inFile, qr/\.[^.]*/);
print STDERR "\"$filePrefix\" ";
my $outputPath = "$outDir/$filePrefix";
#print STDERR "outputPath=$outputPath\n";
# read and encode the queries
my $encoded_query = undef;
#print STDERR "Processing: $inFile \n";
open(QUERY, $inFile) or die "Failed to open $inFile: $!\n";
while (<QUERY>) {
    $encoded_query = $encoded_query . uri_escape($_);
}
close QUERY;

$args = $args . "&QUERY=" . $encoded_query;

#print STDERR $args, "\n";

my $request = new HTTP::Request POST => BLAST_URL;
$request->content_type('application/x-www-form-urlencoded');
$request->content($args);

# get the response
my $ua = LWP::UserAgent->new;
my $response = $ua->request($request);

# parse out the request id
#print STDERR "Response content: ", $response->content, "\n";
$response->content =~ /^    RID = (.*$)/m;
my $rid = $1;

if ($rid eq "") {
    print STDERR "Cannot find RID .. exiting\n";
    my $tr = HTML::TreeBuilder->new_from_content($response->content);
    foreach my $atag ($tr->look_down(_tag => q{p}, 'class' => 'error')) {
        print STDERR $atag->content_list;
    }
    exit 6;
}

#print STDERR "Found RID: ", $rid, "\n";
# parse out the estimated time to completion
$response->content =~ /^    RTOE = (.*$)/m;
my $rtoe = $1;
#print STDERR "Estimated time to complete: ", $rtoe, "\n";
sleep $rtoe;

#print STDERR "Starting poll every 5 seconds\n";
my $trial = 0;

# poll for results
while (true) {
    $trial++;
    if ($trial eq 20) {
        print STDERR "Trial exhausted .. exiting\n";
        exit 0;
    }
#    print STDERR "Creating SearchInfo request\n";
    my $req = new HTTP::Request GET => BLAST_URL . "?CMD=Get&FORMAT_OBJECT=SearchInfo&RID=$rid";
    my $resp = $ua->request($req);
#    print STDERR "Checking if success\n";
    if ($resp->is_success()) {
        #print STDERR "Request success checking status\n";
        if ($resp->content =~ /\s+Status=WAITING/m) {
            #print STDERR "Searching...\n";
            print STDERR ".";
            sleep 10;
            next;
        }

        if ($resp->content =~ /\s+Status=FAILED/m) {
            print STDERR "Search $rid failed; please report to blast-help\@ncbi.nlm.nih.gov.\n";
            exit 4;
        }

        if ($resp->content =~ /\s+Status=UNKNOWN/m) {
            print STDERR "Search $rid expired.\n";
            print STDERR "HTTP status: ", $resp->code(), "\n";
            print STDERR "Status Line: ", $resp->status_line, "\n";
            print STDERR "HTTP Message: ", $resp->message(), "\n";
            print STDERR "HTTP Response as string: ", $resp->as_string();
            exit 3;
        }

        if ($resp->content =~ /\s+Status=READY/m) {
            if ($resp->content =~ /\s+ThereAreHits=yes/m) {
                #print STDERR "Search complete, retrieving results...\n";
                # retrieve and display results
                $req = new HTTP::Request GET => BLAST_URL . "?CMD=Get&FORMAT_TYPE=HTML&RID=$rid";
                $resp = $ua->request($req);
                if ($resp->is_success()) {
                    #print STDERR "Content query success\n";
                    #print STDERR $resp->content, "\n";
                    my $tree = HTML::TreeBuilder->new_from_content($resp->content);
                    my $dscTable = $tree->look_down(_tag => 'table', id => qr/dscTable/);
                    #print STDERR $dscTable->as_HTML, "\n";
                    my $reportFile = "$outputPath.html";
                    open(my $fh, '>', $reportFile);
                    print $fh $dscTable->as_HTML;
                    close $fh;
                }
                else {
                    # if we get here, something unexpected happened.
                    print STDERR "Content query failed", $resp->status_line, "\n";
                }
                last;
            }
            elsif ($resp->content =~ /\s+ThereAreHits=no/m) {
                print STDERR "No hits found. ";
                last;
            }
            else {
                print STDERR "No hits found.\n";
                print STDERR "HTTP status: ", $resp->code(), "\n";
                print STDERR "Status Line: ", $resp->status_line, "\n";
                print STDERR "HTTP Message: ", $resp->message(), "\n";
                print STDERR "HTTP Response as string: ", $resp->as_string();
                exit 2;
            }
        }
    }
    else {
        # if we get here, something unexpected happened.
        print STDERR $resp->status_line, "\n";
        # exit 5;
    }
    sleep 5;
}    # end poll loop



print STDERR " done\n";
exit 0;
