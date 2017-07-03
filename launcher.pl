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
use IPC::System::Simple qw(system capture);

my $argc = $#ARGV + 1;

if ( $argc < 2 ) {
    print "usage: cd-search.pl <input path> <output path>\n";
    print "example: cd-search.pl C:\abcd D:\abcd \n";
    exit 1;
}

my $inputFolder  = shift;
#my $outputFolder = shift;
my $indexFile = "C:\\Users\\Atin\\Documents\\contigs\\F_atropurpurea_533_whole\\contig_atropurpurea.txt";
my $fileCount = 0;
my $maxFileCount=100;

# build the request
my $args = "db=cdd&evalue=0.010000&compbasedadj=T&maxhits=500&mode=rep&filter=false";
print STDERR "Query options: ", $args, "\n";
my $outputFolder = "D:\\Users\\Atin\\output\\F_atropurpurea_533_whole";
make_path($outputFolder);
open(DAT, $indexFile ) || die "Could not open the file $indexFile";
while (<DAT>) {
    $fileCount++;
    if ( $fileCount > $maxFileCount ) {
        print STDERR "Process completed successfully\n";
        exit 0;
    }

    my @line = split( /\t/, $_ );
    print STDERR "scd-search.pl ", "$outputFolder ", "\"@line[0]\"", "\n";
    system($^X, "scd-search.pl", "$outputFolder", "\"@line[0]\"");
}

exit 0;
