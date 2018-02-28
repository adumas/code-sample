#!/usr/bin/perl -w
use strict;
use warnings;
use diagnostics;

use Getopt::Std;
use List::Util 'first';
use POSIX;
use Term::ReadKey;
use Term::ANSIColor;
use File::Basename;

my ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
die "You must have at least 10 characters" unless $wchar >= 10;

my %Options;
getopts("oesrtc:j:l:d:", \%Options);
#l = last N jobs
#j = job N to last
#c = search on commands
#d = date to search specifically

#o = print output
#e = print error
#s = print full status for last job ONLY
#r = recent jobs (last week?)
#t = jobs from today


#read files from PBS directory
my $dirname = "/pbs/$ENV{USER}";
opendir my($dh), $dirname or die "Couldn't open dir '$dirname': $!";
my @pbsfiles = sort readdir $dh;
closedir $dh;
my @status_files = sort grep { /\.status/ } @pbsfiles;
my @found_files;

my $searchCriteria = "";

my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);

#Run search for jobs TODAY or on DATE
if (defined $Options {t} || defined $Options{d}) #jobs from today or another day
{
   @found_files = ();
   my $searchDate;
   if ( $Options{t} ) 
   {
      my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
      $searchDate = "$weekDays[$wday] $months[$mon] $mday";
   }
   
   $searchCriteria = $searchCriteria . "\tdate [$searchDate]\n";

   foreach my $search_file (@status_files)
   {
      #print "$search_file\n";
      open SFILE, "$dirname/$search_file" or die $!;
      my @search_data = <SFILE>;
      push (@found_files, $search_file) if grep { /$searchDate/ } @search_data;
      close SFILE;
   }
   @status_files = @found_files;
}

#Run search for COMMANDS in recent jobs
if ($Options{c})
{
   @found_files = ();
   my $search_cmd = $Options{c};
   $searchCriteria = $searchCriteria . "\tcommand [$search_cmd] \n";
   foreach my $search_file (@status_files)
   {
      open SFILE, "$dirname/$search_file" or die $!;
      
      my $data = do { local $/; <SFILE> };
      my $pattern = qr/\s?# The command submitted was:\n(.+)\n/;
      
      if ($data =~ /$pattern/) {
         my $command = $1;
         if ($command =~ /$search_cmd/) { push (@found_files, $search_file) };
      }
   }
   @status_files = @found_files;
}


#EXIT if no matches... and print criteria
my $noMatch = 255;
if (@status_files == 0) 
{ 
   print "No files match criteria:\n$searchCriteria"; 
   exit $noMatch;
}

my @jobs;
my $nJobs = 10;
if ($Options{l}) { $nJobs = $Options{l}; }
if (@status_files > $nJobs)	{ @jobs = @status_files[-$nJobs..-1]; 	}
else 				{ @jobs = @status_files; 		}

unless ($Options{s} || $Options{e} || $Options{o})
{

my @jobSummary;
my $maxArgLength = 200;
my $minArgLength = 10;
foreach my $job (@jobs)
{
   my (%jd) = &parseJobSummary($job);
   
   push @jobSummary, \%jd;
   
   my $next = $wchar - length($jd{'cmd'}) - length($jd{'stat'}) - 9;
   if ($next < $maxArgLength) 		{ $maxArgLength = $next; }
   if (length($jd{'arg'}) > $minArgLength) 	{ $minArgLength = length($jd{'arg'}); }
}

if ($minArgLength < $maxArgLength) { $maxArgLength = $minArgLength + 7; } #nicely remove extraneous white space in padding if small args
my $cutLength = (-1*$maxArgLength+3);
my $i=0;
foreach my $jobref (@jobSummary)
{
   $i++;
   my $cmd  = $jobref->{'cmd'};
   my $args = $jobref->{'arg'};
   my $stat = $jobref->{'stat'};
   my $num = $jobref->{'n'};

   printf "[%-4d] ", $num;
   print colored ['white bold'], $cmd;
   my $numOfChar = $maxArgLength - length($args) - length($cmd) + 1;
   if ( length($args) > $maxArgLength ) { $args = "..." . substr($args,$cutLength); 	}
   elsif ( ! defined $args )		{ $args = ( ' ' x $numOfChar); 		}
   else 				{ $args = $args . ( ' ' x $numOfChar); 		}
   #printf " %s\t%s\n", $args, $stat;
   printf " %s\t", $args;
   if ( $stat =~ /status [^0]/ )	{ print colored ['yellow'], $stat; }
   elsif ( $stat =~ /running/ )		{ print colored ['blue'], $stat; }
   else 				{ print $stat; }
   print "\n";
}

}

#select last job file match unless otherwise noted by -j option
my $jobn = 1;
$jobn = $Options{j} if defined $Options{j};

