#!/usr/bin/perl

# @author: Luis M Rodriguez-R <lmrodriguezr at gmail dot com>
# @update: Sep-17-2013
# @license: Artistic License 2.0

use warnings;
use strict;
use List::Util qw(sum);
use Getopt::Std;
our $VERSION = 1.0;

sub HELP_MESSAGE {
die "
Description:
   Reformats the node names (labels) of a RAxML_originalLabelledTree.<NAME> file
   (produced by RAxML's EPA, -f v), so it can be opened in most tree viewers (like
   iToL and FigTree).  Also, it creates iToL-compatible files to draw pie-charts
   (based on the classification of short reads) in the nodes of the reference tree.

Usage:
   $0 -n <NAME> [other options...]

   -n <str> *	Name of the run used in RAxML.
   -t <str>	Use this file as original labelled tree, instead of generating one
   		based on the job name.  By default, RAxML_originalLabelledTree.<NAME>
		in the -d directory. See [NOTE1].
   -d <str>	Directory containing RAxML files.  By default: current directory.
   -o <str>	Output tree.  By default, it takes the path to the input tree and
   		appends .nwk to it.
   -l <str>	File containing a list of internal nodes.  The nodes in the list
   		will be renamed, and the reads of all children nodes will be
		transferred to it.  This can be useful if you want to display
		these nodes collapsed.  The format of the file is raw text, with
		two columns separated by tabs or spaces, where the first column is
		the original name of the internal node (without the brackets) and
		the second is the name to be used.  See [NOTE2].
   -a		Append original label to the renamed nodes (only if -l is passed).
   -s <str>	The names of the reads will be assumed to contain the sample name,
   		separated by this string.  For example, if the value is '_', and
		a read has the name 'hco_ABCDEF/1#ACTG', it will be assumed to be
		a read from the sample 'hco'.  If not provided, all the reads are
		assumed to come from the same sample (called 'unknown').
   -m <str>	Comma-delimited list of samples.  If not provided, all found samples
   		will be used (unsorted).
   -c <str>	Comma-delimited list of colors (in RGB hexadecimal) to represent
   		the different samples.  If not provided (or if insufficient values
		are provided) random color are generated.
   -q		Run quietly.
   -h/--help	Displays this message and exits.

   * Mandatory
   [NOTE1] The tree provided by -t MUST be based on a tree produced by this script
   without the -l option.
   [NOTE2] The tree produced by RAxML-EPA is usually not correctly rooted, which
   makes the -l option useless.  However, you can manually root the tree and provide
   the rooted tree in Newick format using the -t option.  If you do this, make
   sure the program doesn't change/delete the names of the internal nodes.  I know
   that iToL can do it correctly (if you export preserving the original IDs), while
   FigTree deletes the labels.  I didn't try any other tool.

";
}

my %o;
getopts('n:t:d:o:l:s:m:c:qh', \%o);
$o{d} ||= '.';
$o{n} or &HELP_MESSAGE;
$o{h} and &HELP_MESSAGE;
$o{c} = [split /,/, (defined $o{c}?$o{c}:"")];

# Set files
my $inTree   = ($o{t} || $o{d}."/RAxML_originalLabelledTree.".$o{n});
my $outTree  = ($o{o} || $inTree.".nwk");
my $inClass  = $o{d}."/RAxML_classification.".$o{n};
my $outClass = $inClass.".iToL";
my $outColl  = $outTree.".collapse.iToL";

# Relocate tree node names
print STDERR "o Reformatting tree.\n" unless $o{q};
open INTREE, "<", $inTree or die "Cannot read file: $inTree: $!\n";
my $tree = <INTREE>;
$tree =~ s/:([\d\.]+)(\[.+?\])/$2:$1/g unless $o{t};
close INTREE;

# Read leaf nodes
print STDERR "o Reading nodes.\n" unless $o{q};
my %tags    = ();

my $t = $tree;
while($t =~ m/([A-Za-z0-9_\|\.-]+\[([A-Za-z0-9_\|\.-]+)\])/){
   my $n = $1;
   my $ta = $2;
   $tags{$ta} = $n;
   $t = substr $t, (length($n) + index $t, $n);
}

# Label/collapse internal nodes
if($o{l}){
   print STDERR "o Labeling/collapsing internal nodes.\n";
   open LIST, "<", $o{l} or die "Cannot read file: $o{l}: $!\n";
   open COLL, ">", $outColl or die "Cannot create file: $outColl: $!\n";
   while(<LIST>){
      chomp;
      next if /^#/ or /^\s*$/;
      # Label internal node
      my @l = split /\s+/;
      $l[0] =~ m/^\[(.+)\]$/ or die "Unable to parse internal node name: $l[0].\n";
      my $ori = $1;
      my $new = $l[1];
      if(exists $tags{$ori}){
	 warn "Warning: Trying to label/collapse $ori as $new, already defined as $tags{$ori}.\n";
	 next;
      }
      $new =~ s/[^A-Za-z0-9_\|\.\-]/_/g;
      $new.= "[$ori]" if $o{a};
      $tags{$ori} = $new;
      $tree =~ s/\[$ori\]/$new/;
      # Isolate node
      $t = substr $tree, 0, index($tree, $new);
      my $i=length($t)-2;
      for(my $c=1 ; $i and $c; $i--){
         my $char = substr $t, $i, 1;
	 $c++ if $char eq ')';
	 $c-- if $char eq '(';
      }
      $t = substr $t, $i;
      # Get children
      $t =~ s/:[\d\.]+|[\(\)]/,/g;
      $t =~ s/,+/,/g;
      my $chn=0;
      for my $child (split /,/, $t){
         next unless $child;
	 $child =~ s/.*\[(.+?)\]/$1/;
	 $tags{$child} = $new;
	 $chn++;
      }
      print STDERR "  Collapsing $new: $chn children.\n" unless $o{q};
      print COLL "$new\n";
   }
   close LIST;
   close COLL;
}

# Save tree
open OUTTREE, ">", $outTree or die "Cannot create file: $outTree: $!\n";
print OUTTREE $tree;
close OUTTREE;

# Count reads
my %samples = ();
my %nodes   = ();
print STDERR "o Counting reads.\n";
my $s = defined $o{s} ? $o{s} : "";
open INCLASS, "<", $inClass or die "Cannot read file: $inClass: $!\n";
while(<INCLASS>){
   my @ln = split /\s+/;
   $ln[0] =~ s/$s.+$//; # Sample name
   $samples{$ln[0]} = 1;
   $tags{$ln[1]} ||= "[".$ln[1]."]"; # Node name
   (($nodes{$tags{$ln[1]}} ||= {})->{$ln[0]} ||= 0)++;
}
close INCLASS;


my $labs = 'LABELS';
my $cols = 'COLORS';
my @samples = $o{m} ? (split /,/, $o{m}) : (keys %samples);
for my $sample (@samples){
   my $col = shift @{$o{c}};
   unless(defined $col and length($col)==6){
      $col = '';
      for (1 .. 3){
	 my $v = int rand 16;
	 $v = chr $v+55 if $v>9;
	 $col.="$v$v";
      }
   }
   $labs.= ','.($sample || 'unknown');
   $cols.= ',#'.$col;
}

open OUTCLASS, ">", $outClass or die "Cannot create file: $outClass: $!\n";
print OUTCLASS "$labs\n$cols\n";
for my $node (keys %nodes){
   print OUTCLASS $node.",R".sum(values %{$nodes{$node}});
   for my $sample (@samples){
      print OUTCLASS ",".($nodes{$node}->{$sample} || 0);
   }
   print OUTCLASS "\n";
}
close OUTCLASS;

