#!/usr/bin/perl

use File::Copy qw(move);

# number of times to retry when ffmpeg encounters network errors
use constant RETRY => 50;

# block subtitle remuxing?
use constant BLOCK_SRT => 1;

# block 4K video encoding requets
use constant BLOCK_TRANSCODE => 1;

# prefer to drop 4K to Google Transcode for 4k video encoding requests
use constant GOOGLE_TRANSCODE => 1;

# prefer to direct stream requests with Google Transcode feeds (will reduce CPU load)
use constant PREFER_GOOGLE_TRANSCODE => 1;

# force remux of all audio?  disable for all tracks except first audio track selected
use constant FORCE_REMUX_AUDIO => 1;

use constant PATH_TO_EMBY_FFMPEG => '/opt/emby-server/bin/';
use constant PATH_TO_FFMPEG => '/u01/ffmpeg-git-20171123-64bit-static/';

use constant PROXY_DETERMINATOR => 'sofasttv';
use constant PROXY => 'http:// :8888';

use constant LOGFILE => '/tmp/transcode.log';


my $pidi=0;

$SIG{QUIT} = sub {  kill 'KILL', $pid;die "Caught a quit $pid $!"; };
$SIG{TERM} = sub {  kill 'KILL', $pid;die "Caught a term $pid $!"; };
$SIG{INT} = sub {  kill 'KILL', $pid;die "Caught a int $pid $!"; };
$SIG{HUP} = sub {  kill 'KILL', $pid;die "Caught a hup $pid $!"; };
$SIG{ABRT} = sub {  kill 'KILL', $pid;die "Caught a abrt $pid $!"; };
$SIG{TRAP} = sub {  kill 'KILL', $pid;die "Caught a trap $pid $!"; };
$SIG{STOP} = sub {  kill 'KILL', $pid;die "Caught a stop $pid $!"; };

my $FFMPEG_OEM = PATH_TO_EMBY_FFMPEG.'/ffmpeg.oem -timeout 5000000 ';
my $FFMPEG = PATH_TO_EMBY_FFMPEG.'/ffmpeg.oem ';
my $FFMPEG_TEST = PATH_TO_EMBY_FFMPEG.'/ffmpeg.oem -reconnect 1 -reconnect_at_eof 1 -reconnect_streamed 1 -reconnect_delay_max 2000 -timeout 5000000 ';
my $FFPROBE = PATH_TO_EMBY_FFMPEG .'/ffprobe ';
my $PROXY = PROXY;
my $PROXY_DETERMINATOR = PROXY_DETERMINATOR;

sub createArglist(){
	my $arglist = '';
	foreach my $current (0 .. $#ARGV) {
		if ($ARGV[$current] =~ m%\s% or $ARGV[$current] =~ m%\(% or $ARGV[$current] =~ m%\)% or $ARGV[$current] =~ m%\&%){
	   		$arglist .= ' "' .$ARGV[$current] . '"';
		}else{$arglist .= ' ' .$ARGV[$current];}
	}
	return $arglist;

}

my $start = time;
my $duration = 0;
my $duration_ptr = -1;
my $arglist = '';
my $filename_ptr = 0;
my $count = 1;
my $renameFileName = '';
my $isSRT = 0;
my $url = '';
my $seek = '';
foreach my $current (0 .. $#ARGV) {
	# fetch how long to encode
	if ($ARGV[$current] =~ m%\d\d:\d\d:\d\d%){
		my ($hour,$min,$sec) = $ARGV[$current] =~ m%0?(\d+):0?(\d+):0?(\d+)%;
		$duration = $hour*60*60 + $min*60 + $sec;
		$duration_ptr = $current;
	}elsif ($ARGV[$current] =~ m%^htt.*\:9988%){
		$url = $ARGV[$current];
	}elsif (0 and $ARGV[$current] =~ m%\-user_agent%){
		$ARGV[$current++] = '';
		$ARGV[$current] = '';
	}elsif ($ARGV[$current] =~ m%\-ss%){
		$ARGV[$current++] = '-ss';
		$seek = $ARGV[$current];
	}elsif (0 and $ARGV[$current] =~ m%\-fflags%){
		$ARGV[$current++] = '';
		$ARGV[$current] = '';
	}elsif (0 and $ARGV[$current] =~ m%\-f%){
		$ARGV[$current++] = '';
		$ARGV[$current] = '';
	}elsif ($ARGV[$current] =~ m%\.ts%){
		$filename_ptr = $current;
		#$ARGV[$filename_ptr] =~ s%\.\d+\.ts%\.$count\.ts%;
	}elsif ($ARGV[$current] =~ m%\.srt%){
		$isSRT = 1;
	}
}
$arglist = createArglist();

