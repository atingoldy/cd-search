#!/usr/bin/perl

use URI::Escape;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use HTML::TreeBuilder;
use Getopt::Mixed;

my $ua = LWP::UserAgent->new;

my $inDir = undef;
Getopt::Mixed::init('i=s inputFile>i');

while(my( $option, $value, $pretty) = Getopt::Mixed::nextOption()) {
    $inDir = $value if $option eq 'i';
}

# read and encode the queries
my $encoded_query = "";
my @files = <$inDir/*.fas>;
foreach my $file (@files) {
    open(QUERY, $file);
    while (<QUERY>) {
        $encoded_query = $encoded_query . uri_escape($_);
    }
}

# build the request
my $args = "CMD=Put&PROGRAM=blastn&DATABASE=nt&WORD_SIZE=11&NUCL_REWARD=2&NUCL_PENALTY=-3&GAPCOSTS=5 2";
print STDERR "Query content: ", $args, "\n";
$args = $args . "&QUERY=" . $encoded_query;

my $req = new HTTP::Request POST => 'https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi';
$req->content_type('application/x-www-form-urlencoded');
$req->content($args);

# get the response
my $response = $ua->request($req);

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

print STDERR "Found RID: ", $rid, "\n";
# parse out the estimated time to completion
$response->content =~ /^    RTOE = (.*$)/m;
my $rtoe = $1;

# wait for search to complete
sleep $rtoe;

# poll for results
while (true) {
    sleep 5;

    $req = new HTTP::Request GET =>
            "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Get&FORMAT_OBJECT=SearchInfo&RID=$rid";
    $response = $ua->request($req);

    if ($response->content =~ /\s+Status=WAITING/m) {
        print STDERR "Searching...\n";
        next;
    }

    if ($response->content =~ /\s+Status=FAILED/m) {
        print STDERR "Search $rid failed; please report to blast-help\@ncbi.nlm.nih.gov.\n";
        exit 4;
    }

    if ($response->content =~ /\s+Status=UNKNOWN/m) {
        print STDERR "Search $rid expired.\n";
        print STDERR "HTTP status: ", $response->code(), "\n";
        print STDERR "Status Line: ", $response->status_line, "\n";
        print STDERR "HTTP Message: ", $response->message(), "\n";
        print STDERR "HTTP Response as string: ", $response->as_string();
        exit 3;
    }

    if ($response->content =~ /\s+Status=READY/m) {
        if ($response->content =~ /\s+ThereAreHits=yes/m) {
            print STDERR "Search complete, retrieving results...\n";
            last;
        }
        else {
            print STDERR "No hits found.\n";
            print STDERR "HTTP status: ", $response->code(), "\n";
            print STDERR "Status Line: ", $response->status_line, "\n";
            print STDERR "HTTP Message: ", $response->message(), "\n";
            print STDERR "HTTP Response as string: ", $response->as_string();
            exit 2;
        }
    }

    # if we get here, something unexpected happened.
    exit 5;
} # end poll loop

# retrieve and display results
$req = new HTTP::Request GET => "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Get&FORMAT_TYPE=HTML&RID=$rid&QUERY_INDEX=1";
$response = $ua->request($req);

print $response->content;
exit 0;
