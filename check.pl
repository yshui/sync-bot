#!/usr/bin/env perl
use warnings;
use strict;
use POSIX;
my $pid;
if($pid=fork){
	die "Can't fork: $!\n" if $pid<0;
	exit 0;
}
POSIX::setsid or die "setsid: $!\n";
if($pid=fork){
	die "Can't fork: $!\n" if $pid<0;
	open my $pidfile, '>', "~/.checker.pid" or die "Can't open pid file\n";
	print $pidfile $pid;
	close $pidfile;
	exit 0;
}
umask 0;
foreach (0 .. (POSIX::sysconf (&POSIX::_SC_OPEN_MAX) || 1024))
	{ POSIX::close $_ }
open (STDIN, "</dev/null");
open (STDERR, ">&STDOUT");
chdir "/";
my $base_dir="/fsdata/site/mirror/";
my $status_dir=$base_dir.".status/";
open (STDOUT, ">>${status_dir}.checker.log");
opendir my $sdh, $status_dir or die "Failed to open $status_dir\n";
opendir my $dh, $base_dir or die "Failed to open $base_dir\n";
while(1){eval{
	rewinddir $dh;
	rewinddir $sdh;
	my @managed_repos = grep { !/\./ && -d "$status_dir/$_" } readdir($sdh);
	my @all_repos = grep { !/\./ && -d "$base_dir/$_" } readdir($dh);
	print "@all_repos";
	my %mask=();
	for my $tmp (@managed_repos){
		$mask{$tmp}=1;
	}
	my @status;
	for my $tmp (@all_repos){
		my %s=();
		$s{name}=$tmp;
		$s{managed} = exists($mask{$tmp});
		if($s{managed}){
			my $lname = $status_dir.$tmp."/lock";
			my $ename = $status_dir.$tmp."/error";
			my $sname = $status_dir.$tmp."/synctime";
			if(-e $ename){
				$s{status}="failed";
				open my $errfile, "<", $ename or die "Can't open $ename\n";
				my $code = <$errfile>;
				chomp $code;
				$s{err}=$code;
				close $errfile;
			}elsif(-e $lname){
				open my $lockfile, "<", $lname or die "Can't open $lname\n";
				my $lockpid = <$lockfile>;
				chomp $lockpid;
				if(!(kill 0, $lockpid)){
					$s{status}="weird";
				}else{
					$s{status}="updating";
				}
				close $lockfile;
			}elsif(!-e $sname){
				$s{status}="nosyncfile";
			}else{
				$s{status}="updated";
				open my $syncfile, "<", $sname or die "Can't open $sname\n";
				$s{synctime}=<$syncfile>;
				chomp $s{synctime};
				close $syncfile;
			}
		};
		push @status, \%s;
	}
	print "@status";
	my $stname=$base_dir."mirror_status.json";
	open my $statusfile, ">", $stname;
	#Hand written json, haha
	print $statusfile "[";
	my $first=1;
	for my $tmp (@status){
		my %a=%{$tmp};
		if(!$first){
			print $statusfile ",";
		}else{
			$first=0;
		}
		print $statusfile '{';
		print $statusfile qq/"name":"$a{name}"/;
		print $statusfile ',"managed":', $a{managed}?"true":"false";
		if($a{managed}){
			print $statusfile qq/,"err":$a{err}/ if($a{status} eq "failed");
			print $statusfile qq/,"synctime":$a{synctime}/ if(exists($a{synctime}));
			print $statusfile qq/,"status":"$a{status}"/;
		}
		print $statusfile '}';
	}
	print $statusfile "]";
	close $statusfile;
};
	if($@){
		print "Update status failed with $@\n";
	}else{
		print "mirror_status.json updated at ", time, "\n";
	}
	sleep 5*60;
}