open (LOG, '>>' . LOGFILE) or die $!;
print LOG "passed in $arglist\n";


# request is for subtitle remuxing
if ($isSRT){

	# block subtitle remuxing requets?
	if (BLOCK_SRT){
		die("SRT transcoding is disabled.");
	}else{
		print STDERR "running " . 'ffmpeg ' . $arglist . "\n";
        print LOG "running " . 'ffmpeg ' . $arglist . "\n\n";

		`$FFMPEG_OEM $arglist`;
	}

# ### Python-GoogleDrive-VideoStream REQUEST
# we've been told to either video/audio transcode or direct stream
}elsif ($arglist =~ m%\:9988%){


	# when direct streaming, prefer the Google Transcode version over remuxing
	# this will reduce ffmpeg from remuxing and causing high cpu at the start of a new playback request
	# the remuxing will be spreadout over the entire playback session as Google will limit the transfer rate
	if (PREFER_GOOGLE_TRANSCODE){

		# request to transcode?
		if ($arglist =~ m%\-pix_fmt yuv420p% or $arglist =~ m%\-bsf\:v h264_mp4toannexb% or $arglist =~ m%\-codec\:v\:0 libx264%){
			if ($arglist =~ m%\,426\)% or $arglist =~ m%\,640\)% ){
				$arglist =~ s%\"?\Q$url\E\"?%\"$url\&preferred_quality\=2\&override\=true\"%;
			}elsif ($arglist =~ m%\,1280\)% or $arglist =~ m%\,720\)%){
				$arglist =~ s%\"?\Q$url\E\"?%\"$url\&preferred_quality\=1\&override\=true\"%;
			}else{#($arglist =~ m%\,1080\)%
				$arglist =~ s%\"?\Q$url\E\"?%\"$url\&preferred_quality\=0\&override\=true\"%;
			}

			$arglist =~ s%\-codec\:v\:0 .* -f segment%\-codec\:v\:0 copy \-copyts \-vsync \-1 \-codec\:a\:0 copy \-copypriorss\:a\:0 0 \-f segment%;

		# direct stream only?
		}else{
			#$arglist =~ s%\"?\Q$url\E\"?%\"$url\&preferred_quality\=0\&override\=true\"%;
			#$arglist =~ s%\"?\Q$url\E\"?%\"$url\&preferred_quality\=0\&override\=true\"%;
		}

		my $audioSelection = 0;
		($audioSelection) = $arglist =~ m%\-map 0\:0 \-map 0\:(\d+) %;

		print LOG "AUDIO SELECTION $audioSelection\n";
		#if ($arglist =~ m%\-map 0\:2 %){
		if ((FORCE_REMUX_AUDIO and $audioSelection == 1) or $audioSelection > 1){
			$arglist =~ s%\-map 0\:$audioSelection %\-map 1\:$audioSelection %;
			my $audioURL = '-i "'.$url.'"';
			if ($seek ne ''){
				$audioURL = '-ss ' . $seek . ' ' . $audioURL;
			}
			$arglist =~ s%\-i "([^\"]+)" %\-i "$1" $audioURL %;
			$arglist =~ s%\-codec\:a\:0 copy \-copypriorss\:a\:0 0 %\-codec\:a aac \-copypriorss\:a 0  %;

		}


		# fix for AVI file transcoding
		$arglist =~ s%\-f avi %-f mp4 %;

		$arglist =~ s%\-f matroska,webm %\-f mp4 %;

		print STDERR "URL = $url, $arglist\n";
	    print LOG "URL = $url, $arglist\n\n";

		#`$FFMPEG_OEM $arglist`;
		$pid = open ( LS, '-|', $FFMPEG_OEM . ' ' . $arglist . ' 2>&1');
		my $output = do{ local $/; <LS> };
		close LS;
		#my $output = `/u01/ffmpeg-git-20171123-64bit-static/ffmpeg $arglist -v error 2>&1`;

		# no transcoding available
		if($output =~ m%moov atom not found%){
			$arglist =~ s%\-f mp4 %\-f matroska,webm %;
			print LOG "$FFMPEG_OEM $arglist\n\n";
			`$FFMPEG_OEM $arglist`;
		}

	# let's check to see if we are trying remux 4k content
	}else{
		$pid = open ( LS, '-|', $FFPROBE . ' -i "' . $url . '" 2>&1');
		my $output = do{ local $/; <LS> };
		close LS;

		# content is 4K HEVC which is going to trigger video transcoding (at this point)
		# even when you block video transcoding in Emby admin console, it will try to video encode if remuxing is enabled
		if (BLOCK_TRANSCODE and $output =~ m%hevc%){
			# prefer to drop to Google Transcode over video transcoding
			if (GOOGLE_TRANSCODE){
				$arglist =~ s%\"?\Q$url\E\"?%\"$url\&preferred_quality\=0\&override\=true\"%;
				$arglist =~ s%\-f matroska,webm %\-f mp4 %;

				print STDERR "URL = $url, $arglist\n";
                print LOG "URL = $url, $arglist\n\n";
				`$FFMPEG_OEM $arglist`;
			# reject the playback request
			}else{
				die("video/audio transcoding is disabled.");
			}

		# direct stream
		}else{
			`$FFMPEG_OEM $arglist`;
		}

	}


