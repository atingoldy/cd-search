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

my($inDir, $outDir) =
    (undef,  undef);

Getopt::Mixed::init('o=s i=s inputDirectory>i outputDirectory>o');

while(my( $option, $value, $pretty) = Getopt::Mixed::nextOption()) {
    $inDir = $value if $option eq 'i';
    $outDir = $value if $option eq 'o';
}

#print STDERR "Input Directory=$inDir\n";
#print STDERR "Output directory=$outDir\n";

Getopt::Mixed::cleanup();

# build the request (this one as per 'Somewhat similar sequences (blastn)')
my $args = "CMD=Put&PROGRAM=blastn&DATABASE=nt&WORD_SIZE=11&NUCL_REWARD=2&NUCL_PENALTY=-3&GAPCOSTS=5 2";
#print STDERR "Query options: ", $args, "\n";
$inDir =~ s/^"(.*)"$/$1/;
$outDir =~ s/^"(.*)"$/$1/;

#my ($filePrefix, $dir, $ext) = fileparse($inFile, qr/\.[^.]*/);
#print STDERR "\"$filePrefix\" ";
#my $outputPath = "$outDir/$filePrefix";

#print STDERR "outputPath=$outputPath\n";
# read and encode the queries
my $encoded_query = undef;
#print STDERR "Processing: $inFile \n";
my @files = <$inDir/*.fas>;
foreach my $file (@files) {
    open(QUERY, $file) or die "Failed to open $file: $!\n";
    while (<QUERY>) {
        $encoded_query = $encoded_query . uri_escape($_);
    }
    close QUERY;
}

$args = $args . "&QUERY=" . $encoded_query;

#print STDERR $args, "\n";
my $request = HTTP::Request->new(POST => BLAST_URL);
$request->content_type('application/x-www-form-urlencoded');
$request->content($args);
my $ua = LWP::UserAgent->new;
my $response = $ua->request($request);

# parse out the request id
#print STDERR "HTTP status: ", $response->code(), "\n";
#print STDERR "Status Line: ", $response->status_line, "\n";
#print STDERR "HTTP Message: ", $response->message(), "\n";
#print STDERR "HTTP Response as string: ", $response->as_string();

#print STDERR "Response content: ", $response->content, "\n";
$response->content =~ /^    RID = (.*$)/m;
my $rid = $1;

if ($rid eq "") {
    print STDERR "Cannot find RID .. exiting\n";
    my $tr = HTML::TreeBuilder->new_from_content($response->content);
    foreach my $error_tag ($tr->look_down(_tag => q{p}, 'class' => 'error')) {
        print STDERR $error_tag->content_list;
    }
    exit 6;
}

print STDERR "Found RID: ", $rid, "\n";
# parse out the estimated time to completion
$response->content =~ /^    RTOE = (.*$)/m;
my $rtoe = $1;
print STDERR "Estimated time to complete: ", $rtoe, "\nSearching ";
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
    my $req = HTTP::Request->new(GET, BLAST_URL . "?CMD=Get&FORMAT_OBJECT=SearchInfo&RID=$rid");
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
            print STDERR "Search $rid failed.\n";
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
                print STDERR " done\n";
                # retrieve and display results
                my $content_req = HTTP::Request->new(GET, BLAST_URL . "?CMD=Get&FORMAT_TYPE=HTML&RID=$rid");
                my $content_resp = $ua->request($content_req);
                if ($content_resp->is_success) {
                    #print STDERR "Content query success\n";
                    #print STDERR $content_resp->content, "\n";
                    my @failed_files = undef;
                    my $resp_tree = HTML::TreeBuilder->new_from_content($content_resp->content);
                    my $queryList = $resp_tree->look_down(_tag => 'select', id => qr/queryList/);
                    for my $i (0 .. @files - 1) {
                        my $statusFor1 = $queryList->look_down(_tag => 'option', value => qr/$i/)->attr('class');
                        if ($statusFor1 eq "nohits") {
                            push @failed_files, @files[$i];
                        }
                    }

                    my %failed_files_table = map {$_ => 1} @failed_files;
                    make_path($outDir);
                    # lets send content request skipping failed files
                    for my $i (0 .. @files - 1) {
                        my ($filePrefix, $dir, $ext) = fileparse(@files[$i], qr/\.[^.]*/);
                        print STDERR $i+1, ". \"$filePrefix.fas\" ";
                        if (exists($failed_files_table{@files[$i]})) {
                            print STDERR "No hits found.\n";
                            next;
                        }
                        else {
                            my $reportFile = "$outDir/$filePrefix.html";
                            if (-e $reportFile) {
                                print STDERR "already done .. skipped\n";
                                next;
                            }
                            my $result_req = HTTP::Request->new(GET, BLAST_URL . "?CMD=Get&FORMAT_TYPE=HTML&RID=$rid&QUERY_INDEX=$i");
                            my $result_resp = $ua->request($result_req);
                            if ($result_resp->is_success) {
                                my $result_tree = HTML::TreeBuilder->new_from_content($result_resp->content);
                                my $dscTable = $result_tree->look_down(_tag => 'table', id => qr/dscTable/);
                                #print STDERR $dscTable->as_HTML, "\n";
                                open(my $fh, '>', $reportFile);
                                print $fh $dscTable->as_HTML;
                                close $fh;
                                print STDERR ".. done\n";
                            }
                            else {
                                print STDERR "Failed to get response for file @files[$i]: ", $result_resp->content, "\n";
                            }
                        }
                    }
                }
                else {
                    # if we get here, something unexpected happened.
                    print STDERR "Content query failed to check status", $content_resp->status_line, "\n";
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

my $delete_req = HTTP::Request->new(GET, BLAST_URL . "?CMD=Delete&RID=$rid");
my $delete_resp = $ua->request($delete_req);
if ($delete_resp->is_success) {
    print STDERR "Done\n";
}
else {
    print STDERR "Failed to delete results $rid\n";
    print STDERR "Status Line: ", $resp->status_line, "\n";
}
exit 0;
