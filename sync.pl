#!/usr/bin/env perl
use strict;
use warnings;
use Fcntl qw(:flock SEEK_END);
use File::Basename;
use config qw(config_select);
my $mirror_base_dir="/fsdata/site/mirror/";
#First, get the arguments
#my $uri=shift or die "You must specify a rsync uri\n";
my $name=shift or die "You must specify a target\n";
die "Mirror name shouldn't contain slashes\n" if $name =~ /\//;

my $max_retries=shift || 5;

my $mirror_status_dir=$mirror_base_dir.".status/";
my $status=$mirror_status_dir.$name."/";
my $cfg=&config_select("$mirror_base_dir/.mirror.cfg", $name);
my %cfg=%{$cfg};
die "Can't find config for given mirror\n" if !$cfg{base_uri} || !$cfg{path} || !$cfg{dest};
my $dest=$cfg{base}.$cfg{dest}."/";
my $uri=$cfg{base_uri}.$cfg{path};

if (! -e $status){
	mkdir $status or die "Can't create stauts dir $status for $name\n";
}

if (!($uri =~ /\/$/)){
	print "Warning: $uri is not ended with a slash\n";
}

#--delay-updates isn't necessery if we have ZFS/BtrFS, sigh
my $default_rsync_options=' -6 --delete-after --no-motd --safe-links --delay-updates --out-format="%n%L" ';
if (-e $status."exclude"){
	$default_rsync_options.="--exclude-from=${status}exclude";
}
my $opts = $cfg{opts}.$default_rsync_options;

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

#print $default_rsync_options;
my $last_exit_code;
while($max_retries--){
	print "$max_retries\n";
	open my $res, "rsync $opts $uri $dest |";
	my $flag=0;
	while(<$res>){
		chomp;
		my $line=$_;
		if(!($line =~ /[\000-\037]/)){
			print "$line\n";
			if(!($line =~ /^\s*$/)){
				#there're changes
				$flag=1;
			}
		}else{
			$line =~ /[\000-\037]([^\000-\037]*)$/;
			my $lastline = $1;
			print "$lastline\n";
			#it's a progress line, parse it here
			/\d+\s+\d+%[\d.]+\wB\/s\s+\d+:\d\d:\d\d\s+\(xfer#\d+, to-check=\d+\/\d+\)/;
		}
	}
	close $res;
	$last_exit_code = $?;
	print "exit code: $last_exit_code\n";
	if ($last_exit_code){
		$flag = 1;
	}
	opendir(my $destdir, $dest);
	my @evilmark = grep { /^Archive-Update-in-Progress/ } readdir $destdir;
	closedir $destdir;
	my $flag2=0;
	for (@evilmark){
		if(-f $dest.$_){
			$flag2 = 1;
			$flag = 1;
			last;
		}
	}
	#Oh shit! This mirror is being updated, sleep for a while and try again.
	print "Zzzzzz...\n" if $flag2;
	sleep 5*60 if $flag2;
	#If there're changes/errors, run again.
	last if !$flag;
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
