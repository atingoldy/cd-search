#!/usr/bin/perl

# $Id: launch.pl,v 0.01 2017/07/03 00:20:00 ajain Exp $
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
use Getopt::Mixed;
use File::Basename;
use File::Path qw(make_path);
use IPC::System::Simple qw(system capture);

my($inDir, $outDir, $count, $mode, $verbose) =
  ( undef,   undef,    200, "full",   undef);

Getopt::Mixed::init('i=s o=s c:i m:s inputDirectory>i outputDirectory>o count>c mode>m');

while(my( $option, $value, $pretty) = Getopt::Mixed::nextOption()) {
    $inDir = $value if $option eq 'i';
    $outDir = $value if $option eq 'o';
    $count = $value if $option eq 'c';
    $mode = $value if $option eq 'm';
#    $verbose = $value if $option eq 'v';
}

print STDERR "Input directory=$inDir\n";
print STDERR "Output directory=$outDir\n";
print STDERR "Contig files to process=$count\n";
print STDERR "Output mode=$mode\n";
#print STDERR "verbose=$verbose\n";

Getopt::Mixed::cleanup();

#print "$_\n" for @files;
my @files = glob "$inDir/*contig*.txt";
#print STDERR "$_\n" for @files;
#print STDERR "FileCount=", $#files+1, "\n";
if($#files+1 > 1) {
    print STDERR "$_\n" for @files;
    die "More than one contig files found.\n";
}
my $indexFile = @files[0];
print STDERR "Found contig index file $indexFile\n";

my @dirs = glob "$inDir/*contig*/";
#print STDERR "$_\n" for @dirs;
#print STDERR "FileCount=", $#files+1, "\n";
if($#dirs+1 > 1) {
    print STDERR "$_\n" for @dirs;
    die "More than one contig directories found.\n";
}

my $readDir = @dirs[0];
print STDERR "Reading contig files from $readDir\n";

my $bDir = basename($inDir);
my $outputDirectory="$outDir/$bDir";
my $fileCount = 0;
make_path($outputDirectory);
open(DAT, $indexFile ) || die "Could not open the file $indexFile\n";
while (<DAT>) {
    $fileCount++;
    if ( $fileCount > $count ) {
        print STDERR "Process completed successfully\n";
        exit 0;
    }

    my @line = split( /\t/, $_ );
#    print STDERR "scd-search.pl ", "$readDir ", "$outputDirectory ", "\"@line[0]\" ", "$mode", "\n";
    system($^X, "scd-search.pl", "-r=\"$readDir\"", "-o=\"$outputDirectory\"", "-f=\"@line[0]\"", "-m=$mode");
}

exit 0;
