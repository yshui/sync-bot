package config;
use Exporter 'import';
@EXPORT_OK = qw(config_load_all config_select);
my $mirror_base_dir="/fsdata/site/mirror/";
sub config_next {
	my $fh = shift;
	my $ctx = shift;
	my %ctx;
	if($ctx){
		%ctx = %{$ctx};
	}else{
		%ctx = ();
	}
	while(<$fh>){
		chomp;
		next if /^#/;
		if(/^=/){
			if(/^==/){
				#reset
				($ctx{host}, $ctx{src}, $ctx{dest}, $ctx{name}) = ();
				$ctx{path} = "";
				$ctx{opts} = "-azHP";
				$ctx{base} = $mirror_base_dir;
			}else{
				s/^=//;
				$ctx{host} = $_;
			}
		}elsif(/^:/){
			s/^://;
			$ctx{path} = $_;
		}elsif(/^-/){
			$ctx{opts} = $_;
			if ($ctx{opts} =~ /(.*-){2,}/){
				#a simple sanity check, prevent abusing of override_options
				die "There should be only one dash in options\n";
			}
		}elsif(/^!/){
			s/^!//;
			$ctx{base} = $_;
			$ctx{base}.="/" if !($ctx{base} =~ /\/$/);
		}else{
			my @nlist = split /:/;
			$name = shift @nlist;
			$dest = shift @nlist || $name;
			$src = shift @nlist || $dest."/";
			my %cfg;
			print "$ctx{base}\n";
			($cfg{base_uri}, $cfg{path}, $cfg{opts}, $cfg{base}, $cfg{dest}, $cfg{name}) =
			    ($ctx{host}."::".$ctx{path}, $src, $ctx{opts}, $ctx{base}, $dest, $name);
			return (\%ctx, \%cfg);
		}
	}
	return ();
}
sub config_load_all {
	my $file_name = shift;
	my @result;
	die "Error in config_parse\n" if !$file_name;
	open my $cfgfh, "<", $file_name or die "Can't open $file_name for reading\n";
	my ($ctx, $cfg)=&config_next($cfgfh, $ctx);
	while($ctx){
		push @result, $cfg;
		($ctx, $cfg) = &config_next($cfgfh, $ctx);
	}
	return @result;
}
sub config_select {
	my $file_name = shift;
	my $target = shift;
	die "Error in config_parse\n" if !$file_name || !target;
	open my $cfgfh, "<", $file_name or die "Can't open $file_name for reading\n";
	my ($ctx, $cfg)=&config_next($cfgfh, $ctx);
	while($ctx){
		my %ctx = %{$ctx};
		for (keys %ctx){
			print "$_ $ctx{$_}\n";
		}
		my %cfg = %{$cfg};
		return $cfg if($cfg{name} eq $target);
		($ctx, $cfg) = &config_next($cfgfh, $ctx);
	}
	return undef;
}
1;
