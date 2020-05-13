#!/usr/bin/perl -w
#
# Author: R.A.Rainton <robin@rainton.com>
#
# Simple script to import raw Loxone stat files into Influx DB.
#
# Config file is JSON format, something like...
# Get the Loxone UUIDs from the stat filenames, web interface, etc.
# 
#{
#	"loxone" : {
#		"statsdir": "/path/to/your/loxone/stats"
#	},
#	
#	"influxdb" : {
#		"transport": "http",
#		"host": "your.influxdb.host",
#		"port": "8086",
#		"database": "yourdb"
#	},
#	
#	"uuids" : {
#		"1234abcd-037d-9763-ffffffee1234abcd": {"measurement": "temperature", "tags": {"room": "Kitchen"} },
#		"1234abcd-005f-8965-ffffffee1234abcd": {"measurement": "humidity", "tags": {"room": "Kitchen"} },
#		"1234abcd-0052-0f08-ffffffee1234abcd": {"measurement": "AnythingYouLike", "tags": {"lots": "OfTags", "AsMany": "AsYouLike"} }
#	}
#}
#
# This code automatically adds the tags, 'uuid' and 'src' to all values.
#

use strict;

use autodie;
use Data::Dumper;
use File::Basename;
use File::Find;
use File::Slurp;
use File::Touch;
use JSON;
use HTTP::Tiny;
use POSIX;
use Time::Local;

# More logging?
# TODO: should be command line option
use constant VERBOSE => 1;

# Dry-run?
# TODO: should be command line option
use constant DRY_RUN => 0;

# Byte positions in Loxone stat files
use constant TITLE_START => 12;
use constant READING_BOUNDARY => 16;
use constant UUID_LENGTH => 4;
use constant DATE_LENGTH => 4;
use constant READING_LENGTH => 8;

# Loxone times begin 1 Jan 2009
use constant TIMESTAMP_OFFSET => 1230768000;

# Load config. JSON is easy to use in Node.js too.
# TODO: should be command line option
my $confref = from_json(read_file($ENV{HOME} . '/.loxone_stats_influx'));

# TODO: we really should allow use of ENV variables (particularly $HOME)
# in the config file at some point. 
my $url = sprintf("%s://%s:%s/write?db=%s&precision=s", $confref->{'influxdb'}->{'transport'}, $confref->{'influxdb'}->{'host'}, $confref->{'influxdb'}->{'port'}, $confref->{'influxdb'}->{'database'});

# Find out when we last ran (this file will be updated with the date
# of the newest file processed on exit).
my $stamp_file = $ENV{HOME} . '/.loxone_stats_influx_import.stamp';
my $lastmtime = (stat($stamp_file))[9];
$lastmtime = 0 if (!defined($lastmtime));
printf("Last mtime: %d\n", $lastmtime) if (VERBOSE);

sub uuid {
	return (split/\./, basename shift)[0];
}

sub get_tags {
	my $uuid = shift;
	my $tags;
	if (defined($confref->{'uuids'}->{$uuid})) {
		$tags = $confref->{'uuids'}->{$uuid}->{'measurement'};
		my $hashref = $confref->{'uuids'}->{$uuid}->{'tags'};
		while (my($key, $value) = each(%$hashref)) {
			$tags .= ",$key=$value";
		}
	}
	return $tags;
}

sub process_file {
	my $stat_file = shift;
	my $uuid = uuid($stat_file);
	my $tags = get_tags($uuid);
	if (!defined($tags)) {
		printf("No tags found for %s. Skipping.", $uuid) if (VERBOSE);
	} else {
		printf("Processing %s ... ", $stat_file);

		my $bin = read_file($stat_file, { binmode => ':raw' });

                # First byte holds number of readings
                my $readings = unpack("C", $bin);

		# TODO: this is pretty horrible, is there a better way?
		my $title = unpack("Z64", substr($bin, TITLE_START));

                printf(" %s (readings: %d)\n", $title, $readings) if(VERBOSE);
                my $data_length = (int((DATE_LENGTH + $readings * READING_LENGTH) / READING_BOUNDARY) + 1) * READING_BOUNDARY;
                
                # Work out the next data boundary
                my $data_position = (int((TITLE_START + length($title)) / READING_BOUNDARY) + 1) * READING_BOUNDARY;
                printf("Data starting at %d with length %d\n", $data_position, $data_length) if(VERBOSE);

		my $http = HTTP::Tiny->new;
		my $points = 0;
		my $form_data = '';
		for(;$data_position < length($bin); $data_position += $data_length) {
			my $data = substr($bin, $data_position, $data_length);

			my $localstamp = unpack("I", substr($data, UUID_LENGTH, DATE_LENGTH)) + TIMESTAMP_OFFSET;
                        
			# Convert to UTC (InfluxDB only works in UTC)
			my $stamp = timelocal(gmtime($localstamp));
			
                        # For now we only handle the first of multi-value files
                        my $lp = 0;
                        my $val = unpack("d", substr($data, (DATE_LENGTH + UUID_LENGTH) + ($lp * READING_LENGTH), 8));
	
			$form_data .= "\n" if ($points > 0);
			# TODO, 3 decimals for now, although it should be possible
			# to determine this from the input stat file.
			$form_data .= sprintf("%s,uuid=%s,src=statfile value=%0.3f %d", $tags, $uuid, $val, $stamp);

			$points++;
		}

		if (DRY_RUN) {
                        print Dumper($form_data) if (VERBOSE);
                        printf("%d points read.\n", $points);
                } else {
                        my $response = $http->request('POST', $url, { content => $form_data });
                        print Dumper($response) if (VERBOSE);
                        printf("%d points read & posted.\n", $points);

                        my $mtime = (stat($stat_file))[9];
                        $lastmtime = $mtime if ($mtime > $lastmtime);
                }
		
	}
}

my @stat_files;

sub filter_files {
	my $name = $File::Find::name;
	print $name, "\n" if (VERBOSE);

	# Only files matching our pattern.
	# Files are something like:
	# 10b85de2-0157-8fb7-fffff62eeb38b63d.201712
	if ($name =~ /.*\/(([0-9a-f]{8})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{16}))\.([0-9]{6})/) {
		# Only files new since we last fully ran.
		my $mtime = (stat($name))[9];
		printf("mtime: %d\n", $mtime);
		if ($mtime > $lastmtime) {
			push @stat_files, $name;
		}
	}
}

find({wanted => \&filter_files, no_chdir => 1}, ($confref->{'loxone'}->{'statsdir'}));
printf("Found %d files to process\n", scalar(@stat_files));

my $file_count = 0;
my $file_todo = scalar(@stat_files);

foreach my $file (sort @stat_files) {
  $file_count++;
  process_file($file);
  print "$file_count/$file_todo\n";
}

# If we've processed anything update our timestamp file
# This isn't imperative because duplicate runs just overwrite data,
# they don't duplicate it.
if ($file_count && $lastmtime > 0) {
	printf("Setting mtime: %d\n", $lastmtime) if (VERBOSE);
	my $touch = File::Touch->new(mtime => $lastmtime, mtime_only => 1);
	$touch->touch($stamp_file);
}