#find job file requested
my $jobfile;
if ($jobn > 100)	{ $jobfile = first{ /pbsjob_$jobn/ } @status_files ; }
else			{ $jobfile = $status_files[-$jobn]; }


#find name of job: pbsjob_xxxx
$jobfile =~ /.*(pbsjob_\d+)\.status/;
my $jobname = $1;

if ($Options{s} || $Options{j})
{
#get job status file contents
print colored ['blue'], "FULL JOB STATUS for $jobname\n";
my (%js) = &parseJobSummary($jobfile);

#Summary output, in more expanded format...
print "COMMAND:\n\t";
print colored ['bold red'], " $js{'cmd'}";
print " $js{'arg'}\n\n";

my $run_pattern = qr/(running)\s?(.+)/;
my $done_pattern = qr/(done)\s?(.+)\s?(status [\d+])/;

if ( $js{'stat'} =~ $run_pattern ) {
   print colored ['blue'], "RUNNING"; print " on $js{'node'} [$2]\n"; 
}
elsif ( $js{'stat'} =~ $done_pattern ) {
   my ($date, $status) = ($2, $3);
   print colored ['green'], "Done, ";
   if ( $status =~ /(status [^0])/ )	{ print colored ['yellow'], "$status"; }
   else				 	{ print colored ['bold white'], "$status"; }
   print "\t[ $date] on $js{'node'}\n";
}

print "qsub options:\t$js{'opts'}\n";
print "qsub output:\t$js{'qout'}\n";
}

if ($Options{o})
{
my $jobOutFile = first { /$jobname\.o\d+/ } @pbsfiles;

open JOBOUT, "$dirname/$jobOutFile" or die $!;
my @job_output = <JOBOUT>;
close JOBOUT;
my $outLength = @job_output;
print "out length = $outLength\n";

if (@job_output) {
   print "JOB OUTPUT ( $dirname/$jobOutFile ) for $jobname\n";
   my $truncLength = 100;
   if ( $outLength > $truncLength ) { @job_output = @job_output[-$truncLength .. -1]; }
   print " LONG; truncated to last $truncLength lines...\n\n";
   print "@job_output\n";
} else {
   print "\n-o: Empty output file.\n"
}

}

if ($Options{e})
{
my $jobErrFile = first { /$jobname\.e\d+/ } @pbsfiles;
open JOBERR, "$dirname/$jobErrFile" or die $!;
my @job_error = <JOBERR>;
close JOBERR;
if (@job_error) {
   print "JOB ERROR OUTPUT for $jobname\n";
   print "@job_error\n"
} else {
   print "\n-e: Empty error file.\n"
}
}

sub parseJobSummary {
   my $job = $_[0]; #scalar input is job name
   my $jd = {};
   my ($full_command, $command, $cmd, $args, $node, $stat, $options, $run, $done, $qsub_out);
   $job =~ /.*pbsjob_(\d+)\.status/;
   my $jobnum = $1;
   my $jobname = "pbsjob_" . $jobnum;
   
   
   
   open JFILE, "$dirname/$job" or die $!;
   my $data = do { local $/; <JFILE> };
   close JFILE;
   my $cmd_pattern = 	 qr/\s?# The command submitted was:\n(.+)\n/;
   my $opts_pattern =	 qr/\s?#qsub command line options used were:\s?\n(.+)\n/;
   my $qsub_pattern =	 qr/\s?#the qsub command output:\s?\n(.+)\n/;
   my $compute_pattern = qr/\s?(compute.+)/;
   my $run_pattern = 	 qr/\s?(running.+)/;
   my $done_pattern = 	 qr/\s?(done.+)/;
   
   if	($data =~ /$cmd_pattern/)	{ $full_command = $1; }
   
   if	($data =~ /$compute_pattern/)	{ $node = $1; }
   
   if	($data =~ /$opts_pattern/)	{ $options = $1; }
   if	($data =~ /$qsub_pattern/)	{ $qsub_out = $1; }
   if	($data =~ /$run_pattern/)	{ $run = $1;	  }
   if	($data =~ /$done_pattern/)	{ $done = $1;	  }

   if    ($data =~ /$done_pattern/)	{ $stat = $1;	  }
   elsif ($data =~ /$run_pattern/)	{ $stat = $1;	  }
   else					{ $stat = "cancelled?";	  }
   
   $full_command =~ /^(\S*)\s?(.*)$/;
   $command = $1;
   $args = $2;
   $cmd = basename($command);
   
   
   return ('job'  => $job,
   	   'cmd'  => $cmd,
           'arg'  => $args,
           'opts' => $options,
           'qout' => $qsub_out,
           'run'  => $run,
	   'stat' => $stat,
	   'node' => $node,
           'n'    => $jobnum);
}