#### LIVE TV REQUEST
# request with no duration, so not a DVR request, cycle over network errors
}elsif ($duration_ptr == -1){
	my $retry=1;
	while ($retry< RETRY and $retry > 0){

		if ($arglist =~ m%\-pix_fmt yuv420p%){
			$arglist =~ s%\-codec\:v\:0 .* -f segment%\-codec\:v\:0 copy \-copyts \-vsync \-1 \-codec\:a\:0 copy \-copypriorss\:a\:0 0 \-f segment%;
		}

		#$pid = open ( LS, '-|', $FFMPEG . ' ' . $arglist . ' 2>&1');
		#my $output = do{ local $/; <LS> };
		#close LS;
		#my $output = `/u01/ffmpeg-git-20171123-64bit-static/ffmpeg $arglist -v error 2>&1`;


		if ($arglist =~ m%$PROXY_DETERMINATOR%){
			print STDERR "running LIVETV " . $FFMPEG_TEST . ' ' . $PROXY . ' '. $arglist . "\n";
	        print LOG "running LIVETV " . $FFMPEG_TEST . ' ' . $PROXY . ' '. $arglist . "\n\n";
			`$FFMPEG_TEST -http_proxy $PROXY $arglist -v error`;
		}else{
			print STDERR "running LIVETV " . $FFMPEG_OEM . ' ' . $arglist . "\n";
	        print LOG "running LIVETV " . $FFMPEG_OEM . ' ' . $arglist . "\n\n";
			`$FFMPEG_TEST $arglist -v error`;
		}

		if ( $arglist =~ m%\/stream\/channelid%){
			last;
		}elsif($output =~ m%403% or $output =~ m%Connection timed out%){
			print STDERR "ERROR:";
			print STDERR $output;
			print STDERR 'retry ffmpeg ' . $arglist . "\n";
			sleep 2;
			$retry++;
		}else{
			print STDERR $output;
			print STDERR "\n\n\nDONE\n\n";
			$retry++;
		}
	}

#### LIVE TV DVR REQUEST
# request with duration indicates timed recording
}elsif ($duration != 0){

	my @moveList;
	my $current=0;
	my $finalFilename = $ARGV[$filename_ptr];
	$finalFilename  =~ s%\.ts%\.mp4%;
	$ARGV[$filename_ptr] =~ s%\.ts%\.$count\.ts%;
	while (-e $ARGV[$filename_ptr]){
		$count++;
		$ARGV[$filename_ptr] =~ s%\.\d+\.ts%\.$count\.ts%;
	}
	$renameFileName = $ARGV[$filename_ptr];
	$renameFileName =~ s%\.ts%\.mp4%;

	my $now = 60;
	my $failures=0;
	while ($now > 59 and $failures < 100){
	  	$arglist = createArglist();

		if ($arglist =~ m%$PROXY_DETERMINATOR%){
			print STDERR 'run ffmpeg $PROXY -v error ' . $arglist . "\n";
			`$FFMPEG_OEM $PROXY $arglist -v error`;
		}else{
			print STDERR 'run ffmpeg  -v error ' . $arglist . "\n";
			`$FFMPEG_OEM $arglist -v error`;

		}

		#$pid = open ( LS, '-|', '/u01/ffmpeg-git-20171123-64bit-static/ffmpeg  -v error ' . $arglist . ' 2>&1');
		#my $output = do{ local $/; <LS> };
		#close LS;
		#print STDERR $output;

		# we will rename the file later
		$moveList[$current][0] = $ARGV[$filename_ptr];
		$moveList[$current++][1] = $renameFileName;

		# calculate the new duration -- add a failure to the counter and wait for 5 seconds to let the failure condition pass
		$now = ($start + $duration + 5) - time ;
		if ($now > 59){
			sleep 5;
			$failures++;
		}

		# print the duration in correct format
		my $hour = int($now /60/60);
	    my $min = int ($now /60%60);
		my $sec = int ($now %60);
		$ARGV[$duration_ptr] = ($hour<10? '0':'').$hour.":".($min <10? '0':'').$min.':' . ($sec<10?'0':'').$sec;

		# increment filename
		$ARGV[$filename_ptr] =~ s%\.\d+\.ts%\.$count\.ts%;
		while (-e $ARGV[$filename_ptr]){
			$count++;
			$ARGV[$filename_ptr] =~ s%\.\d+\.ts%\.$count\.ts%;
			$renameFileName = $ARGV[$filename_ptr];
			$renameFileName =~ s%\.ts%\.mp4%;
		}
		print STDERR "next iteration " .$now . "\n";

	}

	my $concat = '';
	my $previous = '';
	for (my $i=0; $i <= $#moveList; $i++){
		if ($concat eq ''){
			$concat .= 'concat:'.$moveList[$i][0];
		}else{
			if ($moveList[$i][0] ne $moveList[$i-1][0]){
				$concat .= '|'.$moveList[$i][0];
			}
		}

	}
	print STDERR "$FFMPEG -i $concat -codec copy $finalFilename";
    print LOG "$FFMPEG -i $concat -codec copy $finalFilename\n\n";
	`$FFMPEG -i "$concat" -codec copy "$finalFilename"`;


	for (my $i=0; $i <= $#moveList; $i++){
		if ($i==0 or $moveList[$i][0] ne $moveList[$i-1][0]){

			move $moveList[$i][0], $moveList[$i][1];
			print STDERR "move $moveList[$i][0],$moveList[$i][1]\n";
		}
	}
}

close(LOG);
