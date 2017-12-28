#!/usr/bin/perl

# $Id: launch.pl,v 0.01 2017/07/03 00:20:00 ajain Exp $

#use strict;
#use warnings;
use Getopt::Mixed;
use File::Basename;
use File::Path qw(make_path);
use IPC::System::Simple qw(system capture);

my ( $inDir, $outDir, $skipDone) =
    ( undef, undef, "false");

Getopt::Mixed::init(
    'i=s o=s s:s inputDirectory>i outputDirectory>o skipDone>s'
);

while ( my ( $option, $value, $pretty ) = Getopt::Mixed::nextOption() ) {
    $inDir    = $value if $option eq 'i';
    $outDir   = $value if $option eq 'o';
    $skipDone = $value if $option eq 's';
}

print STDERR "Input directory=$inDir\n";
print STDERR "Output directory=$outDir\n";

Getopt::Mixed::cleanup();

my $bDir            = basename($inDir);
my $outputDirectory = "$outDir/$bDir";
my $fileCount       = 0;
make_path($outputDirectory);
my @files = <$inDir/*.fas>;
foreach my $file (@files) {
    $fileCount++;
    print STDERR $fileCount, ". ";
    die
        "The file \"$file\" does not exist, and I can't go on without it."
        unless -e $file;
    my ($filePrefix, $dir, $ext) = fileparse($file, qr/\.[^.]*/);
    my $outFile = "$outputDirectory/$filePrefix.html";
    if ($skipDone eq "true") {
        if (-e $outFile) {
            print STDERR "\"$filePrefix.fas\" already done .. skipped\n";
            #            next LINE;
            next;
        }
    }
    system( $^X, "blast.pl", "-o=\"$outputDirectory\"", "-f=\"$file\"");
}

print STDERR "\nProcess completed";
exit 0;
