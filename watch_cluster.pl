#!/usr/bin/perl -w
use strict;
use warnings;
use diagnostics;

my $username = $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);
open (QSTAT, "qstat | grep \"$username\" | ");
my @qstat = <QSTAT>;
@qstat = split(/\n/, "@qstat");
close QSTAT;

my ($job, $cmd,$s);
my $i = 0;
foreach my $q (@qstat) {
	($job) = ($q =~ m/(pbsjob_\d*)/g);

	$q=("$q" =~ /\S(.*\S)?/s, $&);
	if ($q =~ m/(STDIN)/) {$cmd=$1}
	else 
	{
		my $USERNAME = getlogin();
		$cmd = `cat /pbs/$USERNAME/$job.status | grep -A1 \"The command submitted was:\" | tail -1`;
		$cmd=("$cmd" =~ /\S(.*\S)?/s, $&);
	}
	
	if (length($cmd) > 100) {
		$cmd = substr($cmd, 0, 100);
		$cmd = $cmd . '...';
	}
	print "$q\t$cmd\n";
	$i++;
}
print "$i jobs running\n";

