# cd-search

This tool is used to batch search a nucleotide in NCBI Conserved Domain Database. The input directory contain files with FASTA file format and should end with `.fas` extension.

Example:

```c:\>perl launcher.pl -i=C:\Users\Atin\Documents\contigs\Fritillaria_maximowiczii_333_MOR-90 -o=D:\Users\Atin\output\```

| Switch                      | Description                                                                                                                                                                       |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `-i` or `--inputDirectory`  | Input directory path (if contains spaces then enclose inside double quotes)                                                                                                       |
| `-o` or `--outputDirectory` | Output directory path (if contains spaces then enclose inside double quotes                                                                                                       |
| `-s` or `--skipDone`        | Skip processing those input files which are already done. Supply a boolean value true or false (default: `false`) e.g: `-s=true -s=false`                                         |
| `-m` or `--mode`            | Output mode of the files generated. Controls the amount of information generated in output files (default: `full`) Possible inputs: `concise`, `standard` and `full` e.g.: `-m=standard` |
| `-c` or `--count`           | Number of input files to be processed (default: `200`)                                                                                                                            |

