#!/usr/bin/env perl
use strict;
use warnings;
use Fcntl qw(:flock SEEK_END);
use File::Basename;
#First, get the arguments
#my $uri=shift or die "You must specify a rsync uri\n";
my $name=shift or die "You must specify a destination\n";
my $max_retries=shift || 5;
my $mirror_base_dir="/fsdata/site/mirror/";
my $mirror_status_dir=$mirror_base_dir.".status/";
die "Mirror name shouldn't contain slashes\n" if $name =~ /\//;
my $dest=$mirror_base_dir.$name."/";
my $status=$mirror_status_dir.$name."/";
if (! -e $status){
	mkdir $status or die "Can't create stauts dir $status for $name\n";
}
die "Sync source isn't specified, can't find ${status}source" if (! -e $status."source");
open my $source, "<", $status."source";
my $uri = <$source>;
close $source;
chomp $uri;
if (!($uri =~ /\/$/)){
	print "Warning: $uri is not ended with a slash\n";
}
#acquire lock file
my $lockfile;
if (-e $status."lock"){
	open $lockfile, "<", $status."lock" or die "can't open ${status}lock for read\n";
	my $pid=undef;
	while(<$lockfile>){
		chomp;
		if(/^\d+$/){
			$pid=$_;
			last;
		}
	}
	my $ex = kill 0, $pid;
	die "Another instance is running, $pid\n" if $ex;
	close $lockfile;
}
open $lockfile, ">", $status."lock" or die "can't open ${status}lock for write\n";
flock $lockfile, LOCK_EX or die "Can't lock file ${status}lock\n";
print $lockfile "$$\n";
#--delay-updates isn't necessery if we have ZFS/BtrFS, sigh
my $default_rsync_options_0='-azHP';
my $default_rsync_options=' -6 --delete-after --no-motd --safe-links --delay-updates --out-format="%n%L" ';
if (-e $status."exclude"){
	$default_rsync_options.="--exclude-from=${status}exclude";
}
if (-e $status."override_options"){
	open my $opt, "<", $status."override_options";
	my $tmp = <$opt>;
	chomp $tmp;
	if (/(.*-){2,}/){
		#a simple sanity check, prevent abusing of override_options
		die "There should be only one dash in override_options\n";
	}
	$default_rsync_options_0 = $tmp;
	close $opt;
}
$default_rsync_options = $default_rsync_options_0.$default_rsync_options;
#print $default_rsync_options;
my $last_exit_code;
while($max_retries--){
	print "$max_retries\n";
	open my $res, "rsync $default_rsync_options $uri $dest |";
	my $flag=0;
	while(<$res>){
		chomp;
		my $line=$_;
		print "$line\n";
		if(!($line =~ /^\s*$/)){
			#there're changes
			$flag=1;
		}
	}
	close $res;
	$last_exit_code = $?;
	print "exit code: $last_exit_code\n";
	if ($last_exit_code){
		$flag = 1;
	}
	#If there're changes/errors, run again.
	last if(!$flag);
}
if($last_exit_code != 0){
	#Error occurs
	open my $error, ">", $status."error";
	print $error "$last_exit_code";
}else{
	if (-e $status."error"){
		unlink $status."error";
	}
	open my $syncfile, ">", $status."synctime";
	flock $syncfile, LOCK_EX;
	print $syncfile time, "\n";
	flock $syncfile, LOCK_UN;
	close $syncfile;
}
flock $lockfile, LOCK_UN;
close $lockfile;
unlink $status."lock";
